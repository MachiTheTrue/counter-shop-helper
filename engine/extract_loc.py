"""Native 8.1 localization: item / champion / role / shop-category names read from the game's own
loc tables. Nothing is translated by hand.

Sources (export them with upk, see Docs/Commandes-mod.md):
    <game>\\ChaosGame\\CookedPCConsole\\assembly.dat           -> Work\\Extracted\\8.1.5839.0\\assembly.json
    <game>\\ChaosGame\\Localization\\<LOC>\\Lang_<LOC>.dat      -> Work\\Extracted\\8.1.5839.0\\Lang_<LOC>.json
      & "$T\\upk.exe" mcts export <file.dat> <out.json>

Mapping (verified in the 8.1 data):
    item      DATA_SET_ITEMS[ITEM_ID].NAME_MSG_ID / DESC_MSG_ID       (ITEM_ID = items.game_item_id)
    champion  DATA_SET_BOTS[BOT_ID].NAME_MSG_ID                       (BOT_ID = champion bot_id)
    role      messages PALADINS_ARCHETYPE_TANK / _DAMAGE / _FLANK / _SUPPORT
    category  messages PALADINS_DEFENSE / PALADINS_UTILITY / PALADINS_Healing / PALADINS_Weapon
    inventory class  DATA_SET_ITEMS.INVENTORY_CLASS_RES_ID -> resource NAME (used to recognise owned items)

Writes engine/loc_8_1.json (small, versioned) and prints what is mapped and what falls back to English.
    python extract_loc.py
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_champions_data as B  # noqa: E402

EXTRACTED = os.path.normpath(os.path.join(HERE, "..", "..", "..", "Work", "Extracted", "8.1.5839.0"))
OUT = os.path.join(HERE, "loc_8_1.json")

# game locale folder -> our code. 0.6 UI languages: en fr de it ru zh ja ko; the others are kept for
# reference. The 8.1 client has no Lang_ITA.dat (only a few engine .ITA files): Italian keeps the
# English game names (champions, items, abilities) and gets its own UI table in sc_lang.lua.
LOCALES = {"INT": "en", "FRA": "fr", "DEU": "de", "ESL": "es", "POR": "pt", "POL": "pl", "TUR": "tr",
           "RUS": "ru", "CHN": "zh", "JPN": "ja", "KOR": "ko"}
UI_LANGS = ("en", "fr", "de", "it", "ru", "zh", "ja", "ko")
LATIN1_LANGS = ("en", "fr", "de", "it")   # drawn with the Latin-1 ranges; the others get their own glyphs
ROLE_MSG = {"Frontline": "PALADINS_ARCHETYPE_TANK", "Damage": "PALADINS_ARCHETYPE_DAMAGE",
            "Flank": "PALADINS_ARCHETYPE_FLANK", "Support": "PALADINS_ARCHETYPE_SUPPORT"}
CATEGORY_MSG = {"Defense": "PALADINS_DEFENSE", "Utility": "PALADINS_UTILITY",
                "Healing": "PALADINS_Healing", "Weapon": "PALADINS_Weapon"}
# Ability slots (DATA_SET_BOT_DEVICES.SLOT_USED_VALUE_ID, verified on all 59 champions): key, order.
ABILITY_SLOTS = {221: ("weapon", 0), 199: ("a1", 1), 200: ("a2", 2), 996: ("a3", 3), 198: ("ult", 4)}
# Effects highlighted by the game in ability descriptions (<font color=...>Stuns</font>).
FX_MARKED = [("stun", r"stun"), ("knockback", r"knock|push"), ("pull", r"pull|lift"), ("root", r"root"),
             ("silence", r"silenc"), ("polymorph", r"polymorph"), ("fear", r"fear"), ("banish", r"banish"),
             ("disarm", r"disarm"), ("shock", r"shock"), ("cripple", r"crippl"), ("slow", r"slow"),
             ("reveal", r"reveal"), ("burn", r"burn|ignite|poison"), ("weaken", r"weaken"), ("blind", r"blind")]
# Effects stated in plain text.
FX_PLAIN = [("shield", r"\bshield\b.*\bhealth\b|\bhealth\b.*\bshield\b|deploy a shield|project a .*shield"),
            ("heal", r"\bheal(ing)? (an )?all(y|ies)|heal(s|ing)? (them|allies|nearby)"),
            ("stealth", r"stealth|invisib"), ("mobility", r"teleport|dash|take flight|\bfly\b|\bleap\b|\bglide|\bsoar|propel|\bboost (yourself|upward)|jetpack|\bhover"),
            ("deploy", r"\bdeploy|\bsummon|\bplace a|\bturret|\btotem")]
# Characters the in-game font cannot draw -> Latin-1 (counted in the report).
SUBST = {"’": "'", "‘": "'", "“": '"', "”": '"', "–": "-", "—": "-",
         "…": "...", " ": " ", " ": " ", "≤": "<=", "≥": ">="}


def load(name):
    with open(os.path.join(EXTRACTED, name), encoding="utf-8") as f:
        return json.load(f)["root"]


def clean(s, latin1):
    """Game text -> display text: markup removed, {25} placeholders kept as values, Latin-1 if asked."""
    if s is None:
        return None, 0
    s = re.sub(r"<[^>]+>", "", s)                 # Scaleform tags
    s = re.sub(r"\{([^{}]*)\}", lambda m: m.group(1).replace("|", "/"), s)
    s = re.sub(r"\s+", " ", s).strip()
    fixed = 0
    if latin1:
        out = []
        for ch in s:
            if ord(ch) > 0xFF:
                out.append(SUBST.get(ch, "?"))
                fixed += 1
            else:
                out.append(ch)
        s = "".join(out)
    return s, fixed


def main():
    if not os.path.isfile(os.path.join(EXTRACTED, "assembly.json")):
        print(f"assembly.json introuvable dans {EXTRACTED} : exporter d'abord les .dat (voir l'en-tête)")
        return 1
    asm = load("assembly.json")
    items_by_id = {}
    for r in asm["DATA_SET_ITEMS"]:
        if "ITEM_ID" in r:
            items_by_id.setdefault(r["ITEM_ID"], r)
    bots = {b["BOT_ID"]: b for b in asm["DATA_SET_BOTS"] if "BOT_ID" in b}
    res_names = {}
    for k, v in asm.items():
        if isinstance(v, list) and v and isinstance(v[0], dict) and "RES_ID" in v[0] and "NAME" in v[0]:
            for r in v:
                if "RES_ID" in r and "NAME" in r:
                    res_names[r["RES_ID"]] = r["NAME"]

    msgs, culture, missing_locales = {}, {}, []
    for loc, code in LOCALES.items():
        path = os.path.join(EXTRACTED, f"Lang_{loc}.json")
        if not os.path.isfile(path):
            missing_locales.append(loc)
            continue
        root = load(f"Lang_{loc}.json")
        culture[code] = root.get("CULTURE_CODE")
        by_id, by_name = {}, {}
        for m in root["DATA_SET"]:
            if "MESSAGE" in m:
                by_id[m["MSG_ID"]] = m["MESSAGE"]
                by_name.setdefault(m.get("NAME"), m["MSG_ID"])
        msgs[code] = (by_id, by_name)
    if "en" not in msgs:
        print("Lang_INT.json manquant : impossible de continuer")
        return 1
    en_by_name = msgs["en"][1]

    report = {"mapped": 0, "fallback_en": [], "unmapped": [], "latin1_fixed": 0}

    def texts(msg_id, what):
        out = {}
        for code, (by_id, _) in msgs.items():
            raw = by_id.get(msg_id)
            txt, fixed = clean(raw, code in LATIN1_LANGS)
            if code in LATIN1_LANGS:
                report["latin1_fixed"] += fixed
            if txt:
                out[code] = txt
            elif code in UI_LANGS:
                report["fallback_en"].append(f"{what} [{code}] (MSG_ID {msg_id})")
        if "en" not in out:
            report["unmapped"].append(f"{what} (MSG_ID {msg_id})")
        else:
            report["mapped"] += 1
            for code in UI_LANGS:
                out.setdefault(code, out["en"])
        return out

    items = {}
    for name, it in B.ITEMS.items():
        rec = items_by_id.get(it["game_item_id"])
        if not rec:
            report["unmapped"].append(f"objet {name} (ITEM_ID {it['game_item_id']} absent d'assembly)")
            items[name] = {"name": {c: name for c in UI_LANGS}}
            continue
        inv = lambda r: res_names.get(r.get("INVENTORY_CLASS_RES_ID")) if r.get("INVENTORY_CLASS_RES_ID") else None  # noqa: E731
        items[name] = {
            "item_id": it["game_item_id"],
            "name_msg_id": rec.get("NAME_MSG_ID"), "desc_msg_id": rec.get("DESC_MSG_ID"),
            "name": texts(rec.get("NAME_MSG_ID"), f"objet {name} (nom)"),
            "desc": texts(rec.get("DESC_MSG_ID"), f"objet {name} (description)"),
            "inventory_class": inv(rec),
            "alias_inventory_classes": sorted({inv(items_by_id[a]) for a in it.get("alias_item_ids", [])
                                               if a in items_by_id and inv(items_by_id[a])} - {inv(rec), None}),
        }
        if items[name]["name"].get("en") != name:
            report["unmapped"].append(f"objet {name} : nom anglais du jeu = {items[name]['name'].get('en')!r}")
        for a in it.get("alias_item_ids", []):
            if a not in items_by_id:
                report["unmapped"].append(f"objet {name} : alias ITEM_ID {a} absent d'assembly")

    # Abilities (DATA_SET_BOTS.DATA_SET_BOT_DEVICES -> DATA_SET_DEVICES): name per language and the
    # effects the game highlights in the description (<font>Stun</font>...) or states in plain text.
    devices = {d["DEVICE_ID"]: d for d in asm.get("DATA_SET_DEVICES", []) if "DEVICE_ID" in d}

    def effects(desc):
        if not desc:
            return []
        marked = " ".join(re.findall(r"<font[^>]*>([^<]+)</font>", desc)).lower()
        plain = re.sub(r"<[^>]+>", "", desc).lower()
        fx = [k for k, pat in FX_MARKED if re.search(pat, marked)]
        fx += [k for k, pat in FX_PLAIN if re.search(pat, plain) and k not in fx]
        return fx

    champions = {}
    for name, (pawn, bot_id) in B.PAWN.items():
        b = bots.get(bot_id)
        if not b:
            report["unmapped"].append(f"champion {name} (BOT_ID {bot_id} absent)")
            continue
        abil = []
        for sd in sorted(b.get("DATA_SET_BOT_DEVICES", []), key=lambda x: ABILITY_SLOTS.get(x.get("SLOT_USED_VALUE_ID"), ("z", 9))[1]):
            slot = ABILITY_SLOTS.get(sd.get("SLOT_USED_VALUE_ID"))
            d = devices.get(sd.get("DEVICE_ID"))
            if not slot:
                continue
            if not d:
                report["unmapped"].append(f"champion {name} : capacité {slot[0]} (DEVICE_ID {sd.get('DEVICE_ID')}) absente")
                continue
            nm = texts(d.get("NAME_MSG_ID"), f"capacité {name}/{slot[0]}")
            abil.append({"slot": slot[0], "device_id": d["DEVICE_ID"], "name": nm,
                         "fx": effects(msgs["en"][0].get(d.get("DESC_MSG_ID")))})
        champions[name] = {"bot_id": bot_id, "name": texts(b.get("NAME_MSG_ID"), f"champion {name}"), "abilities": abil}

    def named(table):
        out = {}
        for key, msg_name in table.items():
            mid = en_by_name.get(msg_name)
            if mid is None:
                report["unmapped"].append(f"{key} (message {msg_name} absent)")
                out[key] = {c: key for c in UI_LANGS}
            else:
                out[key] = texts(mid, f"{key} ({msg_name})")
        return out

    data = {
        "meta": {
            "build": "8.1.5839.0 (Wekono's Wake Hotfix 1)",
            "source": "ChaosGame/Localization/<LOC>/Lang_<LOC>.dat + CookedPCConsole/assembly.dat (upk mcts export)",
            "locales": {code: {"folder": loc, "culture": culture.get(code)} for loc, code in LOCALES.items() if code in msgs},
            "ui_langs": list(UI_LANGS),
            "generated_by": "extract_loc.py",
        },
        "items": items,
        "champions": champions,
        "roles": named(ROLE_MSG),
        "categories": named(CATEGORY_MSG),
        "report": report,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)

    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    print(f"{OUT}")
    print(f"locales : {', '.join(f'{c} ({culture.get(c)})' for c in msgs)}"
          + (f" ; absentes : {', '.join(missing_locales)}" if missing_locales else ""))
    print(f"textes mappés : {report['mapped']} ; caractères corrigés en Latin-1 : {report['latin1_fixed']}")
    print("objets :", "; ".join(f"{n} = {v['name'].get('fr')} / {v['name'].get('de')}" for n, v in items.items()))
    na = sum(len(c["abilities"]) for c in champions.values())
    nfx = sum(1 for c in champions.values() for a in c["abilities"] if a["fx"])
    print(f"capacités : {na} ({nfx} avec effet reconnu) ; ex. Makoa : "
          + ", ".join(f"{a['name']['fr']} {a['fx']}" for a in champions.get("Makoa", {}).get("abilities", [])))
    print("catégories :", "; ".join(f"{k}: {v['en']} / {v['fr']} / {v['de']}" for k, v in data["categories"].items()))
    print("objets (ru/zh/ja/ko) :", "; ".join(f"{n} = {v['name'].get('ru')} / {v['name'].get('zh')} / "
                                             f"{v['name'].get('ja')} / {v['name'].get('ko')}" for n, v in list(items.items())[:4]))
    print("rôles :", "; ".join(f"{k}: {v['en']} / {v['fr']} / {v['de']}" for k, v in data["roles"].items()))
    diff = [f"{n} -> {c['name']['fr']}/{c['name']['de']}" for n, c in champions.items()
            if c["name"].get("fr") != n or c["name"].get("de") != n]
    print(f"champions au nom localisé différent : {len(diff)}" + (" : " + ", ".join(diff[:12]) if diff else ""))
    print(f"repli sur l'anglais : {len(report['fallback_en'])}")
    for x in report["fallback_en"]:
        print("   - " + x)
    print(f"non mappés : {len(report['unmapped'])}")
    for x in report["unmapped"]:
        print("   - " + x)
    return 0


if __name__ == "__main__":
    sys.exit(main())
