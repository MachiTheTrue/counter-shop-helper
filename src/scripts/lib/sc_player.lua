-- Counter & Shop Helper: the local player's shop items and their ranks (read-only, reflection only).
--
-- Read from the local player's TgRepInfo_Player (TgGame.upk declarations), the path checked live in
-- 8.1 matches (Siege, TDM, practice):
--   * r_PlayerDevices (DeviceTeamInfo { CurrentDeviceId, Level, ... }, the scoreboard's slots): the deck
--     cards and the shop items, so which items are owned. Its Level is the cards' level: a shop item
--     stays at 0 whatever its rank, so it is not a rank.
--   * r_TempItems (TempItemInfo { nDevId, nRank, nCost }): the match's shop items with their rank.
-- Their entries are structs: fields are read directly (a struct has no has(), see lib/sc_game.lua).
-- The pawn's InvManager.InventoryChain is not read: the client never gets it in a match.
--
-- Shop items are devices: DATA_SET_ITEMS.ITEM_ID equals the device id (Resilience 11683). An item can
-- have several ids in the game data (old card row + shop row): sc_data.lua lists them as alias_ids.
--
-- Counting: the declarations do not say whether nRank counts from 0 or from 1, so it is learnt: an
-- owned item is at least rank I, so a 0 means "counts from 0"; a value equal to the max rank means
-- "counts from 1". Until one of them is seen, values count from 1.
--
-- While the player is dead the last read is kept until the items are back, on the same map only
-- (WorldInfo), so nothing is kept from one game to the next. Nothing is read through raw memory: when
-- nothing answers, the Match tab offers the manual editor.

local PL = {}
PL.__index = PL
PL.INTERVAL = 1.0   -- seconds between two reads (PL:refresh forces the next one)
PL.MAX_LIST = 64    -- r_PlayerDevices has 49 slots in 8.1

local G = require("lib.sc_game")
local get = G.field

function PL.new(DATA, log)
	local by_id = {}
	for name, it in pairs(DATA.items) do
		if it.item_id then by_id[it.item_id] = name end
		for _, a in ipairs(it.alias_ids or {}) do
			if not by_id[a] then by_id[a] = name end
		end
	end
	return setmetatable({
		by_id = by_id,              -- item / device id -> item key
		max_rank = DATA.max_rank,
		base = nil,                 -- 0 or 1 once learnt (how nRank counts), nil = counts from 1
		log = log,                  -- optional log(fmt, ...) for the raw values
		no_list = {},               -- "<PRI class>.<array>" -> true when that array cannot be listed
		raw_sig = nil,              -- last raw values written to the log
		last_why = nil,             -- last "what was read" written to the log
		logged_error = nil,         -- last read error written to the log
		next_at = 0,
		errors = 0,
		last_error = nil,
		state = { source = nil, available = false, owned = {} },
	}, PL)
end

-- Rank 1..max per item from the raw nRank values of one read ({ item = raw }); learns the counting.
function PL:ranks_of(raw)
	for _, v in pairs(raw) do
		if v <= 0 then self.base = 0 break end
		if v >= self.max_rank then self.base = self.base or 1 end
	end
	local shift = self.base == 0 and 1 or 0
	local owned = {}
	for name, v in pairs(raw) do
		owned[name] = math.max(1, math.min(self.max_rank, v + shift))
	end
	return owned
end

local function level(v)
	return type(v) == "number" and math.floor(v) or nil
end

-- A replicated array of the player's TgRepInfo_Player: (array, count), or nil when it is not there or
-- cannot be listed (then it is not asked again for that class). min = fewest entries of a real list.
function PL:pri_list(pri, field, min)
	if G.is_a(pri, "TgGame.TgRepInfo_Player") ~= true then return nil end   -- the lobby's PRI has none
	local key = tostring(G.class_name(pri)) .. "." .. field
	if self.no_list[key] then return nil end
	local arr = get(pri, field)
	local count = (type(arr) == "table" or type(arr) == "userdata") and #arr or nil
	if type(count) ~= "number" or count < min then
		self.no_list[key] = true
		return nil
	end
	return arr, math.min(count, PL.MAX_LIST)
end

-- Which items the scoreboard slots list: { item = true }, nil when they cannot be listed.
function PL:slot_items(pri)
	local slots, count = self:pri_list(pri, "r_PlayerDevices", 2)   -- 1 = a lone struct view, not a list
	if not slots then return nil end
	local items = {}
	for i = 1, count do
		local name = slots[i] and self.by_id[get(slots[i], "CurrentDeviceId")]
		if name then items[name] = true end
	end
	return items
end

-- The match's shop items with their raw rank: { item = nRank }, nil when they cannot be listed.
function PL:temp_ranks(pri)
	local arr, count = self:pri_list(pri, "r_TempItems", 0)
	if not arr then return nil end
	local raw = {}
	for i = 1, count do
		local name = arr[i] and self.by_id[get(arr[i], "nDevId")]
		local r = name and level(get(arr[i], "nRank"))
		if r then raw[name] = math.max(raw[name] or r, r) end
	end
	return raw
end

-- owned { item = rank }: the items the slots list (else, without slots, the shop items), each at its
-- shop rank (rank I without one). nil when neither can be listed. Second value: the source read.
-- Only owned items teach the counting: a sold item can stay in r_TempItems.
function PL:from_devices(pri)
	local items, temp = self:slot_items(pri), self:temp_ranks(pri)
	if not items and not temp then return nil end
	local raw = {}
	for name, r in pairs(temp or {}) do
		if not items or items[name] then raw[name] = r end
	end
	local ranks = self:ranks_of(raw)
	local owned = {}
	for name in pairs(items or raw) do owned[name] = ranks[name] or 1 end
	self:raw_log(owned, temp)
	return owned, temp and "PRI.r_PlayerDevices + r_TempItems" or "PRI.r_PlayerDevices"
end

-- One log line when the raw values change: the shop rank the game gave and the rank kept.
function PL:raw_log(owned, temp)
	if not self.log then return end
	local names, parts = {}, {}
	for name in pairs(owned) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		parts[#parts + 1] = string.format("%s=%d (shop rank %s)", name, owned[name],
			temp and temp[name] ~= nil and tostring(temp[name]) or "-")
	end
	local sig = table.concat(parts, "; ")
	if sig == self.raw_sig then return end
	self.raw_sig = sig
	self.log("items [PRI]: %s", #parts > 0 and sig or "none")
end

-- Returns { source, available, owned, world }, plus `missing = "player" | "pawn" | "items"` when there
-- was nothing to read.
function PL:read()
	local pc = tempest.local_player()
	if not pc then return { available = false, owned = {}, missing = "player" } end
	local out = { available = false, owned = {}, world = G.ptr(get(pc, "WorldInfo")) }
	local owned, source = self:from_devices(get(pc, "PlayerReplicationInfo"))
	if owned then
		out.available, out.owned, out.source = true, owned, source
	else
		out.missing = get(pc, "Pawn") and "items" or "pawn"
	end
	return out
end

local function signature(s)
	local parts = {}
	for name, rank in pairs(s.owned) do parts[#parts + 1] = name .. "=" .. rank end
	table.sort(parts)
	return (s.source or "") .. "|" .. table.concat(parts, ",")
end

-- Every frame; real work at most every INTERVAL. Returns the state and true when it changed.
function PL:poll(now)
	if now < self.next_at then return self.state, false end
	self.next_at = now + PL.INTERVAL
	local ok, st = pcall(self.read, self)   -- an object destroyed between two reads (map change)
	if not ok then
		self.errors = self.errors + 1
		self.last_error = tostring(st)
		if self.log and self.last_error ~= self.logged_error then   -- once per different error
			self.logged_error = self.last_error
			self.log("items: read failed: %s", self.last_error)
		end
		return self.state, false
	end
	if not st.available and st.missing == "pawn" and self.state.available and st.world == self.state.world then
		return self.state, false   -- dead or respawning on this map: keep the items read before
	end
	self:why_log(st)
	local changed = signature(st) ~= signature(self.state)
	self.state = st
	return st, changed
end

local WHY = {
	player = "nothing to read: no local player",
	pawn = "nothing to read: no character (lobby, dead, spectating)",
	items = "nothing to read: the player info lists no shop items",
}

-- One log line when what can be read changes (live source, or why there is nothing to read).
function PL:why_log(st)
	local why = st.available and ("live from the game (" .. tostring(st.source) .. ")")
		or WHY[st.missing or ""] or "nothing to read"
	if why == self.last_why then return end
	self.last_why = why
	if self.log then self.log("items: %s", why) end
end

function PL:refresh()
	self.next_at = 0
end

return PL
