"""Offline checks of the Lua mod (no Lua interpreter needed).

    python check_lua.py
Checks:
  - structure of every src/scripts/**/*.lua (blocks and brackets balanced, strings closed)
  - sc_lang.lua: same keys in the 8 UI languages (0.6: EN FR DE IT RU ZH JA KO); EN / FR / DE / IT
    Latin-1 only, RU Latin-1 + Cyrillic, ZH / JA / KO + CJK (main.lua loads a font set per script);
    no English sentence left untranslated, no English gaming jargon in FR / DE / IT
  - every translation key used by main.lua exists, including the dynamic ones built from the engine
    data (tags, reasons, archetypes, counters, styles, roles, categories, modes, errors...)
  - format arguments: same number of %s/%d in every language
Exit code 0 = OK.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import predictor as P  # noqa: E402

SRC = os.path.normpath(os.path.join(HERE, "..", "src", "scripts"))
errors = []


def err(msg):
    errors.append(msg)


# ------------------------------------------------------------------ structure
def strip(src, path):
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                j = src.find("]" + m.group(1) + "]", i)
                i = n if j < 0 else j + len(m.group(1)) + 2
            else:
                j = src.find("\n", i)
                i = n if j < 0 else j
            continue
        m = re.match(r"\[(=*)\[", src[i:])
        if m:
            j = src.find("]" + m.group(1) + "]", i)
            out.append(' "" ')
            i = n if j < 0 else j + len(m.group(1)) + 2
            continue
        c = src[i]
        if c in "\"'":
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == "\\":
                    j += 1
                elif src[j] == "\n":
                    err(f"{path}: chaîne non fermée ligne {src.count(chr(10), 0, i) + 1}")
                    break
                j += 1
            out.append(' "" ')
            i = j + 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def structure(path):
    code = strip(open(path, encoding="utf-8").read(), path)
    stack = []
    for ln, line in enumerate(code.split("\n"), 1):
        for tok in re.findall(r"[A-Za-z_]\w*|[(){}\[\]]", line):
            if tok in ("function", "if", "do", "repeat", "(", "{", "["):
                stack.append((tok, ln))
            elif tok in ("end", "until", ")", "}", "]"):
                want = {"end": ("function", "if", "do"), "until": ("repeat",), ")": ("(",), "}": ("{",), "]": ("[",)}[tok]
                if not stack or stack[-1][0] not in want:
                    err(f"{os.path.basename(path)}:{ln}: '{tok}' inattendu (ouvert : {stack[-1] if stack else None})")
                    return
                stack.pop()
    for o, ln in stack:
        err(f"{os.path.basename(path)}:{ln}: '{o}' jamais fermé")


for root, _, files in os.walk(SRC):
    for f in files:
        if f.endswith(".lua"):
            structure(os.path.join(root, f))

# ------------------------------------------------------------------ translations
lang_src = open(os.path.join(SRC, "lib", "sc_lang.lua"), encoding="utf-8").read()
tables = {}
for m in re.finditer(r"^T\.(\w+) = \{(.*?)^\}", lang_src, re.S | re.M):
    keys = {}
    for km in re.finditer(r'(\w+) = "((?:[^"\\]|\\.)*)"', m.group(2)):
        keys[km.group(1)] = km.group(2)
    tables[m.group(1)] = keys
UI_LANGS = {"en", "fr", "de", "it", "ru", "zh", "ja", "ko"}
LATIN1 = {"en", "fr", "de", "it"}
# glyphs main.lua can draw: BASE_RANGES (Latin, Latin Ext., Greek, Cyrillic, punctuation, arrows, maths,
# shapes) for every language, + the merged CJK font (U+2E80 and up) for zh / ja / ko
BASE = [(0x20, 0x24F), (0x370, 0x3FF), (0x400, 0x52F), (0x2000, 0x206F), (0x2190, 0x21FF), (0x2200, 0x22FF),
        (0x25A0, 0x25FF)]


def drawable(ch, cjk):
    o = ord(ch)
    return o <= 0xFF or any(a <= o <= b for a, b in BASE) or (cjk and o >= 0x2E80)


if set(tables) != UI_LANGS:
    err(f"sc_lang.lua : langues trouvées {sorted(tables)}")
en = tables.get("en", {})
for lang, keys in tables.items():
    for k in set(en) - set(keys):
        err(f"[{lang}] clé manquante : {k}")
    for k in set(keys) - set(en):
        err(f"[{lang}] clé inconnue en anglais : {k}")
    for k, v in keys.items():
        if lang in LATIN1:
            bad = [c for c in v if ord(c) > 0xFF]
        else:
            bad = [c for c in v if not drawable(c, lang in ("zh", "ja", "ko"))]
        if bad:
            err(f"[{lang}] {k} : caractères non affichables {bad}")
        if lang != "en" and k in en and v == en[k] and len(v) > 14 and not k.startswith("cmd_") and k != "title":
            err(f"[{lang}] {k} : texte resté en anglais")
        if k in en:
            spec = lambda s: re.findall(r"%[-0-9.]*[sdf]", s.replace("%%", ""))  # noqa: E731
            if spec(v) != spec(en[k]):
                err(f"[{lang}] {k} : arguments {spec(v)} au lieu de {spec(en[k])}")
            if re.search(r"%(?![-0-9.]*[sdf])", v.replace("%%", "")) and spec(en[k]):
                err(f"[{lang}] {k} : '%' isolé dans un texte formaté (doubler en %%)")

# ------------------------------------------------------------------ keys used by the code
main_src = open(os.path.join(SRC, "main.lua"), encoding="utf-8").read()
used = set(re.findall(r'\bt\("(\w+)"', main_src)) | set(re.findall(r'L\.maybe\("(\w+)"', main_src))
used = {k for k in used if not k.endswith("_")}   # "act_" .. a : prefixes, covered by `dynamic`
used.discard("tut")  # "tut" .. step is dynamic; "tut" itself is a real key, re-added below
used.add("tut")
data = P.load_data()
dynamic = set()
dynamic |= {"tag_" + x for x in P.TAG_PRIORITY}
dynamic |= {"r_" + r["reason_key"] for c in data["champions"] for r in c["recommended_items_against"]} | {"r_squishy", "r_generic"}
dynamic |= {"arch_" + k for k in P.ARCHETYPES} | {"archs_" + k for k in P.ARCHETYPES}
dynamic |= {"c_" + k for k in P.COUNTERS} | {"c_hole_frontline", "c_hole_support"}
dynamic |= {"style_" + k for k in P.STYLES}
dynamic |= {"role_" + r for r in P.ROLE_ITEM_FACTOR}
dynamic |= {"cat_" + c for c in P.ITEM_CATEGORIES} | {"cat_Other"}
dynamic |= {"phase_" + p for p in P.PHASES}
dynamic |= {"mode_" + m for m in P.MODES} | {"mode_unknown"}
dynamic |= {"st_" + s for s in ("match", "champ_select", "lobby", "no_player", "idle")}
dynamic |= {"err_" + e for e in ("bad_phase", "bad_mode", "bad_count", "unknown_champion", "duplicate")}
dynamic |= {"act_" + a for a in ("menu", "overlay", "settings", "lock", "layout")}
dynamic |= {"fx_" + fx for v in P.TAG_FX.values() for fx in v}
dynamic |= {"disp_" + d for d in ("auto", "compact", "detailed")}
dynamic |= {f"tut{i}" for i in range(1, 5)} | {f"tut{i}_t" for i in range(1, 5)}
dynamic |= {"tab_match", "tab_settings", "tab_help"}
dynamic |= {"badge_" + c for c in ("draft", "match", "plan")}
for k in sorted(used | dynamic):
    if k not in en:
        err(f"clé de traduction absente : {k}")
for item in P.Predictor(data).items:
    pass  # item notes are optional (L.maybe)

# ------------------------------------------------------------------ Latin-1 in displayed Lua sources
for f in ("main.lua", os.path.join("lib", "sc_predictor.lua"), os.path.join("lib", "sc_detect.lua"),
          os.path.join("lib", "sc_player.lua")):
    for ln, line in enumerate(open(os.path.join(SRC, f), encoding="utf-8"), 1):
        code = line.split("--", 1)[0]
        bad = [c for c in code if ord(c) > 0xFF]
        if bad:
            err(f"{f}:{ln}: caractères hors Latin-1 dans du code affiché {bad}")

# ------------------------------------------------------------------ game texts shown by the UI (sc_data.lua)
data_src = open(os.path.join(SRC, "lib", "sc_data.lua"), encoding="utf-8").read()
bad = sorted({c for c in data_src if not drawable(c, True)})
if bad:
    err(f"sc_data.lua : caractères non affichables (noms du jeu) {bad[:10]}")
# icons referenced by the data exist in src/icons
for name, it in data["items"].items():
    p = os.path.join(SRC, "..", "icons", "".join(ch for ch in name if ch.isalnum()) + ".png")
    if not os.path.isfile(p):
        err(f"icône absente : {os.path.normpath(p)}")
# English-only jargon must not leak into FR / DE strings (0.5: zero mixed languages)
# The mod's display name is a proper name: kept as is in every language, never counted as English.
BRAND = "Counter & Shop Helper"
for _lang, _keys in tables.items():
    for k, v in _keys.items():
        if "SmartCounter" in v:
            err(f"[{_lang}] {k} : ancien nom « SmartCounter » (le nom affiché est « {BRAND} »)")
        if re.search(r"mashi", v, re.I):
            err(f"[{_lang}] {k} : ancien nom d'auteur « mashi » (l'auteur est « Machi Konno »)")
# Credit line: one translated text, filled with the author and the Discord handle.
for _lang, _keys in tables.items():
    if _keys.get("about_credit", "").count("%s") != 2:
        err(f"[{_lang}] about_credit : doit contenir l'auteur et le Discord (2 × %s)")
JARGON = re.compile(r"\b(overlay|build|burst|hitscan|poke|dive|blaster|frontline|snowball|lobby|pawn|"
                    r"counter-?picks?|sustain|wrecker|resilience|cauterize|items?)\b", re.I)
for lang in ("fr", "de", "it"):
    for k, v in tables.get(lang, {}).items():
        m = JARGON.search(v.replace(BRAND, ""))
        if m:
            err(f"[{lang}] {k} : mot anglais « {m.group(0)} »")
# RU / ZH / JA / KO: no English word left in a translated text (names, keys and commands excepted)
ASCII_OK = re.compile(r"^(SmartCounter|Tempest|Ctrl|Shift|Alt|Esc|Auto|Discord|Steam|Lua|Python|Machi|Konno|"
                      r"smartcounter\w*|F\d+|Lv|HP|CC|SDK|II|III|Inara|Azaan|Atlas|opt)$", re.I)
for lang in ("ru", "zh", "ja", "ko"):
    for k, v in tables.get(lang, {}).items():
        for w in re.findall(r"[A-Za-z_][A-Za-z_0-9]{3,}", v.replace(BRAND, "")):
            if not ASCII_OK.match(w):
                err(f"[{lang}] {k} : mot anglais « {w} »")

print(f"{len(tables)} langues, {len(en)} clés ; {len(used | dynamic)} clés utilisées vérifiées")
if errors:
    print(f"{len(errors)} problème(s) :")
    for e in errors:
        print("  - " + e)
    sys.exit(1)
print("OK")
