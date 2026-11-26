-- Counter & Shop Helper: from what is known about the match to a prediction.
--
-- Inputs, by priority: what the player picked by hand in the Match tab, then auto-detection
-- (sc_detect), then defaults. Owned items: live reading (sc_player) when it answers, else the manual
-- ranks. The predictor only reruns when one of these inputs changes (signature).

local MT = {}
MT.__index = MT

-- cfg: sc_config values, PRED / DET / PLAYER: engine modules, log: fn
function MT.new(cfg, D, PRED, DET, PLAYER, log)
	return setmetatable({ cfg = cfg, D = D, PRED = PRED, DET = DET, PLAYER = PLAYER, log = log,
		result = nil,     -- last prediction (sc_predictor result), nil when none
		err = nil,        -- { key, arg } of sc_lang when there is no result (translated when drawn)
		inputs = nil,     -- resolved inputs of the last update
		signature = nil,
		changed_at = nil, -- os.clock() of the last change (Auto layout)
		cs_me = nil,      -- my pick seen in champion select, kept for the start of the match
	}, MT)
end

-- "match" (champion locked: in the match, or loading it), "draft" (champion select: picks still
-- possible) or "plan".
function MT:context()
	local st = self.cfg.auto_detect and self.DET.state.status
	if st == "match" or st == "loading" then return "match" end
	if st == "champ_select" then return "draft" end
	return "plan"
end

-- Owned items and where they come from: "live", "manual" or "none".
function MT:owned_items()
	local st = self.PLAYER.state
	if self.cfg.live_items and st.available then return st.owned, "live" end
	if next(self.cfg.owned) then return self.cfg.owned, "manual" end
	return {}, "none"
end

function MT:resolve(st)
	local cfg, D = self.cfg, self.D
	local me = cfg.manual.me ~= "" and cfg.manual.me or nil
	if not me and cfg.auto_detect then me = st.me or self.cs_me end
	local enemies, seen, manual_n = {}, {}, 0
	for _, n in ipairs(cfg.manual.enemies) do
		if n ~= "" and not seen[n] and #enemies < D.max_enemies then
			enemies[#enemies + 1], seen[n] = n, true
			manual_n = manual_n + 1
		end
	end
	if cfg.auto_detect then
		for _, n in ipairs(st.enemies or {}) do
			if not seen[n] and #enemies < D.max_enemies then enemies[#enemies + 1], seen[n] = n, true end
		end
	end
	local phase = cfg.phase ~= "auto" and cfg.phase or (cfg.auto_detect and st.phase) or nil
	if not phase then
		local before = st.status == "champ_select" or st.status == "lobby" or st.status == "loading"
		phase = before and "early" or "mid"
	end
	local mode = cfg.mode ~= "auto" and cfg.mode or (cfg.auto_detect and st.mode) or nil
	return { me = me, enemies = enemies, manual_n = manual_n, phase = phase, mode = mode,
		phase_auto = cfg.phase == "auto", mode_auto = cfg.mode == "auto", style = cfg.style }
end

-- Recomputes the prediction when an input changed. Cheap otherwise (one signature string).
function MT:update()
	local inputs = self:resolve(self.DET.state)
	local owned, src = self:owned_items()
	local names = {}
	for k, v in pairs(owned) do names[#names + 1] = k .. "=" .. tostring(v) end
	table.sort(names)
	inputs.owned, inputs.owned_src = owned, src
	self.inputs = inputs
	-- the enemies' max health read in the match (sc_detect), used by the predictor's squishy rule
	local live_hp, hp = self.DET.state.enemy_hp or {}, {}
	for name, v in pairs(live_hp) do hp[#hp + 1] = name .. "=" .. v end
	table.sort(hp)
	local sig = table.concat({ inputs.me or "", table.concat(inputs.enemies, ","), inputs.phase, inputs.mode or "",
		inputs.style, table.concat(names, ","), table.concat(hp, ",") }, "|")
	if sig == self.signature then return end
	self.signature, self.changed_at = sig, os.clock()
	self.PRED.live_hp = live_hp
	self.result, self.err = nil, nil
	if not inputs.me then
		self.err = { "need_champ" }
	elseif #inputs.enemies == 0 then
		self.err = { "no_enemy" }
	else
		local ok, r, code, detail = pcall(self.PRED.predict, self.PRED, inputs.me, inputs.enemies, inputs.phase,
			inputs.mode, inputs.style, owned)
		if not ok then
			self.err = { "err_internal", tostring(r) }
			self.log("predict failed: %s", tostring(r))
		elseif not r then
			self.err = { "err_" .. tostring(code), tostring(detail or "") }
		else
			self.result = r
		end
	end
end

function MT:err_text(t)
	local e = self.err
	if not e then return nil end
	return e[2] and t(e[1], e[2]) or t(e[1])
end

return MT
