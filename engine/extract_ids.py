"""Game IDs for 8.1: the message ids of every name the mod shows, and the ability effects.

The mod ships none of this: at run time it reads the same fields itself with Tempest's Game Data
API (lib/sc_gamedata.lua: assembly, lib/sc_text.lua: lang). This script checks the mapping offline
against the English table, and its ids feed the test fixture (export_lua.py -> engine/tests/game_ids.lua).

Sources (export them once with upk, see DEVELOPPEMENT.md):
    <game>\\ChaosGame\\CookedPCConsole\\assembly.dat           -> Work\\Extracted\\8.1.5839.0\\assembly.json
    <game>\\ChaosGame\\Localization\\INT\\Lang_INT.dat          -> Work\\Extracted\\8.1.5839.0\\Lang_INT.json
      & "$T\\upk.exe" mcts export <file.dat> <out.json>

Mapping (verified in the 8.1 data):
    item      DATA_SET_ITEMS[ITEM_ID].NAME_MSG_ID / DESC_MSG_ID       (ITEM_ID = items.game_item_id)
    ranks     len(DATA_SET_DEVICES[ITEM_ID].DATA_SET_DEVICE_MODES): one device mode per shop rank
              (FIRE_MODE_SEQUENCE 1..n; 3 for each of the 20 shop items of 8.1)
    champion  DATA_SET_BOTS[BOT_ID].NAME_MSG_ID                       (BOT_ID = champion bot_id)
    ability   DATA_SET_BOTS.DATA_SET_BOT_DEVICES -> DATA_SET_DEVICES[DEVICE_ID].NAME_MSG_ID
    role      messages PALADINS_ARCHETYPE_TANK / _DAMAGE / _FLANK / _SUPPORT
    category  messages PALADINS_DEFENSE / PALADINS_UTILITY / PALADINS_Healing / PALADINS_Weapon

Ability effects (stun, pull, shield...) are strategy tags derived here from the English description;
they are not shown as game text.

Writes engine/game_ids_8_1.json (ids only, versioned) and prints what could not be mapped.
    python extract_ids.py
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_champions_data as B  # noqa: E402

EXTRACTED = os.path.normpath(os.path.join(HERE, "..", "..", "..", "Work", "Extracted", "8.1.5839.0"))
OUT = os.path.join(HERE, "game_ids_8_1.json")

ROLE_MSG = {"Frontline": "PALADINS_ARCHETYPE_TANK", "Damage": "PALADINS_ARCHETYPE_DAMAGE",
            "Flank": "PALADINS_ARCHETYPE_FLANK", "Support": "PALADINS_ARCHETYPE_SUPPORT"}
CATEGORY_MSG = {"Defense": "PALADINS_DEFENSE", "Utility": "PALADINS_UTILITY",
                "Healing": "PALADINS_Healing", "Weapon": "PALADINS_Weapon"}
# Ability slots (DATA_SET_BOT_DEVICES.SLOT_USED_VALUE_ID, verified on all 59 champions): key, order.
ABILITY_SLOTS = {221: ("weapon", 0), 199: ("a1", 1), 200: ("a2", 2), 996: ("a3", 3), 198: ("ult", 4)}
# Effects the game highlights in ability descriptions (<font color=...>Stuns</font>).
FX_MARKED = [("stun", r"stun"), ("knockback", r"knock|push"), ("pull", r"pull|lift"), ("root", r"root"),
             ("silence", r"silenc"), ("polymorph", r"polymorph"), ("fear", r"fear"), ("banish", r"banish"),
             ("disarm", r"disarm"), ("shock", r"shock"), ("cripple", r"crippl"), ("slow", r"slow"),
             ("reveal", r"reveal"), ("burn", r"burn|ignite|poison"), ("weaken", r"weaken"), ("blind", r"blind")]
# Effects stated in plain text.
FX_PLAIN = [("shield", r"\bshield\b.*\bhealth\b|\bhealth\b.*\bshield\b|deploy a shield|project a .*shield"),
            ("heal", r"\bheal(ing)? (an )?all(y|ies)|heal(s|ing)? (them|allies|nearby)"),
            ("stealth", r"stealth|invisib"), ("mobility", r"teleport|dash|take flight|\bfly\b|\bleap\b|\bglide|\bsoar|propel|\bboost (yourself|upward)|jetpack|\bhover"),
            ("deploy", r"\bdeploy|\bsummon|\bplace a|\bturret|\btotem")]


def load(name):
    with open(os.path.join(EXTRACTED, name), encoding="utf-8") as f:
        return json.load(f)["root"]


def effects(desc):
    """Effect tags of an ability, from its English description."""
    if not desc:
        return []
    marked = " ".join(re.findall(r"<font[^>]*>([^<]+)</font>", desc)).lower()
    plain = re.sub(r"<[^>]+>", "", desc).lower()
    fx = [k for k, pat in FX_MARKED if re.search(pat, marked)]
    fx += [k for k, pat in FX_PLAIN if re.search(pat, plain) and k not in fx]
    return fx


def main():
    for name in ("assembly.json", "Lang_INT.json"):
        if not os.path.isfile(os.path.join(EXTRACTED, name)):
            print(f"{name} introuvable dans {EXTRACTED} : exporter d'abord les .dat (voir l'en-tête)")
            return 1
    asm = load("assembly.json")
    lang = load("Lang_INT.json")
    en_by_id, en_by_name = {}, {}
    for m in lang["DATA_SET"]:
        if "MESSAGE" in m:
            en_by_id[m["MSG_ID"]] = m["MESSAGE"]
            en_by_name.setdefault(m.get("NAME"), m["MSG_ID"])
    items_by_id = {}
    for r in asm["DATA_SET_ITEMS"]:
        if "ITEM_ID" in r:
            items_by_id.setdefault(r["ITEM_ID"], r)
    bots = {b["BOT_ID"]: b for b in asm["DATA_SET_BOTS"] if "BOT_ID" in b}
    devices = {d["DEVICE_ID"]: d for d in asm.get("DATA_SET_DEVICES", []) if "DEVICE_ID" in d}
    unmapped = []

    def msg(mid, what):
        """The id itself when the English table has it, else None (reported)."""
        if mid is None or mid not in en_by_id:
            unmapped.append(f"{what} (MSG_ID {mid})")
            return None
        return mid

    items = {}
    for name, it in B.ITEMS.items():
        rec = items_by_id.get(it["game_item_id"])
        if not rec:
            unmapped.append(f"objet {name} (ITEM_ID {it['game_item_id']} absent d'assembly)")
            continue
        dev = devices.get(it["game_item_id"])
        modes = sorted(m.get("FIRE_MODE_SEQUENCE", 0) for m in (dev or {}).get("DATA_SET_DEVICE_MODES", []))
        if modes != list(range(1, len(modes) + 1)) or not modes:
            unmapped.append(f"objet {name} : rangs illisibles (modes {modes}), 3 par défaut")
        items[name] = {"item_id": it["game_item_id"],
                       "name_msg_id": msg(rec.get("NAME_MSG_ID"), f"objet {name} (nom)"),
                       "desc_msg_id": msg(rec.get("DESC_MSG_ID"), f"objet {name} (description)"),
                       "ranks": len(modes) if modes == list(range(1, len(modes) + 1)) and modes else 3}
        english = re.sub(r"<[^>]+>", "", en_by_id.get(rec.get("NAME_MSG_ID"), "")).strip()
        if english != name:
            unmapped.append(f"objet {name} : nom anglais du jeu = {english!r}")
        for a in it.get("alias_item_ids", []):
            if a not in items_by_id:
                unmapped.append(f"objet {name} : alias ITEM_ID {a} absent d'assembly")

    champions = {}
    for name, (_pawn, bot_id) in B.PAWN.items():
        b = bots.get(bot_id)
        if not b:
            unmapped.append(f"champion {name} (BOT_ID {bot_id} absent)")
            continue
        abilities = []
        rows = sorted(b.get("DATA_SET_BOT_DEVICES", []),
                      key=lambda x: ABILITY_SLOTS.get(x.get("SLOT_USED_VALUE_ID"), ("z", 9))[1])
        for sd in rows:
            slot = ABILITY_SLOTS.get(sd.get("SLOT_USED_VALUE_ID"))
            d = devices.get(sd.get("DEVICE_ID"))
            if not slot:
                continue
            if not d:
                unmapped.append(f"champion {name} : capacité {slot[0]} (DEVICE_ID {sd.get('DEVICE_ID')}) absente")
                continue
            abilities.append({"slot": slot[0], "device_id": d["DEVICE_ID"],
                              "name_msg_id": msg(d.get("NAME_MSG_ID"), f"capacité {name}/{slot[0]}"),
                              "fx": effects(en_by_id.get(d.get("DESC_MSG_ID")))})
        champions[name] = {"bot_id": bot_id, "name_msg_id": msg(b.get("NAME_MSG_ID"), f"champion {name}"),
                           "abilities": abilities}

    def named(table):
        out = {}
        for key, msg_name in table.items():
            mid = en_by_name.get(msg_name)
            if mid is None:
                unmapped.append(f"{key} (message {msg_name} absent)")
            out[key] = mid
        return out

    data = {
        "meta": {
            "build": "8.1.5839.0 (Wekono's Wake Hotfix 1)",
            "source": "CookedPCConsole/assembly.dat + Localization/INT/Lang_INT.dat (upk mcts export)",
            "generated_by": "extract_ids.py",
        },
        "items": items,
        "champions": champions,
        "roles": named(ROLE_MSG),
        "categories": named(CATEGORY_MSG),
        "unmapped": unmapped,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)

    n_abil = sum(len(c["abilities"]) for c in champions.values())
    n_fx = sum(1 for c in champions.values() for a in c["abilities"] if a["fx"])
    print(OUT)
    print(f"{len(items)} objets, {len(champions)} champions, {n_abil} capacités ({n_fx} avec effet), "
          f"{len(data['roles'])} rôles, {len(data['categories'])} catégories")
    print(f"non mappés : {len(unmapped)}")
    for x in unmapped:
        print("   - " + x)
    return 0


if __name__ == "__main__":
    sys.exit(main())
