"""SmartCounter 8.1 tests: JSON validity + simulated compositions.

    python test_predictor.py
Exit code 0 = everything passed.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from predictor import Predictor, PredictorError, load_data, validate_data, DATA_PATH  # noqa: E402

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

RESULTS = []


def check(name, cond, detail=""):
    RESULTS.append((name, bool(cond), detail))
    return cond


def top_items(r, n):
    return [i["item"] for i in r["items"][:n]]


def prob(r, key):
    return next(a["probability"] for a in r["forecast"] if a["key"] == key)


def section(title):
    print("\n" + "=" * 78 + f"\n{title}\n" + "=" * 78)


def main():
    # ------------------------------------------------------------ 1. JSON
    section("1. Validité de champions_data.json")
    with open(DATA_PATH, encoding="utf-8") as f:
        raw = f.read()
    try:
        data = json.loads(raw)
        check("JSON parsable", True)
    except json.JSONDecodeError as e:
        check("JSON parsable", False, str(e))
        return
    errs = validate_data(data)
    check("schéma valide", not errs, "; ".join(errs[:5]))
    roles = {}
    for c in data["champions"]:
        roles[c["role"]] = roles.get(c["role"], 0) + 1
    print(f"Build : {data['meta']['build']}")
    print(f"{len(data['champions'])} champions : " + ", ".join(f"{k} {v}" for k, v in sorted(roles.items())))
    print(f"{len(data['items'])} objets ; Wrecker/Bulldozer/Resilience/Sentinel par niveau : "
          + ", ".join(f"{n} {data['items'][n]['per_level']}" for n in ("Wrecker", "Bulldozer", "Resilience", "Sentinel")))
    by = {c["name"]: c for c in data["champions"]}
    check("Atlas : Wrecker inefficace", not by["Atlas"]["wrecker_effective"])
    check("Inara/Azaan : déployables, pas de bouclier Wrecker",
          all("deployables" in by[n]["tags"] and not by[n]["wrecker_effective"] for n in ("Inara", "Azaan")))
    check("Fernando/Makoa/Khan : bouclier Wrecker",
          all(by[n]["wrecker_effective"] for n in ("Fernando", "Makoa", "Khan")))
    gone = {"Cauterize", "Illuminate", "Kill to Heal", "Master Riding"}
    check("boutique 8.1 : ni Cauterize, ni Illuminate, ni Kill to Heal",
          not gone & set(data["items"]) and not any(r["item"] in gone for c in data["champions"]
                                                    for r in c["recommended_items_against"]))
    check("compétences : 5 par champion (arme, 3 capacités, ultime)",
          all(len(c.get("abilities", [])) == 5 for c in data["champions"]),
          str([c["name"] for c in data["champions"] if len(c.get("abilities", [])) != 5]))
    mk = {a["slot"]: a for a in by["Makoa"]["abilities"]}
    check("Makoa : Ancre de drague = étourdit (données du jeu)",
          "stun" in mk["a3"]["fx"] and mk["a3"]["name"]["fr"] == "Ancre de drague", str(mk.get("a3")))

    p = Predictor(data)

    # ------------------------------------------------------------ 2. scenarios
    scenarios = [
        ("A. Double frontline bouclier", "Lian", ["Fernando", "Makoa", "Grohk", "Viktor", "Androxus"], "mid"),
        ("B. Compo CC", "Androxus", ["Inara", "Khan", "Pip", "Mal'Damba", "Cassie"], "mid"),
        ("C. Déployables + flanks", "Drogoz", ["Barik", "Ying", "Kinessa", "Skye", "Evie"], "mid"),
        ("D. Murs non-bouclier (piège Wrecker)", "Viktor", ["Inara", "Azaan", "Atlas"], "mid"),
        ("E. Dive partielle (3 ennemis connus)", "Grohk", ["Talus", "Maeve", "Koga"], "early"),
        ("F. Sustain : early vs late", "Tyra", ["Seris", "Rei", "Io", "Raum"], "early"),
    ]
    reports = {}
    for title, me, foes, phase in scenarios:
        section(f"2.{title}")
        r = p.predict(me, foes, phase)
        reports[title[0]] = r
        print(p.format_report(r))

    A, B, C, D, E, F = (reports[k] for k in "ABCDEF")
    check("A : Shield-Heavy en tête", A["forecast"][0]["key"] == "shield_heavy", A["forecast"][0]["label"])
    check("A : Wrecker 1er achat", top_items(A, 1) == ["Wrecker"], str(top_items(A, 3)))
    check("B : High-CC en tête", B["forecast"][0]["key"] == "high_cc", B["forecast"][0]["label"])
    check("B : Resilience dans le top 2", "Resilience" in top_items(B, 2), str(top_items(B, 3)))
    check("C : Deployable-Heavy ≥ 80 %", prob(C, "deployable_heavy") >= 80, f"{prob(C, 'deployable_heavy')} %")
    check("C : Bulldozer dans le top 2", "Bulldozer" in top_items(C, 2), str(top_items(C, 3)))
    check("C : Havre proposé (Skye furtive)", "Haven" in top_items(C, 6), str(top_items(C, 6)))
    check("D : Shield-Heavy = 0 % (Inara/Azaan/Atlas)", prob(D, "shield_heavy") == 0, f"{prob(D, 'shield_heavy')} %")
    check("D : Wrecker absent du top 4", "Wrecker" not in top_items(D, 4), str(top_items(D, 4)))
    check("D : Bulldozer dans le top 2", "Bulldozer" in top_items(D, 2), str(top_items(D, 3)))
    check("E : Dive / Flank ≥ 80 %", prob(E, "dive_flank") >= 80, f"{prob(E, 'dive_flank')} %")
    check("E : contre-picks avec contrôle ou burst",
          any(p.champion(c["name"])["tags"] and {"heavy_cc", "burst"} & set(p.champion(c["name"])["tags"])
              for c in E["counters"]["picks"][:3]), str([c["name"] for c in E["counters"]["picks"][:3]]))
    late = p.predict("Tyra", ["Seris", "Rei", "Io", "Raum"], "late")
    ts_e = next(i["score"] for i in F["items"] if i["item"] == "Trigger Scent")
    ts_l = next(i["score"] for i in late["items"] if i["item"] == "Trigger Scent")
    print(f"\nFrénésie contre Seris/Rei/Io/Raum : early {ts_e} -> late {ts_l}")
    check("F : Frénésie (burst anti-sustain) plus forte en late", ts_l > ts_e, f"{ts_e} -> {ts_l}")
    check("F : Frénésie dans le build en late", "Trigger Scent" in [b["item"] for b in late["build"]],
          str([b["item"] for b in late["build"]]))
    hoard_e = next((i["score"] for i in F["items"] if i["item"] == "Hoard"), 0)
    check("Amassage : pas de valeur late (économie)", not any(i["item"] == "Hoard" for i in late["items"][:5]),
          f"early {hoard_e}")
    check("contre-picks : raisons variées",
          len({tuple(c["why"]) for c in A["counters"]["picks"]}) > 1, str([c["why"] for c in A["counters"]["picks"]]))

    # ------------------------------------------------------------ 3. edge cases
    section("3. Cas limites")
    one = p.predict("Fernando", ["Kinessa"], "early")
    check("1 seul ennemi accepté", len(one["items"]) > 0, str(top_items(one, 3)))
    check("alias de nom (bombking, maldamba)", p.champion("bombking")["name"] == "Bomb King"
          and p.champion("maldamba")["name"] == "Mal'Damba")
    for label, args in (("champion inconnu refusé", ("Lian", ["Nobody"])),
                        ("6 ennemis refusés", ("Lian", ["Ash", "Atlas", "Azaan", "Barik", "Khan", "Makoa"])),
                        ("doublon ennemi refusé", ("Lian", ["Ash", "Ash"]))):
        try:
            p.predict(*args)
            check(label, False, "aucune erreur levée")
        except PredictorError as e:
            check(label, True, str(e))
    for r in (A, B, C, D, E, F):
        ok = all(0 <= a["probability"] <= 100 for a in r["forecast"])
        check(f"probabilités 0-100 ({', '.join(r['enemies'][:2])}…)", ok)

    # ------------------------------------------------------------ 4. modes / phase / in-game ids
    section("4. Modes de jeu, phase auto, identifiants en jeu")
    from predictor import phase_for_elapsed, MODES  # noqa: E402
    base = p.predict("Lian", ["Fernando", "Makoa", "Grohk", "Viktor", "Androxus"], "mid")
    same = p.predict("Lian", ["Fernando", "Makoa", "Grohk", "Viktor", "Androxus"], "mid", None)
    check("sans mode = résultat inchangé", base["forecast"] == same["forecast"] and base["items"] == same["items"])
    tdm = p.predict("Grohk", ["Talus", "Maeve", "Koga"], "mid", "tdm")
    sie = p.predict("Grohk", ["Talus", "Maeve", "Koga"], "mid", "siege")
    print(f"Dive/Flank vs Talus/Maeve/Koga : siège {prob(sie, 'dive_flank')} % / TDM {prob(tdm, 'dive_flank')} %")
    check("TDM renforce Dive/Flank", prob(tdm, "dive_flank") >= prob(sie, "dive_flank"))
    try:
        p.predict("Lian", ["Ash"], "mid", "arcade")
        check("mode inconnu refusé", False)
    except PredictorError:
        check("mode inconnu refusé", True)
    check("phase auto 0 s / 300 s / 700 s",
          (phase_for_elapsed(0), phase_for_elapsed(300), phase_for_elapsed(700)) == ("early", "mid", "late"))
    check("tous les modes ont un libellé", all(MODES.values()))
    check("pawn Lian = TgPawn_Princess", p.champion("Lian")["pawn_class"] == "TgPawn_Princess")
    check("pawn Inara = TgPawn_BarrierTank", p.champion("Inara")["pawn_class"] == "TgPawn_BarrierTank")

    # ------------------------------------------------------------ 5. 8.1 shop, playstyles, threats (0.3)
    section("5. Boutique 8.1 (20 objets, 5 recommandations), styles Support, menaces")
    from predictor import ITEM_CATEGORIES, BUILD_SLOTS  # noqa: E402
    cats = {}
    for name, it in data["items"].items():
        cats.setdefault(it["category"], []).append(name)
    check("boutique 4x5 (4 catégories de 5 objets)",
          sorted(cats) == sorted(ITEM_CATEGORIES) and all(len(v) == 5 for v in cats.values()),
          str({k: len(v) for k, v in cats.items()}))
    check("objets : icône et identifiant natif partout",
          all(isinstance(it.get("icon_index"), int) and it.get("game_item_id") for it in data["items"].values()))
    check("raisons structurées (reason_key) partout",
          all(r.get("reason_key") for c in data["champions"] for r in c["recommended_items_against"]))
    foes = ["Makoa", "Dredge", "Evie", "Furia", "Androxus"]
    heal = p.predict("Io", foes, "mid")
    aggro = p.predict("Io", foes, "mid", None, "aggro")
    print(p.format_report(heal))
    bh = [b["item"] for b in heal["build"]]
    check("Io : style par défaut = soin", heal["style"] == "heal" and heal["styles"] == ["heal", "aggro"])
    check("Io soin : toujours 5 objets", len(heal["build"]) == BUILD_SLOTS, str(bh))
    check("Io soin : pas plus de 2 défenses (fini le spam tank)",
          sum(1 for b in heal["build"] if b["category"] == "Defense") <= 2, str(bh))
    check("Io soin : Rejuvenate dans le build, en principal", any(b["item"] == "Rejuvenate" and b["kind"] == "primary"
                                                                 for b in heal["build"]), str(bh))
    check("Io soin : Resilience contre le CC de Makoa", "Resilience" in bh, str(bh))
    check("Io soin : pas de Sentinel (objet d'élimination)", "Sentinel" not in bh, str(bh))
    ba = [b["item"] for b in aggro["build"]]
    check("Io agressif : build différent, objets offensifs", ba != bh and
          any(i in ba for i in ("Life Rip", "Bloodbath", "Deft Hands")), str(ba))
    shots = [(me, f) for me in ("Io", "Lian", "Makoa", "Androxus", "Ash", "Seris", "Inara")
             for f in (["Makoa", "Dredge", "Evie", "Furia", "Androxus"], ["Kinessa"], ["Inara", "Azaan", "Atlas"])]
    builds = [p.predict(me, f, ph)["build"] for me, f in shots for ph in ("early", "mid", "late")]
    check("5 objets dans tous les cas (21 compos x 3 phases)", all(len(b) == BUILD_SLOTS for b in builds))
    check("plusieurs objets d'une même catégorie possibles",
          any(len({b["category"] for b in bl}) < len(bl) for bl in builds))
    check("emplacements flex = sous le seuil, niveau 1, triés après les principaux",
          all(b["suggested_level"] == 1 for bl in builds for b in bl if b["kind"] == "flex"))
    check("un seul 'prochain achat' par build", all(sum(b["next"] for b in bl) == 1 for bl in builds))
    check("0.6 : 4 principaux puis le 5e en option (Paladins = 4 objets)",
          all([b["kind"] for b in bl] == ["primary"] * 4 + ["flex"] for bl in builds))
    o4 = p.predict("Io", ["Makoa", "Dredge", "Evie", "Furia", "Androxus"], "mid", None, "heal",
                   {"Hoard": 1, "Nimble": 1, "Chronos": 1, "Wrecker": 1})
    check("0.6 : 4 objets possédés = les 4 principaux, le 5e reste en option",
          {b["item"] for b in o4["build"][:4]} == {"Hoard", "Nimble", "Chronos", "Wrecker"}
          and o4["build"][4]["kind"] == "flex" and o4["build"][4]["rank"] == 0,
          str([(b["item"], b["kind"]) for b in o4["build"]]))
    mk = next(t for t in heal["threats"] if t["name"] == "Makoa")
    check("menace Makoa : CC lié à sa compétence (Ancre de drague, étourdit)",
          any(a["tag"] == "heavy_cc" and a["slot"] == "a3" and a["fx"] == "stun" for a in mk["abilities"]),
          str(mk["abilities"]))
    t0 = heal["threats"][0]
    check("menace n°1 = Makoa (CC + bouclier)", t0["name"] == "Makoa" and "heavy_cc" in t0["tags"], str(t0))
    check("réponse à Makoa présente dans le build", t0["answer_in_build"], str(t0))
    try:
        p.predict("Lian", ["Ash"], "mid", None, "heal")
        check("style invalide pour le rôle refusé", False)
    except PredictorError:
        check("style invalide pour le rôle refusé", True)
    lian = p.predict("Lian", ["Fernando", "Makoa", "Grohk", "Viktor", "Androxus"], "mid")
    check("Lian : Wrecker toujours 1er achat du build", lian["build"][0]["item"] == "Wrecker",
          str([b["item"] for b in lian["build"]]))

    section("6. Objets possédés (état live) : rang, cible, prochain achat")
    foes = ["Makoa", "Dredge", "Evie", "Furia", "Androxus"]
    fresh = p.predict("Io", foes, "mid", None, "heal")
    check("rien d'acheté : tout en 'buy', 1er slot = prochain",
          all(b["rank"] == 0 and b["status"] == "buy" for b in fresh["build"]) and fresh["build"][0]["next"],
          str([(b["item"], b["status"], b["next"]) for b in fresh["build"]]))
    first = fresh["build"][0]
    full = p.predict("Io", foes, "mid", None, "heal", {first["item"]: first["target"]})
    b0 = full["build"][0]
    check("1er objet au rang cible : done, prochain = slot 2",
          b0["status"] == "done" and not b0["next"] and full["build"][1]["next"],
          str([(b["item"], b["rank"], b["target"], b["status"]) for b in full["build"]]))
    if first["target"] > 1:
        part = p.predict("Io", foes, "mid", None, "heal", {first["item"]: first["target"] - 1})
        check("rang sous la cible : upgrade + prochain", part["build"][0]["status"] == "upgrade"
              and part["build"][0]["next"], str(part["build"][0]))
    off = p.predict("Io", foes, "mid", None, "heal", {"Hoard": 1})
    oh = next((b for b in off["build"] if b["item"] == "Hoard"), None)
    check("objet hors méta possédé : gardé dans le build et signalé", oh and oh["offmeta"] and oh["status"] == "done",
          str(oh))
    check("toujours 5 objets avec un achat hors méta", len(off["build"]) == BUILD_SLOTS)
    lian0 = p.predict("Lian", ["Makoa", "Fernando", "Grohk", "Evie", "Strix"], "mid")
    lian1 = p.predict("Lian", ["Makoa", "Fernando", "Grohk", "Evie", "Strix"], "mid", None, None, {"Life Rip": 3})
    i0, i1 = [b["item"] for b in lian0["build"]], [b["item"] for b in lian1["build"]]
    check("achat hors méta (Arrache-vie III) : les emplacements libres s'adaptent (synergie Mains agiles)",
          "Deft Hands" not in i0 and "Deft Hands" in i1
          and next(b for b in lian1["build"] if b["item"] == "Deft Hands")["synergy"] == ["Life Rip"], f"{i0} -> {i1}")
    bz1 = p.predict("Lian", ["Makoa", "Fernando", "Grohk", "Evie", "Strix"], "mid", None, None, {"Bulldozer": 1})
    bz2 = p.predict("Lian", ["Makoa", "Fernando", "Grohk", "Evie", "Strix"], "mid", None, None, {"Bulldozer": 2})
    r1 = next(b for b in bz1["build"] if b["item"] == "Bulldozer")
    r2 = next(b for b in bz2["build"] if b["item"] == "Bulldozer")
    check("Bulldozer I -> II : rang et statut mis à jour", r1["rank"] == 1 and r2["rank"] == 2
          and r1["status"] == "upgrade" and r2["status"] == "done", f"{r1['status']} -> {r2['status']}")
    many = p.predict("Lian", ["Makoa"], "mid", None, None,
                     {"Wrecker": 1, "Haven": 1, "Nimble": 1, "Chronos": 1, "Life Rip": 1, "Veteran": 1})
    check("plus de 5 objets possédés : tous affichés", len(many["build"]) == 6)

    # ------------------------------------------------------------ summary
    section("Résumé")
    failed = [x for x in RESULTS if not x[1]]
    for name, ok, detail in RESULTS:
        print(f"  [{'OK' if ok else 'ÉCHEC'}] {name}" + (f"  - {detail}" if detail and not ok else ""))
    print(f"\n{len(RESULTS) - len(failed)}/{len(RESULTS)} vérifications réussies")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
