-- Counter & Shop Helper: ImGui helpers shared by the panel and the menu.
--
--   G.ui        the Tempest `ui` table, guarded: every scoped call (window, table, tab...) runs its
--               body in pcall, so an error inside never skips the matching End, and the push/pop
--               stacks (colours, style vars, fonts, ids, indent) are put back to their level.
--   G.C         the palette
--   G.with_theme, G.tcol, G.wrapped, G.bor

local G = {}
local RAW = ui

-- ------------------------------------------------------------------ guarded ImGui
local depth = { color = 0, var = 0, font = 0, id = 0, indent = 0 }

local function snapshot()
	return { depth.color, depth.var, depth.font, depth.id, depth.indent }
end

local function restore(s)
	if depth.color > s[1] then pcall(RAW.pop_color, depth.color - s[1]) end
	if depth.var > s[2] then pcall(RAW.pop_var, depth.var - s[2]) end
	for _ = s[3] + 1, depth.font do pcall(RAW.pop_font) end
	for _ = s[4] + 1, depth.id do pcall(RAW.pop_id) end
	if depth.indent > s[5] then pcall(RAW.unindent, depth.indent - s[5]) end
	depth.color, depth.var, depth.font, depth.id, depth.indent = s[1], s[2], s[3], s[4], s[5]
end

-- Wraps a scoped widget (ui.window(title, opts, fn) ...): its function arguments run protected;
-- the first error is raised again once the widget has been closed.
local function scoped(name)
	return function(...)
		local args, n, err = { ... }, select("#", ...), nil
		for k = 1, n do
			local fn = args[k]
			if type(fn) == "function" then
				args[k] = function(...)
					local s = snapshot()
					local ok, e = pcall(fn, ...)
					if not ok then
						restore(s)
						err = err or e
					end
				end
			end
		end
		local r = { RAW[name](unpack(args, 1, n)) }
		if err then error(err, 0) end
		return unpack(r)
	end
end

local U = setmetatable({}, { __index = RAW })
for _, name in ipairs({ "window", "child", "group", "tooltip", "tab_bar", "tab_item", "table", "popup",
	"popup_modal", "popup_context_item", "tree", "menu", "menu_bar", "with_font" }) do
	if RAW[name] then U[name] = scoped(name) end
end
function U.push_color(...) RAW.push_color(...) depth.color = depth.color + 1 end
function U.pop_color(n) n = n or 1 RAW.pop_color(n) depth.color = math.max(0, depth.color - n) end
function U.push_var(...) RAW.push_var(...) depth.var = depth.var + 1 end
function U.pop_var(n) n = n or 1 RAW.pop_var(n) depth.var = math.max(0, depth.var - n) end
function U.push_font(f) RAW.push_font(f) depth.font = depth.font + 1 end
function U.pop_font() RAW.pop_font() depth.font = math.max(0, depth.font - 1) end
function U.push_id(x) RAW.push_id(x) depth.id = depth.id + 1 end
function U.pop_id() RAW.pop_id() depth.id = math.max(0, depth.id - 1) end
function U.indent(w) RAW.indent(w) depth.indent = depth.indent + (w or 0) end
function U.unindent(w) RAW.unindent(w) depth.indent = depth.indent - (w or 0) end
G.ui = U

-- Flags are plain integers; LuaJIT has `bit`, the fallback adds distinct single-bit flags.
G.bor = (bit and bit.bor) or function(...)
	local s = 0
	for _, v in ipairs({ ... }) do s = s + v end
	return s
end

-- ------------------------------------------------------------------ palette and theme
G.C = {
	ACCENT = { 1.0, 0.80, 0.35, 1 }, DIM = { 0.66, 0.68, 0.74, 1 }, WARN = { 1.0, 0.55, 0.45, 1 },
	HIGH = { 1.0, 0.42, 0.38, 1 }, MED = { 1.0, 0.68, 0.30, 1 }, LOW = { 0.95, 0.88, 0.45, 1 },
	GOOD = { 0.55, 0.85, 0.55, 1 },
	-- item chips: grey = not owned, amber = rank rising, green = advised rank reached, blue = optional.
	-- Fills are muted so the label stays readable on them; outlines are 1 px except the next purchase.
	CHIP_BG = { 0.17, 0.18, 0.23, 1 }, CHIP_EDGE = { 0.31, 0.33, 0.42, 1 }, CHIP_TEXT = { 0.95, 0.95, 0.97, 1 },
	FILL_PART = { 0.64, 0.46, 0.16, 1 }, FILL_DONE = { 0.21, 0.48, 0.29, 1 },
	FLEX_BG = { 0.12, 0.16, 0.24, 0.9 }, FLEX_EDGE = { 0.45, 0.62, 0.90, 0.8 }, FLEX_TEXT = { 0.64, 0.79, 1.0, 1 },
}
-- Shop category marks on the chips (drawn shapes, no game art): 0xRRGGBB.
G.CATEGORY_RGB = { Defense = 0x5B9BE6, Utility = 0xB07CE8, Healing = 0x5CCB7A, Weapon = 0xE8775B }

