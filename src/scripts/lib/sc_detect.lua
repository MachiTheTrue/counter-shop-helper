-- Counter & Shop Helper: light auto-detection (champion, teams, map/mode, match clock).
--
-- Low cost: called at most once per second (DET.INTERVAL; DET.FAST_INTERVAL in champion select and
-- while the match loads, so a quick pick is not missed), every engine read is protected
-- (pcall), and each player's champion is cached by PRI pointer so it isn't resolved twice.
-- Nothing is hooked, nothing is written: reflection reads and the game's own getters only.
--
-- Sources:
--   me        local pawn: TgPawn_Character.GetArchetypeBotId() -> champion, else champion select
--             (the lobby's MatchMembers, m_CurrentAllyCustomizeState.nBotId)
--   allies    in match: GRI.PRIArray + team; champion select: MatchMembers of my half
--   enemies   in match: GRI.PRIArray + team (PRI.r_PawnOwner, once the pawn has been replicated)
--   map       prefix of the WorldInfo path ("td_abyss_p.TheWorld..." -> td_abyss_p)
--   mode      heuristics on map / GRI class (MODE_RULES) -> unknown if nothing matches
--   elapsed   GRI.ElapsedTime -> phase early/mid/late
--
-- State kept between reads, and when it is dropped:
--   by_pri     champion and team per PRI pointer: dropped when the world changes (a new map), since
--              pointers are reused by the next match
--   match_me   my champion in this match: kept while I am dead (no pawn), dropped with the world
--   played     rosters of the matches played this session: the lobby keeps the last roster in
--              MatchMembers after a match, which must not read as a new champion select
--   last_cs    the last champion select read (roster id, my pick, allies, time): between champion
--              select and the match (map loading, no player or no GRI yet) the status is "loading"
--              for up to DET.LOADING_GRACE seconds, with that pick, instead of "not in a game"
--   match_world  the world where a match GRI was seen: a world without GRI is "match_over" only
--              there (end of match); on a new world it is still loading
-- state.world counts map changes and state.game names the current game (its roster, else the map),
-- so main.lua can reset what belongs to one game.

local DET = {}
DET.__index = DET
DET.INTERVAL = 1.0
DET.FAST_INTERVAL = 0.25   -- champion select and loading: picks can be quick
DET.LOADING_GRACE = 60     -- seconds a champion select stays the current game while the match loads

-- Mode heuristics: first match wins. `field` = "map" or "gri"; patterns in lowercase.
DET.MODE_RULES = {
	{ field = "map", pat = "^shootingrange", mode = "range" },
	{ field = "map", pat = "^td_", mode = "tdm" },
	{ field = "gri", pat = "deathmatch", mode = "tdm" },
	{ field = "gri", pat = "tdm", mode = "tdm" },
	{ field = "gri", pat = "onslaught", mode = "onslaught" },
	{ field = "gri", pat = "koth", mode = "onslaught" },
	{ field = "map", pat = "^ons_", mode = "onslaught" },
	{ field = "gri", pat = "siege", mode = "siege" },
	{ field = "gri", pat = "payload", mode = "siege" },
}
-- Maps where no match is in progress (detection paused).
DET.IDLE_MAPS = { lobbymapv4_p = true, entry = true, ["chaosentry"] = true }

local function try(f, ...)
	local ok, v = pcall(f, ...)
	if ok then return v end
	return nil
end

local function get(obj, field)
	if not obj then return nil end
	return try(function() return obj[field] end)
end

local function ptr(obj)
	return obj and try(function() return obj:ptr() end)
end

local function class_name(obj)
	return obj and try(function() return obj:class():name() end)
end

function DET.new(pred)
	return setmetatable({
		pred = pred,
		next_at = 0,
		by_pri = {},        -- PRI ptr -> { champ = name|false, team = "ally"|"enemy"|nil }
		pawn_cache = {},    -- pawn class name -> champion name|false
		world_ptr = nil,    -- WorldInfo pointer of the last read
		world = 0,          -- number of map changes seen
		match_me = nil,     -- my champion in the current match (kept while dead)
		played = {},        -- roster id -> true for matches played this session
		last_cs = nil,      -- { id, me, allies, at } of the last champion select read
		match_world = nil,  -- world number where a match GRI was seen
		state = { status = "idle", allies = {}, enemies = {}, world = 0 },
		errors = 0,
		last_error = nil,
	}, DET)
end

function DET:champ_of_bot(id)
	local c = type(id) == "number" and self.pred.by_bot[id]
	return c and c.name or nil
end

-- Champion of a pawn, cached per pawn class. Each champion has its own TgPawn_* class (listed in
-- sc_data.lua), so the class answers first. A class the data does not list is asked once for
-- GetArchetypeBotId (the champion's bot id), and only when it is a character: the payload of Siege
-- (TgPawn_SiegeEngine_*) and other non-champion pawns have no such function, and asking them made
-- Tempest log "has no property `GetArchetypeBotId`" at every read.
local function champion_like(pawn, cn)
	if cn:find("SiegeEngine", 1, true) or cn:find("Payload", 1, true) then return false end
	local ok = try(function() return pawn:is_a("TgGame.TgPawn_Character") end)
	return ok ~= false
end

function DET:champ_of_pawn(pawn)
	if not pawn then return nil end
	local cn = class_name(pawn)
	if not cn then return nil end
	local hit = self.pawn_cache[cn]
	if hit == nil then
		local c = self.pred.by_pawn[cn]
		if c then
			hit = c.name
		elseif champion_like(pawn, cn) then
			hit = self:champ_of_bot(try(function() return pawn:GetArchetypeBotId() end)) or false
		else
			hit = false
		end
		self.pawn_cache[cn] = hit
	end
	return hit or nil
end

function DET:champ_of_pri(pri)
	return self:champ_of_pawn(get(pri, "r_PawnOwner"))
end

-- Team number of a player (TgRepInfo_Player.GetTaskForceNumber; PRI.r_TaskForce is the team object,
-- not a number). nil when unknown: 255 means no team (shooting range, spectators).
local function task_force(pri)
	local tf = try(function() return pri:GetTaskForceNumber() end)
	if type(tf) ~= "number" or tf == 255 then return nil end
	return tf
end

-- "ally" / "enemy" / nil (unknown for now).
local function team_of(pri, my_tf)
	local tf = task_force(pri)
	if my_tf and tf then return tf == my_tf and "ally" or "enemy" end
	local pawn = get(pri, "r_PawnOwner")
	if pawn then
		local friendly = try(function() return pawn:IsFriendlyWithLocalPawn() end)
		if friendly ~= nil then return friendly and "ally" or "enemy" end
	end
	return nil
end

local function map_of(pc)
	local wi = get(pc, "WorldInfo")
	local p = wi and try(function() return wi:path() end)
	return p and (p:match("^([^%.:]+)") or p):lower() or nil
end

function DET:guess_mode(map, gri_class)
	local v = { map = map or "", gri = (gri_class or ""):lower() }
	for _, r in ipairs(DET.MODE_RULES) do
		if v[r.field]:find(r.pat) then return r.mode, r.field .. "~" .. r.pat end
	end
	return nil, nil
end

-- Champion select: allies (my half of MatchMembers) with their nBotId; the local player first.
function DET:read_champ_select(pc)
	local m = get(get(get(get(pc, "myHUD"), "m_pMovie"), "m_UIDataManager"), "m_Match")
	local members = get(m, "MatchMembers")
	if not members or (try(function() return #members end) or 0) == 0 then return nil end
	local all, my_half, names = {}, nil, {}
	try(function()
		for i, mm in members:items() do
			if mm then
				local half = math.floor((get(mm, "m_nMctsMatchIndex") or (i - 1)) / 5)
				local pd = get(mm, "pPlayerData")
				local is_self = pd and get(pd, "bIsSelf") or false
				local cs = get(mm, "m_CurrentAllyCustomizeState")
				local bot = cs and get(cs, "nBotId")
				all[#all + 1] = { half = half, self = is_self, champ = self:champ_of_bot(bot), bot = bot }
				names[#names + 1] = tostring(get(mm, "m_sName") or "?")
				if is_self then my_half = half end
			end
		end
	end)
	if #all == 0 then return nil end
	if my_half == nil then my_half = all[1].half end
	local me, allies = nil, {}
	for _, e in ipairs(all) do
		if e.half == my_half then
			if e.self then me = e.champ elseif e.champ then allies[#allies + 1] = e.champ end
		end
	end
	-- The roster names the game: same match id and players = same game (champion select, then match).
	local match_id = try(function() return m.dwMatchId.A end)
	local id = tostring(match_id or "?") .. ":" .. table.concat(names, ",")
	return { me = me, allies = allies, members = all, id = id }
end

-- A new map (lobby <-> match): what was learnt about the last one no longer applies.
function DET:check_world(pc)
	local p = ptr(get(pc, "WorldInfo"))
	if p == self.world_ptr then return end
	self.world_ptr, self.world = p, self.world + 1
	self.by_pri, self.match_me = {}, nil
end

-- Between champion select and the match: the pick seen last, while it is recent. `cs` = the roster
-- readable right now (the HUD may already hold the final pick), or nil.
function DET:loading(st, now, cs)
	local last = self.last_cs
	if not last or last.used or now - last.at > DET.LOADING_GRACE or self.played[last.id] then return false end
	if cs and cs.id ~= last.id then return false end
	st.status, st.game, st.source = "loading", last.id, "MatchMembers"
	st.me = (cs and cs.me) or last.me
	st.allies = (cs and cs.allies) or last.allies
	return true
end

-- Full read (protected). Returns the new state.
function DET:read(now)
	now = now or os.clock()
	local pc = tempest.local_player()
	local st = { status = "idle", allies = {}, enemies = {}, at = now }
	if not pc then
		st.world = self.world
		if not self:loading(st, now, nil) then st.status = "no_player" end
		return st
	end
	self:check_world(pc)
	st.world = self.world
	st.map = map_of(pc)
	if st.map and DET.IDLE_MAPS[st.map] then
		st.status = "lobby"
		local cs = self:read_champ_select(pc)
		-- a roster already played is what the lobby kept from the last match, not a new selection
		if cs and (cs.me or #cs.allies > 0) and not self.played[cs.id] then
			st.status, st.me, st.allies, st.source = "champ_select", cs.me, cs.allies, "MatchMembers"
			st.game = cs.id
			self.last_cs = { id = cs.id, me = cs.me, allies = cs.allies, at = now }
		end
		return st
	end
	local wi = get(pc, "WorldInfo")
	local gri = get(wi, "GRI")
	-- no GRI on a new world: the match is loading (after a champion select) or not there yet;
	-- end of match / world teardown: stop walking pawns and PRIs (they are being destroyed)
	if not gri or get(gri, "bMatchIsOver") == true then
		self.by_pri = {}
		if gri or self.match_world == self.world then
			st.status = "match_over"
			self.match_world = self.world
			if self.last_cs then self.last_cs.used = true end   -- that champion select's match ended
		elseif not self:loading(st, now, self:read_champ_select(pc)) then
			-- a new map with no champion select before it (training, practice range...): shown as
			-- loading, but nothing is being loaded, so items can be read (see main.lua)
			st.status, st.practice = "loading", true
		end
		return st
	end
	self.match_world = self.world
	if self.last_cs then self.last_cs.used = true end   -- that champion select led to this match
	st.gri_class = class_name(gri)
	st.mode, st.mode_rule = self:guess_mode(st.map, st.gri_class)
	local elapsed = get(gri, "ElapsedTime")
	if type(elapsed) == "number" then
		st.elapsed = elapsed
		st.phase = self.pred:phase_for_elapsed(elapsed)
	end
	-- this game's roster (the HUD movie outlives the map), else the map itself
	local cs = self:read_champ_select(pc)
	if cs then self.played[cs.id] = true end
	st.game = cs and cs.id or ("world:" .. tostring(self.world))
	-- my champion: from my pawn; while I am dead (no pawn), the one seen earlier in this match; before
	-- my pawn exists, my pick in this game's roster (only the roster of the champion select just seen)
	local roster_me = cs and self.last_cs and cs.id == self.last_cs.id and cs.me or nil
	st.me = self:champ_of_pawn(get(pc, "Pawn")) or self.match_me or roster_me
	self.match_me = st.me
	local my_pri = get(pc, "PlayerReplicationInfo")
	local my_ptr = ptr(my_pri)
	local my_tf = my_pri and task_force(my_pri)
	local list = get(gri, "PRIArray")
	local seen = {}
	if list then
		try(function()
			for _, pri in list:items() do
				local p = ptr(pri)
				if p and p ~= my_ptr and try(function() return pri:is_a("TgGame.TgRepInfo_Player") end) then
					seen[p] = true
					local rec = self.by_pri[p] or {}
					self.by_pri[p] = rec
					if not rec.champ then rec.champ = self:champ_of_pri(pri) end
					local t = team_of(pri, my_tf)
					if t then rec.team = t end
					if rec.champ and rec.team == "ally" then st.allies[#st.allies + 1] = rec.champ end
					if rec.champ and rec.team == "enemy" then st.enemies[#st.enemies + 1] = rec.champ end
				end
			end
		end)
	end
	-- Players gone (end of match, map change): forget their cache.
	for p in pairs(self.by_pri) do
		if not seen[p] then self.by_pri[p] = nil end
	end
	table.sort(st.allies)
	table.sort(st.enemies)
	while #st.enemies > self.pred.D.max_enemies do table.remove(st.enemies) end
	st.status = "match"
	st.source = "PRIArray"
	return st
end

-- To call every frame: does the actual work at most once per INTERVAL.
-- Returns the state and true when it changed.
function DET:poll(now)
	now = now or os.clock()
	if now < self.next_at then return self.state, false end
	self.next_at = now + DET.INTERVAL
	local ok, st = pcall(self.read, self, now)
	if not ok then
		self.errors = self.errors + 1
		self.last_error = tostring(st)
		return self.state, false
	end
	-- the pace follows what was just read: a champion select seen now is read again soon
	if st.status == "champ_select" or st.status == "loading" then self.next_at = now + DET.FAST_INTERVAL end
	local changed = self:signature(st) ~= self:signature(self.state)
	self.state = st
	return st, changed
end

function DET:signature(st)
	return table.concat({ st.status or "", st.me or "", st.mode or "", st.phase or "",
		table.concat(st.allies or {}, ","), table.concat(st.enemies or {}, ",") }, "|")
end

return DET
