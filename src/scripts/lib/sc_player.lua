-- Counter & Shop Helper: the local player's shop items and their ranks (read-only, reflection only).
--
-- Field names come from the 8.1 script tables (TgGame.upk / Engine.upk, listed with upk.exe). Shop
-- items are devices: DATA_SET_ITEMS.ITEM_ID equals the device id (Resilience 11683). An item can have
-- several ids in the game data (old card row + shop row): sc_data.lua lists them as alias_ids.
--
-- What a live 8.1 match shows (Match tab diagnostic, Siege / TDM, Win64 client):
--   * Pawn.InvManager.InventoryChain is not replicated to the client: in a match the chain is empty.
--     It is still read when it exists (practice maps, other clients): each object is the item's
--     TgDevice (a TgInventoryObject) with m_InventoryData { nItemId, nLevel } and r_nDeviceLevel.
--   * TgRepInfo_Player.r_PlayerDevices (DeviceTeamInfo { CurrentDeviceId, CurrentDeviceCount, Level,
--     ... }, the scoreboard's slots) lists the deck cards and the shop items: it says which items are
--     owned. Its Level is the cards' level (a card at 5); a shop item stays at 0 whatever its rank, so
--     it is not read as a rank (it made every item look like rank I).
--   * TgRepInfo_Player.r_TempItems (TempItemInfo { nDevId, nRank, nCost }): the match's shop items
--     with their rank. This is where the rank comes from.
--
-- Which items: the chain when it exists, else the slots (else, without a slot list, the shop items).
-- Which rank: the highest of the sources for that item, each turned into a rank on its own:
--   temp  r_TempItems[].nRank
--   dev   TgDevice.r_nDeviceLevel   (chain only; set by ChangeDeviceLevel)
--   inv   m_InventoryData.nLevel    (chain only; the purchase record, stays at the rank bought)
-- An owned item's rank never goes down (selling removes it), so a stale source can only be lower.
-- Nothing is read through raw memory: when no source answers, the Match tab offers the manual editor.
--
-- Lookups: Tempest logs every read of a property the object's class does not declare, so a field is
-- read only on a class that has it (is_a): the PRI arrays on TgRepInfo_Player (the lobby's PRI is a
-- plain Engine PlayerReplicationInfo), device fields on TgDevice. An array that cannot be listed is
-- not asked again for that class. Raw values are written to the log when they change (a purchase, an
-- upgrade, a sale), never at every read.
--
-- Counting: each item's max rank comes from the data (`ranks`, one device mode per rank in the game
-- tables). The declarations do not say whether a rank counts from 0 or from 1, so it is learnt per
-- source: an owned item is at least rank I, so a 0 means "counts from 0"; a value equal to the item's
-- max rank means "counts from 1". Until one of them is seen, values count from 1.
--
-- While the player is dead there is no pawn: the last read is kept until the pawn is back (otherwise
-- the plan would switch to the manual items at every death), but only on the same map (WorldInfo), so
-- nothing is kept from one game to the next.

local PL = {}
PL.__index = PL
PL.INTERVAL = 1.0   -- seconds between two reads (PL:refresh forces the next one)
PL.MAX_CHAIN = 64   -- a pawn holds a few dozen inventory objects at most
PL.MAX_LIST = 64    -- r_PlayerDevices has 49 slots in 8.1

local function try(f, ...)
	local ok, v = pcall(f, ...)
	if ok then return v end
	return nil
end

local function get(obj, field)
	if obj == nil then return nil end
	return try(function() return obj[field] end)
end

-- What a set of raw values says about the counting: 0 (a 0 is seen), 1 (a value reaches the max
-- rank) or nil (nothing conclusive). levels = { { raw, max }, ... }.
local function base_from(levels)
	local base
	for _, x in ipairs(levels) do
		if x[1] <= 0 then return 0 end
		if x[1] >= x[2] then base = 1 end
	end
	return base
end
PL.base_from = base_from

function PL.new(DATA, log)
	local by_id = {}
	local max_rank = {}
	for name, it in pairs(DATA.items) do
		max_rank[name] = tonumber(it.ranks) or 3
		if it.item_id then by_id[it.item_id] = name end
		for _, a in ipairs(it.alias_ids or {}) do
			if not by_id[a] then by_id[a] = name end
		end
	end
	return setmetatable({
		by_id = by_id,     -- item / device id -> item key
		max_rank = max_rank, -- item key -> max shop rank
		bases = {},        -- source ("temp" / "dev" / "inv") -> 0 or 1 once learnt, absent = counts from 1
		log = log,         -- optional log(fmt, ...) for the raw values
		no_list = {},      -- "<PRI class>.<array>" -> true when that array cannot be listed
		raw_sig = nil,     -- last raw values written to the log
		last_why = nil,    -- last "what was read" written to the log (live source or why nothing)
		logged_error = nil, -- last read error written to the log
		polls = 0,         -- reads done (shown by describe)
		next_at = 0,
		errors = 0,
		last_error = nil,
		state = { source = nil, available = false, owned = {} },
	}, PL)
