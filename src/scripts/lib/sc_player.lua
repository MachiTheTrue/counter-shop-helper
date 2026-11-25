-- SmartCounter 8.1: the local player's owned shop items and ranks (live, read-only).
--
-- 0.5.2: real 8.1 paths, taken from the TgGame.upk script table (Tools\...\upk.exe ls, kept in
-- Work\Extracted\8.1.5839.0\upk\TgGame_ls.txt). Shop items are devices: DATA_SET_ITEMS.ITEM_ID equals
-- DATA_SET_DEVICES.DEVICE_ID (Resilience 11683), so every source below maps through DATA item ids.
--
--   1. PRI.r_PlayerDevices        static array of DeviceTeamInfo { Power, Level, CurrentDeviceId,
--                                  LastKnownDeviceId, CurrentDeviceCount, LastKnownDeviceCount }
--                                  (replicated: what the scoreboard shows; primary source)
--   2. Pawn.InvManager chain      TgInventoryObject.m_InventoryData { nInvId, nItemId, nPower, nLevel, ... }
--   3. PC.r_LastPurchasedItems    static array of TG_LAST_PURCHASE { nItemId, nCount }
--   4. PRI.r_TempItems            static array of TempItemInfo { nDevId, nRank, nCost } (purchases of
--                                  the current shop visit, can be undone: fallback only)
--   5. 0.5 heuristics             id / rank field names on inventory objects and replicated lists
--
-- A static array is read through its first element (a Struct view): the element layout is checked
-- against the named fields of that element before any raw read, and every raw read is bounds-checked
-- with memory.readable. A source counts as "available" once its layout is verified, even with no item
-- bought yet: the tracker then shows "live" instead of the manual editor.
-- `smartcounter_items` logs every candidate with its live values; `smartcounter_items_watch` logs each
-- change (buy Bulldozer I, then II, and compare the lines).

local PL = {}
PL.__index = PL
PL.INTERVAL = 1.0
PL.MAX_ELEMS = 16      -- static array bound when its dimension cannot be read
PL.MAX_CHAIN = 64

-- Static struct arrays: field -> default byte offset (declaration order, 4-byte ints).
PL.ARRAYS = {
	{ key = "devices", holder = "pri", field = "r_PlayerDevices", id = "CurrentDeviceId", rank = "Level",
		layout = { Power = 0, Level = 4, CurrentDeviceId = 8, LastKnownDeviceId = 12, CurrentDeviceCount = 16,
			LastKnownDeviceCount = 20 } },
	{ key = "last_purchased", holder = "pc", field = "r_LastPurchasedItems", id = "nItemId", count = "nCount",
		layout = { nItemId = 0, nCount = 4 } },
	{ key = "temp_items", holder = "pri", field = "r_TempItems", id = "nDevId", rank = "nRank",
		layout = { nDevId = 0, nRank = 4, nCost = 8 } },
}

PL.ID_FIELDS = { "m_nItemId", "r_nItemId", "ItemId", "m_ItemId", "m_nDeviceId", "r_nDeviceId", "DeviceId",
	"m_DeviceId", "r_nInventoryId", "m_nId" }
PL.RANK_FIELDS = { "r_nLevel", "m_nLevel", "r_nUpgradeLevel", "m_nUpgradeLevel", "r_nItemLevel", "m_nItemLevel",
	"r_nRank", "m_nRank", "m_nStackCount", "Level" }
PL.LIST_FIELDS = { "r_PurchasedItems", "r_Items", "r_ItemIds", "m_Items", "r_EquippedItems", "r_InventoryItems" }

local function try(f, ...)
	local ok, v = pcall(f, ...)
	if ok then return v end
	return nil
end
local function get(obj, field)
	if obj == nil then return nil end
	return try(function() return obj[field] end)
end
local function has(obj, field)
	return obj ~= nil and try(function() return obj:has(field) end) == true
end
local function class_name(obj)
	return obj and try(function() return obj:class():name() end)
end
local MEM = rawget(_G, "memory")
local function readable(addr, len)
	if not MEM or type(addr) ~= "number" or addr == 0 then return false end
	if MEM.readable then return try(MEM.readable, addr, len) == true end
	return true
end
local function rd32(addr)
	if not readable(addr, 4) then return nil end
	return try(MEM.read_i32, addr)
end

