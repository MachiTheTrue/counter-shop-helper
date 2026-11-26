-- Counter & Shop Helper: hotkeys (tempest.on_key) and rebinding from the menu.
--
-- Every action has one key spec ("Ctrl+J"). Rebinding listens to ImGui's key state while the menu is
-- open, then swaps the Tempest binding; a refused or duplicate key keeps the old one.

local K = {}
K.__index = K
K.ACTIONS = { "menu", "overlay", "settings", "lock", "layout" }

-- Keys offered for rebinding, all on a 60% keyboard (F-keys via Fn): { ImGui name, Tempest name }.
local CAPTURE = {}
for c = 65, 90 do CAPTURE[#CAPTURE + 1] = { string.char(c), string.char(c) } end
for i = 0, 9 do CAPTURE[#CAPTURE + 1] = { tostring(i), tostring(i) } end
for i = 1, 12 do CAPTURE[#CAPTURE + 1] = { "F" .. i, "F" .. i, fkey = true } end
for _, p in ipairs({ { "Semicolon", "Semicolon" }, { "GraveAccent", "Tilde" }, { "Minus", "Minus" },
	{ "Equal", "Equals" }, { "LeftBracket", "LeftBracket" }, { "RightBracket", "RightBracket" },
	{ "Apostrophe", "Quote" }, { "Comma", "Comma" }, { "Period", "Period" }, { "Slash", "Slash" },
	{ "Backslash", "Backslash" } }) do
	CAPTURE[#CAPTURE + 1] = p
end

-- cfg: sc_config object, defaults: key specs, t: translator, log: fn, on_action: fn(id) -> handled
function K.new(cfg, defaults, t, log, on_action)
	return setmetatable({ cfg = cfg, defaults = defaults, t = t, log = log, on_action = on_action,
		ids = {}, rebinding = nil, msg = nil, msg_ok = true }, K)
end

function K:bind(id, spec)
	local ok, kid = pcall(tempest.on_key, spec, function()
		if self.rebinding then return false end   -- the key being typed is for the rebinding
		return self.on_action(id)
	end)
	if ok and kid then
		self.ids[id] = kid
		return true
	end
	return false, tostring(kid)
end

function K:unbind(id)
	if self.ids[id] then pcall(tempest.off_key, self.ids[id]) end
	self.ids[id] = nil
end

-- Binds every action; an invalid key in the config goes back to its default.
function K:bind_all()
	local keys = self.cfg.values.keys
	for _, a in ipairs(K.ACTIONS) do
		if not self:bind(a, keys[a]) then
			self.log("invalid key %s for %s, back to %s", tostring(keys[a]), a, self.defaults[a])
			keys[a] = self.defaults[a]
			self:bind(a, keys[a])
			self.cfg:mark_dirty()
		end
	end
end

function K:rebind(id, spec)
	local keys, t = self.cfg.values.keys, self.t
	for _, a in ipairs(K.ACTIONS) do
		if a ~= id and keys[a] == spec then return false, t("key_in_use", spec, t("act_" .. a)) end
	end
	local old = keys[id]
	self:unbind(id)
	local ok, err = self:bind(id, spec)
	if ok then
		keys[id] = spec
		self.cfg:mark_dirty()
		return true
	end
	self:bind(id, old)
	return false, t("key_refused", tostring(err))
end

function K:start(id)
	self.rebinding, self.msg = id, nil
end

function K:stop()
	self.rebinding = nil
end

local function down(name)
	local k = ui.Key[name]
	return k ~= nil and ui.key_down(k)
end

local function pressed(name)
	local k = ui.Key[name]
	return k ~= nil and ui.key_pressed(k, false)
end
K.pressed = pressed

-- While an action is being rebound (menu open): the first key pressed with a modifier wins.
function K:poll()
	local t = self.t
	if pressed("Escape") then
		self.rebinding, self.msg, self.msg_ok = nil, t("key_cancelled"), true
		return
	end
	for _, k in ipairs(CAPTURE) do
		if pressed(k[1]) then
			local ctrl = down("LeftCtrl") or down("RightCtrl")
			local shift = down("LeftShift") or down("RightShift")
			local alt = down("LeftAlt") or down("RightAlt")
			if not (ctrl or shift or alt or k.fkey) then
				self.msg, self.msg_ok = t("key_need_mod"), false
				return
			end
			local spec = (ctrl and "Ctrl+" or "") .. (shift and "Shift+" or "") .. (alt and "Alt+" or "") .. k[2]
			local id = self.rebinding
			self.rebinding = nil
			local ok, err = self:rebind(id, spec)
			self.msg, self.msg_ok = ok and t("key_saved", spec) or err, ok
			return
		end
	end
end

function K:restore_default(id)
	local ok, err = self:rebind(id, self.defaults[id])
	self.msg, self.msg_ok = ok and self.t("key_restored") or err, ok
end

return K