end

-- Rank 1..max per item from the raw values one source gave in one read ({ item = raw }).
function PL:ranks_of(raw, src)
	src = src or "inv"
	local levels = {}
	for name, v in pairs(raw) do
		levels[#levels + 1] = { v, self.max_rank[name] or 3 }
	end
	local b = base_from(levels)
	if b ~= nil then self.bases[src] = b end
	local shift = self.bases[src] == 0 and 1 or 0
	local owned = {}
	for name, v in pairs(raw) do
		owned[name] = math.max(1, math.min(self.max_rank[name] or 3, v + shift))
	end
	return owned
end

local function level(v)
	return type(v) == "number" and math.floor(v) or nil
end

local function keep_max(t, name, v)
	if v then t[name] = math.max(t[name] or v, v) end
end

-- false only when the object answers is_a and is not of that class (mock tables have no is_a).
local function maybe_a(o, class)
	return try(function() return o:is_a(class) end) ~= false
end

local function class_of(o)
	return try(function() return o:class():name() end)
end

-- A replicated array of the player's TgRepInfo_Player: (array, count), or nil when it is not there or
-- cannot be listed (then it is not asked again for that class). min = fewest entries of a real list.
function PL:pri_list(pri, field, min)
	if not pri or not maybe_a(pri, "TgGame.TgRepInfo_Player") then return nil end
	local key = tostring(class_of(pri) or "?") .. "." .. field
	if self.no_list[key] then return nil end
	local arr = get(pri, field)
	local count = arr and try(function() return #arr end)
	if type(count) ~= "number" or count < (min or 0) then
		if class_of(pri) then self.no_list[key] = true end
		return nil
	end
	return arr, math.min(count, PL.MAX_LIST)
end

-- Raw levels of the inventory chain: items { item = true }, dev / inv / mode { item = raw }; nil
-- without a chain.
function PL:chain_levels(pawn)
	local cur = get(get(pawn, "InvManager"), "InventoryChain")
	if not cur then return nil end
	local items, dev, inv, mode, n = {}, {}, {}, {}, 0
	while cur and n < PL.MAX_CHAIN do
		n = n + 1
		local data = maybe_a(cur, "TgGame.TgInventoryObject") and get(cur, "m_InventoryData")
		local name = data and self.by_id[get(data, "nItemId")]
		if name then
			items[name] = true
			if maybe_a(cur, "TgGame.TgDevice") then
				keep_max(dev, name, level(get(cur, "r_nDeviceLevel")))
				keep_max(mode, name, level(get(cur, "CurrentFireMode")))   -- logged only
			end
			keep_max(inv, name, level(get(data, "nLevel")))
			if not self.chain_class then self.chain_class = class_of(cur) or "?" end
		end
		cur = get(cur, "Inventory")
	end
	return items, dev, inv, mode
end

-- The scoreboard slots: items { item = true }, levels and counts { item = raw } (logged only); nil
-- when they cannot be listed.
function PL:slot_info(pri)
	local slots, count = self:pri_list(pri, "r_PlayerDevices", 2)   -- 1 = a lone struct view, not a list
	if not slots then return nil end
	local items, lv, cnt = {}, {}, {}
	for i = 1, count do
		local slot = try(function() return slots[i] end)
		local name = slot and self.by_id[get(slot, "CurrentDeviceId")]
		if name then
			items[name] = true
			keep_max(lv, name, level(get(slot, "Level")))
			keep_max(cnt, name, level(get(slot, "CurrentDeviceCount")))
		end
	end
	return items, lv, cnt
end

-- The match's shop items with their rank: { item = raw nRank }, nil when they cannot be listed.
function PL:temp_ranks(pri)
	local arr, count = self:pri_list(pri, "r_TempItems", 0)
	if not arr then return nil end
	local raw = {}
	for i = 1, count do
		local e = try(function() return arr[i] end)
		local name = e and self.by_id[get(e, "nDevId")]
		if name then keep_max(raw, name, level(get(e, "nRank"))) end
	end
	return raw
end

-- owned { item = rank }: the items `items` lists, each at the highest rank a source gives (rank I
-- when no source has a value for it).
function PL:merge(items, sources)
	local owned = {}
	for name in pairs(items) do owned[name] = 1 end
	for _, s in ipairs(sources) do
		if s.raw then
			for name, r in pairs(self:ranks_of(s.raw, s.src)) do
				if owned[name] and r > owned[name] then owned[name] = r end
			end
		end
	end
	return owned
end

-- owned { item = rank } from the inventory chain (ranks from the shop items too), nil without a chain.
function PL:from_inventory(pawn, pri)
	local items, dev, inv, mode = self:chain_levels(pawn)
	if not items then return nil end
	local temp = pri and self:temp_ranks(pri)
	local _, slot_lv, slot_n
	if pri then _, slot_lv, slot_n = self:slot_info(pri) end
	local owned = self:merge(items, { { src = "temp", raw = temp }, { src = "dev", raw = dev }, { src = "inv", raw = inv } })
	self:raw_log(self.chain_class or "chain", owned,
		{ temp = temp, dev = dev, inv = inv, mode = mode, slot = slot_lv, count = slot_n })
	return owned
end

-- owned { item = rank } from the player info alone (a match: no chain on the client): the slots say
-- which items, the shop items their rank. nil when neither can be listed. Second value: true when the
-- shop items were read.
function PL:from_devices(pri)
	local items, slot_lv, slot_n = self:slot_info(pri)
	local temp = self:temp_ranks(pri)
	if not items then
		if not temp then return nil end
		items = {}
		for name in pairs(temp) do items[name] = true end
	end
	local owned = self:merge(items, { { src = "temp", raw = temp } })
	self:raw_log("PRI", owned, { temp = temp, slot = slot_lv, count = slot_n })
	return owned, temp ~= nil
end

-- One log line when the raw values change: what each field of the game said, and the rank kept.
function PL:raw_log(where, owned, f)
	if not self.log then return end
	local names, parts = {}, {}
	for name in pairs(owned) do names[#names + 1] = name end
	table.sort(names)
	local function v(t, name) return t and t[name] ~= nil and tostring(t[name]) or "-" end
	for _, name in ipairs(names) do
		parts[#parts + 1] = string.format("%s=%d (shop rank %s, dev %s, buy %s, slot level %s, slot count %s, mode %s)",
			name, owned[name], v(f.temp, name), v(f.dev, name), v(f.inv, name), v(f.slot, name), v(f.count, name),
			v(f.mode, name))
	end
	local sig = where .. "|" .. table.concat(parts, "; ")
	if sig == self.raw_sig then return end
	self.raw_sig = sig
	self.log("items [%s]: %s", where, #parts > 0 and table.concat(parts, "; ") or "none")
end

-- Returns { source, available, owned }, plus `missing = "player" | "pawn" | "chain"` when there was
-- nothing (or no chain) to read.
function PL:read()
	local pc = tempest.local_player()
	local out = { source = nil, available = false, owned = {} }
	if not pc then
		out.missing = "player"
		return out
	end
	local wi = get(pc, "WorldInfo")
	out.world = wi and try(function() return wi:ptr() end)
	local pawn = get(pc, "Pawn")
	if not pawn then out.missing = "pawn" end
	local pri = get(pc, "PlayerReplicationInfo")
	if pawn and not get(get(pawn, "InvManager"), "InventoryChain") then out.missing = "chain" end
	local owned = self:from_inventory(pawn, pri)
	if owned then
		out.source = "InvManager"
	else
		local with_temp
		owned, with_temp = self:from_devices(pri)
		if owned then out.source = with_temp and "PRI.r_PlayerDevices + r_TempItems" or "PRI.r_PlayerDevices" end
	end
	if owned then out.available, out.owned = true, owned end
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
	self.polls = self.polls + 1
	local ok, st = pcall(self.read, self)
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
	chain = "nothing to read: the character has no inventory",
}

-- One log line when what can be read changes (live source, or why there is nothing to read).
function PL:why_log(st)
	local why = st.available and ("live from the game (" .. tostring(st.source) .. ")")
		or WHY[st.missing or ""] or "nothing to read"
	if why == self.last_why then return end
	self.last_why = why
	if self.log then self.log("items: %s", why) end
end

-- What the reader sees right now, line by line, for the Match tab's diagnostic button (one call, one
-- block of log lines). Only declared fields are read (is_a first), like the reader itself.
function PL:describe(status)
	local out = {}
	local function add(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
	local function v(x) return x == nil and "-" or tostring(x) end
	add("diagnostic: status %s, reads %d, read errors %d%s", v(status), self.polls, self.errors,
		self.last_error and (" (last: " .. self.last_error .. ")") or "")
	local pc = tempest.local_player()
	if not pc then
		add("no local player")
		return out
	end
	local pawn, pri = get(pc, "Pawn"), get(pc, "PlayerReplicationInfo")
	local is_rep = pri and maybe_a(pri, "TgGame.TgRepInfo_Player")
	add("character %s, player info %s (TgRepInfo_Player: %s)", v(pawn and (class_of(pawn) or "?")),
		v(pri and (class_of(pri) or "?")), v(is_rep))
	local inv = get(pawn, "InvManager")
	local cur = get(inv, "InventoryChain")
	add("inventory manager %s, chain %s", v(inv and (class_of(inv) or "?")), cur and "yes" or "none")
	local n = 0
	while cur and n < PL.MAX_CHAIN do
		n = n + 1
		local is_obj, is_dev = maybe_a(cur, "TgGame.TgInventoryObject"), maybe_a(cur, "TgGame.TgDevice")
		local data = is_obj and get(cur, "m_InventoryData")
		local id = data and get(data, "nItemId")
		local dev, mode, dev_id
		if is_dev then dev, mode, dev_id = get(cur, "r_nDeviceLevel"), get(cur, "CurrentFireMode"), get(cur, "r_nDeviceId") end
		add("  #%d %s: item id %s (%s), buy level %s, device level %s, mode %s, device id %s", n, v(class_of(cur)),
			v(id), v(id and self.by_id[id]), v(data and get(data, "nLevel")), v(dev), v(mode), v(dev_id))
		cur = get(cur, "Inventory")
	end
	add("chain: %d object(s)", n)
	if is_rep then
		local slots = get(pri, "r_PlayerDevices")
		local count = slots and try(function() return #slots end)
		add("scoreboard slots (r_PlayerDevices): %s", type(count) == "number" and (count .. " listed") or "not a list")
		for i = 1, type(count) == "number" and math.min(count, PL.MAX_LIST) or 0 do
			local slot = try(function() return slots[i] end)
			local sid = slot and get(slot, "CurrentDeviceId")
			if sid and sid ~= 0 then
				add("  slot %d: device id %s (%s), level %s, count %s, last known %s x%s, power %s", i, v(sid),
					v(self.by_id[sid]), v(get(slot, "Level")), v(get(slot, "CurrentDeviceCount")),
					v(get(slot, "LastKnownDeviceId")), v(get(slot, "LastKnownDeviceCount")), v(get(slot, "Power")))
			end
		end
		local temp = get(pri, "r_TempItems")
		local tn = temp and try(function() return #temp end)
		add("shop items (r_TempItems): %s", type(tn) == "number" and (tn .. " listed") or "not a list")
		for i = 1, type(tn) == "number" and math.min(tn, PL.MAX_LIST) or 0 do
			local e = try(function() return temp[i] end)
			local did = e and get(e, "nDevId")
			if did and did ~= 0 then
				add("  shop item %d: device id %s (%s), rank %s, cost %s", i, v(did), v(self.by_id[did]),
					v(get(e, "nRank")), v(get(e, "nCost")))
			end
		end
		local undo = get(pri, "r_TempItemUndoQueue")
		local un = undo and try(function() return #undo end)
		add("shop undo queue (r_TempItemUndoQueue): %s", type(un) == "number" and (un .. " listed") or "not a list")
	end
	if pawn and maybe_a(pawn, "TgGame.TgPawn") then
		local eq = get(pawn, "r_EquipDeviceInfo")
		local en = eq and try(function() return #eq end)
		local shown, others = 0, 0
		for i = 1, type(en) == "number" and math.min(en, PL.MAX_LIST) or 0 do
			local e = try(function() return eq[i] end)
			local did = e and get(e, "nDeviceId")
			if did and self.by_id[did] then
				shown = shown + 1
				add("  equipped %d: device id %s (%s), mode %s", i, v(did), v(self.by_id[did]), v(get(e, "nMode")))
			elseif did and did ~= 0 then
				others = others + 1
			end
		end
		add("equipped devices (r_EquipDeviceInfo): %s, %d item(s), %d other(s)",
			type(en) == "number" and (en .. " listed") or "not a list", shown, others)
	end
	local kept = {}
	for name, r in pairs(self.state.owned or {}) do kept[#kept + 1] = name .. "=" .. r end
	table.sort(kept)
	add("kept: %s, source %s, items %s", self.state.available and "live" or "not live", v(self.state.source),
		#kept > 0 and table.concat(kept, ", ") or "none")
	add("counting learnt: shop rank %s, device %s, purchase %s (0 = from 0, 1 = from 1, - = not yet)",
		v(self.bases.temp), v(self.bases.dev), v(self.bases.inv))
	return out
end

function PL:refresh()
	self.next_at = 0
end


return PL
