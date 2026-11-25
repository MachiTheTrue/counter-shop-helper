# Counter & Shop Helper — notes de développement

Notes techniques : structure, moteur, données du jeu, tests et procédure en jeu. La présentation pour les joueurs est dans [README.md](README.md), l'historique dans [CHANGELOG.md](CHANGELOG.md), la publication (Tempest et GitHub) dans [RELEASE.md](RELEASE.md).

> Les scripts `engine\extract_loc.py` et `engine\make_icons.ps1` lisent les exports du jeu dans `..\..\Work\Extracted\8.1.5839.0\`, hors de ce dépôt (ignoré par git). Les fichiers qu'ils produisent (`loc_8_1.json`, `src\icons\`) sont versionnés, ce qui permet de reconstruire le reste sans le jeu.

| | |
|---|---|
| Nom affiché | **Counter & Shop Helper** (depuis la 0.6.1 ; dossier, id, nom des paquets et commandes `smartcounter*` inchangés) |
| id | `paladins-smartcounter-81` |
| Version | 0.6.2 (voir [CHANGELOG.md](CHANGELOG.md) ; fiche de publication : [RELEASE.md](RELEASE.md)) |
| Auteur | Machi Konno (Discord : machi.konno) |
| Type | Mod Lua (dépend de `tempest-scripting`) + moteur Python hors jeu (`engine\`) |
| Paquet | `dist\Paladins-SmartCounter-8.1-0.6.2.tempest` (signé, `trusted`), installé sur l'instance 8.1 le 25/11/2026 (remplace la 0.6.1) ; pas encore publié |
| État | Moteur Python testé (71/71), contrôles Lua hors jeu OK (`check_lua.py`). Le Lua n'est **toujours pas exécuté localement** : à valider en jeu avec `smartcounter_selftest` (20 scénarios) puis `smartcounter_probe`, qui inclut la lecture des objets |

```
Paladins-SmartCounter-8.1\
├─ src\                         ← ce qui est empaqueté
│  ├─ manifest.toml
│  ├─ icon.png                  GÉNÉRÉ : logo du mod, 512×512, art original (engine\make_logo.py)
│  ├─ README.md                 (texte affiché par le Launcher, en anglais)
│  ├─ icons\                    GÉNÉRÉ : 20 icônes de la boutique (art du jeu, 48×37)
│  └─ scripts\
│     ├─ main.lua               astuce, tutoriel, menu, panneau, thème/polices, touches, réglages, commandes
│     └─ lib\
│        ├─ sc_data.lua         GÉNÉRÉ : données + constantes du moteur (ne pas éditer)
│        ├─ sc_expected.lua     GÉNÉRÉ : résultats Python de 20 scénarios de référence
│        ├─ sc_predictor.lua    port Lua de predictor.py (algorithme seul, résultats structurés)
│        ├─ sc_lang.lua         textes d'interface EN / FR / DE / IT / RU / ZH / JA / KO
│        ├─ sc_detect.lua       détection auto légère (1 Hz, lecture seule)
│        └─ sc_player.lua       objets possédés + rangs du joueur local (4 Hz, lecture seule)
├─ engine\                      ← moteur Python (source de vérité, non empaqueté)
│  ├─ extract_loc.py            noms natifs 8.1 (objets, compétences, catégories, rôles) → loc_8_1.json
│  ├─ loc_8_1.json              GÉNÉRÉ : textes du jeu et rapport de mappage
│  ├─ build_champions_data.py   génère champions_data.json (tables à éditer ici)
│  ├─ champions_data.json       59 champions (+ pawn_class, bot_id, compétences) et les 20 objets de la boutique
│  ├─ predictor.py              compo, build de 4 objets + 1 en option, styles, synergies, menaces, contre-picks, modes
│  ├─ export_lua.py             écrit sc_data.lua et sc_expected.lua
│  ├─ make_logo.py              dessine src\icon.png (Pillow)
│  ├─ make_icons.ps1            exporte et réduit les icônes de la boutique (GameUI_SF.upk)
│  ├─ test_predictor.py         71 vérifications
│  └─ check_lua.py              contrôles hors jeu du Lua (structure, 8 langues, glyphes, icônes, jargon, anglais restant)
├─ dist\                        ← paquets générés (ignorés par git, joints aux GitHub Releases)
├─ .gitignore / .gitattributes  ← jamais de clé, de jeton, de paquet ni de cache dans git
├─ README.md                    ← présentation GitHub (joueurs)
├─ CHANGELOG.md                 ← notes de build, version par version
├─ RELEASE.md                   ← publication Tempest + routine GitHub
└─ DEVELOPPEMENT.md             ← ce fichier
```

## Boutique 8.1 et recommandations (0.5)
- **La boutique compte 20 objets, 4 catégories × 5.** Ce sont les noms natifs du client, relevés dans les données du jeu. Il n'y a ni Cauterize, ni Illuminate, ni Kill to Heal.

| Catégorie | Objets (FR · EN · DE) |
|---|---|
| Défense | Résilience · Resilience · Ohne Grenzen ; Sentinelle · Sentinel · Wachposten ; Blindage · Guardian · Wächter ; Bouclier choc · Blast Shields · Sprengschilde ; Havre · Haven · Refugium |
| Utilitaire | Agile · Nimble · Flinkheit ; Amassage · Hoard · Horten ; Cavalier · Cavalier · Kavalier ; Motivation · Morale Boost · Moralschub ; Chronos |
| PV rendus | Méditation · Meditation ; Arrache-vie · Life Rip · Lebensriss ; Revivifier · Rejuvenate · Verjüngung ; Vétéran · Veteran ; Bain de sang · Bloodbath · Blutbad |
| Arme | Bulldozer ; Mains agiles · Deft Hands · Flinke Hände ; Élan funeste · Lethality · Tödlichkeit ; Frénésie · Trigger Scent · Mündungsfeuer ; Broyeur · Wrecker · Zerstörer |

- **0.6 : 4 objets principaux + 1 en option.** Les objets achetés gardent leur place parmi les 4 principaux (`CORE_SLOTS`). Le 5e est toujours en option : fond bleu, contour pointillé, étiquette « option », sans numéro d'ordre.
- **Toujours 5 objets, triés par priorité.** Plusieurs objets d'une même catégorie sont permis. Chaque objet supplémentaire dans une catégorie voit son score de contre multiplié par 0,7 (`CATEGORY_DECAY`), pour éviter d'empiler les défenses.
- **Principal ou facultatif :**
  - un objet est principal si son score atteint 40 % du meilleur, ou 8 points (`PRIMARY_SHARE`, `PRIMARY_MIN`) ;
  - un objet clé du style est toujours principal (valeur de style ≥ 6, par exemple Revivifier pour un soigneur) ;
  - les autres emplacements sont **facultatifs** : affichés en bleu, avec la mention « opt. » et le niveau I.
- **Adaptation aux achats :**
  - un objet acheté garde toujours sa place ; s'il n'est pas recommandé, il est marqué **hors méta** ;
  - les emplacements libres sont recalculés : score de contre + **synergie** avec les objets possédés (`SYNERGY`, × rang possédé × 2) ;
  - exemple : Lian contre Makoa / Fernando / Grohk / Evie / Strix qui achète Arrache-vie III voit arriver **Mains agiles** (« synergie avec Arrache-vie »).
- **Ordre d'achat :** le prochain achat est encadré en or ; c'est le premier objet principal encore à acheter ou à monter.
- **Couleurs des pastilles :**
  - gris : pas acheté ;
  - ambre : rang en cours (rang possédé inférieur au rang conseillé) ;
  - vert : rang conseillé atteint ;
  - fond bleu : facultatif.
- **Icônes :** l'art de la boutique du jeu (`GameUI_SF.upk`, sprite `ItemCards`), affiché devant chaque pastille. Au survol, l'infobulle donne le nom et la description du jeu (souris disponible menu ouvert).

## Menaces liées aux compétences (0.5)
- `extract_loc.py` lit les 5 compétences de chaque champion :
  - source : `DATA_SET_BOTS.DATA_SET_BOT_DEVICES` → `DATA_SET_DEVICES` ;
  - emplacements : arme, 3 capacités, ultime ;
  - pour chacune : son nom EN/FR/DE et ses effets, mis en évidence par le jeu dans la description (`<font>Stun</font>`…) ou cités en clair (bouclier, soin, furtivité, mobilité, déployable).
- Une menace affiche la compétence du champion au lieu d'un mot générique (`TAG_FX`, `TAG_SLOT`). Par exemple :
  - « Makoa : Ancre de drague (étourdit) » ;
  - « Grohk : Totem de guérison (soigne, déployable) » ;
  - « Lian : dégâts explosifs (*ultime*) ».
- Sur 295 compétences, 149 ont un effet reconnu.

## Langues (0.5, 8 langues en 0.6)
- **0.6 : EN, FR, DE, IT, RU, ZH, JA, KO.**
  - Les noms du jeu viennent de `Lang_RUS`, `Lang_CHN`, `Lang_JPN` et `Lang_KOR`. En ZH et KO, environ 120 textes récents manquent au client et restent en anglais.
  - Il n'y a pas de table italienne dans le client 8.1 : en IT, les noms du jeu sont en anglais.
  - Polices CJK Windows fusionnées, limitées aux glyphes utilisés.
- **Langue Auto :**
  - source principale : la langue du client Steam (`steamapps\appmanifest_444090.acf`, `"language" "french"`) ;
  - repli : `Language=` de `ChaosEngine.ini`, qui vaut `INT` même sur un client français (cause du blocage en anglais de la 0.4).
- **Aucune langue mélangée :**
  - plus de « overlay », « build », « burst », « hitscan », « poke », « dive »… dans les textes FR/DE ;
  - `check_lua.py` refuse ces mots ;
  - les noms d'objets, de catégories, de rôles et de compétences viennent du jeu.
- **Erreurs traduites à l'affichage :** un changement de langue s'applique tout de suite. « Choisis ton champion » n'apparaît plus deux fois.

## Noms natifs et objets possédés (0.4, complété en 0.5)
- **Noms du jeu, jamais traduits à la main.** `extract_loc.py` lit les exports `upk mcts export` de `assembly.dat` et de `Lang_<LOC>.dat`, rangés dans `Work\Extracted\8.1.5839.0\`. Dernier rapport : 0 non mappé, 0 repli sur l'anglais.
- **Objets possédés :** `sc_player.lua` lit l'inventaire du pion, ou des listes candidates. Il reconnaît un objet :
  - par son `ITEM_ID` ou l'un de ses **alias** (plusieurs objets existent deux fois dans `assembly.dat`, par exemple Résilience 11683 / 29446) ;
  - ou par sa classe d'inventaire.
  - Lecture toutes les 0,25 s, pour qu'une montée de rang (Bulldozer I → II) s'affiche aussitôt.
  - Les noms de champs restent des hypothèses : `smartcounter_probe` les liste en jeu, et `smartcounter_dumpsdk` écrit la liste des classes du jeu pour les vérifier.
  - Sinon, repli manuel dans l'onglet Partie : grille 4 × 5, un rang de 0 à III par objet.

## Architecture
```
champions_data.json ─┐
predictor.py ────────┼─ export_lua.py ─→ sc_data.lua (données + constantes)
                     └────────────────→ sc_expected.lua (résultats attendus)
                                             │
 sc_detect.lua ── état (moi, alliés, ennemis, carte, mode, phase) ──┐
 sc_player.lua ── objets possédés + rangs ─────────────────────────────┤
 réglages manuels (onglet Partie) ── prioritaires, l'auto complète ────┼─→ sc_predictor.lua ─→ panneau / menu
                                                                     │   (relancé seulement si les entrées changent)