local COLORS = {
	WindowBg = { 0.07, 0.08, 0.11, 0.96 }, PopupBg = { 0.09, 0.10, 0.14, 0.98 }, Border = { 0.24, 0.26, 0.34, 0.8 },
	TitleBg = { 0.09, 0.10, 0.14, 1 }, TitleBgActive = { 0.13, 0.14, 0.20, 1 },
	FrameBg = { 0.14, 0.15, 0.21, 1 }, FrameBgHovered = { 0.20, 0.22, 0.30, 1 }, FrameBgActive = { 0.26, 0.28, 0.38, 1 },
	Button = { 0.19, 0.21, 0.29, 1 }, ButtonHovered = { 0.30, 0.33, 0.45, 1 }, ButtonActive = { 0.62, 0.46, 0.16, 1 },
	Header = { 0.19, 0.21, 0.29, 1 }, HeaderHovered = { 0.30, 0.33, 0.45, 1 }, HeaderActive = { 0.62, 0.46, 0.16, 1 },
	Tab = { 0.13, 0.14, 0.20, 1 }, TabHovered = { 0.30, 0.33, 0.45, 1 }, TabActive = { 0.55, 0.41, 0.15, 1 },
	TabSelected = { 0.55, 0.41, 0.15, 1 }, CheckMark = { 1.0, 0.80, 0.35, 1 }, SliderGrab = { 0.86, 0.64, 0.24, 1 },
	SliderGrabActive = { 1.0, 0.80, 0.35, 1 }, PlotHistogram = { 0.86, 0.62, 0.22, 1 }, Separator = { 0.26, 0.28, 0.36, 1 },
	Text = { 0.93, 0.93, 0.95, 1 }, TextDisabled = { 0.62, 0.64, 0.70, 1 },
}
local VARS = {
	WindowRounding = { 8 }, ChildRounding = { 6 }, FrameRounding = { 5 }, PopupRounding = { 6 }, GrabRounding = { 4 },
	TabRounding = { 5 }, WindowPadding = { 12, 10 }, FramePadding = { 8, 4 }, ItemSpacing = { 8, 5 },
	WindowBorderSize = { 1 },
}

-- Runs fn with the mod's colours and style pushed (and always popped).
function G.with_theme(fn)
	local nc, nv = 0, 0
	for name, c in pairs(COLORS) do
		local idx = U.Col[name]
		if idx then
			U.push_color(idx, c[1], c[2], c[3], c[4])
			nc = nc + 1
		end
	end
	for name, v in pairs(VARS) do
		local idx = U.StyleVar[name]
		if idx and pcall(U.push_var, idx, v[1], v[2]) then nv = nv + 1 end
	end
	local ok, err = pcall(fn)
	if nv > 0 then U.pop_var(nv) end
	if nc > 0 then U.pop_color(nc) end
	if not ok then error(err, 0) end
end

-- Coloured text (one line), and wrapped text (c = nil: default colour).
function G.tcol(c, s)
	U.text_colored(c[1], c[2], c[3], c[4], "%s", s)
end

function G.wrapped(c, s)
	if c then U.push_color(U.Col.Text, c[1], c[2], c[3], c[4]) end
	U.text_wrapped("%s", s)
	if c then U.pop_color(1) end
end

-- Width left on the current line, with a fallback when ImGui cannot tell.
function G.avail_w()
	local ok, w = pcall(U.content_region_avail)
	if ok and type(w) == "number" and w > 0 then return w end
	return (U.window_width() or 300) - 24
end

return G
