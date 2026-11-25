-- SmartCounter 8.1: light auto-detection (champion, teams, map/mode, match clock).
--
-- Low cost: called at most once per second (DET.INTERVAL), every engine read is protected
-- (pcall), and each player's champion is cached by PRI pointer so it isn't resolved twice.
-- Nothing is hooked, nothing is written: reflection reads only.
--
-- Sources, in order of reliability (see `smartcounter_probe` to check them in game):
--   me        local pawn (class TgPawn_*), else champion select (MatchMembers.nBotId)
--   allies    in match: PRIArray + team; champion select: MatchMembers of my half
--   enemies   in match: PRIArray + team (r_PawnOwner, once the pawn has been replicated)
--   map       prefix of the WorldInfo path ("td_abyss_p.TheWorld..." -> td_abyss_p)
--   mode      heuristics on map / GRI class (MODE_RULES) -> unknown if nothing matches
--   elapsed   GRI.ElapsedTime -> phase early/mid/late

local DET = {}
DET.__index = DET
DET.INTERVAL = 1.0

-- Mode heuristics: first match wins. `field` = "map" or "gri"; patterns in lowercase.
-- To be refined with `smartcounter_probe` output (map + GRI class names of real matches).
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
-- PRI fields tried to read a champion id directly (cheaper/earlier than the pawn).
DET.PRI_BOT_FIELDS = { "r_nBotId", "r_BotId", "r_nCharacterId", "r_CharacterId", "r_nChampionId", "BotId" }

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
		state = { status = "idle", allies = {}, enemies = {} },
		errors = 0,
		last_error = nil,
		bot_field = nil,    -- PRI field that answered, once found
	}, DET)
end

-- Champion from a pawn: exact class name, else is_a over known classes (once per class).
function DET:champ_of_pawn(pawn)
	if not pawn then return nil end
	local cn = class_name(pawn)
	if not cn then return nil end
	local hit = self.pawn_cache[cn]
	if hit ~= nil then return hit or nil end
	local c = self.pred.by_pawn[cn]
	if not c then
		for pc_name, champ in pairs(self.pred.by_pawn) do
			if try(function() return pawn:is_a("TgGame." .. pc_name) end) then
				c = champ
				break
			end
		end
	end
	self.pawn_cache[cn] = c and c.name or false
	return c and c.name or nil
end

function DET:champ_of_bot(id)
	local c = id and self.pred.by_bot[id]
	return c and c.name or nil
end

function DET:champ_of_pri(pri)
	local fields = self.bot_field and { self.bot_field } or DET.PRI_BOT_FIELDS
	for _, f in ipairs(fields) do
		if try(function() return pri:has(f) end) then
			local name = self:champ_of_bot(get(pri, f))
			if name then
				self.bot_field = f
				return name
			end
		end
	end
	return self:champ_of_pawn(get(pri, "r_PawnOwner"))
end

