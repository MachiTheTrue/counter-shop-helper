-- Offline tests of the Lua mod, run by engine/tests/run_lua_tests.ps1 with the game's own Lua51.dll
-- (working directory = the mod folder). No game needed: `tempest`, `ui` and the game objects are mocks.
--
--   1. predictor parity: sc_predictor.lua gives the same results as predictor.py (tests/expected.lua)
--   2. sc_text / sc_player / sc_detect on mock game objects (reflection API shapes)
--   3. main.lua end to end: every game state, the 8 UI languages, keys, rebinding, config saving,
--      hot reload. Each frame checks that the ImGui stacks are balanced, that no draw error was logged,
--      and that no untranslated key, format code or game markup reaches the screen.
--
-- The report is written to %TEMP%\smartcounter_lua_tests.txt; any failure raises an error at the end.

package.path = "src/scripts/?.lua;" .. package.path

local REPORT = (os.getenv("TEMP") or ".") .. "\\smartcounter_lua_tests.txt"
local passed, failed, lines = 0, 0, {}

local function note(s) lines[#lines + 1] = s end

local function check(cond, what)
	if cond then
		passed = passed + 1
	else
		failed = failed + 1
		note("FAIL " .. what)
	end
	return cond
end

local function section(name) note("== " .. name) end

-- ------------------------------------------------------------------ LuaJIT's `bit` (the game has it; Lua 5.1 does not)
-- ImGui flags are distinct single bits, so OR is their sum when each appears once.
bit = bit or { bor = function(...)
	local s = 0
	for _, v in ipairs({ ... }) do s = s + v end
	return s
end }

-- ------------------------------------------------------------------ fake clock
local NOW = 100
os.clock = function() return NOW end   -- deterministic throttling (detection, items, saving)

-- ------------------------------------------------------------------ ui mock
local function enum()
	local n = 0
	return setmetatable({}, { __index = function(t, k)
		n = n + 1
		local v = 2 ^ (n - 1)
		rawset(t, k, v)
		return v
	end })
end

local MOCK = {}

local function strip_id(s)
	s = tostring(s or "")
	return (s:gsub("##.*$", ""))
end

function MOCK.reset_frame()
	MOCK.stack = { color = 0, var = 0, font = 0, id = 0, indent = 0, disabled = 0 }
	MOCK.shown = {}
	MOCK.draws = {}   -- draw-list calls of the frame: { k = "fill" | "edge" | "text", x1, y1, x2, y2, ... }
	MOCK.disabled_n = 0
end

local function show(s)
	s = strip_id(s)
	if s ~= "" then MOCK.shown[#MOCK.shown + 1] = s end
end

-- printf-style calls: ui.text("%s", s)
local function show_fmt(fmt, ...)
	if fmt == "%s" then show((...)) else show(fmt) end
end

local function clicked(label)
	local l = strip_id(label)
	if MOCK.click and MOCK.click[l] then
		MOCK.click[l] = nil
		return true
	end
	return false
end

local function call_fns(...)
	for i = 1, select("#", ...) do
		local f = select(i, ...)
		if type(f) == "function" then f() end
	end
end

local function new_ui()
	MOCK.fonts_added, MOCK.capture, MOCK.keys_pressed, MOCK.keys_down, MOCK.tab_sel = {}, nil, {}, {}, nil
	MOCK.reset_frame()
	local u = {
		WindowFlags = enum(), Cond = enum(), Col = enum(), StyleVar = enum(), TableFlags = enum(),
		TabItemFlags = enum(), Key = enum(),
	}
	local function rec(d) MOCK.draws[#MOCK.draws + 1] = d end
	local draw_list = {
		line = function() end,
		rect_filled = function(x1, y1, x2, y2, c, r) rec({ k = "fill", x1 = x1, y1 = y1, x2 = x2, y2 = y2, c = c, r = r }) end,
		rect = function(x1, y1, x2, y2, c, r, t) rec({ k = "edge", x1 = x1, y1 = y1, x2 = x2, y2 = y2, c = c, r = r, t = t or 1 }) end,
		text = function(x, y, c, fmt, s)
			rec({ k = "text", x1 = x, y1 = y, c = c, s = s })
			show_fmt(fmt, s)
		end,
	}
	u.dl, u.fg = draw_list, draw_list
	u.on_draw = function(fn) MOCK.draw = fn end
	u.ready = function() return true end
	u.capture = function(on) MOCK.capture = on end
	u.add_font = function(path, size, opts)
		MOCK.fonts_added[#MOCK.fonts_added + 1] = { path = path, size = size, merge = opts and opts.merge }
		return { path = path or "built-in", size = size }
	end
	u.rgb = function(hex, a) return hex + (a or 1) end
	u.color = function(r, g, b, a) return { r, g, b, a or 1 } end
	u.cursor_screen_pos = function() return 20, 40 end
	u.dummy = function() end
	u.begin_disabled = function()
		MOCK.stack.disabled = MOCK.stack.disabled + 1
		MOCK.disabled_n = MOCK.disabled_n + 1
	end
	u.end_disabled = function() MOCK.stack.disabled = MOCK.stack.disabled - 1 end
	u.screen = function() return 1920, 1080 end
	u.calc_text_size = function(s) return #tostring(s) * 7, 16 end
	u.window_pos = function() return 100, 100 end
	u.window_width = function() return 420 end
	u.window_height = function() return 300 end
	u.content_region_avail = function() return 390 end
	u.item_rect_min = function() return 10, 10 end
	u.item_rect_max = function() return 90, 30 end
	u.is_item_hovered = function() return true end
	u.key_pressed = function(k) return MOCK.keys_pressed[k] == true end
	u.key_down = function(k) return MOCK.keys_down[k] == true end
	-- scoped widgets: run their body
	for _, name in ipairs({ "child", "group", "tooltip", "tab_bar", "popup", "tree", "menu", "with_font" }) do
		u[name] = function(...) call_fns(...) return true end
	end
	u.window = function(title, opts, fn) show(title); if fn then fn() end; return true end
	-- tabs: like ImGui, only the selected tab's body runs (the first one, or the one asked with SetSelected)
	u.tab_item = function(label, opts, fn)
		show(label)
		local id = tostring(label):match("###(.+)$") or label
		if (opts and opts.flags or 0) ~= 0 or MOCK.tab_sel == nil then MOCK.tab_sel = id end
		if fn and MOCK.tab_sel == id then fn() end
		return true
	end
	u.table = function(id, n, opts, fn) if fn then fn() end; return true end
	-- stacks (checked after every frame)
	u.push_color = function() MOCK.stack.color = MOCK.stack.color + 1 end
	u.pop_color = function(n) MOCK.stack.color = MOCK.stack.color - (n or 1) end
	u.push_var = function() MOCK.stack.var = MOCK.stack.var + 1 end
	u.pop_var = function(n) MOCK.stack.var = MOCK.stack.var - (n or 1) end
	u.push_font = function() MOCK.stack.font = MOCK.stack.font + 1 end
	u.pop_font = function() MOCK.stack.font = MOCK.stack.font - 1 end
	u.push_id = function() MOCK.stack.id = MOCK.stack.id + 1 end
	u.pop_id = function() MOCK.stack.id = MOCK.stack.id - 1 end
	u.indent = function(w) MOCK.stack.indent = MOCK.stack.indent + (w or 0) end
	u.unindent = function(w) MOCK.stack.indent = MOCK.stack.indent - (w or 0) end
	-- text
	u.text = show_fmt
	u.text_wrapped = show_fmt
	u.text_disabled = show_fmt
	u.set_tooltip = show_fmt
	u.text_colored = function(_, _, _, _, fmt, s) show_fmt(fmt, s) end
	u.separator_text = show
	u.progress_bar = function(_, _, _, label) show(label) end
	-- widgets
	u.button = function(label) show(label); return clicked(label) end
	u.small_button = u.button
	u.radio = function(label) show(label); return clicked(label) end
	u.checkbox = function(label, v)
		show(label)
		if clicked(label) then return not v, true end
		return v, false
	end
	MOCK.combos = {}
	u.combo = function(label, idx, items)
		MOCK.combos[label] = items
		show(label)
		for _, s in ipairs(items or {}) do show(s) end
		local want = MOCK.combo and MOCK.combo[strip_id(label) ~= "" and strip_id(label) or label]
		if want then
			MOCK.combo[strip_id(label) ~= "" and strip_id(label) or label] = nil
			return want, true
		end
		return idx, false
	end
	u.slider_int = function(label, v) show(label); return v, false end
	u.slider_float = function(label, v) show(label); return v, false end
	for _, name in ipairs({ "same_line", "set_next_item_width", "table_next_column", "table_next_row",
		"align_text_to_frame_padding", "spacing", "separator", "bullet", "set_next_window_pos",
		"set_next_window_size", "set_next_window_bg_alpha" }) do
		u[name] = function() end
	end
	return u
end

-- ------------------------------------------------------------------ tempest mock
local function new_tempest(saved)
	local T = { logs = {}, toasts = {}, keys = {}, commands = {}, queued = {}, saves = 0, saved = saved,
		player = nil }
	local next_key = 0
	T.api = {
		log = function(s) T.logs[#T.logs + 1] = s end,
		toast = function(s) T.toasts[#T.toasts + 1] = s end,
		config = function(defaults)
			for k, v in pairs(T.saved or {}) do defaults[k] = v end
			T.values = defaults   -- the table the mod keeps as its settings
			return defaults
		end,
		save_config = function(values)
			T.saves = T.saves + 1
			T.last_saved = values
		end,
		on_key = function(spec, fn)
			if type(spec) ~= "string" or not spec:match("^[%w%+]+$") then error("bad key " .. tostring(spec)) end
			next_key = next_key + 1
			T.keys[next_key] = { spec = spec, fn = fn }
			return next_key
		end,
		off_key = function(id) T.keys[id] = nil end,
		command = function(name, fn) T.commands[name] = fn end,
		queue = function(fn) T.queued[#T.queued + 1] = fn end,
		local_player = function() return T.player end,
		engine = function() return MOCK.engine end,
	}
	function T.press(spec)
		for _, k in pairs(T.keys) do
			if k.spec == spec then return k.fn() end
		end
		error("no key bound to " .. spec)
	end
	function T.bound(spec)
		for _, k in pairs(T.keys) do
			if k.spec == spec then return true end
		end
		return false
	end
	return T
end

-- ------------------------------------------------------------------ game object mocks
local function list(t)
	t = t or {}
	t.items = function(self)
		local i = 0
		return function()
			i = i + 1
			if self[i] ~= nil then return i, self[i] end
		end
	end
	return t
end

local next_ptr = 0
local function obj(class, t, fixed_ptr)
	t = t or {}
	next_ptr = next_ptr + 1
	local p = fixed_ptr or next_ptr
	t.class = function() return { name = function() return class end } end
	t.ptr = function() return p end
	t.is_a = function(_, c)
		if c == class or c == t._is_a then return true end
		for _, x in ipairs(t._parents or {}) do
			if x == c then return true end
		end
		return false
	end
	return t
end

-- The HUD's Scaleform movie (champion select reads its UI data manager). Names no longer come from
-- it: they come from the Lang files (lang mock below).
local function movie(_, extra)
	local m = obj("TgClient.TgClientHUDMovie", extra or {})
	m._is_a = "TgClient.UIMoviePlayer"
	return m
end

-- ------------------------------------------------------------------ Game Data API mocks (1.1.0)
-- assembly answers with the rows of engine/tests/game_ids.lua (ids only, written by export_lua.py);
-- rows are strict like the real ones: a field name no row of the table has raises an error, a field
-- this row lacks is nil. lang answers "<prefix><id>" with the game's markup in each installed
-- language (no Lang_ITA.dat, like the 8.1 install); some ids have no text. GAME.lang is the language
-- the client runs in, as the engine answers it (Object.GetLanguage on tempest.engine()); GAME.arg is
-- what lang.language() answers: a -language= start argument, else INT. A Steam client in French runs
-- in FRA with no argument (the 0.7.0 match test): GAME.lang = "FRA", GAME.arg = "INT".
local IDS = dofile("engine/tests/game_ids.lua")
local GAME = { lang = "INT", arg = "INT", loads = {}, unloads = {}, finds = 0, missing = {}, fail = nil,
	installed = { INT = "EN", FRA = "FR", DEU = "DE", ESL = "ES", RUS = "RU", CHN = "ZH", JPN = "名前", KOR = "KO" } }
local function strict_rows(rows)
	local known = {}
	for _, r in ipairs(rows) do
		for k in pairs(r) do known[k] = true end
	end
	local mt = { __index = function(_, k) if not known[k] then error("no field " .. tostring(k), 2) end end }
	for _, r in ipairs(rows) do
		for _, v in pairs(r) do
			if type(v) == "table" then strict_rows(v) end
		end
		setmetatable(r, mt)
	end
end
for _, set in ipairs({ "BOTS", "DEVICES", "ITEMS" }) do strict_rows(IDS[set]) end
_G.assembly = {
	load = function()
		if GAME.fail then return nil, GAME.fail end
		return true
	end,
	unload = function() GAME.asm_unloaded = true end,
	find = function(set, field, value)
		GAME.finds = GAME.finds + 1
		for _, r in ipairs(IDS[set] or error("no table " .. tostring(set))) do
			if r[field] == value then return r end
		end
		return nil
	end,
}
MOCK.engine = obj("Engine.GameEngine", { GetLanguage = function() return GAME.lang end })
_G.lang = {
	language = function() return GAME.arg end,
	load = function(ext)
		ext = ext or GAME.arg
		if not GAME.installed[ext] then return nil, "no Lang_" .. ext .. ".dat" end
		GAME.loads[#GAME.loads + 1] = ext
		return true
	end,
	unload = function(ext) GAME.unloads[#GAME.unloads + 1] = ext or GAME.arg end,
	message = function(id, ext)
		local prefix = GAME.installed[ext or GAME.arg]
		if not prefix or id % 97 == 0 or GAME.missing[id] then return nil end
		return "<font color=\"#FFD266\">" .. prefix .. id .. "</font> {25}%"
	end,
	find = function(field, value)
		assert(field == "NAME", field)
		local id = IDS.lang_names[value]
		return id and { MSG_ID = id, NAME = value } or nil
	end,
}
-- The text the lang mock gives for an id in a language (nil when it has none), as sc_text cleans it.
local function game_text(prefix, id)
	return id and id % 97 ~= 0 and (prefix .. id .. " 25%") or nil
end
local EN   -- EN(name): the champion's English name from the game (set once DATA is filled)

local DATA = require("lib.sc_data")
local GameData = require("lib.sc_gamedata")
section("sc_gamedata: roles, message ids and shop ranks from the game data")
do
	check(DATA.champions[1].role == nil and DATA.items.Haven.name_msg == nil and DATA.max_rank == nil,
		"sc_data.lua ships no role, message id or rank count")
	GAME.fail = "missing file"
	local ok, why = GameData.load(DATA)
	check(ok == nil and why == "assembly.dat: missing file", "no game data: nil and why (" .. tostring(why) .. ")")
	GAME.fail = nil
	ok, why = GameData.load(DATA)
	check(ok == true and GAME.asm_unloaded, "game data read, then the file is freed (" .. tostring(why) .. ")")
	local roles_ok, abil_ok = true, true
	for _, c in ipairs(DATA.champions) do
		if c.role ~= IDS.roles[c.name] or not c.name_msg then roles_ok = false end
		for _, a in ipairs(c.abilities) do
			if not a.name_msg then abil_ok = false end
		end
	end
	check(roles_ok, "every champion's role from its Roles tag, as the engine data has it")
	check(abil_ok, "every ability named through its slot's device")
	local items_ok = true
	for _, k in ipairs(DATA.item_order) do
		local it = DATA.items[k]
		if not (it.name_msg and it.desc_msg and it.ranks == 3) then items_ok = false end
	end
	check(items_ok and DATA.max_rank == 3, "items: name, description, 3 ranks from the device modes")
	check(DATA.role_msg.Frontline == IDS.lang_names.PALADINS_ARCHETYPE_TANK and DATA.category_msg.Weapon ~= nil,
		"role and category labels found by message name")
	check(not pcall(function() return IDS.BOTS[1].NAME_MSGID end), "mock rows are strict: a mistyped field raises")
	-- a champion the game data does not have: all or nothing
	local lost = { champions = { { name = "Nobody", bot_id = 1, abilities = {} } }, items = {}, item_order = {} }
	ok, why = GameData.load(lost)
	check(ok == nil and why:find("Nobody", 1, true), "an unknown champion: nil and why (" .. tostring(why) .. ")")
end
local function champ(name)
	for _, c in ipairs(DATA.champions) do
		if c.name == name then return c end
	end
	error("no champion " .. name)
end
EN = function(name) return game_text("EN", champ(name).name_msg) or name end

-- One TgPawn_* class per champion in the game (sc_data.lua does not list them: the bot id is asked).
local function pawn_class(name)
	return "TgPawn_" .. (champ(name).name:gsub("[^%w]", ""))
end

-- GetBotId is the champion's bot id; GetArchetypeBotId is the role archetype (LiveCheck log: 2573 Front
-- Line ... 2576 Flank), never a champion.
local ARCHETYPE_BOT = { Frontline = 2573, Damage = 2574, Support = 2575, Flank = 2576 }
local function pawn_of(name)
	local c = champ(name)
	return obj(pawn_class(name), {
		GetBotId = function() return c.bot_id end,
		GetArchetypeBotId = function() return ARCHETYPE_BOT[c.role] end,
		_parents = { "TgGame.TgPawn_Character", "TgGame.TgPawn" },   -- every champion pawn in 8.1
	})
end

-- The items of a player as TgRepInfo_Player replicates them: the scoreboard slots (r_PlayerDevices:
-- deck cards, then the shop items at Level 0) and the shop items with their rank (r_TempItems).
-- entries = { { item id, nRank }, ... }
local function give_items(pri, entries)
	local slots, temp = { { CurrentDeviceId = 24554, Level = 5 }, { CurrentDeviceId = 24622, Level = 0 } }, {}
	for _, e in ipairs(entries) do
		slots[#slots + 1] = { CurrentDeviceId = e[1], Level = 0 }
		temp[#temp + 1] = { nDevId = e[1], nRank = e[2] }
	end
	pri.r_PlayerDevices, pri.r_TempItems = slots, temp
	return pri
end

local function pri_items(entries)
	return give_items(obj("TgGame.TgRepInfo_Player", {}), entries)
end

local function pri_of(name, tf, fixed_ptr)
	return obj("TgGame.TgRepInfo_Player", { r_PawnOwner = pawn_of(name), GetTaskForceNumber = function() return tf end },
		fixed_ptr)
end

-- The HUD's match roster (UIData_Match): my team's picks, the local player first.
local function roster(match_id, picks)
	local members = {}
	for i, n in ipairs(picks) do
		members[i] = { m_nMctsMatchIndex = i - 1, pPlayerData = { bIsSelf = i == 1 }, m_sName = "player" .. i,
			m_CurrentAllyCustomizeState = { nBotId = n and champ(n).bot_id or 0 } }
	end
	return { m_Match = { dwMatchId = { A = match_id }, MatchMembers = list(members) } }
end

-- pc in a match: me + allies on team 1, enemies on team 2. `cs` = the roster kept by the HUD.
local function match_pc(lang, prefix, me, allies, enemies, items, cs)
	local my_pri = pri_of(me, 1)
	if items then give_items(my_pri, items) end
	local pris = { my_pri }
	for _, n in ipairs(allies) do pris[#pris + 1] = pri_of(n, 1) end
	for _, n in ipairs(enemies) do pris[#pris + 1] = pri_of(n, 2) end
	local gri = obj("TgGame.TgRepInfo_Game_Payload", { ElapsedTime = 420, bMatchIsOver = false, PRIArray = list(pris) })
	local wi = obj("Engine.WorldInfo", { GRI = gri, path = function() return "Siege_Frog.TheWorld:PersistentLevel" end })
	local hud
	if prefix or cs then hud = { m_pMovie = movie(prefix or "EN", { m_UIDataManager = cs }) } end
	return {
		WorldInfo = wi, Pawn = my_pri.r_PawnOwner, PlayerReplicationInfo = my_pri, myHUD = hud,
		GetLanguage = function() return lang end,
	}
end

local function lobby_pc(lang, prefix, me, allies, match_id)
	local picks = { me }
	for _, a in ipairs(allies) do picks[#picks + 1] = a end
	local m = movie(prefix, { m_UIDataManager = roster(match_id or 1, picks) })
	local wi = obj("Engine.WorldInfo", { path = function() return "LobbyMapV4_P.TheWorld" end })
	return { WorldInfo = wi, myHUD = { m_pMovie = m }, GetLanguage = function() return lang end }
end

-- ------------------------------------------------------------------ 1. predictor parity
section("predictor parity (sc_predictor.lua vs predictor.py)")
local Predictor = require("lib.sc_predictor")
local PRED = Predictor.new(DATA)
local EXPECTED = dofile("engine/tests/expected.lua")

-- Numbers are compared within one unit of their last digit: Python's round() sends exact halves to
-- the even digit (86.5 -> 86), the Lua port rounds them up (87). Orders and names must match exactly.
local function near(a, b, unit) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= unit * 1.01 end
local function same_list(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

for n, e in ipairs(EXPECTED) do
	local id = string.format("#%d %s vs %s", n, e.player, table.concat(e.enemies, ","))
	local r, code, detail = PRED:predict(e.player, e.enemies, e.phase, e.mode, e.style, e.owned)
	if check(r ~= nil, id .. ": no result (" .. tostring(code) .. " " .. tostring(detail) .. ")") then
		local build, kinds, status = {}, {}, {}
		for i, b in ipairs(r.build) do
			build[i] = b.item
			kinds[i] = b.kind:sub(1, 1) .. (b.offmeta and "o" or "") .. (b.blocked and "x" or "")
			status[i] = b.status .. (b.next and "*" or "")
		end
		check(same_list(build, e.build), id .. ": build " .. table.concat(build, ","))
		check(same_list(kinds, e.kinds), id .. ": kinds " .. table.concat(kinds, ","))
		if e.status then check(same_list(status, e.status), id .. ": status " .. table.concat(status, ",")) end
		local th = r.threats[1]
		check(th.name == e.threat1, id .. ": threat " .. tostring(th.name))
		check(th.answer == e.threat1_answer, id .. ": threat answer " .. tostring(th.answer))
		local ab = {}
		for i, a in ipairs(th.abilities or {}) do ab[i] = a.tag .. ":" .. tostring(a.slot) .. ":" .. (a.fx or "") end
		check(same_list(ab, e.threat1_abil), id .. ": threat abilities " .. table.concat(ab, ","))
		for _, a in ipairs(r.forecast) do
			check(near(a.probability, e.probs[a.key], 1), id .. ": forecast " .. a.key .. " " .. a.probability)
		end
		check(r.forecast[1].key == e.top_forecast, id .. ": top forecast " .. r.forecast[1].key)
		for i, x in ipairs(e.items) do
			local got = r.items[i]
			check(got and got.item == x.item and near(got.score, x.score, 0.1) and got.suggested_level == x.level,
				id .. ": item " .. i .. " " .. tostring(got and got.item) .. " " .. tostring(got and got.score))
		end
		local p = r.counters.picks[1]
		check(p.name == e.top_pick and near(p.score, e.top_pick_score, 0.01),
			id .. ": top pick " .. tostring(p.name) .. " " .. tostring(p.score))
	end
end
local bad = { PRED:predict("Nobody", { "Makoa" }) }
check(bad[1] == nil and bad[2] == "unknown_champion", "unknown champion is an error code")
bad = { PRED:predict("Makoa", { "Lian", "Lian" }) }
check(bad[1] == nil and bad[2] == "duplicate", "duplicate enemy is an error code")

-- ------------------------------------------------------------------ 2. modules on mock objects
_G.ui = new_ui()
local T0 = new_tempest()
_G.tempest = T0.api

section("sc_text: names from the game's Lang files (lang API)")
local Text = require("lib.sc_text")
check(Text.clean("<font color=\"#fff\">Stuns</font> for {1.5}s") == "Stuns for 1.5s", "clean keeps words and values")
check(Text.clean("{10|-1}s") == "10s", "clean keeps the first placeholder value")
GAME.lang = "FRA"
local TX = Text.new(DATA, PRED)
local loads0 = #GAME.loads
check(TX.lang_code == "FRA" and TX:ui_lang() == "fr" and lang.language() == "INT",
	"a French Steam client: the engine says FRA while lang.language() says INT -> fr")
check(TX:champion("Makoa") == "Makoa" and TX:item("Haven") == "Haven" and #GAME.loads == loads0,
	"no language shown yet: internal names, no Lang file read")
TX:set_view("fr", false)
local mk = champ("Makoa")
check(TX:champion("Makoa") == (game_text("FR", mk.name_msg) or "Makoa"),
	"champion name from lang.message: " .. tostring(TX:champion("Makoa")))
check(TX:role("Frontline") == game_text("FR", DATA.role_msg.Frontline) and TX:category("Defense") ~= nil,
	"role and category names from the game")
check(GAME.loads[#GAME.loads] == "FRA" and GAME.unloads[#GAME.unloads] == "FRA" and #GAME.loads == loads0 + 1,
	"the French Lang file is read once, then freed")
for _ = 1, 3 do
	TX:champion("Lian")
	TX:item_desc("Haven")
end
check(#GAME.loads == loads0 + 1, "texts are kept: no file read while the panel draws")
local texts = TX:all_texts()
check(#texts > 100 and TX.n_texts == #texts, "all_texts covers champions, abilities and items")
-- the engine sets its language after the script has loaded: picked up within a second
GAME.lang = "INT"
local TXl = Text.new(DATA, PRED)
TXl:set_view(TXl:ui_lang(), true)
check(TXl:ui_lang() == "en" and TXl:names_ext() == "INT", "engine still in INT at load: English")
GAME.lang = "FRA"
local vl = TXl.version
TXl:refresh(NOW)
TXl:set_view("en", true)
check(TXl.lang_code == "FRA" and TXl:ui_lang() == "fr" and TXl.version > vl and TXl:names_ext() == "FRA",
	"a later FRA: Auto follows, names in the client's language are read again")
local calls = 0
MOCK.engine.GetLanguage = function() calls = calls + 1 return GAME.lang end
TXl:refresh(NOW + 0.5)
check(calls == 0, "the language is looked at once per second at most")
MOCK.engine.GetLanguage = function() return GAME.lang end
-- no engine answer (no engine object, an empty string): lang.language()
local saved_engine = MOCK.engine
MOCK.engine = nil
GAME.arg = "DEU"
check(Text.new(DATA, PRED).lang_code == "DEU", "no engine: lang.language()")
MOCK.engine = obj("Engine.GameEngine", { GetLanguage = function() return "" end })
check(Text.new(DATA, PRED).lang_code == "DEU", "an empty engine answer: lang.language()")
MOCK.engine, GAME.arg, GAME.lang = saved_engine, "INT", "INT"

section("sc_player: owned items by reflection (TgRepInfo_Player)")
local Player = require("lib.sc_player")
local PL = Player.new(DATA)
local haven, wrecker = DATA.items["Haven"], DATA.items["Wrecker"]
local owned, src = PL:from_devices(pri_items({ { haven.item_id, 2 }, { 999999, 3 }, { wrecker.item_id, 7 }, { haven.item_id, 1 } }))
check(owned and owned.Haven == 2 and owned.Wrecker == 3 and src == "PRI.r_PlayerDevices + r_TempItems",
	"slots + shop ranks: unknown ids ignored, the highest rank of an item kept, clamp to III")
check(Player.new(DATA):from_devices({ r_PlayerDevices = { { CurrentDeviceId = haven.item_id }, { CurrentDeviceId = 0 } } }) == nil,
	"a plain table is not a TgRepInfo_Player: never read")
check(Player.new(DATA):from_devices(obj("TgGame.TgRepInfo_Player",
	{ r_PlayerDevices = { { CurrentDeviceId = haven.item_id, Level = 1 } } })) == nil, "a single struct view is not a slot list")
local devs, src2 = Player.new(DATA):from_devices(obj("TgGame.TgRepInfo_Player",
	{ r_PlayerDevices = { { CurrentDeviceId = haven.item_id, Level = 2 }, { CurrentDeviceId = 0 } } }))
check(devs and devs.Haven == 1 and src2 == "PRI.r_PlayerDevices",
	"slots alone: which items; their Level (the cards' level) is not a rank")
local ids_ok = true
for name, it in pairs(DATA.items) do
	if PL.by_id[it.item_id] ~= name then ids_ok = false end
	for _, a in ipairs(it.alias_ids or {}) do
		if not PL.by_id[a] then ids_ok = false end
	end
end
check(ids_ok, "every item id and alias id is known")

section("sc_detect: match state by reflection")
local Detect = require("lib.sc_detect")
local DET = Detect.new(PRED)
T0.player = match_pc("INT", nil, "Lian", { "Inara", "Grohk" }, { "Makoa", "Androxus", "Viktor" })
local st = DET:read()
check(st.status == "match" and st.me == "Lian", "match: my champion from GetBotId (GetArchetypeBotId is the role)")
check(same_list(st.enemies, { "Androxus", "Makoa", "Viktor" }), "enemies by GetTaskForceNumber: " .. table.concat(st.enemies, ","))
check(same_list(st.allies, { "Grohk", "Inara" }), "allies by GetTaskForceNumber")
check(st.mode == "siege" and st.phase ~= nil, "mode from the GRI class, phase from ElapsedTime")
-- no team number (255): IsFriendlyWithLocalPawn
local p2 = pawn_of("Makoa")
p2.IsFriendlyWithLocalPawn = function() return false end
local DET2 = Detect.new(PRED)
T0.player = match_pc("INT", nil, "Lian", {}, {})
table.insert(T0.player.WorldInfo.GRI.PRIArray, obj("TgGame.TgRepInfo_Player",
	{ r_PawnOwner = p2, GetTaskForceNumber = function() return 255 end }))
st = DET2:read()
check(same_list(st.enemies, { "Makoa" }), "no team number: IsFriendlyWithLocalPawn")
T0.player = lobby_pc("INT", "EN", "Cassie", { "Inara" })
st = DET:read()
check(st.status == "champ_select" and st.me == "Cassie" and st.allies[1] == "Inara", "champion select from MatchMembers")
T0.player.WorldInfo = obj("Engine.WorldInfo", { GRI = { bMatchIsOver = true }, path = function() return "Siege_Frog" end })
check(DET:read().status == "match_over", "end of match")
T0.player = nil
check(DET:read().status == "no_player", "no player")

-- ------------------------------------------------------------------ 2b. edge cases of the game queries
section("edge cases: a language without Lang file, ids without text (sc_text)")
GAME.lang = "INT"
local TXr = Text.new(DATA, PRED)
TXr:set_view("it", false)
check(TXr:champion("Makoa") == "Makoa" and TXr:item_desc("Haven") == nil and TXr:role("Frontline") == nil,
	"Italian UI (no Lang_ITA.dat in 8.1): internal names, the mod's words, no description")
check(TXr:names_ext() == nil and #TXr:all_texts() == 0, "names fall back to the mod's keys, no game text")
local loads1 = #GAME.loads
TXr:champion("Lian")
TXr:item("Haven")
check(#GAME.loads == loads1, "a missing Lang file is not asked again")
GAME.missing[DATA.items.Haven.name_msg] = true
TXr:set_view("de", false)
check(TXr:item("Haven") == "Haven" and TXr:item("Wrecker") == (game_text("DE", DATA.items.Wrecker.name_msg) or "Wrecker"),
	"an id without text in the file: the internal name for that one only")
GAME.missing = {}
check(Text.clean("Line<br/>two &amp; three<BR>four") == "Line two & three four", "clean: line breaks and entities")
check(Text.clean("&bogus; ok") == "&bogus; ok", "clean: an unknown entity is kept")
check(Text.clean("<b></b>  ") == nil, "clean: markup only = no text")

section("edge cases: font loading (sc_fonts)")
_G.ui = new_ui()
local TF = new_tempest()
_G.tempest = TF.api
local Fonts = require("lib.sc_fonts")
local Lng = require("lib.sc_lang")
local stub = { n_texts = 0 }
function stub:ui_lang() return "ja" end
function stub:all_texts() return self.n_texts > 0 and { "名前" } or {} end
local stuck = { ja = { state = "queued", body = {}, bold = {}, group = "ja", ui_lang = "ja", key = "ja" } }
local FN = Fonts.new(Lng, stub, stuck, function() end)
check(stuck.ja.state == "pending", "a load queued before a hot reload starts again")
local fset = FN:tick(NOW, "ja")
check(fset.state == "queued" and #TF.queued == 1, "fonts load through tempest.queue")
for _ = 1, 4 do
	NOW = NOW + 4
	fset = FN:tick(NOW, "ja")
end
check(fset.state == "failed" and #TF.queued == 3 and #MOCK.fonts_added == 0,
	"a queue that never runs: 3 tries, then the default font (never add_font while drawing)")
local store2 = {}
local FR2 = Fonts.new(Lng, stub, store2, function() end)
TF.queued = {}
local function run_queue()
	local q = TF.queued
	TF.queued = {}
	for _, fn in ipairs(q) do fn() end
end
fset = FR2:tick(NOW, "ja")
run_queue()
NOW = NOW + 0.1
fset = FR2:tick(NOW, "ja")
check(fset.state == "ready" and #MOCK.fonts_added > 0, "queued load, then ready on the next frame")
stub.n_texts = 40   -- names switched to the game's language: more game texts on screen
NOW = NOW + 1
check(FR2:tick(NOW, "ja") == fset and store2.ja == fset, "no rebuild right after a build")
local rebuilds = 0
for _ = 1, 4 do
	NOW = NOW + 6
	local before = store2.ja
	FR2:tick(NOW, "ja")
	if store2.ja ~= before then
		rebuilds = rebuilds + 1
		check(store2.ja.previous == before, "a rebuilt set draws with the previous one until ready")
		local pushed = 0
		local raw_push = ui.push_font
		ui.push_font = function(f) pushed = pushed + 1; raw_push(f) end
		FR2:with(store2.ja, "body", 2, function() end)
		ui.push_font = raw_push
		check(pushed == 1, "previous fonts used while the new set loads")
		FR2:tick(NOW, "ja")
		run_queue()
		NOW = NOW + 0.1
		FR2:tick(NOW, "ja")
	end
end
check(rebuilds == 2, "more game names on screen rebuild a CJK set at most twice (got " .. rebuilds .. ")")
_G.ui = new_ui()
_G.tempest = T0.api

section("edge cases: lobby, maps and deaths (sc_detect)")
local D3 = Detect.new(PRED)
T0.player = lobby_pc("INT", "EN", "Cassie", { "Inara" }, 501)
st = D3:read()
check(st.status == "champ_select" and st.game ~= nil, "champion select names the game")
local game1 = st.game
T0.player = match_pc("INT", nil, "Cassie", { "Inara" }, { "Makoa" }, nil, roster(501, { "Cassie", "Inara" }))
st = D3:read()
check(st.status == "match" and st.game == game1, "the match keeps the game of its champion select")
local w_match = st.world
T0.player.Pawn = nil
st = D3:read()
check(st.me == "Cassie", "dead (no pawn): my champion is kept")
T0.player = lobby_pc("INT", "EN", "Cassie", { "Inara" }, 501)
st = D3:read()
check(st.status == "lobby" and st.world > w_match and st.game == nil,
	"back in the lobby: the roster kept from the last match is not a new champion select")
check(D3.match_me == nil, "my champion of the last match is dropped with the map")
T0.player = lobby_pc("INT", "EN", "Lian", { "Inara" }, 502)
st = D3:read()
check(st.status == "champ_select" and st.me == "Lian" and st.game ~= game1, "a new roster is a new champion select")
local function pc_with_enemy(enemy, pri_ptr)
	local pc = match_pc("INT", nil, "Lian", {}, {})
	table.insert(pc.WorldInfo.GRI.PRIArray, pri_of(enemy, 2, pri_ptr))
	return pc
end
local D4 = Detect.new(PRED)
T0.player = pc_with_enemy("Makoa", 777001)
check(same_list(D4:read().enemies, { "Makoa" }), "match 1: Makoa")
T0.player = pc_with_enemy("Grohk", 777001)
check(same_list(D4:read().enemies, { "Grohk" }), "match 2, a PRI at the same address: Grohk (cache dropped with the map)")

section("edge cases: items while dead (sc_player)")
local PL2 = Player.new(DATA)
T0.player = match_pc("INT", nil, "Makoa", {}, { "Lian" }, { { haven.item_id, 2 } })
NOW = NOW + 2
local p1 = PL2:poll(NOW)
check(p1.available and p1.owned.Haven == 2, "items read")
T0.player.Pawn = nil
NOW = NOW + 2
local p2 = PL2:poll(NOW)
check(p2.available and p2.owned.Haven == 2, "dead: the items read before are kept")
T0.player = lobby_pc("INT", "EN", "Makoa", {})
NOW = NOW + 2
check(not PL2:poll(NOW).available, "another map without a pawn: nothing kept from the last one")

section("names in the shown language (sc_text set_view)")
GAME.lang = "FRA"
local TXv = Text.new(DATA, PRED)
TXv:set_view("fr", false)
local mk_fr = TXv:champion("Makoa")
check(mk_fr == (game_text("FR", mk.name_msg) or "Makoa"), "French game, French UI: the game's French names")
local vv = TXv.version
TXv:set_view("en", false)
check(TXv.version > vv, "a view change bumps the version (layouts and lists are redone)")
local haven = DATA.items.Haven
check(TXv:champion("Makoa") == (game_text("EN", mk.name_msg) or "Makoa")
	and TXv:item("Haven") == (game_text("EN", haven.name_msg) or "Haven"),
	"French game, English UI: the game's English names (Lang_INT), no French")
check(TXv:role("Frontline") == game_text("EN", DATA.role_msg.Frontline)
	and TXv:item_desc("Haven") == game_text("EN", haven.desc_msg),
	"French game, English UI: roles and descriptions in English, from the game")
check(TXv:ability(mk.abilities[1]) == game_text("EN", mk.abilities[1].name_msg), "abilities named in English too")
TXv:set_view("en", true)
check(TXv:champion("Makoa") == mk_fr and TXv:names_ext() == "FRA", "game_names on: names in the game's language")
check(TXv:role("Frontline") == game_text("EN", DATA.role_msg.Frontline)
	and TXv:item_desc("Haven") == game_text("EN", haven.desc_msg),
	"game_names on: roles and descriptions still follow the UI language (no French sentence)")
GAME.lang = "ESL"
local TXs = Text.new(DATA, PRED)
TXs:set_view(TXs:ui_lang(), false)
check(TXs:ui_lang() == "en" and TXs:champion("Makoa") == (game_text("EN", mk.name_msg) or "Makoa"),
	"a game language the mod has no UI for (ESL): English UI, English names")
TXs:set_view("en", true)
check(TXs:champion("Makoa") == (game_text("ES", mk.name_msg) or "Makoa"), "ESL with game_names: Spanish names")
GAME.lang = "INT"

section("names inside the mod's sentences come from the game (sc_view placeholders)")
local LV = require("lib.sc_lang")
local Vw = require("lib.sc_view").new({ t = LV.t, L = LV, TX = TXv, D = DATA, PRED = PRED })
LV.set("fr")
TXv:set_view("fr", false)
local wr_fr, inara_fr = TXv:item("Wrecker"), TXv:champion("Inara")   -- mock names carry a '%' too
local why = { reason = { key = "special_shield" }, arch = { key = "shield_heavy", probability = 80 } }
local fr_text = Vw:why_text("Wrecker", why, true)
check(wr_fr ~= "Wrecker" and fr_text:find(wr_fr, 1, true) and not fr_text:find("Wrecker", 1, true),
	"French UI on a French game: the reason, archetype and note name the item as the shop does")
check(fr_text:find(inara_fr, 1, true) ~= nil, "the Wrecker note names the champions with the game's names")
LV.set("en")
TXv:set_view("en", false)
local en_text = Vw:why_text("Wrecker", why, true)
local wr_en, inara_en = TXv:item("Wrecker"), TXv:champion("Inara")
check(en_text:find(wr_en, 1, true) and en_text:find(inara_en, 1, true) and not en_text:find(wr_fr, 1, true),
	"English UI on a French game: the game's English names, no French name inside an English sentence")
check(not en_text:find("%s", 1, true) and not fr_text:find("%s", 1, true), "every placeholder is filled")
check(Vw:reason_text({ key = "deployables" }) == LV.t("r_deployables") and not LV.t("r_shield"):find("%d"),
	"deployables and shield reasons: no health number (the mod ships no game stats), no object name")

section("quick picks, loading, training (sc_detect)")
local D5 = Detect.new(PRED)
T0.player = lobby_pc("INT", "EN", false, { "Inara" }, 701)
st = D5:read(NOW)
check(st.status == "champ_select" and st.me == nil, "champion select before my pick")
local cs_game = st.game
T0.player = nil
st = D5:read(NOW + 3)
check(st.status == "loading" and st.game == cs_game, "no player right after champion select: loading, same game")
local pc_load = match_pc("INT", nil, "Cassie", { "Inara" }, { "Makoa" }, nil, roster(701, { "Cassie", "Inara" }))
pc_load.WorldInfo.GRI = nil
T0.player = pc_load
st = D5:read(NOW + 6)
check(st.status == "loading" and st.me == "Cassie", "match map without GRI: loading, my pick read from the roster")
pc_load = match_pc("INT", nil, "Cassie", { "Inara" }, { "Makoa" }, nil, roster(701, { "Cassie", "Inara" }))
pc_load.Pawn = nil
T0.player = pc_load
st = D5:read(NOW + 9)
check(st.status == "match" and st.me == "Cassie" and st.game == cs_game,
	"in the match before my pawn exists: my pick from this game's roster")
pc_load.WorldInfo.GRI.bMatchIsOver = true
check(D5:read(NOW + 12).status == "match_over", "end of match")
T0.player = nil
check(D5:read(NOW + 13).status == "no_player", "after the match: no player is not loading")
local D6 = Detect.new(PRED)
T0.player = lobby_pc("INT", "EN", "Cassie", { "Inara" }, 702)
D6:read(NOW)
T0.player = nil
check(D6:read(NOW + Detect.LOADING_GRACE + 1).status == "no_player", "loading lasts LOADING_GRACE at most")
local D7 = Detect.new(PRED)
T0.player = lobby_pc("INT", "EN", false, { "Inara" }, 703)
D7:poll(NOW)
T0.player = lobby_pc("INT", "EN", "Lian", { "Inara" }, 703)
check(D7:poll(NOW + Detect.FAST_INTERVAL + 0.01).me == "Lian", "champion select is read 4 times a second (quick picks)")
T0.player = match_pc("INT", nil, "Lian", {}, { "Makoa" })
D7:poll(NOW + 1)
T0.player = match_pc("INT", nil, "Lian", {}, { "Makoa", "Grohk" })
check(#D7:poll(NOW + 1.3).enemies == 1, "in a match: once a second")
local D8 = Detect.new(PRED)
local pc_tr = match_pc("INT", nil, "Lian", {}, {})
pc_tr.WorldInfo.GRI = nil
T0.player = pc_tr
check(D8:read(NOW).status == "loading", "a new map without GRI and no champion select before it: loading, not match over")

section("4 item slots (sc_predictor)")
local o4 = PRED:predict("Io", { "Makoa", "Dredge", "Evie", "Furia", "Androxus" }, "mid", nil, "heal",
	{ Hoard = 1, Nimble = 1, Chronos = 1, Wrecker = 1 })
check(o4.build[5].kind == "flex" and o4.build[5].blocked and not o4.build[5].next,
	"4 items owned: the optional 5th is blocked and never the next purchase")
local o3 = PRED:predict("Io", { "Makoa", "Dredge", "Evie", "Furia", "Androxus" }, "mid", nil, "heal",
	{ Hoard = 1, Nimble = 1, Chronos = 1 })
check(not o3.build[5].blocked, "3 items owned: the optional 5th can still be bought")

section("item ranks: one max rank for the shop, how the game counts nRank (sc_player)")
check(DATA.max_rank == 3, "every 8.1 shop item has ranks I-III (from the game data's device modes)")
local no_stats = true
local SHIPPED = dofile("src/scripts/lib/sc_data.lua")
for _, it in pairs(SHIPPED.items) do
	if it.cost or it.ranks then no_stats = false end
end
for _, c in ipairs(SHIPPED.champions) do
	if c.hp or c.pawn then no_stats = false end
	for _, r in ipairs(c.recs) do
		if r.args then no_stats = false end
	end
	for _, a in ipairs(c.abilities) do
		if a.device_id then no_stats = false end
	end
end
check(no_stats, "sc_data.lua ships no game stats: no health, shield health, cost, rank count, pawn class, device id")
DATA.max_rank = 2   -- a shop with 2 ranks: everything follows the data
local own2 = Predictor.clean_owned(DATA, { Nimble = 3, Haven = 1 })
check(own2.Nimble == 2 and own2.Haven == 1, "owned ranks are capped at the max rank")
local r2 = PRED:predict("Lian", { "Makoa", "Fernando" }, "mid", nil, nil, { Nimble = 3 })
local cap_ok = true
for _, b in ipairs(r2.build) do
	if b.rank > 2 or b.target > 2 then cap_ok = false end
end
for _, it in ipairs(r2.items) do
	if it.suggested_level > 2 then cap_ok = false end
end
check(cap_ok, "advised rank and owned rank never exceed the max rank")
local o = Player.new(DATA):from_devices(pri_items({ { DATA.items.Nimble.item_id, 7 } }))
check(o.Nimble == 2, "live rank capped at the max rank")
DATA.max_rank = 3
local PL0 = Player.new(DATA)
o = PL0:from_devices(pri_items({ { haven.item_id, 0 }, { wrecker.item_id, 2 } }))
check(PL0.base == 0 and o.Haven == 1 and o.Wrecker == 3, "an nRank 0 means the game counts from 0: 0 = I, 2 = III")
o = PL0:from_devices(pri_items({ { haven.item_id, 1 } }))
check(o.Haven == 2, "the counting learnt stays for the session")
local PL1 = Player.new(DATA)
o = PL1:from_devices(pri_items({ { haven.item_id, 3 } }))
check(PL1.base == 1 and o.Haven == 3, "an nRank equal to the max rank means the game counts from 1")
local PLn = Player.new(DATA)
o = PLn:from_devices(pri_items({ { haven.item_id, 2 } }))
check(PLn.base == nil and o.Haven == 2, "nothing conclusive: counts from 1")
local PLsold = Player.new(DATA)
local pri_sold = pri_items({ { haven.item_id, 2 } })
table.insert(pri_sold.r_TempItems, { nDevId = wrecker.item_id, nRank = 0 })   -- sold: still listed, gone from the slots
o = PLsold:from_devices(pri_sold)
check(PLsold.base == nil and o.Haven == 2 and o.Wrecker == nil,
	"a sold item left in r_TempItems: not owned, and its rank teaches nothing")
local pri_nr = pri_items({ { haven.item_id, 1 } })
pri_nr.r_TempItems[1].nRank = nil
check(Player.new(DATA):from_devices(pri_nr).Haven == 1, "no nRank at all: the owned item is rank I")

do
section("live rank-ups: bought at rank I, upgraded to II and III (sc_player)")
-- The game's shape: r_TempItems[].nRank is the shop rank; r_PlayerDevices[].Level stays at 0 for
-- items (it is the deck cards' level).
local res, hav, wre = DATA.items.Resilience, DATA.items.Haven, DATA.items.Wrecker
local function count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end
local function rank_up_run(label, base)
	local PLu = Player.new(DATA)
	local pri_u = obj("TgGame.TgRepInfo_Player", {})
	local ok, nowu = true, 1000
	for r = 1, 3 do
		give_items(pri_u, { { res.item_id, r - 1 + base }, { hav.item_id, base }, { wre.item_id, 2 + base }, { 0, 0 } })
		T0.player = { Pawn = pawn_of("Makoa"), PlayerReplicationInfo = pri_u, WorldInfo = { ptr = function() return 7 end } }
		nowu = nowu + 1.1
		local st_u, changed = PLu:poll(nowu)
		if st_u.owned.Resilience ~= r or count(st_u.owned) ~= 3 or st_u.owned.Wrecker ~= 3 or st_u.owned.Haven ~= 1 then
			ok = false
		end
		if r > 1 and not changed then ok = false end
	end
	check(ok, label)
end
rank_up_run("nRank counting from 1 (1, 2, 3), slots at Level 0: Resilience I -> II -> III, 3 items", 1)
rank_up_run("nRank counting from 0 (0, 1, 2): Resilience I -> II -> III, 3 items", 0)
-- the plan follows: owned rank III means Resilience is done, and the other slots are planned
local r1 = PRED:predict("Makoa", { "Lian", "Androxus" }, "mid", nil, nil, { Resilience = 1, Haven = 1, Wrecker = 3 })
local r3 = PRED:predict("Makoa", { "Lian", "Androxus" }, "mid", nil, nil, { Resilience = 3, Haven = 1, Wrecker = 3 })
local function build_of(r, item)
	for _, b in ipairs(r.build) do
		if b.item == item then return b end
	end
end
local b1, b3 = build_of(r1, "Resilience"), build_of(r3, "Resilience")
check(b1 and b1.rank == 1 and b3 and b3.rank == 3 and b3.target <= 3 and b3.status ~= "upgrade",
	"predictor: Resilience owned at III is no longer an upgrade to buy")

end
do
section("no lookup of missing properties: siege pawns, lobby PRI, struct entries")
-- a game object that counts reads of the properties its class does not declare (Tempest logs each one)
local function strict(class, parents, fields, missing)
	local o = fields or {}
	o.class = function() return { name = function() return class end } end
	o.ptr = function() return o._p end
	next_ptr = next_ptr + 1
	o._p = next_ptr
	o.is_a = function(_, c)
		if c == class then return true end
		for _, x in ipairs(parents) do
			if x == c then return true end
		end
		return false
	end
	o.has = function(_, k) return rawget(o, k) ~= nil end   -- Object:has: the declared properties
	return setmetatable(o, { __index = function(_, k) missing[k] = (missing[k] or 0) + 1 return nil end })
end
-- 1. the Siege payload is not a champion: never asked for its bot id
local miss = {}
local bot_calls = 0
local cart = strict("TgPawn_SiegeEngine_CaptureAndPayload", { "TgGame.TgPawn" }, {}, miss)
local new_champ = strict("TgPawn_NewChamp", { "TgGame.TgPawn_Character", "TgGame.TgPawn" },
	{ GetBotId = function() bot_calls = bot_calls + 1 return DATA.champions[1].bot_id end }, miss)
local DETs = Detect.new(PRED)
T0.player = match_pc("INT", nil, "Lian", { "Inara" }, { "Makoa" })
table.insert(T0.player.WorldInfo.GRI.PRIArray, obj("TgGame.TgRepInfo_Player",
	{ r_PawnOwner = cart, GetTaskForceNumber = function() return 2 end }))
table.insert(T0.player.WorldInfo.GRI.PRIArray, obj("TgGame.TgRepInfo_Player",
	{ r_PawnOwner = new_champ, GetTaskForceNumber = function() return 2 end }))
local st_s
for i = 1, 5 do st_s = DETs:read(NOW + i) end
check((miss.GetBotId or 0) == 0, "Siege payload pawn: GetBotId never looked up (" .. tostring(miss.GetBotId) .. ")")
check(same_list(st_s.enemies, { "Makoa", DATA.champions[1].name }) or same_list(st_s.enemies, { DATA.champions[1].name, "Makoa" }),
	"the payload is not an enemy; every champion pawn is found by its bot id")
check(bot_calls == 1, "a pawn class is asked for its bot id once, then cached (" .. bot_calls .. " calls)")
-- a pawn being set up (or torn down) answers bot id 0: not cached, asked again
local tries, ids = 0, { 0, champ("Makoa").bot_id }
local late = obj("TgPawn_LateMakoa", { _parents = { "TgGame.TgPawn_Character", "TgGame.TgPawn" },
	GetBotId = function() tries = tries + 1 return ids[math.min(tries, 2)] end })
local l1, l2, l3 = DETs:champ_of_pawn(late), DETs:champ_of_pawn(late), DETs:champ_of_pawn(late)
check(l1 == nil and l2 == "Makoa" and l3 == "Makoa" and tries == 2,
	"bot id 0 while the pawn is set up: not cached, asked again, then the champion is cached (" .. tries .. " calls)")
check(DETs:champ_of_pawn(nil) == nil and DETs:champ_of_pawn(42) == nil and DETs:champ_of_pawn({}) == nil,
	"no pawn, a plain value or a struct: no champion, no error")

-- 2. the lobby's PlayerReplicationInfo has no r_PlayerDevices: never asked
local PLq = Player.new(DATA)
miss = {}
local lobby_pri = strict("PlayerReplicationInfo", { "Engine.PlayerReplicationInfo" }, {}, miss)
for i = 1, 5 do
	T0.player = { PlayerReplicationInfo = lobby_pri, WorldInfo = { ptr = function() return 11 end } }
	PLq:poll(NOW + 10 + i * 1.1)
end
check((miss.r_PlayerDevices or 0) == 0 and (miss.r_TempItems or 0) == 0,
	"lobby PRI (Engine.PlayerReplicationInfo): r_PlayerDevices and r_TempItems never looked up")
-- a TgRepInfo_Player whose slot array cannot be listed: asked once, then not any more
local reads = 0
local match_pri = strict("TgRepInfo_Player", { "TgGame.TgRepInfo_Player" }, {}, miss)
rawset(match_pri, "r_PlayerDevices", nil)
rawset(match_pri, "has", function(_, k) return k == "r_PlayerDevices" end)   -- declared, served below
setmetatable(match_pri, { __index = function(_, k)
	if k == "r_PlayerDevices" then reads = reads + 1 return { CurrentDeviceId = 0 } end   -- one struct view
	return nil
end })
for i = 1, 5 do
	T0.player = { PlayerReplicationInfo = match_pri, WorldInfo = { ptr = function() return 12 end } }
	PLq:poll(NOW + 20 + i * 1.1)
end
check(reads == 1, "slots that cannot be listed are read once per PRI class (" .. reads .. " reads)")

-- 3. the arrays' entries are structs (no has(), as in the LiveCheck log): their fields are read
-- directly; the item line is written once per change, not at every read
miss = {}
local pri_d = strict("TgRepInfo_Player", { "TgGame.TgRepInfo_Player" }, {}, miss)
local logged = {}
local PLd = Player.new(DATA, function(fmt, ...)
	local line = string.format(fmt, ...)
	if line:find("items [", 1, true) then logged[#logged + 1] = line end
end)
local ranks_seen = {}
for r = 1, 3 do
	local arrs = give_items({}, { { DATA.items.Resilience.item_id, r } })
	rawset(pri_d, "r_PlayerDevices", arrs.r_PlayerDevices)
	rawset(pri_d, "r_TempItems", arrs.r_TempItems)
	for k = 1, 3 do
		T0.player = { Pawn = pawn_of("Makoa"), PlayerReplicationInfo = pri_d, WorldInfo = { ptr = function() return 13 end } }
		ranks_seen[r] = PLd:poll(NOW + 40 + r * 10 + k * 1.1).owned.Resilience
	end
end
check(ranks_seen[1] == 1 and ranks_seen[2] == 2 and ranks_seen[3] == 3 and next(miss) == nil,
	"struct entries: Resilience I -> II -> III, no missing property read (" ..
	tostring(ranks_seen[1]) .. tostring(ranks_seen[2]) .. tostring(ranks_seen[3]) .. " " .. tostring(next(miss)) .. ")")
check(#logged == 3 and logged[3]:find("Resilience=3 (shop rank 3)", 1, true) ~= nil,
	"raw values logged once per change, not at every read (" .. #logged .. " lines): " .. tostring(logged[#logged]))

end
do
section("rank display: an arrow from the owned rank to the advised one, never a fraction")
local LVd = require("lib.sc_lang")
LVd.set("en")
local TXd = Text.new(DATA, PRED)
TXd:set_view("it", false)   -- no Lang file: the item keys, so the labels read plainly
local Vd = require("lib.sc_view").new({ t = LVd.t, L = LVd, TX = TXd, D = DATA, PRED = PRED })
local AR = Vd.ARROW
check(AR == " \226\134\146 ", "the arrow is U+2192 between spaces")
check(Vd:chip_label({ item = "Wrecker", rank = 1, target = 3, kind = "core" }) == "Wrecker I" .. AR .. "III",
	"owned I, advised III: 'Wrecker I -> III'")
check(Vd:chip_label({ item = "Nimble", rank = 2, target = 2, kind = "core" }) == "Nimble II", "advised rank reached: 'Nimble II'")
check(Vd:chip_label({ item = "Morale Boost", rank = 0, target = 2, kind = "core" }) == "Morale Boost II", "to buy: the advised rank")
check(Vd:chip_label({ item = "Wrecker", rank = 3, target = 2, kind = "core" }) == "Wrecker III", "owned above the advice: the owned rank")
check(Vd.roman(7) == "III" and Vd.roman(-1) == "0" and Vd.roman(nil) == "0", "a rank out of range is clamped, never nil")
local no_fraction = true
for _, item in ipairs({ "Wrecker", "Nimble", "Morale Boost" }) do
	for r = 0, 3 do
		for tg = 1, 3 do
			local lab = Vd:chip_label({ item = item, rank = r, target = tg, kind = "core" })
			if lab:find("/", 1, true) or lab:find("%d") then no_fraction = false end
		end
	end
end
check(no_fraction, "no '/' and no digit in any rank label (ranks 0..3, targets 1..3)")
check(Vd:slot_status({ status = "upgrade", rank = 1, target = 3 }) == LVd.t("status_upgrade", "I", "III"),
	"detailed status: 'rank I -> III'")

end
do
section("item reader: why nothing is read, read errors, repeated purchases")
local logs = {}
local function logf(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end
local function count_logs(pat)
	local n = 0
	for _, l in ipairs(logs) do
		if l:find(pat, 1, true) then n = n + 1 end
	end
	return n
end
local PLw = Player.new(DATA, logf)
local tw = NOW + 500
local function step(pc)
	T0.player = pc
	tw = tw + 1.1
	return PLw:poll(tw)
end
local wi7 = { ptr = function() return 77 end }
step({ WorldInfo = wi7 })                                       -- lobby: no character
step({ WorldInfo = wi7 })
check(count_logs("no character") == 1, "no character: said once, not at every read")
local bare = pawn_of("Makoa")                                   -- a character, no player info yet
step({ Pawn = bare, WorldInfo = wi7 })
step({ Pawn = bare, WorldInfo = wi7 })
check(count_logs("lists no shop items") == 1, "a character whose player info lists no items: said once")
-- repeated purchases and upgrades: buy Wrecker I, upgrade II, sell, buy again at I, upgrade to III,
-- buy Nimble on the way; every change is one line, the ranks always follow the shop
local wr, nb = DATA.items.Wrecker, DATA.items.Nimble
local pri_w = obj("TgGame.TgRepInfo_Player", {})
local script = {
	{ {}, nil, "nothing bought yet: items none" },
	{ { { wr, 1 } }, { Wrecker = 1 }, "Wrecker bought" },
	{ { { wr, 2 } }, { Wrecker = 2 }, "Wrecker upgraded to II" },
	{ {}, {}, "Wrecker sold" },
	{ { { wr, 1 } }, { Wrecker = 1 }, "Wrecker bought again: rank I, not the II sold" },
	{ { { wr, 1 }, { nb, 1 } }, { Wrecker = 1, Nimble = 1 }, "Nimble bought" },
	{ { { wr, 2 }, { nb, 1 } }, { Wrecker = 2, Nimble = 1 }, "Wrecker II again" },
	{ { { wr, 3 }, { nb, 2 } }, { Wrecker = 3, Nimble = 2 }, "Wrecker III and Nimble II in the same second" },
	{ { { wr, 3 }, { nb, 3 } }, { Wrecker = 3, Nimble = 3 }, "Nimble III" },
}
local all_ok, lines_ok = true, true
for i, sc in ipairs(script) do
	local entries = {}
	for j, e in ipairs(sc[1]) do entries[j] = { e[1].item_id, e[2] } end
	give_items(pri_w, entries)
	local before = count_logs("items [")
	local st_w, changed = step({ Pawn = bare, PlayerReplicationInfo = pri_w, WorldInfo = wi7 })
	step({ Pawn = bare, PlayerReplicationInfo = pri_w, WorldInfo = wi7 })   -- a second read: nothing new
	local want = sc[2] or {}
	for k, r in pairs(want) do
		if st_w.owned[k] ~= r then all_ok = false end
	end
	for k in pairs(st_w.owned) do
		if not want[k] then all_ok = false end
	end
	local new = count_logs("items [") - before
	if new ~= 1 then
		lines_ok = false
		logf("  (step %d %s: %d lines)", i, sc[3], new)
	end
	if i > 1 and not changed then all_ok = false end
end
check(all_ok, "buy, upgrade, sell, buy again, two items at once: the ranks follow every step")
check(lines_ok, "one items line per change and none on the read after it: " .. table.concat(logs, " | "))
check(count_logs("live from the game") == 1, "live reading reported once")
-- a read error is written once, not at every read
local PLe = Player.new(DATA, logf)
PLe.read = function() error("boom") end
for i = 1, 4 do PLe:poll(tw + 10 + i * 1.1) end
check(count_logs("read failed") == 1 and PLe.errors == 4, "a read error is logged once (errors still counted)")
check(Player.describe == nil and Player.from_inventory == nil,
	"no diagnostic dump and no inventory-chain reader in the release (the PRI path is the one checked live)")
end

do
section("a live 8.1 match: slots for which items, r_TempItems for the rank")
-- the shape the Match tab diagnostic showed in td_abyss_p: chain none; 49 slots with deck cards
-- (one at level 5) and the shop items at level 0; the rank is in r_TempItems[].nRank
local hoard, nimble = DATA.items.Hoard, DATA.items.Nimble
local function slots_with(items)
	local t = {}
	for i = 1, 49 do t[i] = { CurrentDeviceId = 0, Level = 0, CurrentDeviceCount = 0 } end
	t[3] = { CurrentDeviceId = 24622, Level = 0 }
	t[6] = { CurrentDeviceId = 24554, Level = 5 }                -- a deck card at level 5
	for i, it in ipairs(items) do t[8 + i] = { CurrentDeviceId = it.item_id, Level = 0, CurrentDeviceCount = 1 } end
	return t
end
local function temp_with(list)
	local t = {}
	for i = 1, 6 do t[i] = { nDevId = 0, nRank = 0, nCost = 0 } end
	for i, e in ipairs(list) do t[i] = { nDevId = e[1].item_id, nRank = e[2], nCost = 300 } end
	return t
end
for _, base in ipairs({ 1, 0 }) do
	local logs = {}
	local PLm = Player.new(DATA, function(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end)
	local pri_m = obj("TgGame.TgRepInfo_Player", {})
	local pawn_m = pawn_of("Io")
	local tm = NOW + 900 + base * 100
	local function read_m(items, temp)
		pri_m.r_PlayerDevices, pri_m.r_TempItems = slots_with(items), temp_with(temp)
		T0.player = { Pawn = pawn_m, PlayerReplicationInfo = pri_m, WorldInfo = { ptr = function() return 88 end } }
		tm = tm + 1.1
		return PLm:poll(tm)
	end
	local function n_items()
		local n = 0
		for _, l in ipairs(logs) do
			if l:find("items [PRI]", 1, true) then n = n + 1 end
		end
		return n
	end
	local b = base == 1 and "from 1" or "from 0"
	local st_m = read_m({ hoard }, { { hoard, base } })
	check(st_m.available and st_m.source == "PRI.r_PlayerDevices + r_TempItems" and st_m.owned.Hoard == 1,
		b .. ": Hoard bought: rank I from the shop items, source named")
	st_m = read_m({ hoard, nimble }, { { hoard, base }, { nimble, base } })
	check(st_m.owned.Nimble == 1 and st_m.owned.Hoard == 1, b .. ": Nimble bought: I")
	local seen = {}
	for r = 2, 3 do
		local before = n_items()
		local changed
		st_m, changed = read_m({ hoard, nimble }, { { hoard, base }, { nimble, r - 1 + base } })
		seen[r] = st_m.owned.Nimble
		check(changed and st_m.owned.Nimble == r and st_m.owned.Hoard == 1 and n_items() == before + 1,
			b .. ": Nimble upgraded to " .. r .. ": shown " .. tostring(st_m.owned.Nimble) .. ", one log line")
		read_m({ hoard, nimble }, { { hoard, base }, { nimble, r - 1 + base } })
		check(n_items() == before + 1, b .. ": no log line on the read after it")
	end
	check(not st_m.owned[""] and st_m.owned.Hoard == 1, b .. ": the deck cards (level 5) are not items")
	local last = logs[#logs]
	for _, l in ipairs(logs) do
		if l:find("items [PRI]", 1, true) then last = l end
	end
	check(last:find("Nimble=3 (shop rank " .. (2 + base) .. ")", 1, true) ~= nil,
		b .. ": the log line names the shop rank the game gave: " .. last)
	-- sold: the slot is empty, the shop item may linger: the item is gone
	st_m = read_m({ hoard }, { { hoard, base }, { nimble, 2 + base } })
	check(st_m.owned.Nimble == nil and st_m.owned.Hoard == 1, b .. ": Nimble sold: gone even if r_TempItems still lists it")
	-- bought again: rank I
	st_m = read_m({ hoard, nimble }, { { hoard, base }, { nimble, base } })
	check(st_m.owned.Nimble == 1, b .. ": Nimble bought again: I")
end
-- r_TempItems that cannot be listed: slots alone, rank I, asked once
local PLn2 = Player.new(DATA)
local reads_t = 0
local pri_n = obj("TgGame.TgRepInfo_Player", { r_PlayerDevices = slots_with({ hoard }) })
setmetatable(pri_n, { __index = function(_, k)
	if k == "r_TempItems" then reads_t = reads_t + 1 return 5 end   -- not a list
end })
for i = 1, 4 do
	T0.player = { Pawn = pawn_of("Io"), PlayerReplicationInfo = pri_n, WorldInfo = { ptr = function() return 89 end } }
	local st_n = PLn2:poll(NOW + 1200 + i * 1.1)
	if i == 4 then
		check(st_n.owned.Hoard == 1 and st_n.source == "PRI.r_PlayerDevices", "without shop items: the slots, rank I")
	end
end
check(reads_t == 1, "r_TempItems that cannot be listed is asked once (" .. reads_t .. ")")
end

do
section("0.7.0 live reads: sc_game, non-champion pawns, live max health, mode from the game-info class")
local Gm = require("lib.sc_game")
-- Object:has: an undeclared property is never read; a struct (no has) is read directly
local touched = {}
local o = setmetatable({ has = function(_, k) return k == "Health" end, Health = 10 },
	{ __index = function(_, k) touched[k] = true end })
check(Gm.field(o, "Health") == 10 and Gm.field(o, "Missing") == nil and not touched.Missing,
	"sc_game.field: declared property read, undeclared one not looked up")
check(Gm.field({ nRank = 2 }, "nRank") == 2 and Gm.field(nil, "x") == nil, "sc_game.field: struct fields read directly")
check(Gm.is_a({ nRank = 1 }, "TgGame.TgPawn") == nil and Gm.class_name(nil) == nil and Gm.ptr(nil) == nil,
	"sc_game: a struct cannot say is_a; nil objects give nil")
-- the LiveCheck log in a Siege match: an illusion and the payload are players' pawns, not champions
local Det = require("lib.sc_detect")
local D7 = Det.new(PRED)
T0.player = match_pc("INT", nil, "Lian", {}, { "Makoa", "Ying" })
-- worst case: an illusion that answers the bot id of the champion it copies (the game's is "Ying_Illusion")
local illusion_calls, payload_calls = 0, 0
local illusion = obj("TgPawn_Illusion", { _parents = { "TgGame.TgPawn_Character", "TgGame.TgPawn" },
	GetBotId = function() illusion_calls = illusion_calls + 1 return champ("Ying").bot_id end })
local payload = obj("TgPawn_SiegeEngine_CaptureAndPayload", { _parents = { "TgGame.TgPawn" },
	GetBotId = function() payload_calls = payload_calls + 1 return 2590 end })
local my_tf
for _, pri in T0.player.WorldInfo.GRI.PRIArray:items() do
	local owner = pri.r_PawnOwner
	if owner and owner:class():name() == pawn_class("Makoa") then pri.r_nHealthMaximum = 5100 end
	if owner and owner:class():name() == pawn_class("Ying") then pri.r_nHealthMaximum = 2600 end
end
table.insert(T0.player.WorldInfo.GRI.PRIArray, obj("TgGame.TgRepInfo_Player", { r_PawnOwner = illusion,
	GetTaskForceNumber = function() return 2 end }))
table.insert(T0.player.WorldInfo.GRI.PRIArray, obj("TgGame.TgRepInfo_Player", { r_PawnOwner = payload,
	GetTaskForceNumber = function() return 2 end }))
local st7 = D7:read()
check(same_list(st7.enemies, { "Makoa", "Ying" }) and payload_calls == 0 and illusion_calls == 0,
	"illusion and Siege payload: not champions, never asked for a bot id: " .. table.concat(st7.enemies, ","))
local classes = {}
for _, rec in ipairs(st7.players) do classes[#classes + 1] = tostring(rec.pawn) .. "=" .. tostring(rec.champ) end
table.sort(classes)
check(#st7.players == 4 and table.concat(classes, ","):find("TgPawn_Illusion=nil", 1, true)
	and st7.players[1].tf ~= nil, "each player as read is kept for the report: " .. table.concat(classes, ","))
check(st7.enemy_hp.Makoa == 5100 and st7.enemy_hp.Ying == 2600, "enemy max health from TgRepInfo_Player.r_nHealthMaximum")
check(st7.mode == "siege" and st7.mode_rule == "class TgGame.TgRepInfo_Game_Payload", "Siege from the game-info class")
-- mode: TDM (and its Roulette subclass) by class, onslaught by map on the base class, nothing else guessed
local function gri_of(class, parents)
	local g = obj(class, {})
	g._parents = parents
	return g
end
check(D7:guess_mode("td_dragonarena_p", gri_of("TgGame.TgRepInfo_Game_TeamDeathMatch_Roulette",
	{ "TgGame.TgRepInfo_Game_TeamDeathMatch", "TgGame.TgRepInfo_Game" })) == "tdm", "Roulette TDM is a TDM by class")
check(D7:guess_mode("ons_brightmarsh_p", gri_of("TgGame.TgRepInfo_Game", {})) == "onslaught", "onslaught by map on the base class")
-- the 8.1 map packages: Siege runs on the base class (sg_icemines_p in a real match), as do onslaught
-- (ON_*) and King of the Hill
local base = gri_of("TgGame.TgRepInfo_Game", {})
for map, want in pairs({ sg_icemines_p = "siege", sg_tcrossing_p = "siege", sgb_serpentbeach_p = "siege",
	s_celestialfortress_p = "siege", on_primalcourt_p = "onslaught", koth_tradedistrict_p = "onslaught",
	tdm_hole_p = "tdm", td_abyss_p = "tdm", ktm_tdv2_p = "tdm", shootingrange_p = "range" }) do
	local got, rule = D7:guess_mode(map, base)
	check(got == want, map .. " on the base class: " .. want .. " (got " .. tostring(got) .. ", " .. tostring(rule) .. ")")
end
check(D7:guess_mode("mystery_p", gri_of("TgGame.TgRepInfo_Game", {})) == nil, "an unknown map on the base class: no mode")
-- the predictor's squishy rule: the live max health; a hand-picked enemy has none, so it is not counted
local function sentinel(live)
	PRED.live_hp = live
	for _, r in ipairs(PRED:rank_items(PRED:champion("Lian"), { PRED:champion("Ying"), PRED:champion("Makoa") }, {}, "mid")) do
		if r.item == "Sentinel" then return r.score end
	end
	return 0
end
local none, tanky, one, two = sentinel({}), sentinel({ Ying = 2600 }), sentinel({ Ying = 2100 }), sentinel({ Ying = 2100, Makoa = 2000 })
PRED.live_hp = {}
check(none == 0 and tanky == 0 and one > 0 and two > one,
	"squishy follows the live max health only, no health shipped (" .. none .. " / " .. tanky .. " / " .. one .. " / " .. two .. ")")
end

-- ------------------------------------------------------------------ 3. main.lua end to end
local L

local function looks_like_key(s)
	return s:match("^[%l][%l%d]*_[%l%d_]+$") ~= nil
end

local function check_frame(app, what)
	local stk = MOCK.stack
	check(stk.color == 0 and stk.var == 0 and stk.font == 0 and stk.id == 0 and stk.indent == 0
		and stk.disabled == 0, what .. ": ImGui stacks balanced")
	local leaks = {}
	for _, s in ipairs(MOCK.shown) do
		if looks_like_key(s) or s:find("%%[sd]") or s:find("<font") or s:find("{%d") then leaks[#leaks + 1] = s end
	end
	check(#leaks == 0, what .. ": no raw key / format / markup shown: " .. table.concat(leaks, " | "))
	for _, l in ipairs(app.T.logs) do
		if l:find("draw error") then
			check(false, what .. ": " .. l)
			app.T.logs = {}
		end
	end
end

-- Loads main.lua as Tempest would (fresh modules, same `shared` when hot reloading).
local function load_app(saved, keep_shared)
	for k in pairs(package.loaded) do
		if k:match("^lib%.") then package.loaded[k] = nil end
	end
	local T = new_tempest(saved)
	_G.tempest = T.api
	_G.ui = new_ui()
	if not keep_shared then _G.shared = {} end
	local before = {}
	for k in pairs(_G) do before[k] = true end
	local chunk = assert(loadfile("src/scripts/main.lua"))
	chunk()
	local leaked = {}
	for k in pairs(_G) do
		if not before[k] then leaked[#leaked + 1] = tostring(k) end
	end
	check(#leaked == 0, "main.lua and its modules create no global: " .. table.concat(leaked, ", "))
	L = require("lib.sc_lang")
	return { T = T, draw = MOCK.draw }
end

local function frame(app, what, dt)
	NOW = NOW + (dt or 0.5)
	MOCK.reset_frame()
	app.draw()
	check_frame(app, what)
	-- what tempest.queue holds runs outside the frame
	local q = app.T.queued
	app.T.queued = {}
	for _, fn in ipairs(q) do fn() end
end

local function frames(app, what, n)
	for i = 1, n or 4 do frame(app, what .. " f" .. i) end
end

local function shown_has(pattern)
	for _, s in ipairs(MOCK.shown) do
		if s:find(pattern, 1, true) then return true end
	end
	return false
end

section("main.lua: load, keys, no player")
local app = load_app()
local GLOBALS = {}
for k in pairs(_G) do GLOBALS[k] = true end
check(app.draw ~= nil, "main.lua registers ui.on_draw")
check(app.T.commands.smartcounter ~= nil, "the smartcounter command exists")
local n_cmd = 0
for _ in pairs(app.T.commands) do n_cmd = n_cmd + 1 end
check(n_cmd == 1, "only the smartcounter command (no debug commands)")
for _, spec in ipairs({ "Ctrl+J", "Ctrl+H", "Ctrl+O", "Ctrl+L", "Ctrl+K" }) do
	check(app.T.bound(spec), "default key bound: " .. spec)
end
frames(app, "idle, nothing shown", 2)
check(#MOCK.shown == 1 or #MOCK.shown == 0, "only the launch tip is drawn while hidden")
app.T.press("Ctrl+H")
frames(app, "panel, no player", 3)
check(shown_has(L.t("need_champ")), "panel asks for a champion")
app.T.press("Ctrl+J")
check(MOCK.capture == nil, "a key only queues its action (run by the next frame, on the draw thread)")
frame(app, "menu opens")
check(MOCK.capture == true, "menu captures the mouse")
frames(app, "menu + tutorial, no player", 3)
check(shown_has(L.t("tut1_t")), "first-run tutorial shown")
app.T.press("Ctrl+J")
frame(app, "menu closes")
check(MOCK.capture == false, "closing the menu releases the mouse")

section("main.lua: champion select, French game")
GAME.lang = "FRA"   -- a French client: lang.language() answers FRA from the start
app = load_app({ tutorial_done = true })
app.T.player = lobby_pc("FRA", "FR", "Cassie", { "Inara" })
app.T.press("Ctrl+J")
frames(app, "champ select FRA", 4)
check(L.lang == "fr", "Auto UI language follows the game (fr), from the engine while lang.language() says INT")
local cassie = champ("Cassie")
check(shown_has("FR" .. cassie.name_msg), "the game's champion name is shown")

section("main.lua: in a match, Japanese game, live items")
GAME.lang = "JPN"
app = load_app({ tutorial_done = true })
app.T.press("Ctrl+J")
local it1, it2 = DATA.items[DATA.item_order[1]], DATA.items[DATA.item_order[6]]
app.T.player = match_pc("JPN", "名前", "Lian", { "Inara" }, { "Makoa", "Androxus", "Viktor", "Grohk", "Fernando" },
	{ { it1.item_id, 2 }, { it2.item_id, 1 } })
frames(app, "match JPN, menu", 4)
check(L.lang == "ja", "Auto UI language follows the game (ja)")
local cjk_loaded = false
for _, f in ipairs(MOCK.fonts_added) do
	if f.merge and f.path and (f.path:find("YuGoth") or f.path:find("meiryo") or f.path:find("msgothic")) then cjk_loaded = true end
end
check(cjk_loaded or not io.open((os.getenv("WINDIR") or "C:\\Windows") .. "\\Fonts\\YuGothM.ttc", "rb"),
	"a Japanese font is merged when the PC has one")
check(shown_has("名前" .. champ("Makoa").name_msg), "Japanese game names reach the screen")
app.T.press("Ctrl+J")   -- close the menu: the panel alone
frames(app, "match JPN, panel", 3)
app.T.press("Ctrl+K")   -- layout toggle
frames(app, "match JPN, other layout", 2)
app.T.press("Ctrl+L")   -- lock toggle
frame(app, "lock")
check(#app.T.toasts >= 2, "lock / layout give a toast")

section("main.lua: every UI language, every tab")
GAME.lang = "INT"
for _, l in ipairs({ "en", "fr", "de", "it", "ru", "zh", "ja", "ko" }) do
	local a = load_app({ lang = l, tutorial_done = true, show_on_start = true })
	a.T.player = match_pc("INT", "EN", "Inara", {}, { "Makoa", "Lian" })
	a.T.press("Ctrl+J")
	frames(a, l .. " match tab", 3)
	check(L.lang == l, l .. ": UI language")
	a.T.press("Ctrl+O")
	frames(a, l .. " settings tab", 2)
	MOCK.tab_sel = "tab_help"
	frames(a, l .. " help tab", 1)
	check(shown_has(L.t("help_autobuy_t")), l .. ": help tab drawn")
	a.T.player = match_pc("INT", nil, "Inara", {}, { "Makoa" })   -- the translator is gone
	frames(a, l .. " no translator", 2)
	a.T.player.WorldInfo.GRI.bMatchIsOver = true
	frames(a, l .. " match over", 2)
	a.T.player = nil
	frames(a, l .. " no player", 2)
end

section("main.lua: help tab, rebinding, config saving, hot reload")
app = load_app({ tutorial_done = true, lang = "en" })
app.T.press("Ctrl+J")
frame(app, "menu")
MOCK.click = { [L.t("key_change")] = true }
app.T.press("Ctrl+O")
frame(app, "settings, start rebinding")
local K_ui = _G.ui
MOCK.keys_down[K_ui.Key.LeftCtrl] = true
MOCK.keys_pressed[K_ui.Key.M] = true
frame(app, "settings, key pressed")
MOCK.keys_down, MOCK.keys_pressed = {}, {}
check(app.T.bound("Ctrl+M") and not app.T.bound("Ctrl+J"), "menu key rebound to Ctrl+M")
local saves = app.T.saves
frame(app, "after change", 0.3)
check(app.T.saves == saves, "no save right after a change (debounced)")
frame(app, "after change", 1.5)
check(app.T.saves == saves + 1 and app.T.last_saved.keys.menu == "Ctrl+M", "saved once, a second after the change")
check(app.T.last_saved.lang ~= nil and app.T.last_saved.owned == nil,
	"config saved through tempest.save_config, without the session-only item ranks")
-- hot reload while the menu holds the mouse: the new instance releases it
local keep = _G.shared
check(keep.smartcounter.captured == true, "capture remembered in shared")
app = load_app({ tutorial_done = true }, true)
check(MOCK.capture == false and keep.smartcounter.captured == false, "hot reload releases the mouse")
frames(app, "after hot reload", 2)

section("main.lua: edge cases (config, Escape, sorted names, deaths, new game)")
app = load_app({ tutorial_done = true, lang = "en", manual = { me = "Nobody", enemies = { "makoa", "Ghost", "", "", "" } } })
local V = app.T.values
check(V.manual.me == "" and V.manual.enemies[1] == "Makoa" and V.manual.enemies[2] == "",
	"manual picks: unknown names dropped, aliases made canonical")
V.manual.enemies[1] = ""
app.T.player = lobby_pc("FRA", "FR", "Cassie", { "Inara" }, 601)
app.T.press("Ctrl+O")
frames(app, "settings, French game", 2)
MOCK.click = { [L.t("key_change")] = true }
frame(app, "rebind starts")
MOCK.keys_pressed[ui.Key.Escape] = true
frame(app, "Escape while rebinding")
MOCK.keys_pressed = {}
check(MOCK.capture == true and app.T.bound("Ctrl+J"), "Escape cancels the rebinding and keeps the menu open")
MOCK.keys_pressed[ui.Key.Escape] = true
frame(app, "Escape")
MOCK.keys_pressed = {}
check(MOCK.capture == false, "Escape then closes the menu")
app.T.press("Ctrl+J")
MOCK.tab_sel = "tab_match"
frames(app, "match tab, French names", 2)
local items = MOCK.combos["##me"] or {}
local sorted = #items > 10
for i = 3, #items do
	if items[i - 1]:lower() > items[i]:lower() then sorted = false end
end
check(sorted, "champion lists are sorted by the names shown (the game's)")
-- manual items set in champion select stay for its match, and go with the next game
V.owned = { Wrecker = 2 }
app.T.player = match_pc("FRA", "FR", "Cassie", { "Inara" }, { "Makoa", "Grohk" }, { { haven.item_id, 2 } },
	roster(601, { "Cassie", "Inara" }))
frames(app, "match of the same game", 3)
check(V.owned.Wrecker == 2, "the match of the same game keeps the manual items")
check(shown_has(L.t("owned_live", "PRI.r_PlayerDevices + r_TempItems")), "items read live in the match")
app.T.player.Pawn = nil
frames(app, "dead", 3)
check(shown_has(L.t("owned_live", "PRI.r_PlayerDevices + r_TempItems")) and shown_has(L.t("st_me", EN("Cassie"))),
	"dead: champion and live items are kept (English UI: the game's English name)")
app.T.player = lobby_pc("FRA", "FR", "Cassie", { "Inara" }, 601)
frames(app, "back in the lobby", 2)
check(V.owned.Wrecker == 2 and not shown_has(L.t("st_champ_select")), "lobby with the last roster: not a new game")
app.T.player = lobby_pc("FRA", "FR", "Lian", { "Inara" }, 602)
frames(app, "next champion select", 2)
check(next(V.owned) == nil, "a new game empties the manual items")

section("main.lua: item chips, 4 slots, header, names, loading")
GAME.lang = "FRA"   -- a French client with the mod in English
app = load_app({ tutorial_done = true, lang = "en" })
V = app.T.values
local four = { { DATA.items.Haven.item_id, 1 }, { DATA.items.Wrecker.item_id, 1 }, { DATA.items.Nimble.item_id, 1 },
	{ DATA.items.Chronos.item_id, 1 } }
app.T.player = match_pc("FRA", "FR", "Cassie", { "Inara" }, { "Makoa", "Grohk", "Lian" }, { four[1] })
app.T.press("Ctrl+H")
frames(app, "panel in a match, one item", 3)
-- geometry: the category mark is inside the chip, clear of every outline; the label after the mark
local marks, edges, texts = {}, {}, {}
for _, d in ipairs(MOCK.draws) do
	if d.k == "fill" and math.abs((d.x2 - d.x1) - 3) < 0.01 then marks[#marks + 1] = d end
	if d.k == "edge" and d.x1 < 40 then edges[#edges + 1] = d end   -- chip outlines (not the launch tip)
	if d.k == "text" and d.x1 > 20 and d.x1 < 40 then texts[#texts + 1] = d end
end
check(#marks > 0 and #edges > 0 and #texts > 0, "chips drawn with marks, outlines and labels")
local clear = true
for _, m in ipairs(marks) do
	for _, e in ipairs(edges) do
		if m.x1 < e.x1 + e.t + 1 or m.y1 < e.y1 + e.t or m.y2 > e.y2 - e.t then clear = false end
	end
	for _, tx in ipairs(texts) do
		if tx.x1 < m.x2 + 4 then clear = false end
	end
end
check(clear, "the category mark never touches the outline (2 px accent included) nor the label")
local accent = false
for _, e in ipairs(edges) do
	if e.t == 2 then accent = true end
end
check(accent, "the next purchase has the 2 px accent outline")
check(not shown_has("FR"), "English UI on a French game: no French name on screen")
-- header: no unknown mode, no automatic phase, no '*'
for _, sh in ipairs(MOCK.shown) do
	if sh:find(L.t("phase_mid") .. "*", 1, true) or sh:find("mode unknown", 1, true) then
		check(false, "header noise shown: " .. sh)
	end
end
check(not shown_has("  ·  " .. L.t("phase_early")) and not shown_has("  ·  " .. L.t("phase_mid")),
	"automatic phase not in the header")
V.phase = "late"
frames(app, "phase set by hand", 2)
check(shown_has("  ·  " .. L.t("phase_late")), "a phase set by hand is shown")
V.phase = "auto"
app.T.player.WorldInfo.GRI.class = function() return { name = function() return "TgGame.TgGRI_Mystery" end } end
app.T.player.WorldInfo.GRI.is_a = function() return false end
app.T.player.WorldInfo.path = function() return "Mystery_P.TheWorld" end
frames(app, "unknown mode", 3)
check(not shown_has(L.t("mode_siege")) and not shown_has("mode_unknown"), "an unknown mode is simply not shown")
-- 4 items owned: count out of 4, the optional 5th dimmed and marked
app.T.player = match_pc("FRA", "FR", "Cassie", { "Inara" }, { "Makoa", "Grohk", "Lian" }, four)
app.T.press("Ctrl+J")
MOCK.tab_sel = "tab_match"
frames(app, "4 items owned", 3)
check(shown_has(L.t("owned_n", 4, 4)) and not shown_has("/5"), "item count out of the game's 4 slots")
check(shown_has(L.t("flex_full")) and shown_has(L.t("flex_full_long")), "optional item marked 'slots full'")
local dim = false
for _, d in ipairs(MOCK.draws) do
	if d.k == "fill" and type(d.c) == "table" and d.c[4] < 0.5 then dim = true end
end
check(dim, "the blocked optional chip is drawn dimmed")
-- names: the French UI shows the game's names, game_names keeps them in English
V.lang = "fr"
frames(app, "French UI", 2)
check(shown_has("FR" .. champ("Cassie").name_msg), "French UI on a French game: the game's names")
V.lang, V.game_names = "en", true
frames(app, "English UI, game names kept", 2)
check(shown_has("FR" .. champ("Cassie").name_msg), "game_names on: the game's names with the English UI")
V.game_names = false
-- manual grid: 4 items max
app.T.player = lobby_pc("FRA", "FR", "Cassie", { "Inara" }, 801)
frames(app, "lobby, champion select", 2)
V.owned = { Haven = 1, Wrecker = 1, Nimble = 1, Chronos = 1 }
frames(app, "manual grid full", 2)
check(shown_has(L.t("owned_full")) and MOCK.disabled_n > 0, "manual grid: 4 items max, the others locked")
-- champion select -> loading -> match
app.T.player = nil
frames(app, "loading after champion select", 3)
check(shown_has(L.t("badge_loading")) and not shown_has(L.t("badge_plan")), "loading: not 'not in a game'")
check(shown_has(L.t("st_auto", L.t("st_loading"))) and shown_has(L.t("st_me", EN("Cassie"))), "loading: my pick kept")
GAME.lang = "INT"

section("main.lua: header without repeats, names setting explained")
app = load_app({ tutorial_done = true, lang = "en", display = "detailed" })
V = app.T.values
app.T.player = match_pc("INT", nil, "Lian", { "Inara" }, { "Makoa", "Grohk" })
app.T.press("Ctrl+H")
frames(app, "Damage champion", 3)
local role_d, style_d = game_text("EN", DATA.role_msg.Damage) or L.t("role_Damage"), L.t("style_dps")   -- the game's label
local twice = false
for _, sh in ipairs(MOCK.shown) do
	if sh:find("(" .. role_d .. ")", 1, true) and sh:find("  ·  " .. style_d, 1, true) then twice = true end
end
check(shown_has("(" .. role_d .. ")") and not twice, "Damage champion: role once, no playstyle repeating it")
app.T.player = match_pc("INT", nil, "Grohk", { "Inara" }, { "Makoa", "Lian" })
frames(app, "Support champion", 3)
check(shown_has("(" .. (game_text("EN", DATA.role_msg.Support) or L.t("role_Support")) .. ")  ·  " .. L.t("style_heal")),
	"Support: role and its chosen playstyle")
local PREFIX = { fr = "FR", de = "DE", ru = "RU", ja = "名前" }
for _, l in ipairs({ "fr", "de", "ru", "ja" }) do
	V.lang = l
	frames(app, "header in " .. l, 2)
	local dup = false
	for _, sh in ipairs(MOCK.shown) do
		local a, b = game_text(PREFIX[l], DATA.role_msg.Support) or L.t("role_Support"), L.t("style_heal")
		if a == b and sh:find(a .. ")  ·  " .. b, 1, true) then dup = true end
	end
	check(not dup, l .. ": no repeated label in the header")
end
V.lang = "en"
-- settings: what the names setting does now, tooltip (a French client)
GAME.lang = "FRA"
app = load_app({ tutorial_done = true, lang = "en", display = "detailed" })
V = app.T.values
app.T.player = match_pc("FRA", "FR", "Lian", { "Inara" }, { "Makoa", "Grohk" })
app.T.press("Ctrl+O")
frames(app, "settings, French game, English mod", 3)
check(shown_has(L.t("set_game_names_now", "Français", "English", "English")), "settings say: names in English now")
check(shown_has(L.t("set_game_names_tip")), "the names setting has a tooltip")
V.game_names = true
frames(app, "game names on", 2)
check(shown_has(L.t("set_game_names_now", "Français", "English", "Français")), "settings say: names in French now")
local french_sentence = false
for _, sh in ipairs(MOCK.shown) do
	if sh:find("FR" .. DATA.items.Haven.desc_msg, 1, true) or sh:find("FR" .. DATA.role_msg.Damage, 1, true) then
		french_sentence = true
	end
end
check(not french_sentence, "game names on: no French description or role in the English panel")
V.game_names = false

section("main.lua: Resilience bought at I, upgraded to II then III in the match")
GAME.lang = "INT"
app = load_app({ tutorial_done = true, lang = "en", display = "detailed" })
local res_m = DATA.items.Resilience
local buy = { { res_m.item_id, 1 }, { DATA.items.Haven.item_id, 1 }, { DATA.items.Wrecker.item_id, 1 } }
app.T.player = match_pc("INT", "EN", "Makoa", { "Inara" }, { "Lian", "Androxus" }, buy)
local temp = app.T.player.PlayerReplicationInfo.r_TempItems
app.T.press("Ctrl+H")
local function res_rank()
	local id = tostring(res_m.name_msg)
	for _, sh in ipairs(MOCK.shown) do
		if sh:find(id, 1, true) or sh:find("Resilience", 1, true) then
			local r = sh:match(" ([I]+)\226\134\146 ?[I]+$") or sh:match(" ([I]+) \226\134\146 [I]+$") or sh:match(" ([I]+)$")
			if r then return r end
		end
	end
end
frames(app, "Resilience rank I", 4)
check(res_rank() == "I", "rank I shown after buying: " .. tostring(res_rank()))
check(shown_has(L.t("owned_n", 3, 4)), "items 3/4")
for r, roman in ipairs({ "I", "II", "III" }) do
	temp[1].nRank = r   -- the shop rank after each upgrade
	frames(app, "Resilience rank " .. roman, 4)
	check(res_rank() == roman, "after the upgrade the panel shows Resilience " .. roman .. " (shown: " .. tostring(res_rank()) .. ")")
	check(shown_has(L.t("owned_n", 3, 4)), "still items 3/4 at rank " .. roman)
end

section("main.lua: Wrecker, Nimble and Morale Boost upgraded I -> II -> III, one log line per change")
for _, ui_lang in ipairs({ "en", "fr" }) do
	app = load_app({ tutorial_done = true, lang = ui_lang, display = "detailed" })
	L.set(ui_lang)
	local three = { "Wrecker", "Nimble", "Morale Boost" }
	local buy3 = {}
	for i, k in ipairs(three) do buy3[i] = { DATA.items[k].item_id, 1 } end
	-- a French client (Broyeur / Agile / Amassage in the shop) with the mod in English or French
	app.T.player = match_pc("FRA", "FR", "Makoa", { "Inara" }, { "Lian", "Androxus" }, buy3)
	local pri3 = app.T.player.PlayerReplicationInfo
	app.T.press("Ctrl+H")
	local function chip_rank(key)
		local id = tostring(DATA.items[key].name_msg)
		for _, sh in ipairs(MOCK.shown) do
			if sh:find(id, 1, true) or sh:find(key, 1, true) then
				local owned = sh:match(" ([I]+) \226\134\146 [I]+$") or sh:match(" ([I]+)$")
				if owned then return owned, sh end
			end
		end
	end
	local function item_logs()
		local n = 0
		for _, line in ipairs(app.T.logs) do
			if line:find("[smartcounter] items [", 1, true) then n = n + 1 end
		end
		return n
	end
	frames(app, ui_lang .. ": three items at rank I", 6)
	local ok, fraction = true, false
	for _, k in ipairs(three) do
		local r, sh = chip_rank(k)
		if r ~= "I" then ok = false end
		if sh and sh:find("/", 1, true) then fraction = true end
	end
	check(ok and not fraction, ui_lang .. ": Wrecker, Nimble, Morale Boost bought: rank I each, no fraction")
	check(item_logs() == 1, ui_lang .. ": one log line for the purchases (" .. item_logs() .. ")")
	for i, k in ipairs(three) do
		for r = 2, 3 do
			pri3.r_TempItems[i].nRank = r   -- the shop rank after the upgrade
			local before = item_logs()
			frames(app, ui_lang .. ": " .. k .. " rank " .. r, 6)
			local shown, sh = chip_rank(k)
			check(shown == require("lib.sc_view").roman(r) and not (sh or ""):find("/", 1, true),
				ui_lang .. ": " .. k .. " upgraded to " .. require("lib.sc_view").roman(r) .. " is shown " .. tostring(shown) .. " (" .. tostring(sh) .. ")")
			check(item_logs() == before + 1, ui_lang .. ": " .. k .. " rank " .. r .. ": exactly one new log line")
			check(shown_has(L.t("owned_n", 3, 4)), ui_lang .. ": still items 3/4")
		end
	end
	local last
	for _, line in ipairs(app.T.logs) do
		if line:find("[smartcounter] items [", 1, true) then last = line end
	end
	check(last and last:find("Wrecker=3 (shop rank 3)", 1, true) and last:find("Nimble=3 (shop rank 3)", 1, true)
		and last:find("Morale Boost=3 (shop rank 3)", 1, true), ui_lang .. ": the last log line has the three items at III: " .. tostring(last))
	local before = item_logs()
	frames(app, ui_lang .. ": nothing changes", 8)
	check(item_logs() == before, ui_lang .. ": no log line while nothing changes (4 s of reads)")
	-- selling one item: its slot is emptied (r_TempItems may still list it): one line, the item is gone
	table.remove(pri3.r_PlayerDevices, 3)
	frames(app, ui_lang .. ": Wrecker sold", 6)
	check(item_logs() == before + 1, ui_lang .. ": a sale writes one log line")
	check(shown_has(L.t("owned_n", 2, 4)), ui_lang .. ": items 2/4 after the sale")
	local warn = false
	for _, line in ipairs(app.T.logs) do
		if line:find("has no property", 1, true) then warn = true end
	end
	check(not warn, ui_lang .. ": no 'has no property' line from the mod")
end
L.set("en")

do
section("main.lua: practice map reads items, status in the log, report button")
GAME.lang = "FRA"   -- a French Steam client, the mod set to English
app = load_app({ tutorial_done = true, lang = "en", display = "detailed" })
local res_p = DATA.items.Resilience
app.T.player = match_pc("INT", "EN", "Makoa", {}, {}, { { res_p.item_id, 1 } })
app.T.player.WorldInfo.GRI = nil                                -- training / range: no match state
app.T.press("Ctrl+H")
frames(app, "practice map", 4)
local function logged(pat)
	local n = 0
	for _, l in ipairs(app.T.logs) do
		if l:find(pat, 1, true) then n = n + 1 end
	end
	return n
end
check(logged("[smartcounter] status: loading, practice map") == 1, "the practice map is said once in the log")
check(logged("item reading paused") == 0, "items are not paused on a practice map")
check(logged("[smartcounter] items [") == 1 and logged("Resilience=1 (shop rank 1)") == 1, "items read on a practice map")
app.T.player.PlayerReplicationInfo.r_TempItems[1].nRank = 2
frames(app, "practice map, upgrade", 4)
check(logged("Resilience=2 (shop rank 2)") == 1, "an upgrade on a practice map is followed")
-- the Match tab's report button (bug reports): one short block from the modules' state, and a toast
app.T.press("Ctrl+J")
MOCK.tab_sel = "tab_match"
frames(app, "match tab", 2)
check(shown_has(L.t("owned_diag")), "the Match tab has the report button")
check(logged("[smartcounter] report") == 0, "no report without a press")
local before = #app.T.logs
MOCK.click = { [L.t("owned_diag")] = true }
frames(app, "report pressed", 2)
MOCK.click = {}
check(logged("[smartcounter] report v0.7.0") == 1 and logged("report: items live (PRI.r_PlayerDevices + r_TempItems), owned Resilience=2") == 1,
	"one press: version, status and the items read, in the log")
check(logged("client language FRA (lang.language INT), UI en (setting en)") == 1,
	"the report says where the language comes from: the engine's FRA, lang.language()'s INT, the setting")
check(#app.T.logs - before <= 6, "one short block per press (" .. (#app.T.logs - before) .. " lines)")
local toasted = false
for _, x in ipairs(app.T.toasts) do
	if x == L.t("owned_diag_done") then toasted = true end
end
check(toasted, "a toast says where the report went")
frames(app, "after the press", 4)
check(logged("[smartcounter] report v0.7.0") == 1, "nothing more without a press")
app.T.press("Ctrl+J")
-- a real loading after champion select still pauses, and says so once
app = load_app({ tutorial_done = true, lang = "en" })
app.T.player = lobby_pc("INT", "EN", "Makoa", { "Inara" }, 901)
app.T.press("Ctrl+H")
frames(app, "champion select", 2)
app.T.player = nil
frames(app, "loading", 3)
check(logged("[smartcounter] status: loading (map") == 1 and logged("item reading paused") == 1,
	"loading after champion select: item reading paused, said once")
end

do
section("main.lua: no game data, the mod stays off and says why")
GAME.lang = "INT"
GAME.fail = "file not found"
app = load_app({ tutorial_done = true })
frame(app, "no game data")
check(#app.T.toasts == 1 and app.T.toasts[1]:find("assembly.dat: file not found", 1, true) and not app.T.bound("Ctrl+J"),
	"no game data: one toast with the reason, no key bound: " .. tostring(app.T.toasts[1]))
frame(app, "no game data, again")
check(#app.T.toasts == 1 and tostring(app.T.logs[#app.T.logs]):find("game data unavailable", 1, true),
	"the reason is said once, and logged")
GAME.fail = nil

section("main.lua: a live match, Nimble upgraded through r_TempItems")
app = load_app({ tutorial_done = true, lang = "fr", display = "detailed" })
L.set("fr")
local hoard, nimble = DATA.items.Hoard, DATA.items.Nimble
app.T.player = match_pc("FRA", "FR", "Io", { "Inara" }, { "Lian", "Androxus" })
local pri = app.T.player.PlayerReplicationInfo
local slots = {}
for i = 1, 49 do slots[i] = { CurrentDeviceId = 0, Level = 0 } end
slots[6] = { CurrentDeviceId = 24554, Level = 5 }
slots[9] = { CurrentDeviceId = hoard.item_id, Level = 0, CurrentDeviceCount = 1 }
slots[10] = { CurrentDeviceId = nimble.item_id, Level = 0, CurrentDeviceCount = 1 }
pri.r_PlayerDevices = slots
pri.r_TempItems = { { nDevId = hoard.item_id, nRank = 1 }, { nDevId = nimble.item_id, nRank = 1 }, { nDevId = 0, nRank = 0 } }
app.T.press("Ctrl+H")
local function chip(key)
	local id = tostring(DATA.items[key].name_msg)
	for _, sh in ipairs(MOCK.shown) do
		if sh:find(id, 1, true) or sh:find(key, 1, true) then
			local owned = sh:match(" ([I]+) \226\134\146 [I]+$") or sh:match(" ([I]+)$")
			if owned then return owned end
		end
	end
end
frames(app, "match: Hoard and Nimble at I", 4)
check(chip("Nimble") == "I" and chip("Hoard") == "I" and shown_has(L.t("owned_n", 2, 4)), "Hoard I, Nimble I, items 2/4")
pri.r_TempItems[2].nRank = 2
frames(app, "Nimble upgraded to II", 4)
check(chip("Nimble") == "II", "the scoreboard's 2 pips: the panel shows Nimble II (shown " .. tostring(chip("Nimble")) .. ")")
pri.r_TempItems[2].nRank = 3
frames(app, "Nimble upgraded to III", 4)
check(chip("Nimble") == "III" and chip("Hoard") == "I" and shown_has(L.t("owned_n", 2, 4)), "Nimble III, Hoard still I, items 2/4")
app.T.press("Ctrl+J")
MOCK.tab_sel = "tab_match"
frames(app, "match tab", 2)
check(shown_has(L.t("owned_live", "PRI.r_PlayerDevices + r_TempItems")), "the Match tab names both sources")
local n_items = 0
for _, l in ipairs(app.T.logs) do
	if l:find("[smartcounter] items [PRI]", 1, true) then n_items = n_items + 1 end
end
check(n_items == 3, "three item lines in the match: bought, II, III (" .. n_items .. ")")
app.T.press("Ctrl+J")
L.set("en")
end

local leaked = {}
for k in pairs(_G) do
	if not GLOBALS[k] then leaked[#leaked + 1] = tostring(k) end
end
check(#leaked == 0, "no global created while drawing: " .. table.concat(leaked, ", "))

-- ------------------------------------------------------------------ report
note(string.format("%d passed, %d failed", passed, failed))
local f = io.open(REPORT, "w")
if f then
	f:write(table.concat(lines, "\n"), "\n")
	f:close()
end
if failed > 0 then
	local fails = {}
	for _, l in ipairs(lines) do
		if l:sub(1, 4) == "FAIL" then fails[#fails + 1] = l end
		if #fails >= 25 then break end
	end
	error(string.format("%d test(s) failed:\n%s", failed, table.concat(fails, "\n")), 0)
end
