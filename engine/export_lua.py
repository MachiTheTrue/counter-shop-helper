"""Exports engine data and constants to the Lua mod (src/scripts/lib/).

Writes:
  sc_data.lua      champions, items and every constant of predictor.py (one source of truth: Python)
  sc_expected.lua  results computed by predictor.py on reference scenarios, checked in game by
                   the `smartcounter_selftest` command (Lua port vs Python engine)

    python export_lua.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import predictor as P  # noqa: E402

LIB = os.path.normpath(os.path.join(HERE, "..", "src", "scripts", "lib"))
UI_LANGS = ("en", "fr", "de", "it", "ru", "zh", "ja", "ko")   # 0.6: + IT RU ZH JA KO (fonts per script in main.lua)

SCENARIOS = [
    ("Lian", ["Fernando", "Makoa", "Grohk", "Viktor", "Androxus"], "mid", None, None),
    ("Androxus", ["Inara", "Khan", "Pip", "Mal'Damba", "Cassie"], "mid", None, None),
    ("Drogoz", ["Barik", "Ying", "Kinessa", "Skye", "Evie"], "mid", None, None),
    ("Viktor", ["Inara", "Azaan", "Atlas"], "mid", None, None),
    ("Grohk", ["Talus", "Maeve", "Koga"], "early", None, None),
    ("Tyra", ["Seris", "Rei", "Io", "Raum"], "early", None, None),
    ("Tyra", ["Seris", "Rei", "Io", "Raum"], "late", None, None),
    ("Grohk", ["Talus", "Maeve", "Koga"], "mid", "tdm", None),
    ("Fernando", ["Kinessa", "Skye", "Seris"], "late", "siege", None),
    # live 8.1 feedback (0.3): Io against Makoa / Dredge / Evie / Furia / Androxus
    ("Io", ["Makoa", "Dredge", "Evie", "Furia", "Androxus"], "mid", None, "heal"),
    ("Io", ["Makoa", "Dredge", "Evie", "Furia", "Androxus"], "mid", None, "aggro"),
    ("Io", ["Makoa", "Dredge", "Evie", "Furia", "Androxus"], "early", "siege", None),
]
# 0.4: live player state (owned items + ranks) -> slot status / next buy, same scenarios with items.
# 0.5: off-meta purchases (synergy re-plan), rank-ups (Bulldozer I -> II), more than 5 owned.
OWNED_SCENARIOS = [
    ("Io", ["Makoa", "Dredge", "Evie", "Furia", "Androxus"], "mid", None, "heal", {"Resilience": 2}),
    ("Io", ["Makoa", "Dredge", "Evie", "Furia", "Androxus"], "mid", None, "heal", {"Haven": 3, "Rejuvenate": 1}),
    ("Lian", ["Fernando", "Makoa", "Grohk", "Viktor", "Androxus"], "mid", None, None, {"Wrecker": 3}),
    ("Lian", ["Makoa", "Fernando", "Grohk", "Evie", "Strix"], "mid", None, None, {"Life Rip": 3}),
    ("Lian", ["Makoa", "Fernando", "Grohk", "Evie", "Strix"], "mid", None, None, {"Bulldozer": 1}),
    ("Lian", ["Makoa", "Fernando", "Grohk", "Evie", "Strix"], "mid", None, None, {"Bulldozer": 2, "Hoard": 1}),
    ("Io", ["Makoa", "Dredge", "Evie", "Furia", "Androxus"], "mid", None, "heal", {"Hoard": 1}),
    ("Lian", ["Makoa"], "mid", None, None,
     {"Wrecker": 1, "Haven": 1, "Nimble": 1, "Chronos": 1, "Life Rip": 1, "Veteran": 1}),
]


def icon_file(item):
    """Icon path inside the mod (src/icons/), exported by make_icons.ps1."""
    return "icons/" + "".join(ch for ch in item if ch.isalnum()) + ".png"


def ordered_values(d):
    """{item: v} -> [{item=, v=}] to keep Python's insertion order (tie-break) in Lua."""
    return [{"item": k, "v": v} for k, v in d.items()]


