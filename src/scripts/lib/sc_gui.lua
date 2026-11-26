-- Counter & Shop Helper: ImGui helpers shared by the panel and the menu.
--
--   G.C         the palette
--   G.with_theme, G.tcol, G.wrapped, G.avail_w
-- Widgets are Tempest's `ui` functions (types/imgui.d.lua), called directly.

local G = {}

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

-- Runs fn with the mod's colours and style pushed. They are popped even when fn raises, so one error
-- in the panel never leaves the game's own UI in the mod's theme; the error is then raised again.
function G.with_theme(fn)
	local nc, nv = 0, 0
	for name, c in pairs(COLORS) do
		local idx = ui.Col[name]   -- nil for a name this ImGui version does not have (TabActive / TabSelected)
		if idx then
			ui.push_color(idx, c[1], c[2], c[3], c[4])
			nc = nc + 1
		end
	end
	for name, v in pairs(VARS) do
		local idx = ui.StyleVar[name]
		if idx then
			ui.push_var(idx, v[1], v[2])
			nv = nv + 1
		end
	end
	local ok, err = pcall(fn)
	ui.pop_var(nv)
	ui.pop_color(nc)
	if not ok then error(err, 0) end
end

-- Coloured text (one line), and wrapped text (c = nil: default colour).
function G.tcol(c, s)
	ui.text_colored(c[1], c[2], c[3], c[4], "%s", s)
end

function G.wrapped(c, s)
	if c then ui.push_color(ui.Col.Text, c[1], c[2], c[3], c[4]) end
	ui.text_wrapped("%s", s)
	if c then ui.pop_color(1) end
end

-- Width left on the current line.
function G.avail_w()
	return (ui.content_region_avail())
end

return G
