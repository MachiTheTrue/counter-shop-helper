-- Counter & Shop Helper: settings, through Tempest's config API.
--
-- tempest.config(defaults) merges the defaults with the mod's config.toml and the player's
-- <game>\ChaosGame\Config\mods\paladins-smartcounter-81.toml; tempest.save_config writes it back.
-- Saving is debounced (CFG:mark_dirty, then one write a second after the last change) so dragging a
-- slider or the panel does not write the file every frame. Session-only values (SESSION_ONLY) are
-- never written.

local CFG = {}
CFG.__index = CFG
CFG.SAVE_DELAY = 1.0
CFG.SESSION_ONLY = { owned = true }   -- manual item ranks: they only apply to the game being played

CFG.DEFAULT_KEYS = { menu = "Ctrl+J", overlay = "Ctrl+H", settings = "Ctrl+O", lock = "Ctrl+L", layout = "Ctrl+K" }
CFG.DEFAULTS = {
	lang = "auto",         -- auto (the game's language) | en | fr | de | it | ru | zh | ja | ko
	live_items = true,     -- read owned items / ranks from the game
	game_names = false,    -- true: the game's names even when the UI shows another language
	owned = {},            -- manual fallback: { [item] = rank 1..3 }, at most 4 items (the game's
	                       -- limit), emptied at every launch and match
	overlay_w = { compact = 0, detailed = 0 },   -- 0 = automatic width, else the width dragged by hand
	show_on_start = false, -- panel shown at launch (otherwise hidden until its key is pressed)
	show_tip = true,       -- short tip at launch
	tutorial_done = false,
	auto_detect = true,
	opacity = 0.88,
	text_size = 2,         -- 1 small, 2 normal, 3 large
	locked = false,
	display = "auto",      -- compact | detailed | auto (detailed on change, then compact)
	pos_x = -1, pos_y = -1, -- -1 = default position (right edge)
	phase = "auto",        -- auto | early | mid | late
	mode = "auto",         -- auto | siege | onslaught | tdm | ranked | range
	style = "auto",        -- auto (role default) | heal | aggro | ...
	keys = CFG.DEFAULT_KEYS,
	manual = { me = "", enemies = { "", "", "", "", "" } },
}

local function copy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[k] = copy(x) end
	return c
end

-- Missing or wrongly typed values are replaced by their default (an old or hand-edited file).
local function fill(dst, defaults)
	for k, v in pairs(defaults) do
		if dst[k] == nil or type(dst[k]) ~= type(v) then
			dst[k] = copy(v)
		elseif type(v) == "table" then
			fill(dst[k], v)
		end
	end
end

-- A manual pick must name a known champion (the data may have changed since it was saved):
-- canonical(name) returns the champion's name, or nil.
local function clean_picks(manual, canonical)
	local function pick(n)
		return type(n) == "string" and n ~= "" and canonical(n) or ""
	end
	manual.me = pick(manual.me)
	for i, n in ipairs(manual.enemies) do manual.enemies[i] = pick(n) end
end

-- valid_lang(code) -> boolean: the UI languages of sc_lang.lua; canonical(name) -> champion name|nil.
function CFG.load(valid_lang, canonical, log)
	local ok, values = pcall(tempest.config, copy(CFG.DEFAULTS))
	if not ok or type(values) ~= "table" then
		log("config could not be read (%s): defaults used", tostring(values))
		values = {}
	end
	fill(values, CFG.DEFAULTS)
	values.opacity = math.max(0.2, math.min(1, values.opacity))
	values.text_size = math.max(1, math.min(3, math.floor(values.text_size)))
	if values.lang ~= "auto" and not valid_lang(values.lang) then values.lang = "auto" end
	clean_picks(values.manual, canonical)
	-- Manual item ranks start empty every session: ranks set by hand in an earlier game don't apply.
	values.owned = {}
	return setmetatable({ values = values, dirty_at = nil, log = log }, CFG)
end

function CFG:mark_dirty()
	self.dirty_at = os.clock()
end

-- Every frame: writes the file once nothing has changed for SAVE_DELAY seconds.
function CFG:tick(now)
	if self.dirty_at and now - self.dirty_at > CFG.SAVE_DELAY then self:save() end
end

function CFG:save()
	self.dirty_at = nil
	local out = {}
	for k, v in pairs(self.values) do
		if not CFG.SESSION_ONLY[k] then out[k] = v end
	end
	local ok, err = pcall(tempest.save_config, out)
	if not ok then self.log("config save failed: %s", tostring(err)) end
end

return CFG