def lua(v, ind=0):
    pad, pad1 = "  " * ind, "  " * (ind + 1)
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        s = v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "")
        return f'"{s}"'
    if isinstance(v, (list, tuple)):
        if not v:
            return "{}"
        if all(not isinstance(x, (dict, list, tuple)) for x in v):
            return "{ " + ", ".join(lua(x) for x in v) + " }"
        return "{\n" + "".join(f"{pad1}{lua(x, ind + 1)},\n" for x in v) + pad + "}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        parts = []
        for k, x in v.items():
            key = k if isinstance(k, str) and k.isidentifier() else f"[{lua(k)}]"
            parts.append(f"{pad1}{key} = {lua(x, ind + 1)},\n")
        return "{\n" + "".join(parts) + pad + "}"
    raise TypeError(type(v))


def ordered(d, extra=None):
    """dict -> list of {key=..., ...} to keep Python's order in Lua."""
    out = []
    for k, v in d.items():
        e = {"key": k}
        e.update(v)
        out.append(e)
    return out


def build_data(data):
    champs = []
    for c in data["champions"]:
        champs.append({
            "name": c["name"], "role": c["role"], "tier": c["meta_tier_8_1"],
            "hp": c["base_health_8_1"], "pawn": c["pawn_class"], "bot_id": c["bot_id"],
            "tags": c["tags"], "wrecker_effective": c["wrecker_effective"],
            "recs": [{"item": r["item"], "weight": r["weight"], "early": r["early_game_priority"],
                      "key": r["reason_key"], "args": r["reason_args"]} for r in c["recommended_items_against"]],
        })
        if any(v != c["name"] for v in c.get("loc_name", {}).values()):
            champs[-1]["names"] = {lg: c["loc_name"].get(lg, c["name"]) for lg in UI_LANGS}  # only when a locale really differs (game data)
    # only the UI languages of sc_lang.lua (ES / PT / PL / TR have no UI table)
    langs = [lg for lg in data["meta"].get("loc", {}).get("ui_langs", ["en"]) if lg in UI_LANGS]
    for c, out in zip(data["champions"], champs):
        # abilities (game data): slot, native name per UI language, effects (stun, pull, shield...)
        out["abilities"] = [{"slot": a["slot"], "fx": a["fx"],
                             "names": {lg: a["name"].get(lg) or a["name"].get("en") for lg in langs}}
                            for a in c.get("abilities", [])]
    items = {}
    for k, v in data["items"].items():
        e = {"cost": v["cost_per_level"], "category": v["category"], "item_id": v["game_item_id"],
             "per_level": v.get("per_level"), "alias_ids": v.get("alias_item_ids", []),
             "icon": icon_file(k), "icon_index": v.get("icon_index")}
        if v.get("loc_name"):
            e["names"] = {lg: v["loc_name"].get(lg, k) for lg in langs}
            e["descs"] = {lg: v["loc_desc"].get(lg, "") for lg in langs if v["loc_desc"].get(lg)}
        if v.get("inventory_class"):
            e["inv_class"] = v["inventory_class"]
        if v.get("alias_inventory_classes"):
            e["alias_inv"] = v["alias_inventory_classes"]
        items[k] = e
    return {
        "build": data["meta"]["build"],
        "generated_by": "engine/export_lua.py (ne pas modifier à la main)",
        "champions": champs,
        "items": items,
        "item_order": list(data["items"]),     # shop order (Python dict order = tie-break in build)
        "build_slots": P.BUILD_SLOTS,
        "core_slots": P.CORE_SLOTS,
        "primary_share": P.PRIMARY_SHARE,
        "primary_min": P.PRIMARY_MIN,
        "synergy_scale": P.SYNERGY_SCALE,
        "core_self": P.CORE_SELF,
        "category_decay": P.CATEGORY_DECAY,
        "flex_order": list(P.FLEX_ORDER),
        "synergy": P.SYNERGY,
        "tag_fx": {k: list(v) for k, v in P.TAG_FX.items()},
        "tag_slot": P.TAG_SLOT,
        "extra_bot_ids": {int(k): v for k, v in data["meta"].get("extra_bot_ids", {}).items()},
        "phases": list(P.PHASES),
        "max_enemies": P.MAX_ENEMIES,
        "modes": [{"key": k, "label": v} for k, v in P.MODES.items()],
        "mode_factor": P.MODE_ARCHETYPE_FACTOR,
        "phase_by_elapsed": [{"limit": a, "phase": b} for a, b in P.PHASE_BY_ELAPSED],
        "archetypes": ordered(P.ARCHETYPES),
        "role_item_factor": P.ROLE_ITEM_FACTOR,
        "phase_blend": P.PHASE_BLEND,
        "phase_item_factor": P.PHASE_ITEM_FACTOR,
        "archetype_scale": P.ARCHETYPE_SCALE,
        "counters": ordered(P.COUNTERS),
        "tier_bonus": P.TIER_BONUS,
        "item_categories": list(P.ITEM_CATEGORIES),
        "styles": {k: ordered_values(v) for k, v in P.STYLES.items()},
        "style_item_factor": P.STYLE_ITEM_FACTOR,
        "role_styles": {k: list(v) for k, v in P.ROLE_STYLES.items()},
        "champ_self_bonus": {k: ordered_values(v) for k, v in P.CHAMP_SELF_BONUS.items()},
        "tag_priority": list(P.TAG_PRIORITY),
        "tag_danger": P.TAG_DANGER,
        # Native 8.1 loc (extract_loc.py): role and shop-category names as the game shows them.
        "loc_langs": langs,
        "loc_roles": {k: {lg: v[lg] for lg in UI_LANGS if lg in v} for k, v in data["meta"].get("loc", {}).get("roles", {}).items()},
        "loc_categories": {k: {lg: v[lg] for lg in UI_LANGS if lg in v} for k, v in data["meta"].get("loc", {}).get("categories", {}).items()},
    }