local function task_force(pri)
	-- 0.5.1: plain field read first; the UFunction call only as a fallback
	local tf = get(pri, "r_TaskForce")
	if tf == nil then tf = try(function() return pri:GetTaskForceNumber() end) end
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
	local all, my_half = {}, nil
	try(function()
		for i, mm in members:items() do
			if mm then
				local half = math.floor((get(mm, "m_nMctsMatchIndex") or (i - 1)) / 5)
				local pd = get(mm, "pPlayerData")
				local is_self = pd and get(pd, "bIsSelf") or false
				local cs = get(mm, "m_CurrentAllyCustomizeState")
				local bot = cs and get(cs, "nBotId")
				all[#all + 1] = { half = half, self = is_self, champ = self:champ_of_bot(bot), bot = bot }
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
	return { me = me, allies = allies, members = all }
end

-- Full read (protected). Returns the new state.
function DET:read()
	local pc = tempest.local_player()
	local st = { status = "idle", allies = {}, enemies = {}, at = os.clock() }
	if not pc then
		st.status = "no_player"
		return st
	end
	st.map = map_of(pc)
	if st.map and DET.IDLE_MAPS[st.map] then
		st.status = "lobby"
		local cs = self:read_champ_select(pc)
		if cs and (cs.me or #cs.allies > 0) then
			st.status, st.me, st.allies, st.source = "champ_select", cs.me, cs.allies, "MatchMembers"
		end
		return st
	end
	local wi = get(pc, "WorldInfo")
	local gri = get(wi, "GRI")
	-- 0.5.1: end of match / world teardown: stop walking pawns and PRIs (they are being destroyed).
	if not gri or get(gri, "bMatchIsOver") == true then
		st.status = "match_over"
		self.by_pri = {}
		return st
	end
	st.gri_class = class_name(gri)
	st.mode, st.mode_rule = self:guess_mode(st.map, st.gri_class)
	local elapsed = get(gri, "ElapsedTime")
	if type(elapsed) == "number" then
		st.elapsed = elapsed
		st.phase = self.pred:phase_for_elapsed(elapsed)
	end
	st.me = self:champ_of_pawn(get(pc, "Pawn"))
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
	local ok, st = pcall(self.read, self)
	if not ok then
		self.errors = self.errors + 1
		self.last_error = tostring(st)
		return self.state, false
	end
	local changed = self:signature(st) ~= self:signature(self.state)
	self.state = st
	return st, changed
end

function DET:signature(st)
	return table.concat({ st.status or "", st.me or "", st.mode or "", st.phase or "",
		table.concat(st.allies or {}, ","), table.concat(st.enemies or {}, ",") }, "|")
end

-- Diagnostic report (`smartcounter_probe` command): what each source really answers.
function DET:probe()
	local L = {}
	local function add(fmt, ...) L[#L + 1] = string.format(fmt, ...) end
	local pc = tempest.local_player()
	add("tempest %s, arch %s", tostring(tempest.version), tostring(try(function() return tempest.status().arch end)))
	if not pc then
		add("pas de PlayerController local")
		return L
	end
	local wi = get(pc, "WorldInfo")
	add("map = %s  (WorldInfo %s)", tostring(map_of(pc)), tostring(wi and try(function() return wi:path() end)))
	local gri = get(wi, "GRI")
	add("GRI = %s  ElapsedTime=%s RemainingTime=%s", tostring(class_name(gri)),
		tostring(get(gri, "ElapsedTime")), tostring(get(gri, "RemainingTime")))
	add("Game (local uniquement) = %s", tostring(class_name(get(wi, "Game"))))
	local mode, rule = self:guess_mode(map_of(pc), class_name(gri))
	add("mode deviné = %s (%s)", tostring(mode), tostring(rule))
	local pawn = get(pc, "Pawn")
	add("pawn local = %s -> %s", tostring(class_name(pawn)), tostring(self:champ_of_pawn(pawn)))
	local my_pri = get(pc, "PlayerReplicationInfo")
	add("mon PRI = %s, task force = %s", tostring(class_name(my_pri)), tostring(my_pri and task_force(my_pri)))
	if my_pri then
		for _, f in ipairs(DET.PRI_BOT_FIELDS) do
			if try(function() return my_pri:has(f) end) then add("  PRI.%s = %s", f, tostring(get(my_pri, f))) end
		end
	end
	local list = get(gri, "PRIArray")
	add("PRIArray : %s entrée(s)", tostring(list and try(function() return #list end)))
	if list then
		local my_tf = my_pri and task_force(my_pri)
		try(function()
			for i, pri in list:items() do
				local pw = get(pri, "r_PawnOwner")
				add("  %d. %s tf=%s équipe=%s pawn=%s champ=%s", i, tostring(class_name(pri)),
					tostring(task_force(pri)), tostring(team_of(pri, my_tf)), tostring(class_name(pw)),
					tostring(self:champ_of_pri(pri)))
			end
		end)
	end
	local cs = self:read_champ_select(pc)
	if cs then
		add("sélection : moi=%s alliés=%s", tostring(cs.me), table.concat(cs.allies, ","))
		for i, m in ipairs(cs.members) do
			add("  membre %d : moitié %s soi=%s nBotId=%s -> %s", i, tostring(m.half), tostring(m.self),
				tostring(m.bot), tostring(m.champ))
		end
	else
		add("sélection : MatchMembers indisponible")
	end
	add("erreurs de lecture : %d (%s)", self.errors, tostring(self.last_error))
	return L
end

return DET
