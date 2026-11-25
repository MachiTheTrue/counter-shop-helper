"""Generates champions_data.json for Paladins 8.1.5839.0 (Wekono's Wake Hotfix 1).

Data sources:
  - VERIFIED (game data 8.1, assembly.dat + Lang_INT.dat exported with `upk mcts export`,
    DBExport 01/30/2025 paladins_live_build_8_1): roster, roles, base HP, shop item values,
    which champions spawn shield deployables or other deployables (with their HP).
  - ESTIMATED (to adjust by hand): meta_tier_8_1, gameplay tags other than shields/deployables.

Edit the CHAMPIONS table or the rules below, then rerun:
    python build_champions_data.py
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "champions_data.json")

ROLES = ("Frontline", "Damage", "Flank", "Support")
TAGS = ("shields", "deployables", "heavy_cc", "slows", "stealth", "high_mobility",
        "burst", "sustained_heal", "poke_sustain", "blaster", "hitscan")
TIERS = ("S+", "S", "A", "B", "C", "D")

# ---------------------------------------------------------------- shop items (verified, 0.5)
# The 8.1 in-game shop: 20 items, 4 categories x 5 (French client reference: Résilience, Sentinelle,
# Blindage, Bouclier choc, Havre / Agile, Amassage, Cavalier, Motivation, Chronos / Méditation,
# Arrache-vie, Revivifier, Vétéran, Bain de sang / Bulldozer, Mains agiles, Élan funeste, Frénésie,
# Broyeur). Several items exist twice in assembly.dat (old card + new shop row): `game_item_id` is
# the row used for names / descriptions, `alias_item_ids` the other rows carrying the same name
# (live detection accepts all of them). No Cauterize / Illuminate / Kill to Heal in this shop.
# Value = per level (level 1/2/3 = value x1/x2/x3); cost = per level. icon_index = frame of the
# game's "ItemCards" sprite (itemimagestack movie, GameUI_SF.upk) = DATA_SET_ICONS.ICON_INDEX.
ITEMS = {
    # Defense
    "Resilience": {"category": "Defense", "game_item_id": 11683, "alias_item_ids": [29446], "icon_index": 2,
                   "cost_per_level": 200, "per_level": 25,
                   "game_text": "Reduce the duration or effectiveness of Crowd Control effects by {25}%."},
    "Sentinel": {"category": "Defense", "game_item_id": 33075, "alias_item_ids": [], "icon_index": 20,
                 "cost_per_level": 225, "per_level": 200,
                 "game_text": "Gain a {200} health Shield for 5s on earning an Elimination. Stacks 3 times."},
    "Guardian": {"category": "Defense", "game_item_id": 13228, "alias_item_ids": [], "icon_index": 13,
                 "cost_per_level": 250, "per_level": 20,
                 "game_text": "Increase the effectiveness of Shields you create by {20}%."},
    "Blast Shields": {"category": "Defense", "game_item_id": 33618, "alias_item_ids": [], "icon_index": 12,
                      "cost_per_level": 275, "per_level": 6,
                      "game_text": "Reduce the Damage you take from Area of Effect attacks by {6}%."},
    "Haven": {"category": "Defense", "game_item_id": 13229, "alias_item_ids": [29436], "icon_index": 16,
              "cost_per_level": 300, "per_level": 6,
              "game_text": "Reduce the Damage you take from Direct attacks by {6}%."},
    # Utility
    "Nimble": {"category": "Utility", "game_item_id": 11826, "alias_item_ids": [29453], "icon_index": 6,
               "cost_per_level": 125, "per_level": 10, "game_text": "Gain {10}% Movement Speed."},
    "Hoard": {"category": "Utility", "game_item_id": 33081, "alias_item_ids": [], "icon_index": 25,
              "cost_per_level": 200, "per_level": 10,
              "game_text": "Gain {10} Credits on Elimination and 10 every {30|-10}s."},
    "Cavalier": {"category": "Utility", "game_item_id": 33083, "alias_item_ids": [11646, 29448], "icon_index": 3,
                 "cost_per_level": 225, "per_level": 15,
                 "game_text": "Increase your Mount Speed by {15}%. Gain a {100} health Shield after mounting."},
    "Morale Boost": {"category": "Utility", "game_item_id": 13165, "alias_item_ids": [29447], "icon_index": 10,
                     "cost_per_level": 250, "per_level": 10,
                     "game_text": "Increase your base Ultimate Charge Rate by {10}%."},
    "Chronos": {"category": "Utility", "game_item_id": 11723, "alias_item_ids": [29451], "icon_index": 8,
                "cost_per_level": 300, "per_level": 10,
                "game_text": "Reduce the Cooldown of all your abilities by {10}%."},
    # Healing
    "Meditation": {"category": "Healing", "game_item_id": 33082, "alias_item_ids": [], "icon_index": 1,
                   "cost_per_level": 175, "per_level": 2.5,
                   "game_text": "Heal for an additional {2.5}% of your max health every 0.25s when out of combat."},
    "Life Rip": {"category": "Healing", "game_item_id": 12010, "alias_item_ids": [29457], "icon_index": 9,
                 "cost_per_level": 225, "per_level": 20, "game_text": "Your weapon shots gain +{20}% Lifesteal."},
    # Two Rejuvenate rows: 14633 "healing output +10%" (most recently modified, purchasable) and 33517
    # "+10% healing received". 14633 is used; unverified in game.
    "Rejuvenate": {"category": "Healing", "game_item_id": 14633, "alias_item_ids": [33517], "icon_index": 21,
                   "cost_per_level": 250, "per_level": 10, "game_text": "Increase your healing output by {10}%."},
    "Veteran": {"category": "Healing", "game_item_id": 13224, "alias_item_ids": [29438], "icon_index": 15,
                "cost_per_level": 275, "per_level": 6, "game_text": "Increase your Base Maximum Health by {6}%."},
    "Bloodbath": {"category": "Healing", "game_item_id": 33070, "alias_item_ids": [], "icon_index": 11,
                  "cost_per_level": 300, "per_level": 360,
                  "game_text": "Kills True Heal you and Eliminations True Heal you & the ally who got the kill for {360} Health over 4s."},
    # Weapon
    "Bulldozer": {"category": "Weapon", "game_item_id": 13079, "alias_item_ids": [29458], "icon_index": 23,
                  "cost_per_level": 150, "per_level": 50,
                  "game_text": "Your weapon shots deal {50}% increased damage to Deployables, Pets and Illusions.",
                  "affects": "Murs d'Inara/Azaan, tourelles de Barik et Vivian, totem de Grohk, illusions de Ying/Evie, mines de Kinessa, pièges de Kasumi, grenades de VII, pièces de Saati, bombes de Bomb King, ailes de Nyx."},
    "Deft Hands": {"category": "Weapon", "game_item_id": 13235, "alias_item_ids": [], "icon_index": 7,
                   "cost_per_level": 200, "per_level": 20, "game_text": "Increase your Reload Speed by {20}%."},
    "Lethality": {"category": "Weapon", "game_item_id": 31100, "alias_item_ids": [29454], "icon_index": 19,
                  "cost_per_level": 200, "per_level": 20,
                  "game_text": "Increase your Movement Speed by {20}% and Jump Height by {60}% for 5s after getting an Elimination."},
    "Trigger Scent": {"category": "Weapon", "game_item_id": 33071, "alias_item_ids": [33079, 29461], "icon_index": 26,
                      "cost_per_level": 250, "per_level": 6,
                      "game_text": "Increase your inhand weapon damage dealt by {6}% for 5s after getting an Elimination."},
    "Wrecker": {"category": "Weapon", "game_item_id": 13071, "alias_item_ids": [29456], "icon_index": 18,
                "cost_per_level": 300, "per_level": 50,
                "game_text": "Your weapon attacks deal {50}% increased Damage to Shields.",
                "affects": "Boucliers déployés (classe TgDeploy_Shield*) : Fernando, Makoa, Khan, Barik (barricade), Ash (Siege Shield), Nyx, Vivian.",
                "does_not_affect": "Murs/déployables non-bouclier (Inara Impasse, Azaan Wall), boucliers spéciaux (Atlas)."},
}

# ---------------------------------------------------------------- champions
# name, role, base_hp (verified), meta tier (estimated), estimated tags,
# shield_kind ("standard" = Wrecker-effective shield deployable, "special", None),
# deployables (verified from DATA_SET_DEPLOYABLES / bots: [(name, hp or None)]), extra note
C = []
def champ(name, role, hp, tier, tags, shield_kind=None, deployables=(), note=None):
    C.append(dict(name=name, role=role, hp=hp, tier=tier, tags=list(tags),
                  shield_kind=shield_kind, deployables=list(deployables), note=note))

# Frontline
champ("Ash", "Frontline", 4500, "A", ["heavy_cc"], "standard", [("Siege Shield", 4750)])
champ("Atlas", "Frontline", 4000, "A", ["heavy_cc", "high_mobility"], "special",
      note="Ses protections ne sont pas des boucliers déployés : Wrecker n'a pas de valeur contre lui.")
champ("Azaan", "Frontline", 4500, "A", ["heavy_cc"], None, [("Azaan Wall", 2500), ("Azaan Wall Effect Field", 1200)],
      note="Son mur (Azaan Wall, classe TgDeploy_AzaanWall) est un déployable, pas un bouclier : Bulldozer oui, Wrecker non.")
champ("Barik", "Frontline", 3400, "B", ["blaster"], "standard",
      [("Barik Barricade", 4500), ("Turret", 1000), ("Flame Turret", 1800)],
      note="Barricade = bouclier (Wrecker) ; tourelles = familiers/déployables (Bulldozer). Les deux objets ont de la valeur.")
champ("Fernando", "Frontline", 4600, "S", ["blaster"], "standard", [("Fernando Shield", 8000)],
      note="Bouclier à 8000 PV dans les données 8.1 : cible n°1 de Wrecker.")
champ("Inara", "Frontline", 4700, "A", ["heavy_cc", "slows"], None,
      [("Impasse", 5000), ("Warder's Field", 1500)],
      note="Impasse (classe TgDeploy_GeometryBarrierTank, 5000 PV) est un mur déployable : Bulldozer oui, Wrecker non.")
champ("Khan", "Frontline", 4000, "S", ["heavy_cc"], "standard", [("Vanguard Shield", 4500)],
      note="Bouclier déployé (TgDeploy_VanguardShield, 4500 PV) : Wrecker ; prise de Khan = CC lourd : Resilience.")
champ("Makoa", "Frontline", 4500, "A", ["heavy_cc", "blaster"], "standard", [("Shell Shield", 4500)])
champ("Nyx", "Frontline", 4700, "B", ["heavy_cc"], "standard", [("Nyx Shield", 2500), ("Nyx Wings", 2500)],
      note="Bouclier (Wrecker) et ailes déployables (Bulldozer).")
champ("Raum", "Frontline", 4500, "B", ["heavy_cc", "sustained_heal"])
champ("Ruckus", "Frontline", 4000, "B", ["hitscan"],
      note="Bouclier de PV supplémentaire, pas un bouclier déployé : effet de Wrecker non vérifié.")
champ("Terminus", "Frontline", 4000, "B", ["burst"])
champ("Torvald", "Frontline", 3000, "B", ["slows"],
      note="Surbouclier de PV, pas un bouclier déployé : effet de Wrecker non vérifié.")
champ("Yagorath", "Frontline", 5750, "B", ["slows", "high_mobility"])
# Damage
champ("Betty la Bomba", "Damage", 2200, "A", ["blaster", "burst"])
champ("Bomb King", "Damage", 2200, "A", ["blaster", "burst", "heavy_cc"], None,
      [("Sticky Bomb", 200), ("Poppy Bomb", 200)])
champ("Cassie", "Damage", 2200, "B", ["heavy_cc", "poke_sustain"])
champ("Dredge", "Damage", 2200, "B", ["blaster", "burst", "slows"], None, [("Abyss Spike", None)])
champ("Drogoz", "Damage", 2200, "A", ["blaster", "burst", "high_mobility"])
champ("Imani", "Damage", 2200, "B", ["blaster", "slows"])
champ("Kinessa", "Damage", 2100, "A", ["hitscan", "poke_sustain", "slows"], None, [("Oppressor Mine", 200)])
champ("Lian", "Damage", 2100, "A", ["hitscan", "burst"])
champ("Octavia", "Damage", 2200, "B", ["burst"])
champ("Omen", "Damage", 2200, "B", ["burst", "high_mobility"])
champ("Saati", "Damage", 2100, "B", ["hitscan"], None, [("Saati Coin", 200), ("Saati Decoy", 1500)])
champ("Sha Lin", "Damage", 2150, "B", ["poke_sustain", "burst"])
champ("Strix", "Damage", 2150, "B", ["hitscan", "stealth", "poke_sustain"])
champ("Tiberius", "Damage", 2200, "A", ["burst", "high_mobility"])
champ("Tyra", "Damage", 2400, "B", ["hitscan", "slows"])
champ("Viktor", "Damage", 2200, "A", ["hitscan", "burst"])
champ("Vivian", "Damage", 2200, "B", ["hitscan"], "standard",
      [("Vivian Shield", 1500), ("Vivian Turret", 1600), ("Vivian Ward", 250)],
      note="Bouclier déployé (Wrecker) + tourelle et balise (Bulldozer).")
champ("Willo", "Damage", 2200, "B", ["burst", "high_mobility"])
# Flank
champ("Androxus", "Flank", 2100, "A", ["high_mobility", "burst"])
champ("Buck", "Flank", 2300, "B", ["high_mobility", "slows", "sustained_heal"])
champ("Caspian", "Flank", 2100, "A", ["high_mobility", "burst"])
champ("Evie", "Flank", 1800, "B", ["high_mobility"], None, [("Evie Illusion", 650)])
champ("Kasumi", "Flank", 2200, "B", ["high_mobility", "burst"], None, [("Kasumi Trap", 300)])
champ("Koga", "Flank", 2000, "B", ["high_mobility", "burst"])
champ("Lex", "Flank", 2200, "B", ["burst", "hitscan"])
champ("Maeve", "Flank", 1900, "A", ["high_mobility", "burst"])
champ("Skye", "Flank", 2000, "B", ["stealth", "burst"])
champ("Talus", "Flank", 1900, "B", ["high_mobility", "burst"])
champ("Vatu", "Flank", 1900, "A", ["high_mobility", "burst"])
champ("VII", "Flank", 1900, "A", ["high_mobility", "burst"], None, [("VII Grenades", 300)])
champ("Vora", "Flank", 2000, "B", ["high_mobility", "burst"])
champ("Zhin", "Flank", 2000, "B", ["high_mobility", "burst"])
# Support
champ("Corvus", "Support", 2200, "B", ["sustained_heal", "hitscan"])
champ("Furia", "Support", 2200, "B", ["sustained_heal", "burst"])
champ("Grohk", "Support", 2200, "B", ["sustained_heal"], None, [("Totemic Ward", 1250)],
      note="Totem de soin à 1250 PV : Bulldozer le détruit beaucoup plus vite.")
champ("Grover", "Support", 2300, "B", ["sustained_heal", "heavy_cc"])
champ("Io", "Support", 2200, "A", ["sustained_heal", "high_mobility"])
champ("Jenos", "Support", 2200, "A", ["sustained_heal", "high_mobility"])
champ("Lillith", "Support", 500, "B", ["sustained_heal"],
      note="PV de base à 500 dans les données (mécanique de sang propre au champion) : à vérifier en jeu.")
champ("Mal'Damba", "Support", 2300, "A", ["sustained_heal", "heavy_cc"])
champ("Moji", "Support", 2400, "C", ["sustained_heal"],
      note="Classé Support dans les données 8.1 (et non Flank) ; tags à confirmer.")
champ("Pip", "Support", 2200, "B", ["sustained_heal", "heavy_cc"])
champ("Rei", "Support", 2200, "A", ["sustained_heal"])
champ("Seris", "Support", 2200, "A", ["sustained_heal"])
champ("Ying", "Support", 2200, "B", ["sustained_heal"], None, [("Ying Illusion", 1500)],
      note="Illusions = cibles de Bulldozer (familiers/illusions).")


# Verified (DATA_SET_BOTS.PAWN_CLASS_RES_ID + BOT_ID, 8.1): in-game pawn class and bot id per champion.
# Used by the Lua mod to recognise champions live. Moji and "Evil Moji" share TgPawn_Rider.
PAWN = {
    "Androxus": ("TgPawn_Androxus", 2205), "Ash": ("TgPawn_Flak", 2404), "Atlas": ("TgPawn_Atlas", 2512),
    "Azaan": ("TgPawn_Azaan", 2548), "Barik": ("TgPawn_Barik", 2073), "Betty la Bomba": ("TgPawn_BombQueen", 2550),
    "Bomb King": ("TgPawn_BombKing", 2281), "Buck": ("TgPawn_Buck", 2147), "Caspian": ("TgPawn_Caspian", 2554),
    "Cassie": ("TgPawn_Cassie", 2092), "Corvus": ("TgPawn_Corvus", 2533), "Dredge": ("TgPawn_Dredge", 2495),
    "Drogoz": ("TgPawn_Drogoz", 2277), "Evie": ("TgPawn_Evie", 2094), "Fernando": ("TgPawn_Fernando", 2071),
    "Furia": ("TgPawn_Furia", 2491), "Grohk": ("TgPawn_Grohk", 2093), "Grover": ("TgPawn_Grover", 2254),
    "Imani": ("TgPawn_Imani", 2509), "Inara": ("TgPawn_BarrierTank", 2348), "Io": ("TgPawn_Druid", 2517),
    "Jenos": ("TgPawn_Astro", 2431), "Kasumi": ("TgPawn_Kasumi", 2555), "Khan": ("TgPawn_Vanguard", 2479),
    "Kinessa": ("TgPawn_Kinessa", 2249), "Koga": ("TgPawn_Koga", 2493), "Lex": ("TgPawn_Lex", 2362),
    "Lian": ("TgPawn_Princess", 2417), "Lillith": ("TgPawn_Vampire", 2551), "Maeve": ("TgPawn_Blades", 2338),
    "Makoa": ("TgPawn_Makoa", 2288), "Mal'Damba": ("TgPawn_MalDamba", 2303), "Moji": ("TgPawn_Rider", 2481),
    "Nyx": ("TgPawn_Nyx", 2560), "Octavia": ("TgPawn_Commander", 2540), "Omen": ("TgPawn_Omen", 2566),
    "Pip": ("TgPawn_Pip", 2056), "Raum": ("TgPawn_Raum", 2528), "Rei": ("TgPawn_Bunny", 2542),
    "Ruckus": ("TgPawn_Ruckus", 2149), "Saati": ("TgPawn_Saati", 2543), "Seris": ("TgPawn_Oracle", 2372),
    "Sha Lin": ("TgPawn_Longbow", 2307), "Skye": ("TgPawn_Skye", 2057), "Strix": ("TgPawn_Owl", 2438),
    "Talus": ("TgPawn_Demon", 2472), "Terminus": ("TgPawn_Lazarus", 2477), "Tiberius": ("TgPawn_Tiberius", 2529),
    "Torvald": ("TgPawn_Gauntlet", 2322), "Tyra": ("TgPawn_Tyra", 2314), "VII": ("TgPawn_Seven", 2549),
    "Vatu": ("TgPawn_Shadow", 2541), "Viktor": ("TgPawn_Viktor", 2285), "Vivian": ("TgPawn_Churchill", 2480),
    "Vora": ("TgPawn_Corrupter", 2536), "Willo": ("TgPawn_Fairy", 2393), "Yagorath": ("TgPawn_Yagorath", 2538),
    "Ying": ("TgPawn_Ying", 2267), "Zhin": ("TgPawn_Darklord", 2420),
}
EXTRA_BOT_IDS = {2590: "Moji"}   # "Evil Moji" skin bot


def clamp(v):
    return max(1, min(10, int(round(v))))


def recommended_items(c):
    """Items that answer this champion. `reason` = French text (Python reports);
    `reason_key` + `reason_args` = language-neutral form, translated by the Lua mod (EN/FR/DE)."""
    t = set(c["tags"])
    rec = []
    def add(item, weight, early, reason, key, args=None):
        rec.append({"item": item, "weight": clamp(weight), "early_game_priority": clamp(early), "reason": reason,
                    "reason_key": key, "reason_args": args or ""})
    shield_hp = max([hp or 0 for n, hp in c["deployables"] if "Shield" in n or "Barricade" in n] or [0])
    other_dep = [(n, hp) for n, hp in c["deployables"] if not ("Shield" in n or "Barricade" in n)]
    if c["shield_kind"] == "standard":
        add("Wrecker", 9 if shield_hp >= 4000 else 7, 7 if shield_hp >= 4000 else 5,
            f"Bouclier déployé ({shield_hp} PV) : +50/100/150 % de dégâts.", "shield", str(shield_hp))
    elif c["shield_kind"] == "special":
        add("Wrecker", 1, 1, "Bouclier spécial : Wrecker sans effet.", "special_shield")
    if other_dep:
        big = max([hp or 0 for _, hp in other_dep])
        names = ", ".join(n for n, _ in other_dep)
        add("Bulldozer", 9 if big >= 2000 else (7 if big >= 1000 else 5), 7 if big >= 1000 else 4,
            "Déployables/illusions : " + names + ".", "deployables", names)
        if c["name"] in ("Inara", "Azaan"):
            add("Wrecker", 1, 1, "Mur déployable, pas un bouclier : Wrecker sans effet.", "wall_not_shield")
    if "heavy_cc" in t:
        add("Resilience", 8, 7, "Contrôle lourd : -25/50/75 % de durée.", "heavy_cc")
    elif "slows" in t:
        add("Resilience", 6, 5, "Ralentissements : -25/50/75 % d'effet.", "slows")
    # No anti-heal in the 8.1 shop: sustain is answered by kill pressure (burst after eliminations).
    if "sustained_heal" in t:
        add("Trigger Scent", 7 if c["role"] == "Support" else 6, 3,
            "Soins continus, pas d'anti-soin en boutique 8.1 : dégâts après élimination.", "sustained_heal")
    elif "poke_sustain" in t:
        add("Trigger Scent", 4, 3, "Poke soutenu par les soins alliés.", "poke_sustain")
    if "stealth" in t:
        add("Haven", 6, 5, "Furtivité : embuscade en dégâts directs.", "stealth")
    if "blaster" in t:
        add("Blast Shields", 7, 5, "Dégâts de zone.", "blaster")
    if "hitscan" in t or ("burst" in t and c["role"] in ("Damage", "Flank")):
        add("Haven", 7 if "burst" in t else 6, 5, "Dégâts directs élevés.", "direct")
    if c["role"] == "Flank" or ("high_mobility" in t and "burst" in t):
        add("Sentinel", 5, 4, "Duels/snowball : bouclier de 200 PV après élimination.", "duel")
    if not rec:
        add("Haven", 4, 4, "Aucune menace spécifique : défense générale.", "generic")
    return rec


def notes(c):
    out = []
    if c["shield_kind"] == "standard":
        out.append("Bouclier = déployable de classe TgDeploy_Shield* dans les données 8.1 : affecté par Wrecker.")
    if c["shield_kind"] == "special":
        out.append("Pas de bouclier déployé dans les données 8.1 : boucliers spéciaux, Wrecker inefficace.")
    if "heavy_cc" in c["tags"] or "slows" in c["tags"]:
        out.append("Ses contrôles/ralentissements sont réduits par Resilience (25/50/75 %).")
    if c["note"]:
        out.append(c["note"])
    out.append("Changements de kit/talents propres à la 8.1 : non extraits, à compléter.")
    return out


LOC_PATH = os.path.join(HERE, "loc_8_1.json")


def load_loc():
    """Native game names (extract_loc.py). Missing file -> official English names only."""
    if not os.path.isfile(LOC_PATH):
        print(f"{LOC_PATH} absent : noms anglais seulement (lancer extract_loc.py)")
        return None
    with open(LOC_PATH, encoding="utf-8") as f:
        return json.load(f)


def build():
    loc = load_loc()
    names = set()
    champions = []
    for c in C:
        assert c["role"] in ROLES, c
        assert c["tier"] in TIERS, c
        assert c["name"] not in names, c["name"]
        names.add(c["name"])
        tags = list(c["tags"])
        if c["shield_kind"] == "standard":
            tags.append("shields")
        if any(not ("Shield" in n or "Barricade" in n) for n, _ in c["deployables"]):
            tags.append("deployables")
        for t in tags:
            assert t in TAGS, (c["name"], t)
        assert c["name"] in PAWN, f"pawn class manquante : {c['name']}"
        pawn_class, bot_id = PAWN[c["name"]]
        champions.append({
            "name": c["name"],
            "role": c["role"],
            "pawn_class": pawn_class,
            "bot_id": bot_id,
            "base_health_8_1": c["hp"],
            "meta_tier_8_1": c["tier"],
            "tags": sorted(set(tags)),
            "shield_kind": c["shield_kind"],
            "wrecker_effective": c["shield_kind"] == "standard",
            "deployables_8_1": [{"name": n, "health": hp} for n, hp in c["deployables"]],
            "8_1_notes": notes(c),
            "recommended_items_against": recommended_items(c),
        })
        if loc and c["name"] in loc["champions"]:
            champions[-1]["loc_name"] = loc["champions"][c["name"]]["name"]
            champions[-1]["abilities"] = loc["champions"][c["name"]].get("abilities", [])
    items = json.loads(json.dumps(ITEMS))
    for name, it in items.items():
        li = (loc or {}).get("items", {}).get(name)
        if li:
            it["loc_name"] = li["name"]
            it["loc_desc"] = li.get("desc", {})
            it["inventory_class"] = li.get("inventory_class")
            it["alias_inventory_classes"] = li.get("alias_inventory_classes", [])
    data = {
        "meta": {
            "game": "Paladins",
            "version": "8.1",
            "patch_name": "Wekono's Wake",
            "build": "8.1.5839.0 (Wekono's Wake Hotfix 1)",
            "build_check": "tempest-cli build identify : ID 8375037790896893010, match 6/6",
            "game_data_source": "assembly.dat + Lang_INT.dat (DBExport 01/30/2025, paladins_live_build_8_1)",
            "verified_fields": ["name", "role", "pawn_class", "bot_id", "base_health_8_1", "deployables_8_1", "shield_kind (standard)", "items.*"],
            "extra_bot_ids": {str(k): v for k, v in EXTRA_BOT_IDS.items()},
            "estimated_fields": ["meta_tier_8_1", "tags (sauf shields/deployables)", "recommended_items_against.weight/early_game_priority"],
            "tags": list(TAGS),
            "roles": list(ROLES),
            "tiers": list(TIERS),
            "item_levels": "Valeur et coût par niveau ; niveau 1/2/3 = x1/x2/x3.",
            "shop": "20 objets, 4 catégories x 5 ; plusieurs objets par catégorie autorisés (0.5).",
            "generated_by": "build_champions_data.py",
            "loc": {
                "source": loc["meta"]["source"] if loc else None,
                "ui_langs": loc["meta"]["ui_langs"] if loc else ["en"],
                "roles": loc["roles"] if loc else {},
                "categories": loc["categories"] if loc else {},
                "report": loc["report"] if loc else {"unmapped": ["loc_8_1.json absent"]},
            },
        },
        "items": items,
        "champions": champions,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"{OUT}: {len(champions)} champions, {len(ITEMS)} objets")


if __name__ == "__main__":
    build()
