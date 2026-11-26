-- Counter & Shop Helper: the game's own names, asked from the game at run time.
--
-- The mod ships no game text and no game art. sc_data.lua only holds message ids (name_msg /
-- desc_msg), found offline by engine/extract_ids.py. Here they are turned into text by the game's
-- translator, UIMoviePlayer.usc_TranslateMsgId(nId) (TgClient), called on the HUD's Scaleform movie
-- (PlayerController.myHUD.m_pMovie). The text comes back in the language the game runs in, exactly
-- as the game's shop and scoreboard show it.
--
-- The language itself comes from Object.GetLanguage() (Core): "INT", "FRA", "DEU"... It drives the
-- "Auto" choice of the UI language.
--
-- One language on screen: the game's names are only used when the game runs in the language the mod
-- shows (TX:set_view). Otherwise (an English UI on a French game, a Chinese UI on a Spanish game...)
-- the mod's own words are used: internal English keys for champions and items, sc_lang words for
-- roles, categories and ability effects, and no item description. The `game_names` setting keeps the
-- game's champion, item and ability names (proper nouns, as the shop and scoreboard show them)
-- whatever the UI language; roles, categories and descriptions always follow the UI language, so the
-- setting never brings game-language sentences into the panel.
--
-- Until the HUD movie exists (first seconds after launch), names fall back to the mod's internal
-- English keys. An id the game answers empty is asked again (TX.RETRY, at most TX.MAX_MISSES times),
-- since the game may not have loaded its text tables yet. Every engine call is protected (pcall).

local TX = {}
TX.__index = TX

-- Object.GetLanguage() code -> UI language of sc_lang.lua (other game languages: English UI).
TX.UI_LANG = { INT = "en", FRA = "fr", DEU = "de", ITA = "it", RUS = "ru", CHN = "zh", CHT = "zh",
	JPN = "ja", KOR = "ko" }
TX.REFRESH = 1.0   -- seconds between two looks for the language / translator

local function try(f, ...)
	local ok, v = pcall(f, ...)
	if ok then return v end
	return nil
end

local function get(obj, field)
	if obj == nil then return nil end
	return try(function() return obj[field] end)
end

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

TX.RETRY = 5.0       -- seconds before asking again for an id the game had no text for
TX.MAX_MISSES = 3    -- then the fallback is kept until the language or the translator changes

-- PRED (sc_predictor) resolves champion names and aliases.
function TX.new(DATA, PRED)
	local self = setmetatable({
		D = DATA,
		PRED = PRED,
		lang_code = nil,   -- "INT", "FRA"... once known
		has_movie = false, -- the translator was reachable at the last refresh
		view_lang = nil,   -- UI language on screen (TX:set_view), nil = not told yet
		always = false,    -- use the game's names even in another language
		next_at = 0,
		version = 0,       -- bumped when any shown text can change (callers redo layouts and lists)
	}, TX)
	self:forget()
	return self
end

-- Drops what was learnt from the game (new language, or the translator came back).
function TX:forget()
	self.cache = {}     -- msg id -> text
	self.missed = {}    -- msg id -> { n = misses, retry_at = os.clock() of the next try }
	self.n_texts = 0    -- texts in the cache (fonts rebuild a CJK set when it grows)
	self.version = self.version + 1
end

-- The translator: the HUD's movie player. Looked up at each use, never kept between frames, so a
-- map change (HUD and movie destroyed) can never leave a dangling object behind.
local function translator()
	local pc = tempest.local_player()
	local movie = get(get(pc, "myHUD"), "m_pMovie")
	if movie and try(function() return movie:is_a("TgClient.UIMoviePlayer") end) then return movie end
	return nil
end

-- Called every frame (does real work at most once per REFRESH): game language and translator state.
function TX:refresh(now)
	if now < self.next_at then return end
	self.next_at = now + TX.REFRESH
	local pc = tempest.local_player()
	local code = pc and try(function() return pc:GetLanguage() end)
	if type(code) == "string" and code ~= "" then
		code = code:upper()
		if code ~= self.lang_code then
			self.lang_code = code
			self:forget()
		end
	end
	local has = translator() ~= nil
	if has ~= self.has_movie then
		self.has_movie = has
		if has then
			self.missed = {}   -- a new HUD: ask again for what the last one could not translate
		end
		self.version = self.version + 1
	end