def build_expected(pred):
    out = []
    for me, foes, phase, mode, style, *rest in SCENARIOS + OWNED_SCENARIOS:
        owned = rest[0] if rest else None
        r = pred.predict(me, foes, phase, mode, style, owned)
        if owned:
            out.append({"owned": owned,
                        "status": [b["status"] + ("*" if b["next"] else "") for b in r["build"]]})
        else:
            out.append({})
        out[-1].update({
            "player": me, "enemies": foes, "phase": phase, "mode": mode or "", "style": style or "",
            "build": [b["item"] for b in r["build"]],
            "kinds": [b["kind"][0] + ("o" if b["offmeta"] else "") for b in r["build"]],
            "threat1": r["threats"][0]["name"], "threat1_answer": r["threats"][0]["answer"],
            "threat1_abil": [f"{a['tag']}:{a['slot']}:{a['fx'] or ''}" for a in r["threats"][0]["abilities"]],
            "probs": {a["key"]: a["probability"] for a in r["forecast"]},
            "top_forecast": r["forecast"][0]["key"],
            "items": [{"item": i["item"], "score": i["score"], "level": i["suggested_level"]} for i in r["items"][:4]],
            "top_pick": r["counters"]["picks"][0]["name"],
            "top_pick_score": r["counters"]["picks"][0]["score"],
        })
    return out


def write(path, header, value):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(header + "return " + lua(value) + "\n")
    print(f"{path} ({os.path.getsize(path)} octets)")


def main():
    data = P.load_data()
    errs = P.validate_data(data)
    if errs:
        print("champions_data.json invalide :", *errs, sep="\n  ")
        return 1
    os.makedirs(LIB, exist_ok=True)
    head = "-- Généré par engine/export_lua.py depuis champions_data.json et predictor.py. Ne pas modifier.\n"
    write(os.path.join(LIB, "sc_data.lua"), head, build_data(data))
    write(os.path.join(LIB, "sc_expected.lua"), head, build_expected(P.Predictor(data)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
