-- Counter & Shop Helper: the menu (Match, Settings, Help & About tabs) and the first-run tutorial.

local M = {}
M.__index = M

local ROLES = { "", "Frontline", "Damage", "Flank", "Support" }   -- "" = all roles (filter)
local TUT_STEPS = 4

-- A: the app context (main.lua), VIEW: sc_view (the Match tab ends with the full detailed view)
function M.new(A, VIEW)
	local champions = {}
	for _, c in ipairs(A.D.champions) do champions[#champions + 1] = c.name end
	table.sort(champions)
	-- manual item editor: the shop grid (4 categories x 5, shop order)
	local by_cat = {}
	for _, name in ipairs(A.D.item_order) do
		local c = A.D.items[name].category or "Other"
		by_cat[c] = by_cat[c] or {}
		table.insert(by_cat[c], name)
	end
	return setmetatable({ A = A, V = VIEW, champions = champions, items_by_cat = by_cat,
		role_filter = 1, want_tab = nil, cur_tab = nil, tut_step = nil }, M)
end

-- ------------------------------------------------------------------ shared widgets
-- UI language picker: Auto (the game's language) + the 8 languages, each in its own name.
function M:lang_picker(id)
	local A = self.A
	local L, cfg = A.L, A.cfg
	local labels, keys, cur = { A.t("lang_auto", L.native(A.game_lang())) }, { "auto" }, 1
	for _, l in ipairs(L.LANGS) do
		labels[#labels + 1], keys[#keys + 1] = l[2], l[1]
		if cfg.lang == l[1] then cur = #keys end
	end
	A.G.ui.set_next_item_width(260)
	local i, changed = A.G.ui.combo("##lang_" .. id, cur, labels)
	if changed and keys[i] then A.set_lang(keys[i]) end
end

-- Champions of the role filter, sorted by the name shown (the game's, in its language). Rebuilt when
-- the filter or the names change.
function M:champion_choices(role)
	local A = self.A
	local key = role .. "|" .. A.TX.version
	if self.choices_key ~= key then
		local list = {}
		for _, n in ipairs(self.champions) do
			if role == "" or A.PRED:champion(n).role == role then
				list[#list + 1] = { key = n, label = A.TX:champion(n) }
			end
		end
		table.sort(list, function(a, b)
			local la, lb = a.label:lower(), b.label:lower()
			if la ~= lb then return la < lb end
			return a.key < b.key
		end)
		self.choices_key, self.choices = key, list
	end
	return self.choices
end

-- Champion combo filtered by role. Shows the game's names, stores the internal key ("" = Auto).
function M:champ_combo(label, current)
	local A = self.A
	local keys, labels = { "" }, { "(" .. A.t("auto") .. ")" }
	local has_current = current == ""
	for _, c in ipairs(self:champion_choices(ROLES[self.role_filter])) do
		keys[#keys + 1], labels[#labels + 1] = c.key, c.label
		if c.key == current then has_current = true end
	end
	if not has_current then
		table.insert(keys, 2, current)
		table.insert(labels, 2, A.TX:champion(current))
	end
	local idx = 1
	for i, n in ipairs(keys) do
		if n == current then idx = i end
	end
	local ni, changed = A.G.ui.combo(label, idx, labels)
	if changed then return keys[ni] or "", true end
	return current, false
end

-- ------------------------------------------------------------------ Match tab
function M:status_text(st)
	local A = self.A
	local t = A.t
	if not A.cfg.auto_detect then return t("st_off") end
	local parts = { t("st_auto", t("st_" .. tostring(st.status))) }
	if st.map then parts[#parts + 1] = st.map end
	if st.me then parts[#parts + 1] = t("st_me", A.TX:champion(st.me)) end
	if #(st.enemies or {}) > 0 then parts[#parts + 1] = t("st_enemies", #st.enemies) end
	return table.concat(parts, "  ·  ")
end

-- Manual ranks, at most D.core_slots (4) items like the game: once 4 are set, the others are locked
-- until one goes back to 0.
function M:owned_editor()
	local A = self.A
	local ui, G, cfg = A.G.ui, A.G, A.cfg
	local slots, n = A.D.core_slots or 4, 0
	for _ in pairs(cfg.owned) do n = n + 1 end
	local full = n >= slots
	ui.table("sc_owned", 4, { flags = ui.TableFlags.SizingStretchSame or 0 }, function()
		for _, cat in ipairs(A.D.item_categories) do
			ui.table_next_column()
			G.tcol(G.C.ACCENT, self.V:category(cat))
			for _, n in ipairs(self.items_by_cat[cat] or {}) do
				ui.push_id("own_" .. n)
				local r = cfg.owned[n] or 0
				local locked = full and r == 0
				ui.text("%s", A.TX:item(n))
				ui.set_next_item_width(-1)
				if locked and ui.begin_disabled then ui.begin_disabled(true) end
				local max_r = A.PRED.ranks(A.D, n)
				local v, c = ui.slider_int("##rank", r, 0, max_r, r == 0 and "-" or self.V.roman(r))
				if locked and ui.end_disabled then ui.end_disabled() end
				if c and not locked then
					v = math.max(0, math.min(max_r, v))
					cfg.owned[n] = v > 0 and v or nil
					A.CFG:mark_dirty()
				end
				ui.pop_id()
			end
		end
	end)
	if full then G.wrapped(G.C.DIM, A.t("owned_full")) end
	if ui.small_button(A.t("owned_reset")) then
		cfg.owned = {}
		A.CFG:mark_dirty()
	end
end

function M:owned_section()
	local A = self.A
	local G, C, t, st = A.G, A.G.C, A.t, A.PLAYER.state
	A.G.ui.separator_text(t("owned_hdr"))
	if A.cfg.live_items and st.available then
		local names = {}
		for n, r in pairs(st.owned) do names[#names + 1] = A.TX:item(n) .. " " .. self.V.roman(r) end
		table.sort(names)
		G.wrapped(C.GOOD, t("owned_live", st.source))
		G.wrapped(nil, #names > 0 and table.concat(names, ", ") or t("owned_none"))
	else
		G.wrapped(C.DIM, t("owned_manual"))
		if A.cfg.live_items then G.wrapped(C.DIM, t("owned_wait")) end
		self:owned_editor()
		G.wrapped(C.DIM, t("owned_hint"))
	end
	if A.cfg.live_items then
		if ui.small_button(t("owned_diag")) then A.items_diag() end
		if ui.is_item_hovered and ui.is_item_hovered() then pcall(ui.set_tooltip, "%s", t("owned_diag_tip")) end
	end
end

function M:pick_section()
	local A = self.A
	local ui, cfg, t, DET = A.G.ui, A.cfg, A.t, A.DET
	ui.separator_text(t("my_champion"))
	ui.set_next_item_width(220)
	local me, ch = self:champ_combo("##me", cfg.manual.me)
	if ch then cfg.manual.me = me; A.CFG:mark_dirty() end
	if cfg.manual.me == "" then
		local auto = DET.state.me or A.MATCH.cs_me
		ui.same_line()
		ui.text_disabled("%s", t("auto") .. ": " .. (auto and A.TX:champion(auto) or t("not_detected")))
	end
	local inputs = A.MATCH.inputs
	local styles = A.PRED:styles_for(inputs and inputs.me)
	if #styles > 1 then
		ui.align_text_to_frame_padding()
		ui.text("%s", t("playstyle"))
		ui.same_line()
		if ui.radio(t("auto") .. "##st", cfg.style == "auto") then cfg.style = "auto"; A.CFG:mark_dirty() end
		for _, s in ipairs(styles) do
			ui.same_line()
			if ui.radio(t("style_" .. s) .. "##st", cfg.style == s) then cfg.style = s; A.CFG:mark_dirty() end
		end
		A.G.wrapped(A.G.C.DIM, t("playstyle_hint"))
	end
end

function M:enemies_section()
	local A = self.A
	local ui, cfg, t, D = A.G.ui, A.cfg, A.t, A.D
	ui.separator_text(t("enemies_hdr"))
	local role_items = {}
	for i, r in ipairs(ROLES) do role_items[i] = r == "" and t("all_roles") or self.V:role(r) end
	ui.set_next_item_width(180)
	local rf, rch = ui.combo(t("role_filter"), self.role_filter, role_items)
	if rch then self.role_filter = rf end
	ui.table("sc_enemies", 2, { flags = ui.TableFlags.SizingStretchSame or 0 }, function()
		for i = 1, D.max_enemies do
			ui.table_next_column()
			ui.set_next_item_width(-1)
			local v, c = self:champ_combo("##enemy" .. i, cfg.manual.enemies[i])
			if c then cfg.manual.enemies[i] = v; A.CFG:mark_dirty() end
		end
		ui.table_next_column()
		if ui.button(t("clear_all"), -1, 0) then
			cfg.manual.me = ""
			for i = 1, D.max_enemies do cfg.manual.enemies[i] = "" end
			A.CFG:mark_dirty()
		end
	end)
	local inputs = A.MATCH.inputs
	if inputs and #inputs.enemies > inputs.manual_n then
		local names = {}
		for i = inputs.manual_n + 1, #inputs.enemies do names[#names + 1] = A.TX:champion(inputs.enemies[i]) end
		A.G.wrapped(A.G.C.DIM, t("filled_auto", table.concat(names, ", ")))
	end
end

function M:phase_mode_section()
	local A = self.A
	local ui, cfg, t = A.G.ui, A.cfg, A.t
	ui.separator_text(t("phase_mode"))
	ui.align_text_to_frame_padding()
	ui.text("%s", t("phase"))
	for _, p in ipairs({ "auto", "early", "mid", "late" }) do
		ui.same_line()
		if ui.radio((p == "auto" and t("auto") or t("phase_" .. p)) .. "##ph", cfg.phase == p) then
			cfg.phase = p
			A.CFG:mark_dirty()
		end
	end
	local items, keys, cur = { t("auto") }, { "auto" }, 1
	for _, m in ipairs(A.D.modes) do
		items[#items + 1], keys[#keys + 1] = t("mode_" .. m.key), m.key
		if cfg.mode == m.key then cur = #keys end
	end
	ui.set_next_item_width(220)
	local mi, changed = ui.combo(t("mode"), cur, items)
	if changed then cfg.mode = keys[mi]; A.CFG:mark_dirty() end
end

function M:tab_match()
	local A = self.A
	A.G.wrapped(A.G.C.DIM, self:status_text(A.DET.state))
	self:pick_section()
	self:enemies_section()
	self:phase_mode_section()
	self:owned_section()
	A.G.ui.spacing()
	A.G.ui.separator()
	A.MATCH:update()   -- the choices above may have changed the inputs this frame
	self.V:draw_detailed(true)
end

-- ------------------------------------------------------------------ Settings tab
-- What the names setting does right now: "game in Français, mod in English, names in English".
-- nil while the game's language is unknown.
function M:names_now()
	local A = self.A
	local TX, L = A.TX, A.L
	if not TX.lang_code then return nil end
	local game = TX.UI_LANG[TX.lang_code]
	local game_name = game and L.native(game) or TX.lang_code
	local names = TX:names_ok("name") and game_name or L.native("en")
	return A.t("set_game_names_now", game_name, L.native(A.ui_lang()), names)
end

function M:checkbox(key, field)
	local A = self.A
	local v, c = A.G.ui.checkbox(A.t(key), A.cfg[field])
	if c then A.cfg[field] = v; A.CFG:mark_dirty() end
end

function M:display_settings()
	local A = self.A
	local ui, cfg, t = A.G.ui, A.cfg, A.t
	ui.separator_text(t("set_display"))
	self:checkbox("set_show_on_start", "show_on_start")
	self:checkbox("set_show_tip", "show_tip")
	self:checkbox("set_auto", "auto_detect")
	self:checkbox("set_live_items", "live_items")
	self:checkbox("set_game_names", "game_names")
	if ui.is_item_hovered and ui.is_item_hovered() then pcall(ui.set_tooltip, "%s", t("set_game_names_tip")) end
	A.G.wrapped(A.G.C.DIM, t("set_game_names_hint"))
	local now = self:names_now()
	if now then A.G.wrapped(A.G.C.ACCENT, now) end
	ui.align_text_to_frame_padding()
	ui.text("%s", t("set_mode"))
	for _, d in ipairs({ "auto", "compact", "detailed" }) do
		ui.same_line()
		if ui.radio(t("disp_" .. d) .. "##disp", cfg.display == d) then cfg.display = d; A.CFG:mark_dirty() end
	end
	ui.set_next_item_width(220)
	local v, c = ui.slider_float(t("set_opacity"), cfg.opacity, 0.2, 1.0, "%.2f")
	if c then cfg.opacity = v; A.CFG:mark_dirty() end
	ui.set_next_item_width(220)
	v, c = ui.slider_int(t("set_text"), cfg.text_size, 1, 3, ({ "S", "M", "L" })[cfg.text_size])
	if c then cfg.text_size = math.max(1, math.min(3, v)); A.CFG:mark_dirty() end
	self:checkbox("set_lock", "locked")
	if ui.button(t("set_reset_pos")) then
		cfg.pos_x, cfg.pos_y, self.V.was_draggable = -1, -1, false
		A.CFG:mark_dirty()
	end
	ui.same_line()
	if ui.button(t("set_auto_width")) then
		cfg.overlay_w = { compact = 0, detailed = 0 }
		A.CFG:mark_dirty()
	end
	ui.same_line()
	if ui.button(t("set_tutorial")) then self.tut_step = 1 end
end

function M:key_settings()
	local A = self.A
	local ui, G, C, t, K, keys = A.G.ui, A.G, A.G.C, A.t, A.KEYS, A.cfg.keys
	ui.separator_text(t("set_keys"))
	ui.table("sc_keys", 3, { flags = ui.TableFlags.SizingStretchProp or 0 }, function()
		for _, a in ipairs(K.ACTIONS) do
			ui.push_id(a)
			ui.table_next_row()
			ui.table_next_column()
			ui.align_text_to_frame_padding()
			G.wrapped(nil, t("act_" .. a))
			ui.table_next_column()
			ui.align_text_to_frame_padding()
			G.tcol(C.ACCENT, K.rebinding == a and "..." or keys[a])
			ui.table_next_column()
			if K.rebinding ~= a and ui.small_button(t("key_change")) then K:start(a) end
			if keys[a] ~= K.defaults[a] then
				ui.same_line()
				if ui.small_button(t("key_default")) then K:restore_default(a) end
			end
			ui.pop_id()
		end
	end)
	if K.rebinding then G.wrapped(C.ACCENT, t("key_press")) end
	if K.msg then G.wrapped(K.msg_ok and C.GOOD or C.WARN, K.msg) end
	G.wrapped(C.DIM, t("key_hint"))
	if K.rebinding then K:poll() end
end

function M:tab_settings()
	self.A.G.ui.separator_text(self.A.t("set_language"))
	self:lang_picker("set")
	self:display_settings()
	self:key_settings()
end

-- ------------------------------------------------------------------ Help & About tab
function M:tab_help()
	local A = self.A
	local ui, G, C, t, keys = A.G.ui, A.G, A.G.C, A.t, A.cfg.keys
	G.wrapped(nil, t("help_keys", keys.menu, keys.overlay, keys.settings, keys.lock, keys.layout))
	ui.separator_text(t("help_cmds"))
	ui.bullet()
	ui.same_line()
	G.wrapped(nil, t("cmd_menu"))
	ui.separator_text(t("help_detect_t"))
	G.wrapped(nil, t("help_detect"))
	G.wrapped(nil, t("help_names"))
	ui.separator_text(t("help_about"))
	A.bold(C.ACCENT, t("title"))
	G.wrapped(nil, t("about_version", A.VERSION))
	A.bold(C.GOOD, t("about_credit", A.AUTHOR, A.DISCORD))
	G.wrapped(C.DIM, t("about_data", A.D.build))
	ui.separator_text(t("help_autobuy_t"))
	G.wrapped(C.DIM, t("help_autobuy"))
end

-- ------------------------------------------------------------------ tutorial (non-blocking)
function M:end_tutorial()
	local A = self.A
	self.tut_step = nil
	if not A.cfg.tutorial_done then
		A.cfg.tutorial_done = true
		A.CFG:mark_dirty()
	end
end

-- Next to the menu (right side when it fits, else left).
function M:draw_tutorial(mx, my, mw)
	local A = self.A
	local ui, t, keys, step = A.G.ui, A.t, A.cfg.keys, self.tut_step
	local sw = ui.screen()
	local tw = math.floor(340 * ({ 0.92, 1.0, 1.16 })[A.cfg.text_size])
	local tx = (mx + mw + tw + 16 < sw) and (mx + mw + 12) or math.max(0, mx - tw - 12)
	ui.set_next_window_pos(tx, my, ui.Cond.Always)
	ui.set_next_window_size(tw, 0, ui.Cond.Always)
	local text = t("tut" .. step)
	if step == 3 then text = t("tut3", keys.overlay, keys.layout, keys.lock) end
	if step == 4 then text = t("tut4", keys.settings) end
	local WF = ui.WindowFlags
	local open = ui.window(t("tut", step, TUT_STEPS) .. "###sc_tuto",
		{ open = true, flags = A.G.bor(WF.NoCollapse, WF.NoSavedSettings, WF.NoResize, WF.NoFocusOnAppearing) },
		function()
			A.with_font("body", function()
				A.bold(A.G.C.ACCENT, t("tut" .. step .. "_t"))
				A.G.wrapped(nil, text)
				if step == 1 then self:lang_picker("tut") end
				ui.spacing()
				if step > 1 then
					if ui.button(t("tut_prev")) then self.tut_step = step - 1 end
					ui.same_line()
				end
				if step < TUT_STEPS then
					if ui.button(t("tut_next")) then self.tut_step = step + 1 end
					ui.same_line()
					if ui.button(t("tut_skip")) then self:end_tutorial() end
				elseif ui.button(t("tut_done")) then
					self:end_tutorial()
				end
			end)
		end)
	if open == false then self:end_tutorial() end
end

-- ------------------------------------------------------------------ menu window
local TABS = { { "match", "tab_match" }, { "settings", "tab_settings" }, { "help", "tab_help" } }

function M:open_tab(id)
	self.want_tab = id
end

function M:draw()
	local A = self.A
	local ui, t, cfg = A.G.ui, A.t, A.cfg
	local sw, sh = ui.screen()
	local k = ({ 0.92, 1.0, 1.16 })[cfg.text_size]
	local w = math.floor(math.max(480, math.min(640, sw * 0.36)) * k)
	ui.set_next_window_pos(math.floor((sw - w) / 2), math.floor(sh * 0.1), ui.Cond.FirstUseEver)
	ui.set_next_window_size(w, math.floor(sh * 0.72), ui.Cond.FirstUseEver)
	local mx, my, mw = 0, 0, w
	-- Escape cancels a key rebinding (in the Settings tab) without closing the menu as well
	local was_rebinding = A.KEYS.rebinding ~= nil
	local open = ui.window(t("title") .. "###smartcounter_menu", { open = true, flags = ui.WindowFlags.NoCollapse }, function()
		A.with_font("body", function()
			mx, my = ui.window_pos()
			mw = ui.window_width()
			ui.tab_bar("sc_tabs", function()
				for _, tab in ipairs(TABS) do
					local opts = { flags = (self.want_tab == tab[1]) and ui.TabItemFlags.SetSelected or 0 }
					ui.tab_item(t(tab[2]) .. "###tab_" .. tab[1], opts, function()
						self.cur_tab = tab[1]
						self[tab[2]](self)
					end)
				end
				self.want_tab = nil
			end)
			ui.spacing()
			ui.separator()
			ui.text_disabled("%s", t("title") .. "  ·  v" .. A.VERSION .. "  ·  " .. t("about_credit", A.AUTHOR, A.DISCORD))
			if not was_rebinding and not A.KEYS.rebinding and A.KEYS.pressed("Escape") then A.set_menu(false) end
		end)
	end)
	if open == false then A.set_menu(false) end
	if A.state.menu_open and self.tut_step then self:draw_tutorial(mx, my, mw) end
end

return M