end

-- UI language matching the game's ("fr"...), nil while unknown.
function TX:ui_lang()
	return self.lang_code and (TX.UI_LANG[self.lang_code] or "en") or nil
end

-- The language the mod shows, and whether the game's names are kept in another one. Called every
-- frame by main.lua; the version moves when the names on screen switch source.
function TX:set_view(lang, always)
	always = always == true
	if lang == self.view_lang and always == self.always then return end
	self.view_lang, self.always = lang, always
	self.version = self.version + 1
end

-- The game runs in the shown language (an unknown game language counts as a match: nothing better
-- is known yet).
function TX:same_lang()
	if not self.view_lang or not self.lang_code then return true end
	return TX.UI_LANG[self.lang_code] == self.view_lang
end

-- kind "name" (champion, item, ability) or "text" (role, category, description): a game text is
-- shown in the shown language, and a name also when the player keeps the game's names.
function TX:names_ok(kind)
	return self:same_lang() or (kind == "name" and self.always)
end

function TX:shown(id, kind)
	if not self:names_ok(kind) then return nil end
	return self:msg(id)
end

-- Text of a message id, nil when the game cannot give it (yet). An empty answer is not final: the
-- game may not have loaded its text tables yet, so the id is asked again a few times.
function TX:msg(id)
	if type(id) ~= "number" then return nil end
	local hit = self.cache[id]
	if hit then return hit end
	if not self.has_movie then return nil end
	local miss = self.missed[id]
	if miss and (miss.n >= TX.MAX_MISSES or os.clock() < miss.retry_at) then return nil end
	local movie = translator()
	if not movie then return nil end
	local s = clean(try(function() return movie:usc_TranslateMsgId(id) end))
	if s then
		self.cache[id], self.missed[id] = s, nil
		self.n_texts = self.n_texts + 1
		self.version = self.version + 1
	else
		miss = miss or { n = 0 }
		miss.n, miss.retry_at = miss.n + 1, os.clock() + TX.RETRY
		self.missed[id] = miss
	end
	return s
end

-- ------------------------------------------------------------------ names used by the UI
function TX:champion(name)
	local c = name and self.PRED:champion(name)
	return (c and self:shown(c.name_msg, "name")) or name
end

function TX:item(key)
	local it = key and self.D.items[key]
	return (it and self:shown(it.name_msg, "name")) or key or "?"
end

function TX:item_desc(key)
	local it = key and self.D.items[key]
	return it and self:shown(it.desc_msg, "text")
end

-- Role / shop category / ability: nil when unknown, the caller then uses its own word.
function TX:role(role)
	return self:shown(self.D.role_msg[role], "text")
end

function TX:category(cat)
	return self:shown(self.D.category_msg[cat], "text")
end

function TX:ability(a)
	return a and self:shown(a.name_msg, "name")
end

-- Every message id the UI can show (fonts: the glyphs of a CJK game language are collected from them).
function TX:all_ids()
	local D, ids = self.D, {}
	for _, c in ipairs(D.champions) do
		ids[#ids + 1] = c.name_msg
		for _, a in ipairs(c.abilities or {}) do ids[#ids + 1] = a.name_msg end
	end
	for _, it in pairs(D.items) do
		ids[#ids + 1] = it.name_msg
		ids[#ids + 1] = it.desc_msg
	end
	for _, id in pairs(D.role_msg) do ids[#ids + 1] = id end
	for _, id in pairs(D.category_msg) do ids[#ids + 1] = id end
	return ids
end

-- All the game texts, translated now (one call per id, then cached). Returns them, or nil when the
-- translator is not there yet.
function TX:all_texts()
	if not self.has_movie then return nil end
	local out = {}
	for _, id in ipairs(self:all_ids()) do
		local s = self:msg(id)
		if s then out[#out + 1] = s end
	end
	return out
end

return TX
