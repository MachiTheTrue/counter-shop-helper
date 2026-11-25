"""SmartCounter 8.1: enemy composition forecast, item order and counter-picks.

Usage:
    from predictor import Predictor
    p = Predictor()                         # loads champions_data.json next to this file
    r = p.predict("Lian", ["Fernando", "Makoa", "Grohk"], phase="early")
    print(p.format_report(r))

CLI:
    python predictor.py Lian Fernando Makoa Grohk --phase mid
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA_PATH = os.path.join(HERE, "champions_data.json")

PHASES = ("early", "mid", "late")
MAX_ENEMIES = 5

# Game modes (estimated weighting, to tune): multiplier on each enemy's contribution to an archetype.
# None = no mode = previous behaviour, unchanged.
MODES = {
    "siege": "Siège",
    "onslaught": "Onslaught",
    "tdm": "Team Deathmatch",
    "ranked": "Classé (Siège)",
    "range": "Entraînement",
}
MODE_ARCHETYPE_FACTOR = {
    "siege": {"shield_heavy": 1.1, "deployable_heavy": 1.1},
    "ranked": {"shield_heavy": 1.1, "deployable_heavy": 1.1},
    "onslaught": {"area_damage": 1.15, "sustain_scaling": 1.1},
    "tdm": {"dive_flank": 1.15, "sustain_scaling": 1.15, "shield_heavy": 0.9, "deployable_heavy": 0.9},
    "range": {},
}
# Automatic phase from the match clock (seconds): < 240 s early, < 540 s mid, then late.
PHASE_BY_ELAPSED = ((240, "early"), (540, "mid"))


def phase_for_elapsed(seconds):
    for limit, phase in PHASE_BY_ELAPSED:
        if seconds < limit:
            return phase
    return "late"

# ---------------------------------------------------------------- composition archetypes
# Per enemy, contribution = min(1, sum of tag weights + role weight).
# Archetype probability = 1 - prod(1 - contribution): one strong enemy is enough to signal it,
# several of them push it toward 100%.
ARCHETYPES = {
    "shield_heavy": {
        "label": "Shield-Heavy / Wrecker Value",
        "tags": {"shields": 0.75},
        "items": {"Wrecker": 1.0},
    },
    "deployable_heavy": {
        "label": "Deployable-Heavy / Bulldozer Value",
        "tags": {"deployables": 0.7},
        "items": {"Bulldozer": 1.0},
    },
    "high_cc": {
        "label": "High-CC / Resilience Value",
        "tags": {"heavy_cc": 0.6, "slows": 0.35},
        "items": {"Resilience": 1.0},
    },
    "dive_flank": {
        "label": "Dive / Flank Pressure",
        "tags": {"high_mobility": 0.3, "burst": 0.25, "stealth": 0.2},
        "roles": {"Flank": 0.25},
        "items": {"Haven": 0.6, "Nimble": 0.3, "Sentinel": 0.5, "Bloodbath": 0.2},
    },
    # 0.5: no anti-heal in the 8.1 shop: answer sustain with burst damage after a pick.
    "sustain_scaling": {
        "label": "Sustained Sustain / Late Scaling",
        "tags": {"sustained_heal": 0.55, "poke_sustain": 0.3},
        "roles": {"Support": 0.15},
        "items": {"Trigger Scent": 0.6, "Deft Hands": 0.3},
    },
    "stealth": {
        "label": "Stealth / Ambush",
        "tags": {"stealth": 0.8},
        "items": {"Haven": 0.6},
    },
    "area_damage": {
        "label": "Area Damage / Blasters",
        "tags": {"blaster": 0.55},
        "items": {"Blast Shields": 1.0},
    },
    "direct_damage": {
        "label": "Hitscan / Direct Damage",
        "tags": {"hitscan": 0.45, "burst": 0.15},
        "items": {"Haven": 0.8},
    },
}

# ---------------------------------------------------------------- item weighting
# How useful an item is for the player's own role (multiplier on the total score).
ROLE_ITEM_FACTOR = {
    "Frontline": {"Wrecker": 0.8, "Bulldozer": 0.8, "Trigger Scent": 0.7, "Sentinel": 0.8, "Haven": 1.15,
                  "Blast Shields": 1.15, "Resilience": 1.15, "Nimble": 0.8, "Lethality": 0.6},
    "Damage": {"Wrecker": 1.2, "Bulldozer": 1.2, "Trigger Scent": 1.15, "Sentinel": 1.1, "Haven": 0.95,
               "Blast Shields": 0.95, "Resilience": 1.0, "Nimble": 0.9, "Guardian": 0.3},
    "Flank": {"Wrecker": 0.75, "Bulldozer": 0.9, "Trigger Scent": 1.1, "Sentinel": 1.3, "Haven": 1.0,
              "Blast Shields": 0.9, "Resilience": 1.1, "Nimble": 1.15, "Guardian": 0.3},
    # 0.3: Haven/Blast Shields/Resilience lowered (1.1/1.1/1.2 before), they made a Support stack
    # tank defenses. Resilience stays above 1 to keep answering hooks and stuns (Makoa, Khan...).
    "Support": {"Wrecker": 0.6, "Bulldozer": 0.85, "Trigger Scent": 0.8, "Sentinel": 0.7, "Haven": 0.95,
                "Blast Shields": 0.95, "Resilience": 1.1, "Nimble": 1.0, "Lethality": 0.6},
}
# Blend between early_game_priority and weight, per phase.
PHASE_BLEND = {"early": 0.65, "mid": 0.3, "late": 0.0}   # share given to early_game_priority
# Economy items pay off early (Hoard), kill-snowball items later.
PHASE_ITEM_FACTOR = {
    "early": {"Sentinel": 0.85, "Hoard": 1.3, "Trigger Scent": 0.85},
    "mid": {"Sentinel": 1.1, "Hoard": 0.9},
    "late": {"Hoard": 0.5, "Trigger Scent": 1.1},
}
ARCHETYPE_SCALE = 12.0   # archetype probability (0..1) x link x this = points

# ---------------------------------------------------------------- counter-picks
# Which tags/roles answer which archetype (bonus for a candidate champion).
COUNTERS = {
    "shield_heavy": {"tags": {"blaster": 0.6, "high_mobility": 0.4, "burst": 0.3},
                     "why": "contourner ou exploser les boucliers (zone, mobilité)"},
    "deployable_heavy": {"tags": {"blaster": 0.6, "burst": 0.4},
                         "why": "dégâts de zone pour nettoyer déployables et illusions"},
    "high_cc": {"tags": {"high_mobility": 0.5, "sustained_heal": 0.2},
                "why": "mobilité pour esquiver les contrôles"},
    "dive_flank": {"tags": {"heavy_cc": 0.6, "burst": 0.3, "shields": 0.3},
                   "why": "contrôles et burst pour punir les plongeurs"},
    "sustain_scaling": {"tags": {"burst": 0.6, "hitscan": 0.3},
                        "why": "burst pour tuer avant les soins"},
    "stealth": {"tags": {"blaster": 0.4, "heavy_cc": 0.3},
                "why": "zone et contrôles pour révéler/punir la furtivité"},
    "area_damage": {"tags": {"high_mobility": 0.5, "hitscan": 0.3},
                    "why": "mobilité et longue portée face aux blasters"},
    "direct_damage": {"tags": {"shields": 0.6, "high_mobility": 0.3},
                      "why": "boucliers et mobilité face aux dégâts directs"},
}
TIER_BONUS = {"S+": 0.3, "S": 0.22, "A": 0.14, "B": 0.06, "C": 0.0, "D": -0.06}

# ---------------------------------------------------------------- shop (8.1) and playstyles
# The 8.1 shop: 20 items in 4 categories; 0.5: several items of the same category are allowed.
ITEM_CATEGORIES = ("Defense", "Utility", "Healing", "Weapon")
BUILD_SLOTS = 5          # always 5 recommendations
CORE_SLOTS = 4           # 0.6: Paladins holds 4 items -> 4 core slots + the 5th is optional (flex)
PRIMARY_SHARE = 0.4      # score >= 40 % of the best = primary item, otherwise flex (optional)
PRIMARY_MIN = 8.0        # ... or at least this many points (one dominant item must not flex the rest)
SYNERGY_SCALE = 2.0      # SYNERGY points x owned rank x this
CORE_SELF = 6           # own-kit value >= this = core item of the style, always primary
CATEGORY_DECAY = 0.7     # each item already picked in a category scales the next one of it
# Fallback order for flex slots when nothing else scores (generic value, best first).
FLEX_ORDER = ("Chronos", "Nimble", "Veteran", "Haven", "Life Rip", "Morale Boost", "Resilience",
              "Deft Hands", "Meditation", "Blast Shields")
# Synergy with items the player already owns: points per owned rank given to an unowned item.
SYNERGY = {
    "Life Rip": {"Deft Hands": 1.5, "Bloodbath": 1.0},
    "Deft Hands": {"Life Rip": 1.5, "Trigger Scent": 1.0},
    "Trigger Scent": {"Lethality": 1.0, "Bloodbath": 1.0, "Deft Hands": 1.0},
    "Lethality": {"Bloodbath": 1.5, "Sentinel": 1.0, "Trigger Scent": 1.0},
    "Bloodbath": {"Sentinel": 1.0, "Lethality": 1.0},
    "Sentinel": {"Bloodbath": 1.0, "Lethality": 1.0},
    "Guardian": {"Chronos": 1.5, "Veteran": 0.5},
    "Chronos": {"Morale Boost": 1.0},
    "Morale Boost": {"Chronos": 1.0},
    "Rejuvenate": {"Chronos": 1.5, "Morale Boost": 1.0},
    "Veteran": {"Meditation": 1.0, "Haven": 1.0},
    "Meditation": {"Veteran": 1.0},
    "Hoard": {"Chronos": 0.5},
    "Nimble": {"Lethality": 1.0, "Cavalier": 0.5},
    "Cavalier": {"Nimble": 0.5},
    "Haven": {"Veteran": 1.0, "Blast Shields": 0.5},
    "Blast Shields": {"Veteran": 1.0, "Haven": 0.5},
    "Resilience": {"Veteran": 0.5},
    "Wrecker": {"Deft Hands": 1.0},
    "Bulldozer": {"Deft Hands": 1.0},
}
# Own-kit value of an item for a playstyle (points, same scale as counter points), added after the
# role/phase factors. Without it the engine only knew counter items: a Support got three defenses.
STYLES = {
    "tank": {"Veteran": 6, "Chronos": 4, "Morale Boost": 3, "Bloodbath": 3, "Life Rip": 2, "Nimble": 1,
             "Cavalier": 1},
    "dps": {"Deft Hands": 4, "Life Rip": 4, "Trigger Scent": 4, "Bloodbath": 3, "Chronos": 3,
            "Morale Boost": 3, "Lethality": 2, "Nimble": 2},
    "flank": {"Bloodbath": 6, "Lethality": 4, "Nimble": 4, "Chronos": 4, "Life Rip": 3, "Deft Hands": 3,
              "Trigger Scent": 3},
    "heal": {"Rejuvenate": 9, "Chronos": 6, "Morale Boost": 4, "Meditation": 3, "Nimble": 3, "Veteran": 3,
             "Hoard": 2, "Deft Hands": 1},
    "aggro": {"Life Rip": 6, "Chronos": 5, "Bloodbath": 5, "Deft Hands": 4, "Trigger Scent": 3, "Nimble": 3,
              "Rejuvenate": 3},
}
# Multiplier on the counter part of an item for a playstyle: a healer rarely gets eliminations,
# so kill-based items (Sentinel, Bloodbath, Lethality, Trigger Scent) are worth less to them.
STYLE_ITEM_FACTOR = {
    "heal": {"Sentinel": 0.5, "Bloodbath": 0.6, "Lethality": 0.5, "Trigger Scent": 0.6},
    "aggro": {},
    "tank": {},
    "dps": {},
    "flank": {},
}
STYLE_LABELS = {"tank": "tank", "dps": "dégâts", "flank": "flank", "heal": "soin", "aggro": "agressif"}
# Playstyles offered per role; the first one is the default. Supports can flex heal / aggro (Io, Jenos...).
ROLE_STYLES = {"Frontline": ("tank",), "Damage": ("dps",), "Flank": ("flank",), "Support": ("heal", "aggro")}
# Per-champion own-kit tweaks (estimated): cooldown- or mobility-heavy kits.
CHAMP_SELF_BONUS = {
    "Io": {"Chronos": 1, "Nimble": 1},
    "Jenos": {"Chronos": 1},
    "Seris": {"Chronos": 1},
    "Grohk": {"Chronos": 1},
}
# Threat ranking: tags shown first, and how much each adds to an enemy's danger.
TAG_PRIORITY = ("heavy_cc", "shields", "burst", "stealth", "high_mobility", "sustained_heal", "blaster",
                "deployables", "hitscan", "slows", "poke_sustain")
TAG_DANGER = {"heavy_cc": 2.0, "burst": 1.5, "high_mobility": 1.0, "stealth": 1.0, "shields": 1.0,
              "sustained_heal": 1.0}
# Which ability effects (extract_loc.FX_*) back a threat tag, best first: the overlay shows the
# champion's own ability ("Ancre de drague : étourdit") instead of a generic word.
TAG_FX = {
    "heavy_cc": ("stun", "pull", "knockback", "polymorph", "fear", "silence", "banish", "root", "disarm"),
    "slows": ("slow", "cripple"),
    "shields": ("shield",),
    "stealth": ("stealth",),
    "sustained_heal": ("heal",),
    "poke_sustain": ("heal",),
    "high_mobility": ("mobility",),
    "deployables": ("deploy",),
}
# Tags without an effect: shown with this ability slot (burst = ultimate, others = weapon).
TAG_SLOT = {"burst": "ult", "hitscan": "weapon", "blaster": "weapon"}


class PredictorError(ValueError):
    pass


def load_data(path=DATA_PATH):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def validate_data(data):
    """Returns a list of problems (empty = valid)."""
    errs = []
    meta = data.get("meta", {})
    tags = set(meta.get("tags", []))
    roles = set(meta.get("roles", []))
    tiers = set(meta.get("tiers", []))
    items = data.get("items", {})
    if not tags or not roles or not tiers:
        errs.append("meta.tags/roles/tiers manquants")
    for name in ("Resilience", "Wrecker", "Bulldozer", "Sentinel", "Haven"):
        if name not in items:
            errs.append(f"objet obligatoire absent : {name}")
    seen = set()
    for c in data.get("champions", []):
        n = c.get("name")
        if not n:
            errs.append("champion sans nom")
            continue
        if n.lower() in seen:
            errs.append(f"doublon : {n}")
        seen.add(n.lower())
        if c.get("role") not in roles:
            errs.append(f"{n}: rôle invalide {c.get('role')}")
        if c.get("meta_tier_8_1") not in tiers:
            errs.append(f"{n}: tier invalide {c.get('meta_tier_8_1')}")
        for t in c.get("tags", []):
            if t not in tags:
                errs.append(f"{n}: tag inconnu {t}")
        if not isinstance(c.get("8_1_notes"), list) or not c["8_1_notes"]:
            errs.append(f"{n}: 8_1_notes vide")
        if c.get("wrecker_effective") != (c.get("shield_kind") == "standard"):
            errs.append(f"{n}: wrecker_effective incohérent avec shield_kind")
        recs = c.get("recommended_items_against")
        if not recs:
            errs.append(f"{n}: recommended_items_against vide")
        for r in recs or []:
            if r.get("item") not in items:
                errs.append(f"{n}: objet inconnu {r.get('item')}")
            for k in ("weight", "early_game_priority"):
                v = r.get(k)
                if not isinstance(v, int) or not 1 <= v <= 10:
                    errs.append(f"{n}: {r.get('item')}.{k} hors 1-10 ({v})")
            if not r.get("reason"):
                errs.append(f"{n}: {r.get('item')} sans reason")
    for role in roles:
        if not any(c.get("role") == role for c in data.get("champions", [])):
            errs.append(f"aucun champion pour le rôle {role}")
    pawns, bots = {}, {}
    for c in data.get("champions", []):
        pc, bid = c.get("pawn_class"), c.get("bot_id")
        if not pc or not isinstance(bid, int):
            errs.append(f"{c.get('name')}: pawn_class/bot_id manquant")
            continue
        if pc in pawns:
            errs.append(f"pawn_class en double : {pc} ({pawns[pc]}, {c['name']})")
        if bid in bots:
            errs.append(f"bot_id en double : {bid}")
        pawns[pc], bots[bid] = c["name"], c["name"]
    return errs


class Predictor:
    def __init__(self, data=None, path=DATA_PATH):
        self.data = data if data is not None else load_data(path)
        errs = validate_data(self.data)
        if errs:
            raise PredictorError("champions_data.json invalide :\n  " + "\n  ".join(errs))
        self.items = self.data["items"]
        self.champs = {c["name"].lower(): c for c in self.data["champions"]}
        # tolerant lookups: "BombKing", "bomb-king", "maldamba"
        self.alias = {}
        for c in self.data["champions"]:
            self.alias[self._key(c["name"])] = c

    @staticmethod
    def _key(s):
        return "".join(ch for ch in s.lower() if ch.isalnum())

    def champion(self, name):
        c = self.champs.get(name.lower()) or self.alias.get(self._key(name))
        if not c:
            raise PredictorError(f"champion inconnu : {name!r}")
        return c

    # ---------------------------------------------------------------- forecast
    @staticmethod
    def _contribution(champ, arch):
        t = set(champ["tags"])
        v = sum(w for tag, w in arch.get("tags", {}).items() if tag in t)
        v += arch.get("roles", {}).get(champ["role"], 0.0)
        return min(1.0, v)

    def forecast(self, enemies, mode=None):
        out = []
        mode_f = MODE_ARCHETYPE_FACTOR.get(mode, {}) if mode else {}
        for key, arch in ARCHETYPES.items():
            contribs = []
            for e in enemies:
                c = self._contribution(e, arch)
                if key == "shield_heavy" and not e["wrecker_effective"]:
                    c = 0.0           # Atlas / Inara / Azaan: no Wrecker value
                if key in ("shield_heavy", "deployable_heavy") and c > 0:
                    # scale by how much the shield/deployable matters (its item weight, 9 = full)
                    item = "Wrecker" if key == "shield_heavy" else "Bulldozer"
                    w = max([r["weight"] for r in e["recommended_items_against"] if r["item"] == item] or [0])
                    c *= min(1.0, w / 9.0)
                if c > 0 and key in mode_f:
                    c = min(1.0, c * mode_f[key])
                if c > 0:
                    contribs.append((e["name"], round(c, 2)))
            miss = 1.0
            for _, c in contribs:
                miss *= (1.0 - c)
            prob = 1.0 - miss
            out.append({"key": key, "label": arch["label"], "probability": round(prob * 100),
                        "drivers": [n for n, _ in sorted(contribs, key=lambda x: -x[1])]})
        out.sort(key=lambda a: -a["probability"])
        return out

    # ---------------------------------------------------------------- items
    @staticmethod
    def self_values(player, style):
        """Own-kit value per item for this champion and playstyle (insertion order = tie order)."""
        out = dict(STYLES[style])
        for item, v in CHAMP_SELF_BONUS.get(player["name"], {}).items():
            out[item] = out.get(item, 0) + v
        if "shields" in player["tags"]:
            out["Guardian"] = out.get("Guardian", 0) + 5     # +20/40/60 % on the champion's own shields
        return out

    def rank_items(self, player, enemies, forecast, phase, style=None):
        style = style or ROLE_STYLES[player["role"]][0]
        blend = PHASE_BLEND[phase]
        totals, reasons = {}, {}
        n = max(1, len(enemies))
        for e in enemies:
            for r in e["recommended_items_against"]:
                item = r["item"]
                pts = (1 - blend) * r["weight"] + blend * r["early_game_priority"]
                if item == "Wrecker" and not e["wrecker_effective"]:
                    pts = 0.0
                totals[item] = totals.get(item, 0.0) + pts / n * 2.0
                if pts >= 4:
                    reasons.setdefault(item, []).append(f"{e['name']}: {r['reason']}")
        for a in forecast:
            p = a["probability"] / 100.0
            for item, link in ARCHETYPES[a["key"]]["items"].items():
                totals[item] = totals.get(item, 0.0) + p * link * ARCHETYPE_SCALE
        # Sentinel: snowball/duel value grows with the number of squishy targets
        squishy = sum(1 for e in enemies if e["base_health_8_1"] <= 2200)
        if squishy:
            totals["Sentinel"] = totals.get("Sentinel", 0.0) + squishy / n * 3.0
            reasons.setdefault("Sentinel", []).append(f"{squishy} cible(s) fragile(s) (≤ 2200 PV) : valeur de snowball")
        selfv = self.self_values(player, style)
        for item in selfv:
            totals.setdefault(item, 0.0)
        role_f = ROLE_ITEM_FACTOR[player["role"]]
        phase_f = PHASE_ITEM_FACTOR[phase]
        style_f = STYLE_ITEM_FACTOR[style]
        ranked = []
        for item, base in totals.items():
            own = selfv.get(item, 0)
            score = base * role_f.get(item, 1.0) * phase_f.get(item, 1.0) * style_f.get(item, 1.0) + own
            if score <= 0.5:
                continue
            why = self._explain(item, reasons.get(item, []), forecast, phase)
            if own > 0:
                why = f"style {STYLE_LABELS[style]} (+{own})" + ("" if why == "valeur générale" else " ; " + why)
            ranked.append({"item": item, "score": round(score, 1), "own": own,
                           "category": self.items.get(item, {}).get("category"),
                           "cost_per_level": self.items.get(item, {}).get("cost_per_level"),
                           "why": why})
        ranked.sort(key=lambda x: -x["score"])
        top = ranked[0]["score"] if ranked else 1
        for i, r in enumerate(ranked, 1):
            r["order"] = i if i <= 3 else "4+"
            r["suggested_level"] = self.level_for(r["score"], top)
        return ranked

    @staticmethod
    def level_for(score, top):
        return 3 if score >= 0.75 * top else (2 if score >= 0.45 * top else 1)

    def _explain(self, item, reasons, forecast, phase):
        arch = [a for a in forecast if item in ARCHETYPES[a["key"]]["items"] and a["probability"] >= 30]
        parts = []
        if arch:
            parts.append(f"{arch[0]['label']} à {arch[0]['probability']} %")
        if reasons:
            parts.append(reasons[0])
        if item == "Wrecker":
            parts.append("n'affecte pas Inara Impasse / Azaan Wall ni Atlas")
        if item == "Resilience":
            parts.append("-25/50/75 % de durée des contrôles et ralentissements")
        if item == "Bulldozer":
            parts.append("+50/100/150 % contre déployables, familiers et illusions")
        if item == "Sentinel":
            parts.append("bouclier de 200 PV pendant 5 s sur élimination")
        return " ; ".join(parts) or "valeur générale"

    # ---------------------------------------------------------------- counter-picks
    def counter_picks(self, player, enemies, forecast, top_n=5):
        threats = {a["key"]: a["probability"] / 100.0 for a in forecast}
        roles_present = {e["role"] for e in enemies}
        holes = []
        if len(enemies) >= 3:
            for role in ("Frontline", "Support"):
                if role not in roles_present:
                    holes.append(role)
        taken = {e["name"] for e in enemies} | {player["name"]}
        cands = []
        for c in self.data["champions"]:
            if c["name"] in taken:
                continue
            t = set(c["tags"])
            score, why = 0.0, []
            for key, rule in COUNTERS.items():
                p = threats.get(key, 0.0)
                gain = sum(w for tag, w in rule["tags"].items() if tag in t) * p
                if gain > 0.15:
                    why.append((gain, rule["why"]))
                score += gain
            if "Frontline" in holes and (c["role"] == "Flank" or "burst" in t):
                score += 0.25
                why.append((0.25, "pas de frontline adverse : pression directe"))
            if "Support" in holes and "poke_sustain" in t:
                score += 0.2
                why.append((0.2, "pas de soigneur adverse : le poke s'accumule"))
            why = [w for _, w in sorted(why, key=lambda x: -x[0])]
            # the candidate is itself exposed to what the enemy does well
            if threats.get("high_cc", 0) > 0.6 and "high_mobility" not in t and c["role"] in ("Damage", "Support"):
                score -= 0.1
            score += TIER_BONUS.get(c["meta_tier_8_1"], 0.0)
            cands.append({"name": c["name"], "role": c["role"], "tier": c["meta_tier_8_1"],
                          "score": round(score, 2), "why": list(dict.fromkeys(why))[:2]})
        cands.sort(key=lambda x: -x["score"])
        role_score = {}
        for c in cands[:15]:
            role_score[c["role"]] = role_score.get(c["role"], 0.0) + c["score"]
        roles = sorted(role_score, key=lambda r: -role_score[r])
        return {"picks": cands[:top_n], "recommended_roles": roles[:2], "enemy_holes": holes}

    # ---------------------------------------------------------------- build (5 slots, live-adapted)
    @staticmethod
    def clean_owned(owned):
        return {k: max(0, min(3, int(v))) for k, v in (owned or {}).items() if v and int(v) > 0}

    def build(self, ranked, owned=None):
        """The 5 items to show, best first (several per category allowed).

        Owned items ({item: rank 1..3}) always keep a slot; an owned item the engine would not
        recommend is flagged `offmeta`. Free slots go to the best unowned items, scored with the
        counter score plus SYNERGY with what is owned (x owned rank), so buying off-meta re-plans
        the rest. A slot under PRIMARY_SHARE of the best score is `flex` (optional, shown in blue).
        Each slot: item, category, score, suggested_level / target, rank (0 = not bought),
        status buy | upgrade | done, kind primary | flex, offmeta, synergy, order, next, alt."""
        owned = self.clean_owned(owned)
        by_item = {r["item"]: r for r in ranked}
        top = ranked[0]["score"] if ranked else 1.0
        floor = min(PRIMARY_SHARE * top, PRIMARY_MIN)
        syn, syn_from = {}, {}
        for it, rk in owned.items():
            for other, pts in SYNERGY.get(it, {}).items():
                if other not in owned:
                    syn[other] = syn.get(other, 0.0) + pts * rk * SYNERGY_SCALE
                    syn_from.setdefault(other, []).append(it)
        pool = []
        for n, item in enumerate(self.items):
            r = by_item.get(item)
            base = r["score"] if r else 0.0
            flex_rank = FLEX_ORDER.index(item) if item in FLEX_ORDER else len(FLEX_ORDER) + n
            score = base + syn.get(item, 0.0)
            pool.append({"item": item, "category": self.items[item].get("category"),
                         "base": base, "syn": syn.get(item, 0.0), "score": round(score, 1), "flex_rank": flex_rank,
                         "core": bool(r and r.get("own", 0) >= CORE_SELF),
                         "synergy": syn_from.get(item, []) if syn.get(item) else []})
        pool.sort(key=lambda p: (-p["score"], p["flex_rank"]))
        n_slots = max(BUILD_SLOTS, len(owned))
        chosen = [dict(p, eff=p["score"]) for p in pool if p["item"] in owned]
        rest = [p for p in pool if p["item"] not in owned]
        while len(chosen) < n_slots and rest:
            # greedy: several items per category allowed, each extra one of a category decays
            # (the counter part only: synergy with owned items is not reduced)
            def eff(p):
                k = sum(1 for c in chosen if c["category"] == p["category"])
                return p["base"] * CATEGORY_DECAY ** k + p["syn"]
            best = min(rest, key=lambda p: (-eff(p), p["flex_rank"]))
            rest.remove(best)
            chosen.append(dict(best, eff=round(eff(best), 1)))
        chosen.sort(key=lambda p: (-p["eff"], p["flex_rank"]))
        # 0.6: the 4 core slots = owned items first (they hold a real slot), then the best others;
        # everything after them is optional (flex): a swap that depends on how the match goes.
        core = [p for p in chosen if p["item"] in owned][:CORE_SLOTS]
        core += [p for p in chosen if p not in core][:CORE_SLOTS - len(core)]
        core.sort(key=lambda p: (-p["eff"], p["flex_rank"]))
        chosen = core + [p for p in chosen if p not in core]
        picked = {p["item"] for p in chosen}
        out, nxt = [], None
        for i, p in enumerate(chosen, 1):
            rank = owned.get(p["item"], 0)
            primary = i <= len(core)
            target = self.level_for(p["eff"], top) if primary else 1
            if rank and not primary:
                target = rank                 # off-meta and owned: no further upgrade advised
            b = {"item": p["item"], "category": p["category"], "score": p["eff"],
                 "suggested_level": target, "target": target, "rank": rank, "order": i,
                 "kind": "primary" if primary else "flex",
                 "offmeta": bool(rank) and p["base"] < floor,
                 "synergy": p["synergy"],
                 "status": "buy" if rank == 0 else ("done" if rank >= target else "upgrade"),
                 "alt": next((q["item"] for q in pool if q["category"] == p["category"]
                              and q["item"] not in picked and q["score"] > 0), None)}
            out.append(b)
        # next purchase: the first primary to buy / upgrade, else the first flex
        for want in ("primary", "flex"):
            nxt = next((b["order"] for b in out if b["kind"] == want and b["status"] != "done"), None)
            if nxt:
                break
        for b in out:
            b["next"] = b["order"] == nxt
        return out

    # ---------------------------------------------------------------- threats (per enemy)
    @staticmethod
    def tag_ability(champ, tag):
        """Ability slot + effect backing a threat tag for this champion, or None."""
        abil = champ.get("abilities") or []
        for fx in TAG_FX.get(tag, ()):
            a = next((a for a in abil if fx in a.get("fx", [])), None)
            if a:
                return {"tag": tag, "slot": a["slot"], "fx": fx}
        slot = TAG_SLOT.get(tag)
        if slot and any(a["slot"] == slot for a in abil):
            return {"tag": tag, "slot": slot, "fx": None}
        return None

    def threats(self, enemies, build):
        in_build = {b["item"] for b in build}
        out = []
        for i, e in enumerate(enemies):
            recs = [r for r in e["recommended_items_against"]
                    if not (r["item"] == "Wrecker" and not e["wrecker_effective"]) and r["weight"] > 1]
            recs = sorted(recs, key=lambda r: -r["weight"])
            answer = next((r for r in recs if r["item"] in in_build), recs[0] if recs else None)
            tags = [t for t in TAG_PRIORITY if t in e["tags"]]
            danger = (recs[0]["weight"] if recs else 0) + sum(TAG_DANGER.get(t, 0.0) for t in tags)
            out.append({"name": e["name"], "role": e["role"], "danger": round(danger, 1), "tags": tags[:3],
                        "abilities": [a for a in (self.tag_ability(e, t) for t in tags[:3]) if a],
                        "answer": answer["item"] if answer else None,
                        "answer_in_build": bool(answer and answer["item"] in in_build),
                        "reason_key": answer.get("reason_key") if answer else None, "index": i})
        out.sort(key=lambda t: -t["danger"])
        return out

    # ---------------------------------------------------------------- main entry
    def predict(self, player_name, enemy_names, phase="mid", mode=None, style=None, owned=None):
        if phase not in PHASES:
            raise PredictorError(f"phase invalide : {phase} (early/mid/late)")
        if mode is not None and mode not in MODES:
            raise PredictorError(f"mode invalide : {mode} ({'/'.join(MODES)})")
        if not 1 <= len(enemy_names) <= MAX_ENEMIES:
            raise PredictorError("il faut entre 1 et 5 ennemis")
        player = self.champion(player_name)
        styles = ROLE_STYLES[player["role"]]
        if style is None:
            style = styles[0]
        if style not in styles:
            raise PredictorError(f"style invalide pour {player['name']} : {style} ({'/'.join(styles)})")
        enemies = [self.champion(n) for n in enemy_names]
        if len({e["name"] for e in enemies}) != len(enemies):
            raise PredictorError("un même champion ne peut pas apparaître deux fois chez l'ennemi")
        fc = self.forecast(enemies, mode)
        items = self.rank_items(player, enemies, fc, phase, style)
        build = self.build(items, owned)
        return {
            "player": {"name": player["name"], "role": player["role"]},
            "enemies": [e["name"] for e in enemies],
            "phase": phase,
            "mode": mode,
            "style": style,
            "styles": list(styles),
            "forecast": fc,
            "items": items,
            "build": build,
            "threats": self.threats(enemies, build),
            "counters": self.counter_picks(player, enemies, fc),
        }

    @staticmethod
    def format_report(r, max_items=5, min_prob=15):
        L = []
        mode = f"  |  mode : {MODES[r['mode']]}" if r.get("mode") else ""
        L.append(f"Joueur : {r['player']['name']} ({r['player']['role']}, style {STYLE_LABELS[r['style']]})"
                 f"  |  phase : {r['phase']}{mode}")
        L.append(f"Ennemis : {', '.join(r['enemies'])}")
        L.append("Build (5 objets) : " + "  >  ".join(
            f"{b['item']} niv.{b['suggested_level']} [{b['category']}]"
            + (" (option)" if b["kind"] == "flex" else "") + (" (hors méta)" if b["offmeta"] else "")
            for b in r["build"]))
        L.append("Menaces :")
        for t in r["threats"]:
            L.append(f"  {t['danger']:4.1f}  {t['name']:<10} {', '.join(t['tags']) or '-'}"
                     f"  ->  {t['answer'] or '-'}{'' if t['answer_in_build'] else ' (hors build)'}")
        L.append("Prévision de compo :")
        for a in r["forecast"]:
            if a["probability"] < min_prob:
                continue
            bar = "#" * (a["probability"] // 10)
            L.append(f"  {a['probability']:3d} % {bar:<10} {a['label']}  ({', '.join(a['drivers'][:3])})")
        L.append("Ordre d'achat :")
        for it in r["items"][:max_items]:
            L.append(f"  {str(it['order']):>2}. {it['item']:<14} score {it['score']:5.1f}  niv. {it['suggested_level']}  "
                     f"({it['cost_per_level']}/niv.) - {it['why']}")
        c = r["counters"]
        L.append(f"Rôles conseillés : {', '.join(c['recommended_roles'])}"
                 + (f"  |  trous adverses : {', '.join(c['enemy_holes'])}" if c["enemy_holes"] else ""))
        L.append("Contre-picks :")
        for p in c["picks"]:
            L.append(f"  - {p['name']} ({p['role']}, {p['tier']}) {p['score']:.2f} : {'; '.join(p['why']) or 'méta'}")
        return "\n".join(L)


def _main(argv):
    import argparse
    ap = argparse.ArgumentParser(description="SmartCounter 8.1")
    ap.add_argument("player")
    ap.add_argument("enemies", nargs="+")
    ap.add_argument("--phase", default="mid", choices=PHASES)
    ap.add_argument("--mode", default=None, choices=list(MODES))
    ap.add_argument("--style", default=None, choices=list(STYLES))
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    p = Predictor()
    r = p.predict(a.player, a.enemies, a.phase, a.mode, a.style)
    print(json.dumps(r, ensure_ascii=False, indent=2) if a.json else p.format_report(r))


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    _main(sys.argv[1:])
