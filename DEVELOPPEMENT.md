# Counter & Shop Helper — notes de développement

Notes techniques : architecture, sources des données, tests et validation en jeu. La présentation pour les joueurs est dans [README.md](README.md), l'historique dans [CHANGELOG.md](CHANGELOG.md), la publication (Tempest et GitHub) dans [RELEASE.md](RELEASE.md).

| | |
|---|---|
| Nom affiché | **Counter & Shop Helper** (dossier, id, nom des paquets, commande `smartcounter` et préfixe de log `[smartcounter]` inchangés) |
| id | `paladins-smartcounter-81` |
| Version | 0.7.0 (voir [CHANGELOG.md](CHANGELOG.md)) |
| Auteur | Machi Konno (Discord : machi.konno) |
| Type | Mod Lua (dépend de `tempest-scripting>=1.1.0` : API Game Data `assembly` / `lang`) + moteur Python hors jeu (`engine\`) |
| Signature | clé `machi-konno-v2`, empreinte `80AD2C078946FE3019DB48BCE76DD8DAD1490829` (la clé privée reste dans `%USERPROFILE%\.tempest-keys\`) |
| État | Python : 79/79. Lua hors jeu : `check_lua.py` OK et `run_lua_tests.ps1` (1480 vérifications, Lua 5.1 du jeu, objets du jeu simulés). **Non vérifié en jeu** : voir [À valider en jeu](#à-valider-en-jeu) |

## Ce qui vient du jeu, ce qui est livré
Le mod ne livre **aucun texte ni aucune image du jeu**. Ce qui peut être demandé au jeu pendant la partie l'est ; le reste est de la donnée de stratégie propre au mod.

| Donnée | Source à l'exécution | Repli si le jeu ne répond pas |
|---|---|---|
| Noms des champions, objets, compétences, rôles, catégories | identifiants de message lus dans `assembly.dat` au chargement (`sc_gamedata.lua` : `BOTS.NAME_MSG_ID`, `DATA_SET_BOT_DEVICES` par emplacement → `DEVICES.NAME_MSG_ID`, `ITEMS.NAME_MSG_ID` ; libellés de rôle et de catégorie par `lang.find("NAME", …)`), puis texte par `lang.message(id, ext)` dans les fichiers Lang du jeu (`sc_text.lua`), **dans la langue affichée par le mod** (ou celle du client avec le réglage `game_names`, pour les noms seulement). Les textes d'une langue sont lus d'un coup à sa première utilisation, gardés, et le fichier est libéré (`lang.unload`) | langue sans fichier Lang (italien) : nom interne anglais (champion, objet) ; texte du mod `role_*` / `cat_*` ; mot générique `tag_*` / `fx_*` pour une compétence |
| Descriptions des objets (infobulle, menu) | idem, `ITEMS.DESC_MSG_ID`, toujours dans la langue affichée | pas de description |
| Langue du client (UI en Auto) | `Object.GetLanguage()` sur `tempest.engine()` → `INT`, `FRA`, `JPN`…, relue chaque seconde. Paladins prend la langue du jeu de Steam au démarrage : la config du moteur reste à `INT` et `lang.language()` ne connaît qu'un argument `-language=` (sinon `INT`), d'où l'anglais en Auto sur un client français au 2e test 0.7.0 | `lang.language()`, puis anglais |
| Rôle des champions, rangs de la boutique | `assembly.dat` au chargement (`sc_gamedata.lua`) : tag « Roles » du bot (`BOTS.DATA_SET_BOT_TAGS`, `TAG_TYPE_VALUE_ID` 10591) ; un mode de device par rang (`DEVICES.DATA_SET_DEVICE_MODES`, 3 pour chaque objet 8.1). Puis `assembly.unload()`. Vérifié hors jeu : mêmes réponses que les anciennes données pour les 59 champions et les 20 objets | aucun : si les données du jeu ne se lisent pas, le mod reste éteint et le dit (toast + journal) |
| Mon champion, alliés, ennemis | `TgPawn.GetBotId()` (Buck 2147, Maeve 2338… dans le journal de la sonde), demandé aux seuls pawns de champion (ni illusion `TgPawn_Illusion`, ni charge du Siège `TgPawn_SiegeEngine_*`), retenu par classe de pawn ; un identifiant inconnu (0 pendant la mise en place du pawn) n'est pas retenu et redemandé à la lecture suivante. **Pas `GetArchetypeBotId()`** : il donne l'archétype du rôle (2573 Front Line … 2576 Flank), d'où « aucun ennemi » au premier test 0.7.0 ; équipe par `TgRepInfo_Player.GetTaskForceNumber()` | équipe : `IsFriendlyWithLocalPawn()` ; choix manuel dans l'onglet Partie |
| Sélection des champions | `myHUD.m_pMovie.m_UIDataManager.m_Match.MatchMembers[i].m_CurrentAllyCustomizeState.nBotId` | choix manuel |
| Objets possédés et rangs | `TgRepInfo_Player` du joueur, le chemin vérifié en partie (Siège, TDM, entraînement) : quels objets = emplacements `r_PlayerDevices[].CurrentDeviceId` (leur `Level` est le niveau des cartes, 0 pour un objet quel que soit son rang) ; quel rang = `r_TempItems[].nRank` (`TempItemInfo { nDevId, nRank, nCost }`). Les entrées sont des structures, lues directement (pas de `has()`). Base 0 ou 1 apprise pendant la session (un 0 lu → base 0, une valeur égale au rang max → base 1), **seulement sur les objets possédés** : un objet vendu peut rester dans `r_TempItems`. Rang plafonné à `max_rank` (3 pour toute la boutique 8.1). La chaîne d'inventaire du pawn n'est pas lue : le client ne la reçoit pas en partie | emplacements seuls (rang I) ; sinon grille manuelle |
| Phase, carte, mode | `GRI.ElapsedTime`, chemin de `WorldInfo` ; mode par la classe du GRI (`is_a TgRepInfo_Game_TeamDeathMatch` / `_Payload`), sinon par le préfixe des cartes 8.1 (classe de base) : Siège `SG_` / `SGA_` / `SGB_` / `S_` (`sg_icemines_p` en partie réelle), onslaught `ON_` et Roi de la colline `KOTH_`, TDM `TD_` / `TDM_`, entraînement | réglage manuel ; mode inconnu = neutre |
| PV max des ennemis | `TgRepInfo_Player.r_nHealthMaximum` (cartes comprises), règle « fragile » de Sentinel (`squishy_hp` = 2200) | aucun : le mod ne livre pas de PV, un ennemi choisi à la main ne compte pas comme fragile |
| Lecture des propriétés | `lib/sc_game.lua` : `Object:has(nom)` avant chaque lecture ; structures (emplacements, objets de la boutique) lues directement | — |

**Livré dans `sc_data.lua` (ASCII pur, aucun texte du jeu) :**
- les **identifiants** qui servent à interroger le jeu : un `bot_id` par champion, un identifiant d'objet (et ses alias) par objet de la boutique ;
- la **donnée de stratégie** du mod : tiers, tags, contres recommandés (objet, poids, clé de raison), effets des compétences par emplacement (`fx`, déduits hors jeu), catégories de la boutique, poids du moteur.

**Aucune donnée que le jeu possède** (0.7.0, vérifié par `check_lua.py`) : ni nom, ni identifiant de message, ni rôle, ni nombre de rangs, ni PV, ni PV de bouclier ou de déployable, ni coût, ni classe de pawn, ni identifiant de device. Les PV viennent du jeu en partie ; les raisons « bouclier » et « déployables » ne citent plus de nombre ; les notes d'objets tapées à la main (Résilience, Bulldozer, Sentinelle) sont remplacées par la description du jeu (`desc_msg`). `sc_data.lua` est écrit une table courte par ligne (1451 lignes au lieu de 4305).

**Une seule langue à l'écran (`TX:set_view`, au chargement puis à chaque image par `main.lua`).** Les noms viennent du fichier Lang de la langue affichée : une interface anglaise sur un client français montre les noms et descriptions anglais du jeu (`Lang_INT.dat`). Le réglage `game_names` garde les noms des champions, objets et compétences dans la langue du client ; rôles, catégories, effets et descriptions suivent toujours la langue du mod, donc jamais de phrase française dans un panneau anglais. Une langue sans fichier Lang (italien en 8.1) prend les mots du mod.

**Sources externes : aucune.** Pas de wiki, pas de site de fans, pas de copie de textes : ce serait du texte du jeu livré avec le mod, ce que la revue refuse. L'API publique de Hi-Rez (clé développeur requise) ne sert que le jeu actuel, pas la 8.1.5839.0, et le mod n'envoie rien sur le réseau. Les noms anglais de repli sont les identifiants internes des tables (`sc_data.lua`, ASCII), pas une traduction.

**Ne peut pas être demandé au jeu :**
- les **icônes** : `ui.load_image` n'ouvre que des fichiers image, et les icônes du jeu sont dans ses paquets, pas en fichiers ; les extraire pour les livrer est ce que la revue refuse. Les pastilles portent à la place une marque de couleur dessinée par catégorie (`G.CATEGORY_RGB`) ;
- la **donnée de stratégie** (tiers, tags, contres) : elle n'existe pas dans le jeu, c'est l'avis du mod.

**Réponses tardives, vides ou changeantes du jeu :**
- **Textes du jeu** : lus d'un coup par langue dans le fichier Lang (`lang.message`), à la première utilisation de la langue, puis le fichier est libéré : rien n'est demandé pendant le dessin, pas de réponse tardive à attendre. Un identifiant sans texte dans le fichier prend le mot du mod pour celui-là seulement ; une langue sans fichier Lang n'est demandée qu'une fois.
- **Polices** : chargées seulement par `tempest.queue` (jamais pendant le dessin). File jamais exécutée : 3 essais, puis police par défaut. Un jeu de police CJK construit avant que les noms passent dans la langue du client (réglage `game_names`) est reconstruit (2 fois au plus, 5 s après le précédent) ; l'ancien sert pendant le chargement. Un chargement en cours lors d'un rechargement à chaud repart de zéro.
- **Choix rapide et chargement** : en sélection et pendant le chargement, la détection lit 4 fois par seconde (`DET.FAST_INTERVAL`), sinon 1 fois. Après une sélection, tant que la partie charge (pas de joueur, ou carte sans GRI) l'état est `loading` pendant `DET.LOADING_GRACE` (60 s) au plus, avec le choix vu (relu dans la composition si le HUD l'a déjà) ; le contexte est « partie » (contre-choix masqués). En partie, avant que mon pawn existe, mon champion vient de la composition de cette partie (seulement celle de la sélection qui vient d'être vue). Une carte sans GRI et sans sélection avant (entraînement) est aussi `loading`, plus `match_over`.
- **Sélection des champions** : le HUD garde la composition de la dernière partie après celle-ci. Une composition (`dwMatchId` + noms des joueurs) déjà vue en partie reste « lobby » ; une nouvelle est une nouvelle sélection, et vide les rangs d'objets saisis à la main pour la partie précédente.
- **Carte** : au changement de `WorldInfo`, le cache champion par PRI est vidé (adresse réutilisée possible).
- **Mort** (pas de pawn) : mon champion et les objets lus en direct sont gardés tant que la carte ne change pas.
- **4 objets** : Paladins en porte 4 (`D.core_slots`). Le moteur (Python et Lua) marque `blocked` un emplacement non possédé quand 4 objets sont possédés, et ne le propose jamais comme prochain achat. Le panneau affiche « objets n/4 », atténue la pastille bloquée et la marque « emplacements pleins » ; la grille manuelle bloque un 5e objet.
- **En-tête** : champion (rôle), style, mode s'il est connu. La phase n'apparaît que si elle est réglée à la main (la phase automatique est une estimation par l'horloge : elle règle les conseils, ce n'est pas une information). Plus de « mode inconnu » ni de « * ».
- **Réglages** : les rangs d'objets manuels ne sont pas sauvegardés (ils valent pour une partie) ; les champions choisis à la main sont vérifiés au chargement (inconnu → vide, alias → nom canonique).
- **Touches** : le rappel de `tempest.on_key` et la commande ne font que mettre l'action en file ; elle s'exécute à l'image suivante, sur le fil de dessin.

Les identifiants viennent des données du jeu 8.1.5839.0 et ne changent qu'avec une mise à jour du jeu (relancer `extract_ids.py`).

## Structure
```
Paladins-SmartCounter-8.1\
├─ src\                         ← ce qui est empaqueté
│  ├─ manifest.toml
│  ├─ icon.png                  GÉNÉRÉ : logo du mod, 512×512, art original (engine\make_logo.py)
│  ├─ README.md                 texte affiché par le Launcher (anglais)
│  └─ scripts\
│     ├─ main.lua               assemble les modules et dessine l'image (aucune logique métier)
│     └─ lib\
│        ├─ sc_data.lua         GÉNÉRÉ : identifiants + données de stratégie (ne pas éditer)
│        ├─ sc_predictor.lua    port Lua de predictor.py (résultats structurés, sans texte)
│        ├─ sc_detect.lua       état de la partie par réflexion (lecture seule, 1 Hz)
│        ├─ sc_player.lua       objets et rangs du joueur local par réflexion (lecture seule, 1 Hz)
│        ├─ sc_text.lua         noms et descriptions demandés au jeu, dans sa langue
│        ├─ sc_lang.lua         textes propres au mod, 8 langues
│        ├─ sc_config.lua       réglages (tempest.config / tempest.save_config, écriture différée)
│        ├─ sc_keys.lua         raccourcis (tempest.on_key / off_key) et réassignation
│        ├─ sc_match.lua        entrées (manuel > auto) → prédiction, relancée seulement si elles changent
│        ├─ sc_fonts.lua        polices Windows via ui.add_font (glyphes CJK limités au texte affiché)
│        ├─ sc_gui.lua          ImGui protégé (piles rétablies après une erreur), palette, thème
│        ├─ sc_view.lua         le panneau (compact / détaillé) et les textes tirés d'un résultat
│        └─ sc_menu.lua         le menu (Partie, Paramètres, Aide) et le tutoriel
├─ engine\                      ← moteur Python (source de vérité, non empaqueté)
│  ├─ extract_ids.py            identifiants de message + effets des compétences → game_ids_8_1.json
│  ├─ game_ids_8_1.json         GÉNÉRÉ : identifiants seulement (aucun texte)
│  ├─ build_champions_data.py   tables de stratégie → champions_data.json (à éditer ici)
│  ├─ champions_data.json       GÉNÉRÉ : 59 champions et 20 objets
│  ├─ predictor.py              compo, build 4 + 1 en option, styles, synergies, menaces, contre-picks, modes
│  ├─ export_lua.py             écrit src\scripts\lib\sc_data.lua et tests\expected.lua
│  ├─ test_predictor.py         79 vérifications du moteur Python
│  ├─ check_lua.py              contrôles statiques du Lua (structure, 8 langues, clés, rien d'obsolète)
│  ├─ make_logo.py              dessine src\icon.png (Pillow)
│  └─ tests\
│     ├─ expected.lua           GÉNÉRÉ : résultats Python de 20 scénarios de référence
│     ├─ lua_tests.lua          tests Lua hors jeu (parité, modules, main.lua de bout en bout)
│     └─ run_lua_tests.ps1      les lance avec le Lua51.dll du jeu (32 bits)
├─ dist\                        ← paquets générés (ignorés par git, joints aux GitHub Releases)
├─ README.md · CHANGELOG.md · RELEASE.md · DEVELOPPEMENT.md
└─ release-notes.ps1            extrait la section d'une version de CHANGELOG.md
```

## Architecture
```
 extract_ids.py ─→ game_ids_8_1.json ─┐
 build_champions_data.py ─────────────┼─→ champions_data.json ─→ export_lua.py ─→ sc_data.lua
 predictor.py (source de vérité) ─────┘                                       └─→ tests\expected.lua

 sc_detect ── qui joue quoi, phase, mode ───┐
 sc_player ── objets et rangs ──────────────┼─→ sc_match ─→ sc_predictor ─→ résultat structuré
 onglet Partie ── choix manuels (prioritaires)┘                               │
                                                                              ▼
 sc_text (noms du jeu) + sc_lang (textes du mod) ───────────→ sc_view (panneau) / sc_menu (menu)
```
- **Une seule source de vérité : Python.** Le Lua ne contient que l'algorithme ; les tables viennent de `sc_data.lua`. Après toute modification de `predictor.py` ou des données, relancer `export_lua.py`. Si l'algorithme change, porter le changement dans `sc_predictor.lua` : `run_lua_tests.ps1` vérifie la parité sur les 20 scénarios.
- **Résultats sans texte.** Le prédicteur rend des clés (`reason.key`, `arch.key`, tags, compétences avec `name_msg`). Le texte est composé au dessin : noms du jeu par `sc_text`, phrases du mod par `sc_lang`. Un changement de langue s'applique donc à l'image suivante.
- **`main.lua`** construit le contexte `A` (modules, réglages, état menu / panneau), branche les touches et dessine : `TX:refresh` → langue → polices → astuce → lecture du jeu (seulement si quelque chose est affiché) → `MATCH:update` → panneau / menu → sauvegarde différée.
- **API Tempest utilisées :** `tempest.config`, `save_config`, `on_key`, `off_key`, `command`, `local_player`, `queue`, `toast`, `log`, `shared` ; `ui.on_draw`, `ui.add_font` (via `tempest.queue`, utilisable à l'image suivante), `ui.capture` (souris seulement menu ouvert), widgets ImGui, listes de dessin `ui.dl` / `ui.fg`. Lecture du jeu par réflexion uniquement (`obj.Champ`, `obj:Fonction()`, `:is_a`, vues `Array` / `Struct`) : pas de lecture mémoire brute, pas de FFI.
- **Lecture seule.** Le mod n'appelle aucune fonction qui modifie la partie et n'utilise pas les hooks (`tempest.on` / `before`). Il n'achète rien.
- **Coût.** Rien n'est lu tant que rien n'est affiché. Détection et objets : une lecture par seconde au plus (`PL:refresh` force une lecture à l'ouverture du menu). Traductions : en cache par identifiant, vidé au changement de langue. Largeur du panneau : en cache (clé = entrées, langue, police, version des textes).

## Boutique 8.1 et recommandations
- **20 objets, 4 catégories × 5** (clés internes, les noms affichés viennent du jeu) :

| Catégorie | Objets |
|---|---|
| Defense | Resilience, Sentinel, Guardian, Blast Shields, Haven |
| Utility | Nimble, Hoard, Cavalier, Morale Boost, Chronos |
| Healing | Meditation, Life Rip, Rejuvenate, Veteran, Bloodbath |
| Weapon | Bulldozer, Deft Hands, Lethality, Trigger Scent, Wrecker |

- **4 objets principaux + 1 en option.** Les objets achetés gardent leur place parmi les 4 principaux (`CORE_SLOTS`). Le 5e est toujours en option : fond bleu, contour pointillé, étiquette « option ».
- **Plusieurs objets d'une même catégorie sont permis.** Chaque objet supplémentaire d'une catégorie voit son score multiplié par 0,7 (`CATEGORY_DECAY`).
- **Principal ou facultatif :** principal si le score atteint 40 % du meilleur ou 8 points (`PRIMARY_SHARE`, `PRIMARY_MIN`), ou si c'est un objet clé du style (valeur de style ≥ 6).
- **Adaptation aux achats :** un objet acheté garde sa place (marqué **hors méta** s'il n'est pas recommandé) ; les emplacements libres sont recalculés avec la **synergie** (`SYNERGY`, × rang possédé × 2).
- **Ordre d'achat :** le prochain achat est encadré en or.
- **Pastilles :** gris = pas acheté, ambre = rang en cours, vert = rang conseillé atteint, fond bleu = option ; marque de couleur à gauche = catégorie (bleu Défense, violet Utilitaire, vert Soins, orange Arme).

## Menaces liées aux compétences
- `extract_ids.py` relève les 5 compétences de chaque champion (`DATA_SET_BOTS.DATA_SET_BOT_DEVICES` → `DATA_SET_DEVICES`) : emplacement, `device_id`, identifiant de message du nom, et un effet (`fx` : étourdit, attire, bouclier, soin…) déduit hors jeu de la description anglaise. Seuls les identifiants et l'effet sont gardés.
- Une menace affiche la compétence du champion au lieu d'un mot générique (`TAG_FX`) : « Makoa : Ancre de drague (étourdit) ». Sans nom du jeu, le mot générique du mod est utilisé.
- 295 compétences, 0 non mappée.

## Langues
- **Interface du mod : EN, FR, DE, IT, RU, ZH, JA, KO** (`sc_lang.lua`, mêmes clés partout, contrôlé par `check_lua.py`).
- **Auto** suit la langue du client telle que le moteur la donne (`Object.GetLanguage()` sur `tempest.engine()`, relue chaque seconde ; `lang.language()` seulement si le moteur ne répond pas). Aucun fichier n'est lu : les anciennes lectures de `appmanifest_444090.acf` (Steam) et de `ChaosEngine.ini` restent supprimées.
- **Noms du jeu** dans la langue affichée, lus dans les fichiers Lang du jeu (`lang.message`) ; réglage `game_names` : noms dans la langue du client (rôles, catégories, effets et descriptions suivent toujours la langue du mod). Langue sans fichier Lang : noms internes anglais.
- **Aucun nom du jeu écrit dans `sc_lang.lua`** : les phrases qui citent un objet ou un champion (archétypes, bouclier spécial, note du Broyeur) ont des `%s` remplis par `sc_view` avec les noms de `sc_text`. La raison « déployables » donne les PV du plus gros déployable, pas les noms des objets. `check_lua.py` refuse tout nom de champion ou d'objet tapé dans les textes.
- **Polices :** Segoe UI (Latin, Grec, Cyrillique), plus une police CJK Windows fusionnée quand l'interface **ou** les noms du jeu sont en chinois, japonais ou coréen. Seuls les glyphes affichés sont ajoutés (textes du mod + noms rendus par le jeu) ; le jeu de polices est reconstruit une fois quand les noms du jeu arrivent après le chargement.

## Tests
```powershell
cd "C:\FiF Project\Mods\Paladins-8.1\Mods\Paladins-SmartCounter-8.1\engine"
python -I -B -X utf8 extract_ids.py          # après une mise à jour du jeu seulement (exports dans Work\Extracted)
python -I -B -X utf8 build_champions_data.py # après une modification des tables
python -I -B -X utf8 test_predictor.py       # 79 vérifications, code de sortie 0 = OK
python -I -B -X utf8 export_lua.py           # TOUJOURS après une modification : met à jour le Lua
python -I -B -X utf8 check_lua.py            # contrôles statiques, doit finir par « OK »
powershell -ExecutionPolicy Bypass -File tests\run_lua_tests.ps1   # tests Lua, doit finir par « Lua tests: OK »
python -I -B -X utf8 predictor.py Lian Fernando Makoa Grohk --phase mid --mode tdm
```
- **`check_lua.py`** : structure des fichiers, mêmes clés dans les 8 langues, glyphes affichables, arguments de format, toutes les clés utilisées par `main.lua` et `lib\*.lua` (y compris les clés dynamiques), pas de jargon anglais dans les traductions, `sc_data.lua` en ASCII pur, et rien d'obsolète (pas de `icons\`, de `sc_expected`, de commandes de débogage, de lecture mémoire brute ni de fichiers Steam / du jeu).
- **`run_lua_tests.ps1`** lance `tests\lua_tests.lua` avec `Binaries\Win32\Lua51.dll` du jeu (Lua 5.1 ; Tempest Scripting utilise LuaJIT, compatible). `tempest`, `ui` et les objets du jeu sont simulés :
  - parité Lua / Python sur les 20 scénarios (noms et ordres exacts ; nombres à une unité près du dernier chiffre, car `round()` de Python arrondit les demis au pair) ;
  - `assembly` et `lang` simulés à partir de `engine/tests/game_ids.lua` (identifiants seulement, écrit par `export_lua.py`, jamais livré) ; lignes strictes comme les vraies (un champ mal tapé lève une erreur) ;
  - `sc_text`, `sc_player`, `sc_detect` sur des objets qui ont la forme des objets du jeu ;
  - `main.lua` de bout en bout : sans joueur, sélection des champions (jeu en français), partie (jeu en japonais, objets lus), fin de partie, données du jeu illisibles, les 8 langues de l'interface, les 3 onglets, réassignation d'une touche, sauvegarde différée, rechargement à chaud ;
  - pastilles : marque de catégorie toujours à l'intérieur, jamais sous le contour (2 px compris) ni sous le texte ; contour doré du prochain achat ; pastille bloquée atténuée ; « n/4 » ; en-tête sans mode inconnu ni phase automatique ; noms selon la langue affichée et le réglage `game_names` ; grille manuelle à 4 objets ;
  - cas limites : langue sans fichier Lang, identifiant sans texte, fichier lu une fois puis libéré, champion inconnu des données du jeu (tout ou rien), illusion qui répond le bot id d'un champion, préfixes de cartes 8.1, file de polices jamais exécutée, reconstruction CJK, retour au lobby après une partie, PRI réutilisé d'une carte à l'autre, mort, nouvelle partie, Échap pendant une réassignation, listes triées par nom affiché, réglages invalides ;
  - à chaque image : piles ImGui équilibrées, aucune erreur de dessin, aucune clé de traduction, code de format ou balise du jeu à l'écran, aucune variable globale créée.
- DLL ailleurs : `-Dll <chemin>` ou variable `PALADINS_LUA51`. Le rapport complet est dans `%TEMP%\smartcounter_lua_tests.txt`.

## À valider en jeu
Les tests hors jeu valident la logique sur des objets simulés. Les points suivants dépendent du vrai jeu :
1. `%TEMP%\tempest-scripting.log` : `[smartcounter] loaded v0.7.0 …` puis `fonts latin (queue): 6/6 loaded …`, sans `draw error`.
2. **Données du jeu** (`assembly`, `lang`, Tempest Scripting 1.1.0) : dans le journal, `[smartcounter] loaded v0.7.0 …` sans `game data unavailable`. Le bouton de rapport (onglet Partie) écrit `report: game data 59 champions, 20 items, max rank 3; texts INT (names INT) …`. Les noms du menu Partie sont ceux du jeu dans la langue affichée (anglais du jeu sur une interface anglaise, même sur un client français).
3. **Langue Auto** (`Object.GetLanguage()` du moteur) : sur un client français (langue du jeu Steam = français), l'interface du mod passe en français. Le rapport écrit `client language FRA (lang.language INT), UI fr (setting auto)`.
4. **Détection** (`GetBotId`, `GetTaskForceNumber`) : la ligne d'état de l'onglet Partie affiche « toi : … » en sélection, puis « n ennemi(s) vu(s) » en partie, et le mode (Siège sur `sg_*`). Le rapport écrit une ligne `report: game info …, my team …, players TgPawn_Buck bot 2147 tf 1 = Buck (enemy); …` : la charge du Siège et les illusions y sont sans champion.
5. **Objets** (`r_PlayerDevices` + `r_TempItems`) — journal `%TEMP%\tempest-scripting.log` : une ligne `status: ...` à chaque changement d'état, `items: live from the game (PRI.r_PlayerDevices + r_TempItems)` quand la lecture marche, puis une ligne `[smartcounter] items [PRI]: Resilience=2 (shop rank 2)` par achat / amélioration / vente (rien à chaque seconde, aucun « has no property »). Sur une carte d'entraînement, les objets sont lus aussi. Après un achat, l'onglet Partie affiche « Lus en direct depuis le jeu (PRI.r_PlayerDevices + r_TempItems) » et le rang monte dans la seconde quand on améliore l'objet (I → II → III, comme les pastilles du tableau des scores ; jamais « I/II ») ; un objet vendu disparaît. Sinon, la grille manuelle s'affiche : relever ce cas avec le bouton de rapport de l'onglet Partie (Ctrl+J). En mourant, les objets doivent rester affichés. Pour le détail brut, la sonde de dev **SmartCounter-LiveCheck-8.1** (hors paquet, jamais publiée).
6. **Après une partie** : de retour au lobby, la ligne d'état doit dire « lobby » et non « sélection des champions » ; à la partie suivante, la sélection est de nouveau reconnue (`dwMatchId` change bien d'une partie à l'autre).
7. **Polices CJK** : jeu en japonais, les noms des champions s'affichent sans carrés vides une fois le menu principal chargé (reconstruction après l'arrivée des noms).
8. **Pastilles** : la marque de catégorie ne touche plus le contour doré du prochain achat (ex. Havre III) ; l'objet en option a un contour bleu discret ; avec 4 objets, il est atténué et marqué « emplacements pleins », et l'en-tête des achats dit « objets 4/4 ».
9. **Langues** : client français, interface du mod en anglais → aucun nom français ; interface en français → noms du jeu. Le réglage « Garder les noms du jeu… » rétablit les noms du jeu.
10. **Choix rapide** : choisir son champion en 1 à 2 s puis lancer : la ligne d'état passe par « chargement de la partie » avec le champion choisi, jamais par « hors partie » ; en partie, le champion est reconnu avant même l'apparition du personnage.

### Modes de jeu (estimés, à ajuster)
| Mode | Effet |
|---|---|
| Siège et Classé | Shield-Heavy et Deployable-Heavy ×1,1 |
| Assaut | Zone ×1,15, Sustain ×1,1 |
| TDM | Dive/Flank ×1,15, Sustain ×1,15, boucliers et déployables ×0,9 |
| Entraînement | aucun |

### Données : ce qui est vérifié et ce qui est estimé
- **Vérifié dans les données du jeu 8.1.5839.0** (`assembly.dat`, `Lang_INT.dat`), côté moteur hors jeu (`engine/champions_data.json`, jamais livré) : champions, rôles, PV de base, classes de pawn, bot IDs, identifiants des objets et des messages, compétences et leurs effets, coûts et valeurs des objets. Le paquet n'en garde que les identifiants et les rôles.
- **Estimé, à ajuster à la main** dans `build_champions_data.py` / `predictor.py` : `meta_tier_8_1`, les tags, les poids, les styles, les synergies, les facteurs de mode.

### Règles d'objets de la 8.1 appliquées
| Objet | Coût/niv. | Effet par niveau (données 8.1) | Règle du moteur |
|---|---|---|---|
| Resilience | 200 | -25 % de contrôles et ralentissements | Priorité haute contre `heavy_cc` / `slows` |
| Wrecker | 300 | +50 % de dégâts aux boucliers | Seulement si `wrecker_effective` ; jamais pour Inara, Azaan ni Atlas |
| Bulldozer | 150 | +50 % contre déployables, familiers et illusions | Priorité haute contre `deployables`, pondérée par les PV |
| Sentinel | 225 | Bouclier de 200 PV pendant 5 s sur élimination | Bonus contre les cibles de 2200 PV max ou moins (lus en partie) ; ×0,5 pour un soigneur |
| Trigger Scent | 250 | +6 % de dégâts d'arme 5 s après une élimination | Réponse au sustain ; plus forte en fin de partie |
| Guardian | 250 | +20 % d'efficacité de tes boucliers | +5 points pour un champion à bouclier |
| Hoard | 200 | Crédits par élimination et dans le temps | ×1,3 en début, ×0,5 en fin de partie |
| Haven | 300 | -6 % de dégâts directs | Aussi contre la furtivité (embuscade) |

## Empaqueter, signer, vérifier, installer
```powershell
$T = "C:\FiF Project\Tools\TempestStudio\1.0.0-alpha.10"
$M = "C:\FiF Project\Mods\Paladins-8.1\Mods\Paladins-SmartCounter-8.1"
$G = "D:\SteamLibrary\steamapps\common\Paladins"
$K = "$env:USERPROFILE\.tempest-keys\machi-konno-v2"
$P = "$M\dist\Paladins-SmartCounter-8.1-0.7.0.tempest"
& "$T\tempest-cli.exe" mod fingerprint "$K.pub"          # doit afficher 80AD2C078946FE3019DB48BCE76DD8DAD1490829
& "$T\tempest-cli.exe" mod pack   "$M\src" $P --key "$K.key"
& "$T\tempest-cli.exe" mod verify $P --game-path $G
& "$T\tempest-cli.exe" mod install $G tempest-scripting --replace   # Tempest Scripting 1.1.0 (API Game Data), depuis le dépôt
& "$T\tempest-cli.exe" mod install $G $P --replace --defer   # vérification à blanc
& "$T\tempest-cli.exe" mod install $G $P --replace           # installation réelle
```
- Pour une mise à jour : numéro choisi selon la section « Versioning » de `RELEASE.md` (MAJOR.MINOR.PATCH, un seul pas après le dernier tag), écrit partout où il figure (`src\manifest.toml`, `VERSION` dans `main.lua`, section en tête de `CHANGELOG.md`, versions affichées dans `README.md` / `RELEASE.md` / ce fichier, ligne `report vX.Y.Z` des tests), vérifié par `check-version.ps1 X.Y.Z`, puis tests et réempaquetage.

## Prochaines étapes
1. Valider en jeu les 5 points ci-dessus et corriger selon les résultats (`MODE_MAPS` dans `sc_detect.lua` notamment).
2. Lever les doutes sur trois objets en double dans les données : Rejuvenate (14633 ou 33517), Cavalier (33083 ou 11646) et Trigger Scent (33071 ou 29461). La lecture accepte les deux identifiants ; le nom et la description affichés viennent du premier.