```
- **Une seule source de vérité : Python.** Le Lua ne contient que l'algorithme. Les tables (archétypes, facteurs, synergies, contre-picks, tiers) viennent de `sc_data.lua`. Après toute modification de `predictor.py` ou des données, relancer `export_lua.py`. Si l'algorithme lui-même change, porter le changement dans `sc_predictor.lua`.
- **Parité vérifiée en jeu** par `smartcounter_selftest`, qui compare 20 scénarios à `sc_expected.lua` :
  - éléments comparés : build, type d'emplacement (principal, facultatif, hors méta), statut, menace n°1 et ses compétences ;
  - tolérances : ±1 % sur les probabilités, ±0,15 sur les scores d'objets.

## Fonctionnalités
### Astuce et tutoriel
- **Astuce discrète** une fois par lancement du jeu, environ 10 s en haut de l'écran. Elle se désactive dans Paramètres.
- **Mini-tutoriel** de 4 étapes à la première ouverture du menu. Il ne bloque rien et se revoit depuis Paramètres.

### Touches par défaut, toutes sur un clavier 60 %, sans pavé numérique
| Action | Touche |
|---|---|
| Ouvrir ou fermer le menu | `Ctrl+J` |
| Afficher ou masquer le panneau | `Ctrl+H` |
| Ouvrir les paramètres | `Ctrl+O` |
| Verrouiller ou déverrouiller le panneau | `Ctrl+L` |
| Basculer compact / détaillé (0.5) | `Ctrl+K` |

- Les touches se réassignent dans Paramètres → Touches. Un modificateur est obligatoire, sauf pour F1–F12. Une combinaison déjà prise est refusée.

### Affichage
- **Compact :** les 5 pastilles avec icône et barre de rang, la menace principale avec sa compétence, et les contres hors match.
- **Détaillé :**
  - le badge de contexte ;
  - les 5 objets avec catégorie, statut, mentions facultatif / hors méta / synergie ;
  - la raison du prochain achat seulement ;
  - 2 menaces ;
  - les contres hors match.
- **Auto (par défaut) :** détaillé hors match ; en match, détaillé 8 s après chaque changement, puis compact. `Ctrl+K` force l'un ou l'autre.
- **Taille du panneau :**
  - la largeur est mesurée sur le texte de la langue active et les icônes, avec des bornes selon l'écran ;
  - la hauteur s'ajuste au contenu ;
  - les pastilles ne passent à la ligne qu'entre deux pastilles.
- **Polices :**
  - Segoe UI, chargée une fois l'interface prête, hors du dessin (`tempest.queue`) ;
  - sinon, police intégrée du jeu à la bonne taille ;
  - sinon, mise à l'échelle de la police par défaut (`igSetWindowFontScale`), pour que la taille du texte fonctionne toujours.

### Détection automatique et repli manuel
| Donnée | Source | Statut |
|---|---|---|
| Mon champion | classe du pawn local (`TgPawn_Princess` → Lian), sinon mon pick en sélection | table pawn vérifiée dans les données 8.1 ; lecture à confirmer en jeu |
| Alliés en sélection | `myHUD.m_pMovie.m_UIDataManager.m_Match.MatchMembers[i].m_CurrentAllyCustomizeState.nBotId` | chemin utilisé par le mod *while-you-wait* |
| Ennemis en match | `WorldInfo.GRI.PRIArray` → `r_PawnOwner` (classe du pawn) | un ennemi apparaît une fois son pawn répliqué |
| Carte / mode | préfixe du chemin de `WorldInfo`, règles `MODE_RULES` | **heuristique** |
| Phase | `GRI.ElapsedTime` : moins de 240 s early, moins de 540 s mid, sinon late | à confirmer |
| Objets / rangs | `Pawn.InvManager.InventoryChain`, sinon listes du PRI ou du pawn | **noms de champs non vérifiés** (voir plus bas) |

## À faire en jeu (première session)
1. Installer le paquet (voir plus bas), lancer l'instance 8.1. Dans `%TEMP%\tempest-scripting.log`, vérifier `[smartcounter] loaded v0.6.2 … lang … (game fr via steam:french)` et la ligne `fonts (…)`.
2. Dans la console : `smartcounter_selftest`. Résultat attendu : **20/20 OK**.
3. En partie, après avoir acheté un objet puis monté son rang : `smartcounter_probe`, et me renvoyer les lignes `[smartcounter] probe …`. Elles disent quel champ porte l'identifiant et le rang de l'objet.
4. Si la lecture des objets échoue : `smartcounter_dumpsdk`, puis m'indiquer le dossier `types\sdk` du mod pour que je cherche les vrais champs d'inventaire.

## Moteur Python (`engine\`)
```powershell
cd "C:\FiF Project\Mods\Paladins-8.1\Mods\Paladins-SmartCounter-8.1\engine"
python -I -B -X utf8 extract_loc.py          # noms natifs + compétences (après une mise à jour du jeu)
python -I -B -X utf8 build_champions_data.py # régénérer le JSON après modification des tables
python -I -B -X utf8 test_predictor.py       # 69 vérifications, code de sortie 0 = OK
python -I -B -X utf8 export_lua.py           # TOUJOURS après une modification : met à jour le Lua
python -I -B -X utf8 check_lua.py            # contrôles hors jeu du Lua
powershell -ExecutionPolicy Bypass -File make_icons.ps1   # icônes (une fois par version du jeu)
python -I -B -X utf8 predictor.py Lian Fernando Makoa Grohk --phase mid --mode tdm
```

### Modes de jeu (estimés, à ajuster)
| Mode | Effet |
|---|---|
| Siège et Classé | Shield-Heavy et Deployable-Heavy ×1,1 |
| Assaut | Zone ×1,15, Sustain ×1,1 |
| TDM | Dive/Flank ×1,15, Sustain ×1,15, boucliers et déployables ×0,9 |
| Entraînement | aucun |

### Données : ce qui est vérifié et ce qui est estimé
- **Vérifié dans les données du jeu 8.1.5839.0** (`assembly.dat` + `Lang_*.dat`) :
  - champions, rôles, PV de base, classes de pawn et bot IDs ;
  - les 20 objets : noms, descriptions, valeurs, coûts, icônes ;
  - compétences et effets.
- **Estimé, à ajuster à la main** dans `build_champions_data.py` / `predictor.py` :
  - `meta_tier_8_1` et les tags ;
  - les poids, les styles, les synergies ;
  - les facteurs de mode.

### Règles d'objets de la 8.1 appliquées
| Objet | Coût/niv. | Effet par niveau (données 8.1) | Règle du moteur |
|---|---|---|---|
| Résilience | 200 | -25 % de contrôles et ralentissements | Priorité haute contre `heavy_cc` / `slows` |
| Broyeur | 300 | +50 % de dégâts aux boucliers | Seulement si `wrecker_effective` ; jamais pour Inara, Azaan ni Atlas |
| Bulldozer | 150 | +50 % contre déployables, familiers et illusions | Priorité haute contre `deployables`, pondérée par les PV |
| Sentinelle | 225 | Bouclier de 200 PV pendant 5 s sur élimination | Bonus contre les cibles de 2200 PV ou moins ; ×0,5 pour un soigneur |
| Frénésie | 250 | +6 % de dégâts d'arme 5 s après une élimination | Réponse au sustain (tuer vite, plus d'anti-soin en 8.1) ; plus forte en fin de partie |
| Blindage | 250 | +20 % d'efficacité de tes boucliers | +5 points pour un champion à bouclier |
| Amassage | 200 | Crédits par élimination et dans le temps | ×1,3 en début, ×0,5 en fin de partie |
| Havre | 300 | -6 % de dégâts directs | Aussi contre la furtivité (embuscade) |

## Variables
```powershell
$T = "C:\FiF Project\Tools\TempestStudio\1.0.0-alpha.10"
$M = "C:\FiF Project\Mods\Paladins-8.1\Mods\Paladins-SmartCounter-8.1"
$G = "D:\SteamLibrary\steamapps\common\Paladins"
```

## Empaqueter, signer, vérifier, installer
```powershell
& "$T\tempest-cli.exe" mod pack   "$M\src" "$M\dist\Paladins-SmartCounter-8.1-0.6.2.tempest" --key "$env:USERPROFILE\.tempest-keys\testmod81.key"
& "$T\tempest-cli.exe" mod verify "$M\dist\Paladins-SmartCounter-8.1-0.6.2.tempest" --game-path $G
& "$T\tempest-cli.exe" mod install $G "$M\dist\Paladins-SmartCounter-8.1-0.6.2.tempest" --replace --defer   # vérification à blanc
& "$T\tempest-cli.exe" mod install $G "$M\dist\Paladins-SmartCounter-8.1-0.6.2.tempest" --replace           # installation réelle
```
- Pour une mise à jour : augmenter `version` dans `src\manifest.toml`, réempaqueter, puis réinstaller avec `--replace`.

## Prochaines étapes
1. Valider en jeu avec selftest et probe. Ensuite, corriger les champs d'objets (`ID_FIELDS`, `RANK_FIELDS`, `LIST_FIELDS` dans `sc_player.lua`) et `MODE_RULES` selon les résultats.
2. Lever les doutes sur trois objets en double dans les données : Revivifier (14633 « soins prodigués » ou 33517 « soins reçus »), Cavalier (33083 ou 11646) et Frénésie (33071 Trigger Scent ou 29461 Frenzy). La lecture live accepte les deux identifiants, mais la description affichée est celle du premier.
3. Option : tests Lua hors jeu avec `lupa` (`pip install lupa`), pour lancer le selftest sans Paladins.
