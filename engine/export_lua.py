"""Exports engine data and constants to the Lua mod, and the Lua test expectations.

Writes:
  src/scripts/lib/sc_data.lua   champions, items and every constant of predictor.py (one source of
                                truth: Python). Game names are NOT exported: only their message ids
                                (name_msg / desc_msg), translated by the game at run time.
  engine/tests/expected.lua     results of predictor.py on reference scenarios; tests/lua_tests.lua
                                checks that the Lua port gives the same results (run_lua_tests.ps1)

    python export_lua.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import predictor as P  # noqa: E402

LIB = os.path.normpath(os.path.join(HERE, "..", "src", "scripts", "lib"))
TESTS = os.path.join(HERE, "tests")

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
    # 4 items owned (off-meta ones included): the game's 4 slots are full, the optional one is blocked
    ("Io", ["Makoa", "Dredge", "Evie", "Furia", "Androxus"], "mid", None, "heal",
     {"Hoard": 3, "Nimble": 3, "Chronos": 3, "Wrecker": 3}),
]


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
            "name_msg": c.get("name_msg_id"),
            "tags": c["tags"], "wrecker_effective": c["wrecker_effective"],
            "recs": [{"item": r["item"], "weight": r["weight"], "early": r["early_game_priority"],
                      "key": r["reason_key"], "args": r["reason_args"]} for r in c["recommended_items_against"]],
            # slot, device id, name message id, effects (strategy tags: stun, pull, shield...)
            "abilities": [{"slot": x["slot"], "device_id": x["device_id"], "name_msg": x["name_msg_id"],
                           "fx": x["fx"]} for x in c.get("abilities", [])],
        })
    items = {}
    for k, v in data["items"].items():
        items[k] = {"cost": v["cost_per_level"], "category": v["category"], "item_id": v["game_item_id"],
                    "alias_ids": v.get("alias_item_ids", []),
                    "name_msg": v.get("name_msg_id"), "desc_msg": v.get("desc_msg_id"),
                    "ranks": v.get("ranks", 3)}
    text_ids = data["meta"].get("text_ids", {})
    return {
        "build": data["meta"]["build"],
        "generated_by": "engine/export_lua.py (do not edit by hand)",
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
        "modes": [{"key": k} for k in P.MODES],   # labels are the Python report's text: not exported
        "mode_factor": P.MODE_ARCHETYPE_FACTOR,
        "phase_by_elapsed": [{"limit": a, "phase": b} for a, b in P.PHASE_BY_ELAPSED],
        "archetypes": ordered({k: {f: x for f, x in v.items() if f != "label"} for k, v in P.ARCHETYPES.items()}),
        "role_item_factor": P.ROLE_ITEM_FACTOR,
        "phase_blend": P.PHASE_BLEND,
        "phase_item_factor": P.PHASE_ITEM_FACTOR,
        "archetype_scale": P.ARCHETYPE_SCALE,
        "counters": ordered({k: {f: x for f, x in v.items() if f != "why"} for k, v in P.COUNTERS.items()}),   # "why" = report text
        "tier_bonus": P.TIER_BONUS,
        "item_categories": list(P.ITEM_CATEGORIES),
        "styles": {k: ordered_values(v) for k, v in P.STYLES.items()},
        "style_item_factor": P.STYLE_ITEM_FACTOR,
        "role_styles": {k: list(v) for k, v in P.ROLE_STYLES.items()},
        "champ_self_bonus": {k: ordered_values(v) for k, v in P.CHAMP_SELF_BONUS.items()},
        "tag_priority": list(P.TAG_PRIORITY),
        "tag_danger": P.TAG_DANGER,
        # message ids of the role and shop-category names (extract_ids.py)
        "role_msg": text_ids.get("roles", {}),
        "category_msg": text_ids.get("categories", {}),
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
            "kinds": [b["kind"][0] + ("o" if b["offmeta"] else "") + ("x" if b["blocked"] else "")
                      for b in r["build"]],
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
    os.makedirs(TESTS, exist_ok=True)
    head = "-- Generated by engine/export_lua.py from champions_data.json and predictor.py. Do not edit.\n"
    write(os.path.join(LIB, "sc_data.lua"), head, build_data(data))
    write(os.path.join(TESTS, "expected.lua"), head, build_expected(P.Predictor(data)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