function PL.new(DATA)
	local self = setmetatable({ by_id = {}, by_class = {}, next_at = 0, errors = 0, watch = false,
		layouts = {}, last_raw = nil,
		state = { source = nil, available = false, owned = {}, ranks_known = false } }, PL)
	local function add_class(c, name)
		local cls = c:match("([^%.]+)$") or c
		if not cls:find("^TgInvListener_") and not self.by_class[cls] then self.by_class[cls] = name end
	end
	for name, it in pairs(DATA.items) do
		if it.item_id then self.by_id[it.item_id] = name end
		for _, a in ipairs(it.alias_ids or {}) do
			if not self.by_id[a] then self.by_id[a] = name end
		end
		if it.inv_class then add_class(it.inv_class, name) end
		for _, c in ipairs(it.alias_inv or {}) do add_class(c, name) end
	end
	return self
end

-- ------------------------------------------------------------------ static struct arrays
-- Number of elements of a static array property: UProperty.ArrayDim sits right before ElementSize.
local function array_dim(info, esz)
	if not info or not info.ptr or info.ptr == 0 then return nil end
	for off = 0x28, 0x90, 4 do
		if rd32(info.ptr + off) == esz then
			local dim = rd32(info.ptr + off - 4)
			if dim and dim >= 1 and dim <= 64 then return dim end
		end
	end
	return nil
end

-- Verifies (or finds) the byte offset of every int field of element 0, from its named values.
local function verify_layout(first, base, esz, layout)
	local out, ok_all = {}, true
	for name, off in pairs(layout) do
		local want = get(first, name)
		if type(want) ~= "number" then return nil, "field " .. name .. " unreadable" end
		if off + 4 <= esz and rd32(base + off) == want then
			out[name] = off
		else
			ok_all = false
			local hit
			for o = 0, esz - 4, 4 do
				if rd32(base + o) == want then
					if hit then hit = nil break end   -- ambiguous
					hit = o
				end
			end
			if not hit then return nil, "offset of " .. name .. " not found" end
			out[name] = hit
		end
	end
	return out, ok_all and "default" or "derived"
end

