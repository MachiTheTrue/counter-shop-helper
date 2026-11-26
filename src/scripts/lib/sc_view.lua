-- Counter & Shop Helper: the panel (compact / detailed) and the texts built from a prediction.
--
-- Layout rule: every line is either wrapped (text_wrapped) or an atomic "chip" whose width was
-- measured, and the panel width is computed from the measured text of the current language and font.
-- Nothing runs past the right edge, and a rank number is never left alone at the end of a line.
--
-- Item chips show the rank progress: grey = not owned, amber = rank rising, green = advised rank
-- reached; accent outline = the next purchase; soft blue outline = the optional 5th item, dimmed when
-- the game's 4 item slots are already full. A small coloured mark inside the chip gives the shop
-- category (drawn, no game art).

local V = {}
V.__index = V

local ROMAN = { [0] = "0", "I", "II", "III" }
V.ROMAN = ROMAN
-- " -> " as the arrow U+2192, written as bytes so the source stays ASCII; the arrows block is in every
-- font set (sc_fonts BASE_RANGES).
local ARROW = " \226\134\146 "
V.ARROW = ARROW

-- Roman numeral of a rank, clamped to the table (a rank read from the game is never shown as nil).
function V.roman(n)
	n = math.floor(tonumber(n) or 0)
	return ROMAN[math.max(0, math.min(#ROMAN, n))]
end
local roman = V.roman
-- Chip geometry: the category mark sits MARK_X inside the left edge (clear of a 2 px outline), the
-- label starts at TEXT_X; CHIP_PAD on the right.
local CHIP_PAD, CHIP_GAP, ROUND = 10, 8, 5
local MARK_X, MARK_Y, MARK_W = 6, 5, 3
local TEXT_X = MARK_X + MARK_W + 7
local AUTO_DETAIL_SECONDS = 8    -- Auto layout: detailed this long after a change, then compact
local TIP_SECONDS = 10

-- A: the app context built by main.lua (cfg, CFG, t, TX, MATCH, G, fonts, state, S)
function V.new(A)
	return setmetatable({ A = A, width_cache = {}, width_n = 0, last_h = 0, was_draggable = false,
		tip_start = nil }, V)
end

-- ------------------------------------------------------------------ names (game text first)
function V:item(key) return self.A.TX:item(key) end
function V:champion(name) return self.A.TX:champion(name) end
function V:category(cat) return self.A.TX:category(cat) or self.A.t("cat_" .. tostring(cat)) end
function V:role(role) return self.A.TX:role(role) or self.A.t("role_" .. tostring(role)) end

-- ------------------------------------------------------------------ texts from structured results
-- Names inside the mod's sentences are never typed in sc_lang.lua: the sentences have %s and get the
-- names from sc_text (the game's names, in the shown language). Item keys and champion names here are
-- the mod's internal ids.
local ARCH_ITEM = { shield_heavy = "Wrecker", deployable_heavy = "Bulldozer", high_cc = "Resilience" }
local REASON_ITEM = { special_shield = "Wrecker" }
local NOTE_CHAMPS = { Wrecker = { "Inara", "Azaan", "Atlas" } }

function V:reason_text(r)
	if not r then return nil end
	local item = REASON_ITEM[r.key]
	local txt = self.A.t("r_" .. tostring(r.key), item and self:item(item) or (r.args or ""))
	return r.enemy and (self:champion(r.enemy) .. ": " .. txt) or txt
end

-- Why an item is suggested. full=false: the main reason only (panel), full=true: everything (menu).
function V:why_text(item, why, full)
	local t, parts = self.A.t, {}
	if why then
		local rt = self:reason_text(why.reason)
		if rt then parts[#parts + 1] = rt end
		if why.arch then
			local label = t((full and "arch_" or "archs_") .. why.arch.key, self:item(ARCH_ITEM[why.arch.key]))
			parts[#parts + 1] = t("why_arch", label, why.arch.probability)
		end
		if (why.own or 0) > 0 then parts[#parts + 1] = t("why_own", t("style_" .. tostring(why.style))) end
	end
	if full then
		local names = {}
		for i, c in ipairs(NOTE_CHAMPS[item] or {}) do names[i] = self:champion(c) end
		local note = self.A.L.maybe("note_" .. item, unpack(names))
		if note then parts[#parts + 1] = note end
	elseif #parts > 1 then
		parts = { parts[1] }
	end
	if #parts == 0 then return t("r_generic") end
	return table.concat(parts, "  ·  ")
end

-- What makes an enemy dangerous, named with the champion's own abilities when the game gives their
-- names: "Makoa: Dredge Anchor (stuns)". An ability backing several tags is named once:
-- "Grohk: Healing Totem (heals, deployable)". Without a name, the generic tag word is used.
function V:threat_parts(th, n)
	local t, parts, by_slot = self.A.t, {}, {}
	for i, tag in ipairs(th.tags) do
		if i > n then break end
		local ability
		for _, x in ipairs(th.abilities or {}) do
			if x.tag == tag then ability = x end
		end
		local name = ability and self.A.TX:ability(ability)
		local fx = ability and ability.fx and t("fx_" .. ability.fx) or t("tag_" .. tag)
		if name and by_slot[ability.slot] then
			local p = by_slot[ability.slot]
			p.fx[#p.fx + 1] = fx
		elseif name then
			local p = { name = name, fx = { fx } }
			by_slot[ability.slot] = p
			parts[#parts + 1] = p
		else
			parts[#parts + 1] = { text = t("tag_" .. tag) }
		end
	end
	local out = {}
	for _, p in ipairs(parts) do
		out[#out + 1] = p.text or (p.name .. " (" .. table.concat(p.fx, ", ") .. ")")
	end
	return out
end

-- short=true: first tag only and no "(not in your items)" (panel); false: up to 3 tags (menu).
function V:threat_text(th, short)
	local t = self.A.t
	local tags = self:threat_parts(th, short and 1 or 3)
	local s = self:champion(th.name) .. ": " .. (#tags > 0 and table.concat(tags, ", ") or t("r_generic"))
	if th.answer then
		s = s .. "  ->  " .. self:item(th.answer) .. ((th.answer_in_build or short) and "" or (" " .. t("not_in_build")))
	end
	return s
end

function V:slot_status(b)
	local t = self.A.t
	if b.status == "buy" then return t("status_buy") end
	if b.status == "upgrade" then return t("status_upgrade", roman(b.rank), roman(b.target)) end
	return t("status_done", roman(b.rank))
end

local function danger_color(C, d)
	if d >= 11 then return C.HIGH elseif d >= 8 then return C.MED end
	return C.LOW
end

-- The playstyle, only when the champion has a choice (Supports: Heal / Aggro). For the other roles
-- the only style is the role itself ("Damage (Damage)"), so it would say the same word twice.
function V:style_label(me, style, role_text)
	if not (me and style) or #self.A.PRED:styles_for(me) < 2 then return nil end
	local s = self.A.t("style_" .. style)
	if role_text and s:lower() == role_text:lower() then return nil end
	return s
end

-- Champion (role) · style · mode. The mode only when it is known; the game phase only when the player
-- set it by hand (an automatic phase is a guess from the clock: it tunes the advice, it is not news).
function V:header_text(long)
	local A, t = self.A, self.A.t
	local result, inputs = A.MATCH.result, A.MATCH.inputs
	local parts = { (inputs.me and self:champion(inputs.me)) or t("need_champ") }
	local role_text = result and self:role(result.player.role)
	if long and role_text then parts[1] = parts[1] .. " (" .. role_text .. ")" end
	local style = self:style_label(inputs.me, result and result.style, role_text)
	if style then parts[#parts + 1] = style end
	if not inputs.phase_auto then parts[#parts + 1] = t("phase_" .. inputs.phase) end
	if long and inputs.mode then parts[#parts + 1] = t("mode_" .. inputs.mode) end
	return table.concat(parts, "  ·  ")
end

-- The header already says "Pick your champion" when none is known: not repeated here.
function V:waiting_block()
	local A = self.A
	local e = A.MATCH.err and A.MATCH.err[1] ~= "need_champ" and A.MATCH:err_text(A.t)
	A.G.wrapped(A.G.C.DIM, (e and (e .. "  ·  ") or "") .. A.t("press_menu", A.cfg.keys.menu))
end

-- ------------------------------------------------------------------ item chips
-- "Haven III" (to buy: the advised rank), "Haven I -> III" (owned at I, advised III; an arrow, not
-- "I/III", which read as a fraction), "Haven II" (owned rank reached), "Nimble I · optional" (5th
-- item), "· slots full" once the game's 4 item slots are taken.
function V:chip_label(b)
	local rank
	if b.rank > 0 and b.rank < b.target then
		rank = roman(b.rank) .. ARROW .. roman(b.target)
	else
		rank = roman(math.max(b.rank, b.target))
	end
	local s = self:item(b.item) .. " " .. rank
	if b.kind == "flex" then s = s .. "  ·  " .. self.A.t(b.blocked and "flex_full" or "flex_tag") end
	return s
end

-- Width and height of a chip: [inset | category mark | gap | label | pad].
local function chip_size(label)
	local w, h = ui.calc_text_size(label)
	return math.ceil(w + TEXT_X + CHIP_PAD), math.ceil(h + 8)
end

-- The label cut to a width ("..." at the end), on whole UTF-8 characters.
local function fit_label(label, max_w)
	if ui.calc_text_size(label) <= max_w then return label end
	local s = label
	while #s > 0 do
		s = s:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
		if ui.calc_text_size(s .. "...") <= max_w then break end
	end
	return s .. "..."
end

function V:item_tooltip(b)
	if not ui.is_item_hovered() then return end
	local lines = { self:item(b.item) .. "  ·  " .. self:category(b.category) }
	if b.blocked then lines[#lines + 1] = self.A.t("flex_full_long") end
	local d = self.A.TX:item_desc(b.item)
	if d then lines[#lines + 1] = d end
	ui.set_tooltip("%s", table.concat(lines, "\n"))
end

-- Colours of a chip, from the palette (G.C): background, progress fill, outline (nil = none), text.
-- The next purchase gets the accent outline; the optional item a soft blue one; a blocked optional
-- item (4 slots full) is dimmed as a whole.
function V:chip_style(b)
	local C = self.A.G.C
	local st = { bg = C.CHIP_BG, fill = b.rank >= b.target and C.FILL_DONE or C.FILL_PART, edge = C.CHIP_EDGE,
		edge_w = 1, text = C.CHIP_TEXT, alpha = 1 }
	if b.kind == "flex" then st.bg, st.edge, st.text = C.FLEX_BG, C.FLEX_EDGE, C.FLEX_TEXT end
	if b.next then st.edge, st.edge_w = C.ACCENT, 2 end
	if b.blocked then st.alpha, st.text, st.edge = 0.45, C.DIM, nil end
	return st
end

-- The chip, drawn in the window's draw list over an ImGui dummy of the same size (layout, hover).
-- Everything stays inside the rectangle: the category mark is inset by MARK_X, clear of the outline,
-- whatever its width; the outline is drawn last so nothing covers it.
function V:draw_chip(b, label, w, h)
	local G = self.A.G
	local C = G.C
	local x1, y1 = ui.cursor_screen_pos()
	ui.dummy(w, h)
	local st = self:chip_style(b)
	local function col(c, a) return ui.color(c[1], c[2], c[3], (c[4] or 1) * (a or 1) * st.alpha) end
	local dl, x2, y2 = ui.dl, x1 + w, y1 + h
	dl.rect_filled(x1, y1, x2, y2, col(st.bg), ROUND)
	local frac = b.target > 0 and math.min(1, b.rank / b.target) or 0
	if frac > 0 then
		dl.rect_filled(x1, y1, x1 + math.max(2 * ROUND, w * frac), y2, col(st.fill, 0.9), ROUND)
	end
	local rgb = G.CATEGORY_RGB[b.category]
	if rgb then
		dl.rect_filled(x1 + MARK_X, y1 + MARK_Y, x1 + MARK_X + MARK_W, y2 - MARK_Y,
			ui.rgb(rgb, 0.95 * st.alpha), MARK_W / 2)
	end
	local text = fit_label(label, w - TEXT_X - CHIP_PAD)
	local _, th = ui.calc_text_size(text)
	dl.text(x1 + TEXT_X, y1 + math.floor((h - (th or 0)) / 2), col(st.text), "%s", text)
	if st.edge then
		local inset = st.edge_w / 2
		dl.rect(x1 + inset, y1 + inset, x2 - inset, y2 - inset, col(st.edge), ROUND, st.edge_w)
	end
	self:item_tooltip(b)
end

-- Chips in reading order, wrapping only between chips.
function V:chip_flow(build)
	local avail, used = self.A.G.avail_w(), 0
	for i, b in ipairs(build) do
		local label = self:chip_label(b)
		local w, h = chip_size(label)
		w = math.min(w, avail)
		if i > 1 and used + CHIP_GAP + w <= avail then
			ui.same_line()
			used = used + CHIP_GAP + w
		else
			used = w
		end
		self:draw_chip(b, label, w, h)
	end
end

-- ------------------------------------------------------------------ panel contents
function V:draw_compact()
	local A = self.A
	local G, C, t, result = A.G, A.G.C, A.t, A.MATCH.result
	A.bold(C.ACCENT, self:header_text(false))
	if not result then return self:waiting_block() end
	self:chip_flow(result.build)
	local th = result.threats[1]
	if th then
		G.tcol(danger_color(C, th.danger), t("watch"))
		ui.same_line()
		local s = self:threat_text(th, true)
		local th2 = result.threats[2]
		if th2 then s = s .. "   +" .. self:champion(th2.name) end
		G.wrapped(nil, s)
	end
	if A.MATCH:context() ~= "match" then
		local names = {}
		for i = 1, math.min(3, #result.counters.picks) do names[i] = self:champion(result.counters.picks[i].name) end
		G.wrapped(C.GOOD, t("counters") .. ": " .. table.concat(names, ", "))
	end
end

function V:draw_counters(full)
	local A = self.A
	local G, C, t = A.G, A.G.C, A.t
	local c = A.MATCH.result.counters
	ui.separator_text(t("counters"))
	if full then G.wrapped(C.DIM, t("counters_hint")) end
	for i = 1, math.min(full and 5 or 3, #c.picks) do
		local p = c.picks[i]
		local why = {}
		for k, key in ipairs(p.why) do
			if full or k == 1 then why[#why + 1] = t("c_" .. key) end
		end
		G.tcol(C.GOOD, self:champion(p.name))
		ui.same_line()
		local info = full and ("(" .. self:role(p.role) .. ", " .. p.tier .. ")  ") or ""
		G.wrapped(C.DIM, info .. table.concat(why, "; "))
	end
	if full then
		local roles = {}
		for _, r in ipairs(c.recommended_roles) do roles[#roles + 1] = self:role(r) end
		G.wrapped(C.DIM, t("roles", table.concat(roles, ", ")))
		if #c.enemy_holes > 0 then
			local holes = {}
			for _, h in ipairs(c.enemy_holes) do holes[#holes + 1] = self:role(h) end
			G.wrapped(C.DIM, t("holes", table.concat(holes, ", ")))
		end
	end
end

local BADGE = { draft = "GOOD", match = "ACCENT", plan = "DIM" }

-- The badge under the header: draft / match / plan, and "loading" between champion select and the
-- match (champion locked, the map not there yet).
function V:badge_key(ctx)
	if ctx == "match" and self.A.DET.state.status == "loading" then return "loading" end
	return ctx
end

-- One build slot of the detailed view: chip, then its status line and explanation.
function V:draw_slot(b, full)
	local A = self.A
	local G, C, t = A.G, A.G.C, A.t
	local label = self:chip_label(b)
	local w, h = chip_size(label)
	self:draw_chip(b, label, math.min(w, G.avail_w()), h)
	local parts = { self:category(b.category), self:slot_status(b) }
	if b.next then parts[2] = t("next_buy") .. ": " .. parts[2] end
	if b.kind == "flex" then parts[#parts + 1] = t(b.blocked and "flex_full_long" or "flex_long") end
	if b.offmeta then parts[#parts + 1] = t("offmeta") end
	if b.synergy and #b.synergy > 0 then
		local names = {}
		for i, n in ipairs(b.synergy) do names[i] = self:item(n) end
		parts[#parts + 1] = t("synergy", table.concat(names, ", "))
	end
	if full and b.alt then parts[#parts + 1] = t("alt", self:item(b.alt)) end
	ui.indent(CHIP_PAD)
	local tc = b.next and C.ACCENT or (b.blocked and C.DIM) or (b.kind == "flex" and C.FLEX_TEXT) or C.DIM
	G.wrapped(tc, table.concat(parts, "  ·  "))
	-- the panel explains only the next purchase; the menu explains everything
	if full or (b.next and b.kind == "primary") then G.wrapped(nil, self:why_text(b.item, b.why, full)) end
	if full then
		local d = A.TX:item_desc(b.item)
		if d then G.wrapped(C.DIM, t("desc", d)) end
	end
	ui.unindent(CHIP_PAD)
end

-- Detailed view; full=true in the menu (all explanations, descriptions, all threats, forecast).
function V:draw_detailed(full)
	local A = self.A
	local G, C, t = A.G, A.G.C, A.t
	local result, ctx = A.MATCH.result, A.MATCH:context()
	A.bold(C.ACCENT, self:header_text(true))
	G.wrapped(C[BADGE[ctx]], t("badge_" .. self:badge_key(ctx)))
	if not result then return self:waiting_block() end
	if full then
		local names = {}
		for i, n in ipairs(result.enemies) do names[i] = self:champion(n) end
		G.wrapped(C.DIM, t("vs", table.concat(names, ", ")))
	end
	local n_owned = 0
	for _, b in ipairs(result.build) do
		if b.rank > 0 then n_owned = n_owned + 1 end
	end
	-- out of the game's 4 item slots (the optional 5th is a swap, not a 5th slot)
	local slots = A.D.core_slots or 4
	ui.separator_text(t("buy") .. (n_owned > 0 and ("  ·  " .. t("owned_n", math.min(n_owned, slots), slots)) or ""))
	for _, b in ipairs(result.build) do self:draw_slot(b, full) end
	ui.separator_text(t("threats"))
	for i = 1, math.min(full and 5 or 2, #result.threats) do
		local th = result.threats[i]
		local dc = danger_color(C, th.danger)
		ui.push_color(ui.Col.Text, dc[1], dc[2], dc[3], 1)
		ui.bullet()
		ui.pop_color(1)
		ui.same_line()
		G.wrapped(nil, self:threat_text(th, not full))
	end
	if full then
		ui.separator_text(t("forecast"))
		local fc = {}
		for _, a in ipairs(result.forecast) do
			if a.probability >= 30 then fc[#fc + 1] = t("archs_" .. a.key) .. " " .. a.probability .. "%" end
		end
		G.wrapped(nil, #fc > 0 and table.concat(fc, "  ·  ") or "-")
	end
	if ctx == "match" then
		if full then G.wrapped(C.DIM, t("hidden_in_match")) end
	else
		self:draw_counters(full)
	end
end

-- ------------------------------------------------------------------ panel window
-- Auto: detailed outside a match; in a match detailed for a few seconds after each change (new
-- enemy seen, purchase, phase), then compact. Small screens stay compact in a match.
function V:display_mode(now, sw)
	local A = self.A
	if A.cfg.display ~= "auto" then return A.cfg.display end
	if A.MATCH:context() ~= "match" then return "detailed" end
	local at = A.MATCH.changed_at
	if sw >= 1280 and at and now - at < AUTO_DETAIL_SECONDS then return "detailed" end
	return "compact"
end

-- Natural width of the panel content in the current font and language, clamped to the screen.
-- Cached: the key holds everything the measured texts depend on.
function V:natural_width(sw, mode)
	local A = self.A
	local t, MATCH = A.t, A.MATCH
	local key = table.concat({ MATCH.signature or "", A.ui_lang(), A.cfg.text_size, mode, MATCH:context(),
		A.font_key(), A.TX.version, MATCH:err_text(t) or "" }, "|")
	local hit = self.width_cache[key]
	if hit then return hit end
	local pad = 2 * 12 + 4
	local widest_chip, natural, widths = 0, 0, {}
	local function fit(s, extra)
		natural = math.max(natural, ui.calc_text_size(s) + (extra or 0))
	end
	A.with_font("bold", function() fit(self:header_text(mode ~= "compact")) end)
	local result = MATCH.result
	if not result then
		fit(t("press_menu", A.cfg.keys.menu) .. "  ·  " .. (MATCH:err_text(t) or ""))
	else
		for i, b in ipairs(result.build) do
			widths[i] = chip_size(self:chip_label(b))
			widest_chip = math.max(widest_chip, widths[i])
		end
	end
	local lo = math.max(mode == "compact" and 200 or 300, widest_chip + pad)
	local hi = math.max(lo, math.floor(sw * (mode == "compact" and 0.30 or 0.34)))
	if result then
		if mode == "compact" then
			-- the widest line once the chips wrap inside the cap, exactly as chip_flow draws them
			local cap, line, widest_line = hi - pad, 0, 0
			for i, w in ipairs(widths) do
				if i > 1 and line + CHIP_GAP + w <= cap then line = line + CHIP_GAP + w else line = w end
				widest_line = math.max(widest_line, line)
			end
			natural = math.max(natural, widest_line)
		else
			fit(t("badge_" .. self:badge_key(MATCH:context())))
			natural = math.max(natural, widest_chip)
			for i = 1, math.min(2, #result.threats) do fit(self:threat_text(result.threats[i], true), 22) end
		end
	end
	local w = math.floor(math.max(lo, math.min(hi, natural + pad)))
	self.width_n = self.width_n + 1
	if self.width_n > 64 then self.width_cache, self.width_n = {}, 1 end
	self.width_cache[key] = w
	return w
end

-- While the menu is open (and the panel unlocked) the panel can be dragged and resized: position and
-- width are remembered per layout.
function V:remember_drag(x, y, w, mode)
	local A = self.A
	local cfg = A.cfg
	A.G.wrapped(A.G.C.DIM, A.t("drag_hint", cfg.keys.lock))
	local wx, wy = ui.window_pos()
	if math.abs(wx - x) > 1 or math.abs(wy - y) > 1 then
		cfg.pos_x, cfg.pos_y = math.floor(wx), math.floor(wy)
		A.CFG:mark_dirty()
	end
	local ww = ui.window_width()
	if math.abs(ww - w) > 2 and type(cfg.overlay_w) == "table" then
		cfg.overlay_w[mode] = math.floor(ww)
		A.CFG:mark_dirty()
	end
end

function V:draw_overlay(now)
	local A = self.A
	local cfg = A.cfg
	local WF, COND = ui.WindowFlags, ui.Cond
	local sw, sh = ui.screen()
	local mode = self:display_mode(now, sw)
	A.S.last_mode = mode
	local w
	A.with_font("body", function() w = self:natural_width(sw, mode) end)
	-- a width dragged by hand wins over the automatic one
	local manual_w = type(cfg.overlay_w) == "table" and tonumber(cfg.overlay_w[mode]) or 0
	if manual_w and manual_w > 0 then w = math.floor(math.max(160, math.min(sw - 16, manual_w))) end
	local x = cfg.pos_x >= 0 and cfg.pos_x or (sw - w - 24)
	local y = cfg.pos_y >= 0 and cfg.pos_y or math.floor(sh * 0.18)
	x = math.max(0, math.min(x, sw - w))
	y = math.max(0, math.min(y, sh - math.max(60, self.last_h) - 8))
	local draggable = A.state.menu_open and not cfg.locked
	local bor = bit.bor
	local flags = bor(WF.NoTitleBar, WF.NoCollapse, WF.NoSavedSettings, WF.NoFocusOnAppearing, WF.NoNav,
		WF.NoScrollbar, WF.NoScrollWithMouse or 0)
	if not draggable then flags = bor(flags, WF.NoInputs, WF.NoMove, WF.NoResize) end
	if not draggable or not self.was_draggable then ui.set_next_window_pos(x, y, COND.Always) end
	self.was_draggable = draggable
	ui.set_next_window_size(w, 0, COND.Always)   -- height 0 = fit the content (no scrolling)
	ui.set_next_window_bg_alpha(cfg.opacity)
	ui.window("##smartcounter_overlay", { flags = flags }, function()
		A.with_font("body", function()
			if mode == "compact" then self:draw_compact() else self:draw_detailed(false) end
			if draggable then self:remember_drag(x, y, w, mode) end
			self.last_h = ui.window_height()
		end)
	end)
end

-- Short tip at launch, centred near the top, fading out.
function V:draw_tip(now)
	local A = self.A
	self.tip_start = self.tip_start or now
	local el = now - self.tip_start
	if el > TIP_SECONDS then
		A.S.tip_done = true
		return
	end
	local a = el > TIP_SECONDS - 2 and (TIP_SECONDS - el) / 2 or 1
	local msg = A.t("tip", A.cfg.keys.menu, A.cfg.keys.overlay)
	A.with_font("body", function()
		local sw, sh = ui.screen()
		local tw, th = ui.calc_text_size(msg)
		local x, y = math.floor((sw - tw) / 2), math.floor(sh * 0.08)
		ui.fg.rect_filled(x - 14, y - 8, x + tw + 14, y + th + 8, ui.rgb(0x0F1118, 0.78 * a), 7)
		ui.fg.rect(x - 14, y - 8, x + tw + 14, y + th + 8, ui.rgb(0xDBA43C, 0.6 * a), 7, 1)
		ui.fg.text(x, y, ui.rgb(0xFFD266, a), "%s", msg)
	end)
end

return V
