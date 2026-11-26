-- Counter & Shop Helper: fonts (Windows TTFs through ui.add_font).
--
-- One font set per script: "latin" (Segoe UI with Latin, Latin Extended, Greek, Cyrillic, punctuation,
-- arrows) or "zh" / "ja" / "ko" (the same base + a Windows CJK font merged in). Each set has a body
-- and a bold font at the 3 text sizes.
--
-- Timing, as the API asks: ui.add_font must run outside a frame being built, once the UI backend is up
-- (ui.ready()), and a font is usable from the next frame. A set is therefore loaded through
-- tempest.queue the first time it is needed: pending -> queued -> wait -> ready. A queued load that never
-- ran (hot reload, lost event) is queued again, at most MAX_TRIES times, then the set is marked failed
-- and the default font is used. Sets live in `shared`, so a hot reload reuses them instead of growing
-- the font atlas.
--
-- CJK glyphs: only the characters really shown are added, to keep the atlas small: the UI strings of
-- the language (sc_lang.lua) plus the game's own names on screen (sc_text.lua). When more game names
-- come on screen after the set was built (names switched to the game's language), it is rebuilt, at
-- most MAX_REBUILDS times.

local F = {}
F.__index = F

F.SIZES = { 15, 17, 20 }
local BASE_RANGES = { 0x0020, 0x024F, 0x0370, 0x03FF, 0x0400, 0x052F, 0x2000, 0x206F, 0x2190, 0x21FF,
	0x2200, 0x22FF, 0x25A0, 0x25FF, 0 }
local CJK_FONTS = {
	zh = { { "msyh.ttc", "msyhbd.ttc" }, { "simhei.ttf", "simhei.ttf" }, { "simsun.ttc", "simsun.ttc" } },
	ja = { { "YuGothM.ttc", "YuGothB.ttc" }, { "meiryo.ttc", "meiryob.ttc" }, { "msgothic.ttc", "msgothic.ttc" } },
	ko = { { "malgun.ttf", "malgunbd.ttf" }, { "gulim.ttc", "gulim.ttc" } },
}
local FONT_DIR = ((os and os.getenv and os.getenv("WINDIR")) or "C:\\Windows") .. "\\Fonts\\"
local QUEUE_TIMEOUT = 3   -- seconds: a queued load that never ran is queued again
local MAX_TRIES = 3
local MAX_REBUILDS = 2
local REBUILD_DELAY = 5   -- seconds between two builds of a CJK set

local function is_cjk(lang)
	return lang == "zh" or lang == "ja" or lang == "ko"
end

-- UTF-8 code points >= U+2E80 (CJK) of a string, added to `out` (LuaJIT has no utf8 library).
local function cjk_codepoints(s, out)
	local i, n = 1, #s
	while i <= n do
		local c = s:byte(i)
		local cp, len
		if c < 0x80 then cp, len = c, 1
		elseif c >= 0xF0 then cp, len = c % 0x08, 4
		elseif c >= 0xE0 then cp, len = c % 0x10, 3
		elseif c >= 0xC0 then cp, len = c % 0x20, 2
		else cp, len = nil, 1 end
		if cp and len > 1 then
			for k = 1, len - 1 do
				local b = s:byte(i + k)
				if not b then cp = nil break end
				cp = cp * 64 + (b % 64)
			end
		end
		if cp and cp >= 0x2E80 then out[cp] = true end
		i = i + len
	end
	return out
end

-- Sorted code points -> ImGui glyph ranges { a, b, a2, b2, ..., 0 }, merging neighbours if asked.
local function to_ranges(set, merge)
	local cps = {}
	for cp in pairs(set) do cps[#cps + 1] = cp end
	table.sort(cps)
	local r = {}
	for _, cp in ipairs(cps) do
		if merge and #r > 0 and r[#r] == cp - 1 then r[#r] = cp else r[#r + 1] = cp; r[#r + 1] = cp end
	end
	r[#r + 1] = 0
	return r, #cps
end

-- L: sc_lang, TX: sc_text, store: a table kept across hot reloads, log: fn(fmt, ...)
function F.new(L, TX, store, log)
	-- A load queued by the previous instance (hot reload) may never run: start it again.
	for _, set in pairs(store) do
		if set.state == "queued" or set.state == "loading" then set.state = "pending" end
	end
	return setmetatable({ L = L, TX = TX, sets = store, log = log }, F)
end

-- Script of the text on screen: the UI language, or the game's when only the game names are CJK.
function F:group(ui_lang)
	if is_cjk(ui_lang) then return ui_lang end
	local game = self.TX:ui_lang()
	if is_cjk(game) then return game end
	return "latin"
end

-- A CJK set holds the glyphs of its UI strings too, so it is kept per UI language ("ja" for a
-- Japanese UI, "ja/en" for an English UI over a Japanese game).
local function new_set(group, ui_lang, key)
	return { state = "pending", body = {}, bold = {}, group = group, ui_lang = ui_lang, key = key }
end

function F:set_for(ui_lang)
	local g = self:group(ui_lang)
	local key = (g == "latin" or g == ui_lang) and g or (g .. "/" .. ui_lang)
	local s = self.sets[key]
	if not s then
		s = new_set(g, ui_lang, key)
		self.sets[key] = s
	end
	return s
end

local function try_add(path, size, opts)
	local ok, f = pcall(ui.add_font, path, size, opts)
	if ok and f then return f end
	return nil, ok and "nil" or f
end

-- Path of the first font of the list present in the Windows font folder. A read-only existence check:
-- ui.add_font needs a file path, and a missing file must not reach ImGui.
local function pick(...)
	for _, name in ipairs({ ... }) do
		local f = io and io.open(FONT_DIR .. name, "rb")
		if f then
			f:close()
			return FONT_DIR .. name
		end
	end
	return nil
end

-- The CJK font pair { regular, bold } of a group that exists on this PC.
local function cjk_pair(group)
	for _, pair in ipairs(CJK_FONTS[group] or {}) do
		local r = pick(pair[1])
		if r then return { r, pick(pair[2]) or r } end
	end
	return nil
end

function F:glyphs(set)
	local found = {}
	for _, s in pairs(self.L.strings(set.ui_lang) or {}) do
		if type(s) == "string" then cjk_codepoints(s, found) end
	end
	local game_texts = self.TX:all_texts()
	for _, s in ipairs(game_texts or {}) do cjk_codepoints(s, found) end
	for cp = 0x3000, 0x303F do found[cp] = true end      -- CJK punctuation
	for cp = 0xFF01, 0xFF5E do found[cp] = true end      -- full-width forms
	set.n_game_texts = game_texts and #game_texts or 0
	return to_ranges(found, true)
end

-- Loads a whole set (body + bold, 3 sizes). Runs from tempest.queue, outside any frame.
function F:load(set, how)
	if set.state ~= "pending" and set.state ~= "queued" then return end
	if not ui.ready() then return end
	set.state = "loading"
	local regular = pick("segoeui.ttf", "arial.ttf")
	local bold = pick("segoeuib.ttf", "arialbd.ttf") or regular
	-- CJK set: the main CJK font and the glyphs to take from it
	local cjk, ranges, nglyphs
	if set.group ~= "latin" then
		cjk = cjk_pair(set.group)
		if cjk then ranges, nglyphs = self:glyphs(set) end
	end
	-- the language picker shows the CJK languages' own names: merge those few glyphs in every set
	local picker = {}
	for _, lg in ipairs({ "zh", "ja", "ko" }) do
		local pair = lg ~= set.group and cjk_pair(lg)
		if pair then picker[#picker + 1] = { pair[1], (to_ranges(cjk_codepoints(self.L.native(lg), {}), false)) } end
	end
	local n, last_err = 0, nil
	-- A base font (the built-in one if the TTF fails), then the merged CJK glyphs: merging always goes
	-- into the font added just before, so the order matters.
	local function add(path, size, cjk_path)
		local f, e = nil, "no TTF"
		if path then f, e = try_add(path, size, { ranges = BASE_RANGES }) end
		if not f then f, e = try_add(nil, size) end
		if not f then
			last_err = e
			return nil
		end
		if cjk_path then try_add(cjk_path, size, { merge = true, ranges = ranges }) end
		for _, p in ipairs(picker) do try_add(p[1], size, { merge = true, ranges = p[2] }) end
		return f
	end
	for i, size in ipairs(F.SIZES) do
		set.body[i] = add(regular, size, cjk and cjk[1])
		set.bold[i] = add(bold, size + 2, cjk and cjk[2])
		n = n + (set.body[i] and 1 or 0) + (set.bold[i] and 1 or 0)
	end
	set.name = (regular and (regular:match("([^\\]+)$") or "?") or "built-in")
		.. (cjk and (" + " .. (cjk[1]:match("([^\\]+)$") or "?")) or "")
	set.state = n > 0 and "wait" or "failed"
	self.log("fonts %s (%s): %d/%d loaded (%s)%s%s", set.group, how, n, #F.SIZES * 2, set.name,
		nglyphs and string.format(", %d CJK glyphs", nglyphs) or "",
		last_err and (", last error: " .. tostring(last_err)) or "")
end

local function queue_load(self, set, now)
	set.tries = (set.tries or 0) + 1
	tempest.queue(function() self:load(set, "queue") end)
	set.state, set.queued_at = "queued", now
end

-- More game names on screen than when this CJK set was built (names switched to the game's
-- language): build it again.
function F:wants_rebuild(set, now)
	return set.group ~= "latin" and (set.rebuilds or 0) < MAX_REBUILDS
		and (self.TX.n_texts or 0) > (set.n_game_texts or 0) and now - (set.ready_at or now) >= REBUILD_DELAY
end

-- Every frame, before drawing: moves the current set through pending -> queued -> wait -> ready.
function F:tick(now, ui_lang)
	local set = self:set_for(ui_lang)
	if set.state == "wait" then
		set.state, set.ready_at, set.previous = "ready", now, nil
	elseif set.state == "pending" and ui.ready() then
		queue_load(self, set, now)
	elseif set.state == "queued" and now - (set.queued_at or now) > QUEUE_TIMEOUT then
		if set.tries >= MAX_TRIES then
			set.state = "failed"
			self.log("fonts %s: the queued load never ran (%d tries), default font kept", set.group, set.tries)
		else
			queue_load(self, set, now)
		end
	elseif set.state == "ready" and self:wants_rebuild(set, now) then
		local again = new_set(set.group, set.ui_lang, set.key)
		again.rebuilds = (set.rebuilds or 0) + 1
		again.previous = set   -- drawn with until the new one is ready (no flash of the default font)
		self.sets[set.key] = again
	end
	return set
end

-- Runs fn with the body / bold font of the current text size (default font while loading or failed).
function F:with(set, kind, size, fn)
	if set.state ~= "ready" and set.previous then set = set.previous end
	local f = set.state == "ready" and set[kind][size]
	if not f then return fn() end
	ui.push_font(f)
	local ok, err = pcall(fn)
	ui.pop_font()
	if not ok then error(err, 0) end
end

return F