-- Elements of a static struct array as plain tables { field = value }. Returns elems, info.
function PL:read_array(holder, spec)
	if not has(holder, spec.field) then return nil, "absent" end
	local v = get(holder, spec.field)
	if v == nil then return nil, "nil" end
	local elems = {}
	-- Case 1: exposed as a Lua sequence / Array.
	local n = try(function() return #v end)
	if type(n) == "number" and n > 0 and try(function() return v[1] end) ~= nil then
		for i = 1, math.min(n, PL.MAX_ELEMS * 2) do
			local e = try(function() return v[i] end)
			if e ~= nil then
				local row = {}
				for name in pairs(spec.layout) do row[name] = get(e, name) end
				elems[#elems + 1] = row
			end
		end
		return elems, "sequence(" .. n .. ")"
	end
	-- Case 2: a Struct view of element 0 + raw reads with a verified layout.
	local base = try(function() return v:addr() end)
	local esz = try(function() return v:size() end)
	local info = try(function() return holder:prop(spec.field) end)
	if (not base or base == 0) and info and info.offset then
		local p = try(function() return holder:ptr() end)
		base = p and (p + info.offset) or nil
	end
	if not base or not esz or esz <= 0 or esz > 256 then return nil, "no struct view" end
	local cache = self.layouts[spec.key]
	if not cache or cache.esz ~= esz then
		local offs, how = verify_layout(v, base, esz, spec.layout)
		if not offs then return nil, "layout: " .. tostring(how) end
		local dim = array_dim(info, esz)
		if not dim and info and info.size and info.size > esz and info.size % esz == 0 then dim = math.floor(info.size / esz) end
		cache = { esz = esz, offs = offs, how = how, dim = dim }
		self.layouts[spec.key] = cache
	end
	local count = math.min(cache.dim or PL.MAX_ELEMS, PL.MAX_ELEMS * 2)
	for i = 0, count - 1 do
		local a = base + i * esz
		if not readable(a, esz) then break end
		local row = {}
		for name, off in pairs(cache.offs) do row[name] = rd32(a + off) end
		elems[#elems + 1] = row
	end
	return elems, string.format("struct %dB x %s (%s layout)", esz, cache.dim and tostring(cache.dim) or
		("<=" .. PL.MAX_ELEMS), cache.how)
end

-- Rank from a level value: 1..3 as is; 0 on a known item means the field is 0-based.
local function to_rank(v, zero_based)
	if type(v) ~= "number" then return nil end
	v = math.floor(v) + (zero_based and 1 or 0)
	if v < 1 then return nil end
	return math.min(3, v)
end

-- owned { name = rank } from array elements; nil when nothing could be read.
function PL:owned_from(elems, spec)
	local owned, zero = {}, false
	if spec.rank then
		for _, e in ipairs(elems) do
			if self.by_id[e[spec.id]] and e[spec.rank] == 0 then zero = true end
		end
	end
	local ranks_known = false
	for _, e in ipairs(elems) do
		local name = self.by_id[e[spec.id]]
		if name then
			local r
			if spec.rank then r = to_rank(e[spec.rank], zero) end
			if r then ranks_known = true end
			if not r and spec.count then r = to_rank(e[spec.count], false) end
			owned[name] = math.max(owned[name] or 0, r or 1)
		end
	end
	return owned, ranks_known, zero
end

-- ------------------------------------------------------------------ inventory objects
function PL:item_of(obj)
	local data = get(obj, "m_InventoryData")
	local id = data and get(data, "nItemId")
	if type(id) == "number" and self.by_id[id] then return self.by_id[id], "m_InventoryData", data end
	for _, f in ipairs(PL.ID_FIELDS) do
		if has(obj, f) then
			local v = get(obj, f)
			if type(v) == "number" and self.by_id[v] then return self.by_id[v], "id:" .. f end
		end
	end
	local cn = class_name(obj)
	if cn and self.by_class[cn] then return self.by_class[cn], "class" end
	return nil
end

local function rank_of(obj, data)
	if data then
		local r = to_rank(get(data, "nLevel"), false)
		if r then return r, "nLevel" end
	end
	for _, f in ipairs(PL.RANK_FIELDS) do
		if has(obj, f) then
			local r = to_rank(get(obj, f), false)
			if r then return r, f end
		end
	end
	return nil
end

function PL:from_inventory(pawn)
	local inv = get(pawn, "InvManager")
	local cur = get(inv, "InventoryChain")
	if not cur then return nil end
	local owned, n, ranks_known = {}, 0, false
	while cur and n < PL.MAX_CHAIN do
		n = n + 1
		local name, _, data = self:item_of(cur)
		if name then
			local r = rank_of(cur, data)
			if r then ranks_known = true end
			owned[name] = math.max(owned[name] or 0, r or 1)
		end
		cur = get(cur, "Inventory")
	end
	return owned, ranks_known
end

function PL:from_lists(...)
	for _, holder in ipairs({ ... }) do
		for _, f in ipairs(PL.LIST_FIELDS) do
			if has(holder, f) then
				local arr = get(holder, f)
				local owned, any = {}, false
				try(function()
					for _, e in arr:items() do
						local name = type(e) == "number" and self.by_id[e] or self:item_of(e)
						if name then owned[name], any = math.max(owned[name] or 0, 1), true end
					end
				end)
				if any then return owned, f end
			end
		end
	end
	return nil
end

-- ------------------------------------------------------------------ read / poll
local function holders()
	local pc = tempest.local_player()
	return { pc = pc, pri = get(pc, "PlayerReplicationInfo"), pawn = get(pc, "Pawn") }
end

function PL:read()
	local h = holders()
	local out = { source = nil, available = false, owned = {}, ranks_known = false, raw = {} }
	if not h.pc or (not h.pri and not h.pawn) then return out end
	-- 1. replicated device slots (primary), 3. last purchases, 4. temp items: all read, first usable wins
	local found = {}
	for _, spec in ipairs(PL.ARRAYS) do
		local holder = h[spec.holder]
		local elems = holder and self:read_array(holder, spec)
		if elems then
			local owned, rk = self:owned_from(elems, spec)
			found[spec.key] = { owned = owned, ranks_known = rk, n = #elems }
			local parts = {}
			for _, e in ipairs(elems) do
				local id = e[spec.id]
				if type(id) == "number" and id ~= 0 then
					parts[#parts + 1] = string.format("%d:%s", id, tostring(e[spec.rank or spec.count]))
				end
			end
			out.raw[#out.raw + 1] = spec.field .. "=" .. table.concat(parts, ",")
		end
	end
	local function take(src, owned, rk)
		out.source, out.available, out.ranks_known = src, true, rk
		for k, v in pairs(owned) do out.owned[k] = v end
	end
	local dev = found.devices
	if dev then
		take("PRI.r_PlayerDevices", dev.owned, dev.ranks_known)
	else
		local inv_owned, inv_rk = self:from_inventory(h.pawn)
		if inv_owned and next(inv_owned) then
			take("InvManager", inv_owned, inv_rk)
		elseif found.last_purchased and next(found.last_purchased.owned) then
			take("PC.r_LastPurchasedItems", found.last_purchased.owned, false)
		elseif found.temp_items and next(found.temp_items.owned) then
			take("PRI.r_TempItems", found.temp_items.owned, found.temp_items.ranks_known)
		else
			local lo, f = self:from_lists(h.pri, h.pawn)
			if lo then take("list:" .. f, lo, false) end
		end
	end
	-- an in-progress shop visit can be ahead of the replicated slots: keep the higher rank
	local tmp = found.temp_items
	if dev and tmp then
		for k, v in pairs(tmp.owned) do
			if (out.owned[k] or 0) < v and tmp.ranks_known then out.owned[k] = v end
		end
	end
	return out
end

local function sig(s)
	local names = {}
	for n in pairs(s.owned) do names[#names + 1] = n .. "=" .. s.owned[n] end
	table.sort(names)
	return (s.source or "") .. "|" .. table.concat(names, ",")
end

-- Every frame; real work at most every INTERVAL (or at once after `refresh`). Returns state, changed.
function PL:poll(now, log)
	now = now or os.clock()
	if now < self.next_at then return self.state, false end
	self.next_at = now + PL.INTERVAL
	local ok, st = pcall(self.read, self)
	if not ok then
		self.errors = self.errors + 1
		self.last_error = tostring(st)
		return self.state, false
	end
	local changed = sig(st) ~= sig(self.state)
	if self.watch and log then
		local raw = table.concat(st.raw or {}, " ; ")
		if changed or raw ~= self.last_raw then
			log("items watch: source=%s owned={%s} raw: %s", tostring(st.source), sig(st):match("|(.*)$") or "", raw)
		end
		self.last_raw = raw
	end
	self.state = st
	return st, changed
end

function PL:refresh()
	self.next_at = 0
end

-- ------------------------------------------------------------------ diagnostics
-- `smartcounter_items`: every candidate property with its live values.
function PL:probe()
	local L = {}
	local function add(fmt, ...) L[#L + 1] = string.format(fmt, ...) end
	local h = holders()
	add("items: pc=%s pri=%s pawn=%s memory=%s", tostring(class_name(h.pc)), tostring(class_name(h.pri)),
		tostring(class_name(h.pawn)), MEM and "yes" or "no")
	for _, spec in ipairs(PL.ARRAYS) do
		local holder = h[spec.holder]
		local info = holder and try(function() return holder:prop(spec.field) end)
		add("  %s.%s: prop=%s", spec.holder, spec.field, info and string.format("kind=%s size=%s offset=%s ext=%s",
			tostring(info.kind), tostring(info.size), tostring(info.offset), tostring(info.ext_name)) or "absent")
		if holder then
			self.layouts[spec.key] = nil   -- re-verify on demand
			local elems, how = self:read_array(holder, spec)
			add("    read: %s", tostring(how))
			for i, e in ipairs(elems or {}) do
				local f = {}
				for name in pairs(spec.layout) do f[#f + 1] = name .. "=" .. tostring(e[name]) end
				table.sort(f)
				local id = e[spec.id]
				if (type(id) == "number" and id ~= 0) or i <= 2 then
					add("    [%d] %s -> %s", i, table.concat(f, " "), tostring(self.by_id[id]))
				end
			end
		end
	end
	local inv = get(h.pawn, "InvManager")
	add("  InvManager=%s r_ItemCount=%s", tostring(class_name(inv)), tostring(get(inv, "r_ItemCount")))
	local cur, n = get(inv, "InventoryChain"), 0
	while cur and n < PL.MAX_CHAIN do
		n = n + 1
		local data = get(cur, "m_InventoryData")
		local d = data and string.format("nItemId=%s nLevel=%s nPower=%s nInstanceCount=%s", tostring(get(data, "nItemId")),
			tostring(get(data, "nLevel")), tostring(get(data, "nPower")), tostring(get(data, "nInstanceCount"))) or "-"
		local name, how = self:item_of(cur)
		add("    inv %d. %s %s stack=%s -> %s (%s)", n, tostring(class_name(cur)), d, tostring(get(cur, "m_nStackCount")),
			tostring(name), tostring(how))
		cur = get(cur, "Inventory")
	end
	local st = self:read()
	local owned = {}
	for k, v in pairs(st.owned) do owned[#owned + 1] = k .. " " .. v end
	table.sort(owned)
	add("items: source=%s available=%s ranks_known=%s owned={%s} errors=%d (%s)", tostring(st.source),
		tostring(st.available), tostring(st.ranks_known), table.concat(owned, ", "), self.errors, tostring(self.last_error))
	return L
end

return PL
