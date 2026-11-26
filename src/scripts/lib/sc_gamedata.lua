-- Counter & Shop Helper: game facts from Tempest's Game Data API (assembly.dat, Tempest Scripting 1.1.0).
--
-- sc_data.lua holds the mod's own rules and the ids that tie them to the game: one bot id per
-- champion, one item id per shop item. What the game data knows about them is read here, once, when
-- the script loads (the quiet moment the API docs advise, about 70 ms), then the file is freed:
--   champion  role           the bot's "Roles" tag (BOTS.DATA_SET_BOT_TAGS)
--             name           BOTS.NAME_MSG_ID
--             ability names  BOTS.DATA_SET_BOT_DEVICES (per slot) -> DEVICES.NAME_MSG_ID
--   item      name, text     ITEMS.NAME_MSG_ID / DESC_MSG_ID
--             shop ranks     one device mode per rank (DEVICES.DATA_SET_DEVICE_MODES)
--   labels    role and shop-category names: Lang messages found by NAME (lang.find)
-- The results are set on the DATA tables the other modules read (c.role, c.name_msg, a.name_msg,
-- it.name_msg, it.desc_msg, it.ranks, D.max_rank, D.role_msg, D.category_msg). Message ids become text
-- in sc_text.lua (lang.message). All or nothing: a champion or item the game data does not have makes
-- load() return nil and the reason, and the mod stays off (main.lua).

local GD = {}

-- Game values used as query keys (8.1 DATA_SET_VALID_VALUES, checked on the 59 champions by
-- engine/extract_ids.py): the "Roles" tag type and its values, and the ability slots.
GD.ROLE_TAG_TYPE = 10591
GD.ROLE_TAGS = { [10542] = "Frontline", [10601] = "Damage", [10541] = "Flank", [15060] = "Support" }
GD.SLOTS = { [221] = "weapon", [199] = "a1", [200] = "a2", [996] = "a3", [198] = "ult" }
-- Lang message names of the labels the game's own UI shows for roles and shop categories.
GD.ROLE_MSG = { Frontline = "PALADINS_ARCHETYPE_TANK", Damage = "PALADINS_ARCHETYPE_DAMAGE",
	Flank = "PALADINS_ARCHETYPE_FLANK", Support = "PALADINS_ARCHETYPE_SUPPORT" }
GD.CATEGORY_MSG = { Defense = "PALADINS_DEFENSE", Utility = "PALADINS_UTILITY", Healing = "PALADINS_Healing",
	Weapon = "PALADINS_Weapon" }

local function role_of(bot)
	for _, tag in ipairs(bot.DATA_SET_BOT_TAGS or {}) do
		if tag.TAG_TYPE_VALUE_ID == GD.ROLE_TAG_TYPE then return GD.ROLE_TAGS[tag.TAG_VALUE_ID] end
	end
	return nil
end

local function champion(c)
	local bot = assembly.find("BOTS", "BOT_ID", c.bot_id)
	local role = bot and role_of(bot)
	if not role then return "no role for champion " .. c.name .. " (bot " .. c.bot_id .. ")" end
	c.role, c.name_msg = role, bot.NAME_MSG_ID
	local by_slot = {}
	for _, slot in ipairs(bot.DATA_SET_BOT_DEVICES or {}) do
		local key = GD.SLOTS[slot.SLOT_USED_VALUE_ID]
		local device = key and assembly.find("DEVICES", "DEVICE_ID", slot.DEVICE_ID)
		if device then by_slot[key] = device.NAME_MSG_ID end
	end
	for _, a in ipairs(c.abilities) do a.name_msg = by_slot[a.slot] end
	return nil
end

local function item(key, it)
	local row = assembly.find("ITEMS", "ITEM_ID", it.item_id)
	local device = assembly.find("DEVICES", "DEVICE_ID", it.item_id)
	local ranks = 0
	for _ in ipairs(device and device.DATA_SET_DEVICE_MODES or {}) do ranks = ranks + 1 end
	if not row or ranks == 0 then return "no shop item " .. key .. " (item " .. it.item_id .. ")" end
	it.name_msg, it.desc_msg, it.ranks = row.NAME_MSG_ID, row.DESC_MSG_ID, ranks
	return nil
end

local function msg_ids(names)
	local out = {}
	for key, name in pairs(names) do
		local row = lang.find("NAME", name)
		out[key] = row and row.MSG_ID
	end
	return out
end

-- Fills DATA from the game data. Returns true, or nil and the reason.
function GD.load(D)
	local ok, why = assembly.load()
	if not ok then return nil, "assembly.dat: " .. tostring(why) end
	local err
	for _, c in ipairs(D.champions) do err = err or champion(c) end
	D.max_rank = 0
	for _, key in ipairs(D.item_order) do
		err = err or item(key, D.items[key])
		D.max_rank = math.max(D.max_rank, D.items[key].ranks or 0)
	end
	assembly.unload()
	if err then return nil, err end
	D.role_msg, D.category_msg = msg_ids(GD.ROLE_MSG), msg_ids(GD.CATEGORY_MSG)
	lang.unload()   -- the game language's file, read by lang.find; sc_text reads the texts it needs
	return true
end

return GD
