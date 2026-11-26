-- Counter & Shop Helper: the game's own names, from the game's Lang files (Tempest Game Data API).
--
-- The mod ships no game text. lib/sc_gamedata.lua finds the message ids of what the panel names
-- (champions, abilities, items and their descriptions, roles, shop categories); here they become text
-- with lang.message(id, ext), from the game's own Lang_<ext>.dat. The texts of one language are read
-- all at once the first time that language is shown, kept, and the file is freed (lang.unload):
-- nothing is looked up while the panel draws.
--
-- The client's language ("INT", "FRA"...) drives the "Auto" UI language. It is the engine's own answer,
-- Object.GetLanguage() (Core), asked of the engine object: the language the game loaded its texts in.
-- Paladins takes it from Steam's game language when it starts, so neither its engine config (INT on
-- a French client) nor lang.language() (a -language= start argument, else INT) knows it;
-- lang.language() is only the answer when the engine gives none. Read again each second (TX.REFRESH),
-- in case the engine sets it after the script has loaded.
--
-- Names (champions, items, abilities) are shown in the language the mod shows, from that language's
-- Lang file; the `game_names` setting keeps them in the client's language whatever the UI language. Roles, categories and descriptions always follow the UI
-- language. A language the game has no file for (Italian) falls back to the mod's own words:
-- internal English keys for names, sc_lang words for roles and categories, no item description.

local TX = {}
TX.__index = TX

-- Lang file of each UI language of sc_lang.lua, and the UI language of each game language (other
-- game languages: English UI).
TX.EXT = { en = "INT", fr = "FRA", de = "DEU", it = "ITA", ru = "RUS", zh = "CHN", ja = "JPN", ko = "KOR" }
TX.UI_LANG = { INT = "en", FRA = "fr", DEU = "de", ITA = "it", RUS = "ru", CHN = "zh", CHT = "zh",
	JPN = "ja", KOR = "ko" }
TX.REFRESH = 1.0   -- seconds between two looks at the client's language

-- Game strings carry Scaleform markup, entities and value placeholders: "<font color=...>Stuns</font>",
-- "Line<br>line", "&amp;", "Reduce ... by {25}%", "{10|-1}s". Keep the words and the shown value (the
-- first one of a placeholder; what follows "|" is a per-level modifier, not meant to be read).
local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'", nbsp = " " }

local function clean(s)
	if type(s) ~= "string" then return nil end
	s = s:gsub("<[Bb][Rr]%s*/?>", " "):gsub("<[^>]*>", "")
	s = s:gsub("&(%a+);", function(e) return ENTITIES[e:lower()] end)
	s = s:gsub("{([^{}]*)}", function(v) return v:match("^[^|]*") end)
	s = s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	if s == "" then return nil end
	return s
end
TX.clean = clean

-- The client's language, as the engine runs it (see above).
local function client_language()
	local engine = tempest.engine()
	local code = engine and engine:GetLanguage()
	if type(code) == "string" and code ~= "" then return code:upper() end
	return lang.language()
end

-- PRED (sc_predictor) resolves champion names and aliases.
function TX.new(DATA, PRED)
	return setmetatable({
		D = DATA,
		PRED = PRED,
		lang_code = client_language(),   -- the client's language: "INT", "FRA"...
		next_at = 0,
		texts = {},          -- Lang ext -> { msg id -> text }, or false when the game has no such file
		view_lang = nil,     -- UI language on screen (TX:set_view)
		always = false,      -- names in the game's language whatever the UI language
		name_ext = nil,      -- Lang ext of the names on screen
		text_ext = nil,      -- Lang ext of the roles, categories and descriptions on screen
		n_texts = 0,         -- game texts on screen (fonts build a CJK set from them)
		version = 0,         -- bumped when the shown texts change (callers redo layouts and lists)
	}, TX)
end

-- Every message id the panel can show.
function TX:all_ids()
	local D, ids = self.D, {}
	local function add(id) if id then ids[#ids + 1] = id end end
	for _, c in ipairs(D.champions) do
		add(c.name_msg)
		for _, a in ipairs(c.abilities) do add(a.name_msg) end
	end
	for _, it in pairs(D.items) do
		add(it.name_msg)
		add(it.desc_msg)
	end
	for _, id in pairs(D.role_msg) do add(id) end
	for _, id in pairs(D.category_msg) do add(id) end
	return ids
end

-- The texts of one Lang file, read once (one lang.message per id), then the file is freed. false when
-- the game cannot read that language.
function TX:texts_of(ext)
	if not ext then return false end
	local t = self.texts[ext]
	if t ~= nil then return t end
	t = false
	if lang.load(ext) then
		t = {}
		for _, id in ipairs(self:all_ids()) do t[id] = clean(lang.message(id, ext)) end
		lang.unload(ext)
	end
	self.texts[ext] = t
	return t
end

-- Called every frame (looks at most once per REFRESH): a new client language moves the version and
-- makes the next set_view read the view again.
function TX:refresh(now)
	if now < self.next_at then return end
	self.next_at = now + TX.REFRESH
	local code = client_language()
	if code == self.lang_code then return end
	self.lang_code, self.view_lang = code, nil
	self.version = self.version + 1
end

-- UI language matching the game's ("fr"...).
function TX:ui_lang()
	return TX.UI_LANG[self.lang_code] or "en"
end

-- The language the mod shows, and whether names stay in the game's language. Called once at load and
-- every frame by main.lua; a change reads the new language's texts (once) and moves the version.
function TX:set_view(ui_lang, always)
	always = always == true
	if ui_lang == self.view_lang and always == self.always then return end
	self.view_lang, self.always = ui_lang, always
	self.text_ext = TX.EXT[ui_lang]
	self.name_ext = always and self.lang_code or self.text_ext
	self.n_texts = #self:all_texts()
	self.version = self.version + 1
end

-- Lang ext the names are shown in, nil when they fall back to the mod's English keys.
function TX:names_ext()
	return self:texts_of(self.name_ext) and self.name_ext or nil
end

function TX:name(id)
	local t = self:texts_of(self.name_ext)
	return t and id and t[id] or nil
end

function TX:text(id)
	local t = self:texts_of(self.text_ext)
	return t and id and t[id] or nil
end

-- ------------------------------------------------------------------ names used by the UI
function TX:champion(name)
	local c = name and self.PRED:champion(name)
	return (c and self:name(c.name_msg)) or name
end

function TX:item(key)
	local it = key and self.D.items[key]
	return (it and self:name(it.name_msg)) or key or "?"
end

function TX:item_desc(key)
	local it = key and self.D.items[key]
	return it and self:text(it.desc_msg)
end

-- Role / shop category / ability: nil when unknown, the caller then uses its own word.
function TX:role(role)
	return self:text(self.D.role_msg[role])
end

function TX:category(cat)
	return self:text(self.D.category_msg[cat])
end

function TX:ability(a)
	return a and self:name(a.name_msg)
end

-- The game texts on screen (fonts: the glyphs of a CJK language are collected from them).
function TX:all_texts()
	local out, exts = {}, { self.name_ext }
	if self.text_ext ~= self.name_ext then exts[#exts + 1] = self.text_ext end
	for _, ext in ipairs(exts) do
		for _, s in pairs(self:texts_of(ext) or {}) do out[#out + 1] = s end
	end
	return out
end

return TX
