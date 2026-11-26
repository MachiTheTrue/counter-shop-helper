-- Counter & Shop Helper: Lua port of engine/predictor.py.
-- Constants and data come from sc_data.lua (generated from Python): only the algorithm lives here.
-- Any change to predictor.py's logic must be mirrored here; engine/tests/run_lua_tests.ps1 checks
-- parity offline (engine/tests/expected.lua). Results hold structured keys and game ids, never text:
-- the UI translates them (sc_lang.lua for its own words, sc_text.lua for the game's names).

local M = {}
M.__index = M

local function round(x, d)
	local m = 10 ^ (d or 0)
	return math.floor(x * m + 0.5) / m
end

local function key_of(s)
	return (s:lower():gsub("[^%w]", ""))
end

function M.new(D)
	local self = setmetatable({ D = D, by_name = {}, by_key = {}, by_bot = {}, live_hp = {} }, M)
	for i, c in ipairs(D.champions) do
		c.index = i
		c.tagset = {}
		for _, t in ipairs(c.tags) do c.tagset[t] = true end
		self.by_name[c.name:lower()] = c
		self.by_key[key_of(c.name)] = c
		self.by_bot[c.bot_id] = c
	end
	for bot, name in pairs(D.extra_bot_ids or {}) do
		self.by_bot[bot] = self.by_name[name:lower()]
	end
	self.arch_by_key = {}
	for i, a in ipairs(D.archetypes) do
		a.index = i
		self.arch_by_key[a.key] = a
	end
	self.known_mode = {}
	for _, m in ipairs(D.modes) do self.known_mode[m.key] = true end
	return self
end

function M:champion(name)
	if not name or name == "" then return nil end
	return self.by_name[name:lower()] or self.by_key[key_of(name)]
end

-- Playstyles offered for a champion (first = default).
function M:styles_for(name)
	local c = self:champion(name)
	return c and self.D.role_styles[c.role] or {}
end

function M:phase_for_elapsed(seconds)
	for _, p in ipairs(self.D.phase_by_elapsed) do
		if seconds < p.limit then return p.phase end
	end
	return "late"
end

local function contribution(ch, arch)
	local v = 0
	for tag, w in pairs(arch.tags or {}) do
		if ch.tagset[tag] then v = v + w end
	end
	v = v + ((arch.roles or {})[ch.role] or 0)
	return math.min(1, v)
end

local function max_weight(e, item)
	local w = 0
	for _, r in ipairs(e.recs) do
		if r.item == item and r.weight > w then w = r.weight end
	end
	return w
end

function M:forecast(enemies, mode)
	local out = {}
	local mode_f = (mode and self.D.mode_factor[mode]) or {}
	for _, arch in ipairs(self.D.archetypes) do
		local contribs = {}
		for ei, e in ipairs(enemies) do
			local c = contribution(e, arch)
			if arch.key == "shield_heavy" and not e.wrecker_effective then c = 0 end
			if (arch.key == "shield_heavy" or arch.key == "deployable_heavy") and c > 0 then
				local item = arch.key == "shield_heavy" and "Wrecker" or "Bulldozer"
				c = c * math.min(1, max_weight(e, item) / 9)
			end
			if c > 0 and mode_f[arch.key] then c = math.min(1, c * mode_f[arch.key]) end
			if c > 0 then contribs[#contribs + 1] = { name = e.name, c = round(c, 2), i = ei } end
		end
		local miss = 1
		for _, x in ipairs(contribs) do miss = miss * (1 - x.c) end
		table.sort(contribs, function(a, b)
			if a.c ~= b.c then return a.c > b.c end
			return a.i < b.i
		end)
		local drivers = {}
		for _, x in ipairs(contribs) do drivers[#drivers + 1] = x.name end
		out[#out + 1] = { key = arch.key, probability = round((1 - miss) * 100),
			drivers = drivers, index = arch.index }
	end
	table.sort(out, function(a, b)
		if a.probability ~= b.probability then return a.probability > b.probability end
		return a.index < b.index
	end)
	return out
end

-- Own-kit value per item (ordered list, same insertion order as Python).
function M:self_values(player, style)
	local list, pos = {}, {}
	for _, e in ipairs(self.D.styles[style] or {}) do
		list[#list + 1] = { item = e.item, v = e.v }
		pos[e.item] = #list
	end
	local function add(item, v)
		if pos[item] then
			list[pos[item]].v = list[pos[item]].v + v
		else
			list[#list + 1] = { item = item, v = v }
			pos[item] = #list
		end
	end
	for _, e in ipairs(self.D.champ_self_bonus[player.name] or {}) do add(e.item, e.v) end
	if player.tagset.shields then add("Guardian", 5) end   -- +20/40/60 % on the champion's own shields
	return list
end

-- why = { arch = {key, probability} | nil, reason = {enemy, key, args} | nil, own = n, style = s }
local function explain(self, item, reasons, forecast)
	local why = {}
	for _, a in ipairs(forecast) do
		if a.probability >= 30 and (self.arch_by_key[a.key].items or {})[item] then
			why.arch = { key = a.key, probability = a.probability }
			break
		end
	end
	if reasons and reasons[1] then why.reason = reasons[1] end
	return why
end

function M:rank_items(player, enemies, forecast, phase, style)
	local D = self.D
	style = style or D.role_styles[player.role][1]
	local blend = D.phase_blend[phase]
	local totals, reasons, first = {}, {}, {}
	local order = 0
	local function add(item, v)
		if totals[item] == nil then
			order = order + 1
			first[item] = order
			totals[item] = 0
		end
		totals[item] = totals[item] + v
	end
	local n = math.max(1, #enemies)
	for _, e in ipairs(enemies) do
		for _, r in ipairs(e.recs) do
			local pts = (1 - blend) * r.weight + blend * r.early
			if r.item == "Wrecker" and not e.wrecker_effective then pts = 0 end
			add(r.item, pts / n * 2)
			if pts >= 4 then
				reasons[r.item] = reasons[r.item] or {}
				table.insert(reasons[r.item], { enemy = e.name, key = r.key })
			end
		end
	end
	for _, a in ipairs(forecast) do
		local p = a.probability / 100
		for item, link in pairs(self.arch_by_key[a.key].items or {}) do
			add(item, p * link * D.archetype_scale)
		end
	end
	-- squishy: live max health at most D.squishy_hp (TgRepInfo_Player.r_nHealthMaximum, cards included).
	-- The mod ships no champion health: an enemy without a live value (picked by hand) is not counted.
	local squishy = 0
	for _, e in ipairs(enemies) do
		local hp = self.live_hp[e.name]
		if hp and hp <= D.squishy_hp then squishy = squishy + 1 end
	end
	if squishy > 0 then
		add("Sentinel", squishy / n * 3)
		reasons.Sentinel = reasons.Sentinel or {}
		table.insert(reasons.Sentinel, { key = "squishy", args = tostring(squishy) })
	end
	local own = {}
	for _, e in ipairs(self:self_values(player, style)) do
		own[e.item] = e.v
		add(e.item, 0)
	end
	local role_f = D.role_item_factor[player.role] or {}
	local phase_f = D.phase_item_factor[phase] or {}
	local style_f = D.style_item_factor[style] or {}
	local ranked = {}
	for item, base in pairs(totals) do
		local o = own[item] or 0
		local score = base * (role_f[item] or 1) * (phase_f[item] or 1) * (style_f[item] or 1) + o
		if score > 0.5 then
			local why = explain(self, item, reasons[item], forecast)
			why.own, why.style = o, style
			ranked[#ranked + 1] = { item = item, score = round(score, 1), first = first[item], own = o,
				category = (D.items[item] or {}).category, why = why }
		end
	end
	table.sort(ranked, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return a.first < b.first
	end)
	local top = ranked[1] and ranked[1].score or 1
	for i, r in ipairs(ranked) do
		r.order = i <= 3 and tostring(i) or "4+"
		r.suggested_level = math.min(M.level_for(r.score, top), D.max_rank)
	end
	return ranked
end

function M.level_for(score, top)
	return (score >= 0.75 * top and 3) or (score >= 0.45 * top and 2) or 1
end

function M.clean_owned(D, owned)
	local own = {}
	for k, v in pairs(owned or {}) do
		local r = math.floor(tonumber(v) or 0)
		if r > 0 and D.items[k] then own[k] = math.min(D.max_rank, r) end
	end
	return own
end

-- Mirror of predictor.py build(): the 5 items to show, best first, several per category allowed.
-- Owned items always keep a slot (`offmeta` when the engine would not recommend them); free slots
-- go to the best unowned items, counter score (decayed per extra item of a category) + synergy with
-- what is owned. Under the primary floor = `flex` (optional, blue). Slot fields: item, category,
-- score, suggested_level / target, rank, status buy|upgrade|done, kind primary|flex, offmeta,
-- blocked (not owned while the game's 4 item slots are full), synergy (owned items it pairs with),
-- order, next (never a blocked slot), alt, why.
function M:build(ranked, owned)
	local D = self.D
	local own = M.clean_owned(D, owned)
	local by_item = {}
	for _, r in ipairs(ranked) do by_item[r.item] = r end
	local top = ranked[1] and ranked[1].score or 1
	local floor = math.min(D.primary_share * top, D.primary_min)
	local flex_pos = {}
	for i, it in ipairs(D.flex_order) do flex_pos[it] = i - 1 end
	local syn, syn_from = {}, {}
	for _, it in ipairs(D.item_order) do        -- shop order: deterministic synergy lists
		local rk = own[it]
		if rk then
			for other, pts in pairs(D.synergy[it] or {}) do
				if not own[other] then
					syn[other] = (syn[other] or 0) + pts * rk * D.synergy_scale
					syn_from[other] = syn_from[other] or {}
					table.insert(syn_from[other], it)
				end
			end
		end
	end
	local pool = {}
	for n, item in ipairs(D.item_order) do
		local r = by_item[item]
		local base = r and r.score or 0
		local s = syn[item] or 0
		pool[#pool + 1] = { item = item, category = D.items[item].category, base = base, syn = s,
			score = round(base + s, 1), flex_rank = flex_pos[item] or (#D.flex_order + n - 1),
			core = r ~= nil and (r.own or 0) >= D.core_self, synergy = s > 0 and syn_from[item] or {},
			why = r and r.why }
	end
	local function cmp(a, b)
		if a.k ~= b.k then return a.k > b.k end
		return a.p.flex_rank < b.p.flex_rank
	end
	local function sort_by(list, key)
		local tmp = {}
		for i, p in ipairs(list) do tmp[i] = { p = p, k = key(p) } end
		table.sort(tmp, cmp)
		for i, x in ipairs(tmp) do list[i] = x.p end
	end
	sort_by(pool, function(p) return p.score end)
	local n_slots = D.build_slots
	local n_own = 0
	for _ in pairs(own) do n_own = n_own + 1 end
	if n_own > n_slots then n_slots = n_own end
	local chosen, rest = {}, {}
	for _, p in ipairs(pool) do
		if own[p.item] then
			p.eff = p.score
			chosen[#chosen + 1] = p
		else
			rest[#rest + 1] = p
		end
	end
	local function eff(p)
		local k = 0
		for _, c in ipairs(chosen) do
			if c.category == p.category then k = k + 1 end
		end
		return p.base * D.category_decay ^ k + p.syn
	end
	while #chosen < n_slots and #rest > 0 do
		local bi, bk
		for i, p in ipairs(rest) do
			local k = eff(p)
			if not bi or k > bk or (k == bk and p.flex_rank < rest[bi].flex_rank) then bi, bk = i, k end
		end
		local best = table.remove(rest, bi)
		best.eff = round(bk, 1)
		chosen[#chosen + 1] = best
	end
	sort_by(chosen, function(p) return p.eff end)
	-- core slots (D.core_slots, 4) = owned items first, then the best others; the rest is optional (flex)
	local core_n, core, in_core = D.core_slots or 4, {}, {}
	for _, p in ipairs(chosen) do
		if own[p.item] and #core < core_n then core[#core + 1], in_core[p] = p, true end
	end
	for _, p in ipairs(chosen) do
		if not in_core[p] and #core < core_n then core[#core + 1], in_core[p] = p, true end
	end
	sort_by(core, function(p) return p.eff end)
	local ordered = {}
	for _, p in ipairs(core) do ordered[#ordered + 1] = p end
	for _, p in ipairs(chosen) do
		if not in_core[p] then ordered[#ordered + 1] = p end
	end
	chosen = ordered
	local picked = {}
	for _, p in ipairs(chosen) do picked[p.item] = true end
	local full = n_own >= core_n   -- every item slot of the game is taken
	local out = {}
	for i, p in ipairs(chosen) do
		local rank = own[p.item] or 0
		local primary = i <= #core
		local target = primary and math.min(M.level_for(p.eff, top), D.max_rank) or 1
		if rank > 0 and not primary then target = rank end
		local alt
		for _, q in ipairs(pool) do
			if q.category == p.category and not picked[q.item] and q.score > 0 then
				alt = q.item
				break
			end
		end
		out[i] = { item = p.item, category = p.category, score = p.eff, suggested_level = target, target = target,
			rank = rank, order = i, kind = primary and "primary" or "flex", offmeta = rank > 0 and p.base < floor,
			blocked = full and rank == 0, synergy = p.synergy, alt = alt, why = p.why,
			status = rank == 0 and "buy" or (rank >= target and "done" or "upgrade") }
	end
	local nxt
	for _, want in ipairs({ "primary", "flex" }) do
		for _, b in ipairs(out) do
			if b.kind == want and b.status ~= "done" and not b.blocked then
				nxt = b.order
				break
			end
		end
		if nxt then break end
	end
	for _, b in ipairs(out) do b.next = b.order == nxt end
	return out
end

-- Ability (slot + effect) backing a threat tag for this champion (mirror of predictor.tag_ability).
function M:tag_ability(champ, tag)
	local abil = champ.abilities or {}
	for _, fx in ipairs(self.D.tag_fx[tag] or {}) do
		for _, a in ipairs(abil) do
			for _, f in ipairs(a.fx or {}) do
				if f == fx then return { tag = tag, slot = a.slot, fx = fx, name_msg = a.name_msg } end
			end
		end
	end
	local slot = self.D.tag_slot[tag]
	if slot then
		for _, a in ipairs(abil) do
			if a.slot == slot then return { tag = tag, slot = slot, name_msg = a.name_msg } end
		end
	end
	return nil
end

function M:threats(enemies, build)
	local D = self.D
	local in_build = {}
	for _, b in ipairs(build) do in_build[b.item] = true end
	local out = {}
	for i, e in ipairs(enemies) do
		local recs = {}
		for ri, r in ipairs(e.recs) do
			if not (r.item == "Wrecker" and not e.wrecker_effective) and r.weight > 1 then
				recs[#recs + 1] = { r = r, i = ri }
			end
		end
		table.sort(recs, function(a, b)
			if a.r.weight ~= b.r.weight then return a.r.weight > b.r.weight end
			return a.i < b.i
		end)
		local answer = recs[1] and recs[1].r
		for _, x in ipairs(recs) do
			if in_build[x.r.item] then
				answer = x.r
				break
			end
		end
		local tags, danger = {}, recs[1] and recs[1].r.weight or 0
		for _, t in ipairs(D.tag_priority) do
			if e.tagset[t] then
				tags[#tags + 1] = t
				danger = danger + (D.tag_danger[t] or 0)
			end
		end
		while #tags > 3 do table.remove(tags) end
		local abil = {}
		for _, t in ipairs(tags) do
			local a = self:tag_ability(e, t)
			if a then abil[#abil + 1] = a end
		end
		out[#out + 1] = { name = e.name, role = e.role, danger = round(danger, 1), tags = tags, abilities = abil,
			answer = answer and answer.item, answer_in_build = answer ~= nil and in_build[answer.item] == true,
			reason_key = answer and answer.key, index = i }
	end
	table.sort(out, function(a, b)
		if a.danger ~= b.danger then return a.danger > b.danger end
		return a.index < b.index
	end)
	return out
end

function M:counter_picks(player, enemies, forecast, top_n)
	local D = self.D
	top_n = top_n or 5
	local threats = {}
	for _, a in ipairs(forecast) do threats[a.key] = a.probability / 100 end
	local present = {}
	for _, e in ipairs(enemies) do present[e.role] = true end
	local holes = {}
	if #enemies >= 3 then
		for _, role in ipairs({ "Frontline", "Support" }) do
			if not present[role] then holes[#holes + 1] = role end
		end
	end
	local hole = {}
	for _, h in ipairs(holes) do hole[h] = true end
	local taken = { [player.name] = true }
	for _, e in ipairs(enemies) do taken[e.name] = true end
	local cands = {}
	for _, c in ipairs(D.champions) do
		if not taken[c.name] then
			local t = c.tagset
			local score, why = 0, {}
			for _, rule in ipairs(D.counters) do
				local p = threats[rule.key] or 0
				local gain = 0
				for tag, w in pairs(rule.tags) do
					if t[tag] then gain = gain + w end
				end
				gain = gain * p
				if gain > 0.15 then why[#why + 1] = { g = gain, w = rule.key, i = #why + 1 } end
				score = score + gain
			end
			if hole.Frontline and (c.role == "Flank" or t.burst) then
				score = score + 0.25
				why[#why + 1] = { g = 0.25, w = "hole_frontline", i = #why + 1 }
			end
			if hole.Support and t.poke_sustain then
				score = score + 0.2
				why[#why + 1] = { g = 0.2, w = "hole_support", i = #why + 1 }
			end
			table.sort(why, function(a, b)
				if a.g ~= b.g then return a.g > b.g end
				return a.i < b.i
			end)
			if (threats.high_cc or 0) > 0.6 and not t.high_mobility and (c.role == "Damage" or c.role == "Support") then
				score = score - 0.1
			end
			score = score + (D.tier_bonus[c.tier] or 0)
			local reasons, seen = {}, {}
			for _, w in ipairs(why) do
				if not seen[w.w] and #reasons < 2 then
					seen[w.w] = true
					reasons[#reasons + 1] = w.w   -- counter key, translated by the UI
				end
			end
			cands[#cands + 1] = { name = c.name, role = c.role, tier = c.tier, score = round(score, 2),
				why = reasons, index = c.index }
		end
	end
	table.sort(cands, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return a.index < b.index
	end)
	local role_score, role_first, roles = {}, {}, {}
	for i = 1, math.min(15, #cands) do
		local c = cands[i]
		if not role_score[c.role] then
			role_first[c.role] = i
			roles[#roles + 1] = c.role
			role_score[c.role] = 0
		end
		role_score[c.role] = role_score[c.role] + c.score
	end
	table.sort(roles, function(a, b)
		if role_score[a] ~= role_score[b] then return role_score[a] > role_score[b] end
		return role_first[a] < role_first[b]
	end)
	local picks = {}
	for i = 1, math.min(top_n, #cands) do picks[i] = cands[i] end
	return { picks = picks, recommended_roles = { roles[1], roles[2] }, enemy_holes = holes }
end

-- player_name: string, enemy_names: 1..5 strings, phase: early|mid|late, mode: key or nil,
-- style: playstyle key or nil (role default). Returns result, or nil + error code + detail.
function M:predict(player_name, enemy_names, phase, mode, style, owned)
	local D = self.D
	phase = phase or "mid"
	if D.phase_blend[phase] == nil then return nil, "bad_phase", tostring(phase) end
	if mode == "" then mode = nil end
	if mode and not self.known_mode[mode] then return nil, "bad_mode", tostring(mode) end
	if #enemy_names < 1 or #enemy_names > D.max_enemies then return nil, "bad_count" end
	local player = self:champion(player_name)
	if not player then return nil, "unknown_champion", tostring(player_name) end
	local styles = D.role_styles[player.role]
	if style == "" or style == "auto" then style = nil end
	if style then
		local ok = false
		for _, s in ipairs(styles) do
			if s == style then ok = true end
		end
		if not ok then style = nil end   -- e.g. a Support style kept after switching to a Damage champion
	end
	style = style or styles[1]
	local enemies, seen = {}, {}
	for _, n in ipairs(enemy_names) do
		local e = self:champion(n)
		if not e then return nil, "unknown_champion", tostring(n) end
		if seen[e.name] then return nil, "duplicate", e.name end
		seen[e.name] = true
		enemies[#enemies + 1] = e
	end
	local fc = self:forecast(enemies, mode)
	local names = {}
	for i, e in ipairs(enemies) do names[i] = e.name end
	local items = self:rank_items(player, enemies, fc, phase, style)
	local build = self:build(items, owned)
	return {
		player = { name = player.name, role = player.role },
		enemies = names,
		phase = phase,
		mode = mode,
		style = style,
		styles = styles,
		forecast = fc,
		items = items,
		build = build,
		threats = self:threats(enemies, build),
		counters = self:counter_picks(player, enemies, fc),
	}
end

return M
