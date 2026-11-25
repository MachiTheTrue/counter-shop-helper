# Counter & Shop Helper — journal des versions

Build du jeu visée : **8.1.5839.0** (Wekono's Wake Hotfix 1). Auteur : **Machi Konno** (Discord : **machi.konno**).
Une section `## X.Y.Z — JJ/MM/AAAA` par version, la plus récente en haut. Le texte de chaque section sert de notes pour la GitHub Release du même numéro (`vX.Y.Z`). Le mod s'appelait « SmartCounter » avant la 0.6.1 : les anciennes sections gardent ce nom.

## 0.6.2 — 25/11/2026 (préparation à la publication)

### Auteur et crédits
- Auteur : **Machi Konno** partout. Il remplace l'ancienne graphie dans :
  - le manifeste (`[[mod.authors]] name = "Machi Konno"`, `link = "Discord: machi.konno"`) ;
  - le README du Launcher, Aide & infos, le pied de page, ce journal et le README du projet.
- Une seule ligne de crédit traduite : `about_credit = "Made by %s  ·  Discord: %s"`. Elle est remplie dans `main.lua` par `AUTHOR = "Machi Konno"` et `DISCORD = "machi.konno"`. On lit par exemple « Made by Machi Konno · Discord: machi.konno » ou « Créé par Machi Konno · Discord : machi.konno ».
  - Elle s'affiche dans l'onglet Aide & infos et en pied de page, dans la langue choisie.
  - La ligne « Discord » séparée et la clé `about_discord` sont retirées.
- `check_lua.py` refuse « mashi » dans tout texte affiché, et exige que `about_credit` contienne l'auteur et le Discord (2 × `%s`).

### Métadonnées publiques
- Vérifié dans `tempest-cli` et sur les 19 mods installés : le manifeste ne connaît que `id`, `name`, `version`, `icon`, `readme`, `dependencies` et `[[mod.authors]]` (`name`, `link`).
- Le résumé, les tags, la compatibilité et le changelog se donnent à la publication (`mod publish --summary --tags --patch --changelog`). Ils sont préparés dans `RELEASE.md`, avec la commande complète, qui n'est pas lancée.
  - Compatibilité : patch `8.1` (`build identify` : 8.1, « Wekono's Wake Hotfix 1 »).
  - Tags : `ui,overlay,hud,items,shop,counter,quality-of-life`, au format du dépôt.
- `src/README.md` est réécrit en description publique :
  - fonctions, touches, 8 langues ;
  - « lecture seule, pas d'achat automatique » ;
  - commandes console ;
  - ligne de crédit.

### Logo
- Nouveau `src/icon.png` : 512 × 512, art original, sans élément du jeu. Il est généré par `engine/make_logo.py` (Pillow, dessiné en 4× puis réduit).
  - Une tuile marine, un écusson doré et trois chevrons de rang aux couleurs du mod : vert = rang atteint, ambre = en cours, gris = pas acheté.
  - Un badge « + » bleu pointillé représente le 5e objet en option.
- Ajouté au manifeste par `icon = "icon.png"`, comme les autres mods. La signature et la vérification du paquet passent.

## 0.6.1 — 25/11/2026

### Nouveau nom : « Counter & Shop Helper »
- Le nom affiché change partout : titre du menu, astuce de lancement, notifications, tutoriel, aide, pied de page, `manifest.toml` (`name`) et README du Launcher. Le nom est gardé tel quel dans les 8 langues, comme un nom propre.
- Rien ne change en interne, pour rester compatible :
  - l'id `paladins-smartcounter-81`, donc `--replace` met à jour l'installation existante ;
  - les commandes `smartcounter*` ;
  - le préfixe de journal `[smartcounter]` ;
  - les identifiants des fenêtres ImGui (`###smartcounter_menu`, `##smartcounter_overlay`), donc la position du panneau est conservée ;
  - le dossier et le nom des paquets `Paladins-SmartCounter-8.1-<version>.tempest`.
- `check_lua.py` refuse l'ancien nom « SmartCounter » dans les textes affichés, et ne compte pas « Counter & Shop Helper » comme un mot anglais.
- Crédit Discord **machi.konno** inchangé : il apparaît dans l'onglet Aide & infos (« Discord : machi.konno ») et en pied de page.

### Achat automatique : désactivé, expliqué dans l'aide
- Revérifié : Tempest Scripting n'expose aucune fonction de boutique, ni aucun moyen d'intercepter une fonction du jeu (seulement `on_key` et `on_game_thread`). Les seuls achats possibles passeraient par les appels serveur bruts `ServerPurchaseItem` / `ServerUpgradeItem`, avec des identifiants de table de butin invérifiables.
- Il n'y a aucun réglage d'achat automatique dans les Paramètres (il n'y en a jamais eu dans le code).
- Aide, dans les 8 langues : la section s'intitule « Achat automatique : désactivé ». Elle explique que l'achat automatique est abandonné et sans réglage, faute de fonction de boutique sûre, et rappelle que le mod ne fait que lire le jeu.

### Inchangé (vérifié)
- Objets réglés à la main à 0 au démarrage ; largeur compacte sans vide à droite ; 4 objets + 1 en option en bleu pointillé, sans numéros ; couleurs par rang ; adaptation hors méta ; 8 langues natives. Tests : 71/71, `check_lua.py` OK.

## 0.6.0 — 25/11/2026

### Objets : 4 principaux + 1 en option
- Le build affiche 4 objets principaux, puis un 5e **en option** (selon la partie). Ce 5e a un fond bleu, un contour bleu pointillé et l'étiquette « option ». En vue détaillée : « 5e objet en option : à prendre selon la partie ».
- Les objets déjà achetés gardent une place parmi les 4 principaux (`CORE_SLOTS = 4`, moteurs Python et Lua). Il y a 2 nouveaux tests : 71/71.
- Les numéros d'ordre `1 2 3 4 5` sont retirés des pastilles, car l'ordre de lecture suffit.

### Réglage manuel et largeur
- Les rangs réglés à la main repartent de 0 (`-`) à chaque session et à chaque nouveau match, sauf si la lecture directe est active.
- Vue compacte : la largeur est calculée sur le retour à la ligne réel des pastilles (minimum 200 px). Le texte des menaces ne l'élargit plus, donc plus de vide à droite, quelle que soit la langue.
- Redimensionnement manuel : la largeur tirée au bord est retenue par vue (`overlay_w`). Le bouton « Largeur automatique » des paramètres revient au calcul automatique.

### Langues : 8
- Ajout de l'italien, du russe, du chinois simplifié, du japonais et du coréen, en plus de EN / FR / DE. Le sélecteur est désormais une liste déroulante.
- Les noms d'objets, de catégories, de rôles et de champions viennent des tables du jeu : `Lang_RUS`, `Lang_CHN`, `Lang_JPN` et `Lang_KOR`.
  - RU et JA sont complets.
  - En ZH et KO, il manque environ 120 textes aux tables du client (champions et objets récents), qui restent en anglais.
  - Le client 8.1 n'a pas de table italienne : en IT, les noms du jeu restent en anglais.
- Polices : un jeu de polices par écriture.
  - Pour le latin, le grec et le cyrillique : Segoe UI.
  - Pour ZH, JA et KO : une police Windows CJK fusionnée (Microsoft YaHei, Yu Gothic, Malgun Gothic, ou leurs replis). Elle est limitée aux glyphes réellement utilisés, pour garder l'atlas petit.
- `check_lua.py` vérifie :
  - les mêmes clés dans les 8 tables ;
  - aucun texte resté en anglais ;
  - aucun mot anglais dans les tables RU / ZH / JA / KO ;
  - des glyphes affichables.
- Langue détectée via Steam ou le jeu : `italian`, `russian`, `schinese`, `japanese`, `koreana` / ITA, RUS, CHN, JPN, KOR.

### Achat automatique : non inclus
- La 8.1 a bien les appels serveur (`TgPlayerController.ServerPurchaseItem(nLootTableId, nLootTableItemId, nItemCount)`, `ServerUpgradeItem`, `ServerSellItem`), mais :
  - ils prennent des identifiants de table de butin (`DATA_SET_LOOT_TABLES`), et leur correspondance avec les 20 objets de la boutique n'est pas univoque ; elle n'est pas vérifiable hors match ;
  - un mauvais identifiant partirait vers le serveur officiel, qui a des protections anti-flood ;
  - Tempest n'expose aucun moyen d'intercepter une fonction du jeu (seulement `on_key` et `on_game_thread`), donc impossible d'enregistrer les vrais paramètres d'un achat manuel pour les valider.
- Le mod reste en lecture seule : il n'envoie rien au serveur. L'aide le dit, et rappelle l'option d'achat automatique du jeu (`SetAutoPurchase`).

### Crédits
- « Discord : machi.konno » dans l'onglet Aide & infos et en pied de page, en plus de « Créé par Machi Konno ».

## 0.5.2 — 24/11/2026

Lecture directe des objets achetés et de leurs rangs, avec les vrais champs de la 8.1, relevés dans la table de script de `TgGame.upk` (`upk.exe ls`, copie dans `Work\Extracted\8.1.5839.0\upk\TgGame_ls.txt`). Dans la 8.1, un objet de boutique est un device : `ITEM_ID` = `DEVICE_ID` (Résilience 11683).
- Sources, dans l'ordre :
  1. `PRI.r_PlayerDevices` (tableau de `DeviceTeamInfo` : `CurrentDeviceId`, `Level`, `Power`…), la source principale et répliquée ;
  2. `InvManager` → `TgInventoryObject.m_InventoryData` (`nItemId`, `nLevel`) ;
  3. `PC.r_LastPurchasedItems` (`nItemId`, `nCount`) ;
  4. `PRI.r_TempItems` (`nDevId`, `nRank`) en repli. Les achats de la visite en cours peuvent faire monter le rang.
- Tableaux statiques : lus via la vue Struct du 1er élément. La disposition est vérifiée sur les champs nommés avant toute lecture brute, et chaque lecture est bornée par `memory.readable`. La taille du tableau est lue sur l'UProperty (ArrayDim), sinon plafonnée à 16.
- Rang : `Level` 1..3. Si un objet connu a `Level` 0, le champ est traité comme commençant à 0 (+1).
- La source est « disponible » dès que sa disposition est vérifiée, même sans objet acheté : « Tes objets » affiche alors « Lus en direct » au lieu de l'éditeur manuel. Sinon, le repli manuel reste, avec la ligne « La lecture directe démarre quand ton champion est en jeu ».
- Lecture à 1 Hz, et immédiate à l'ouverture du menu.
- Nouvelles commandes : `smartcounter_items` (journalise chaque source, ses propriétés et ses valeurs) et `smartcounter_items_watch` (une ligne de journal à chaque changement).

## 0.5.1 — 24/11/2026

Corrections de robustesse après un gel en fin de partie (écran noir, son actif, Échap sans effet). Ce gel s'est produit sous la 0.4.0 et aucune erreur Lua n'a été journalisée ; la cause n'est pas prouvée (d'autres mods de script sont installés).
- `ui.on_draw` tourne sur le thread du jeu : toute lecture d'objet y est donc risquée pendant la destruction du monde.
- ImGui protégé : chaque fenêtre, table ou onglet exécute son contenu sous pcall, donc une erreur ne saute plus le `End` correspondant. Les piles couleur / style / police / id / indentation sont comptées et rétablies en cas d'erreur.
- Fin de match (`GRI.bMatchIsOver`) ou GRI absent : nouvel état `match_over`. La détection ne parcourt plus les PRI ni les pawns, et la lecture des objets est suspendue (idem sans joueur local).
- Équipe : le champ `r_TaskForce` est lu d'abord ; l'appel `GetTaskForceNumber()` ne sert plus que de repli.
- Reste à faire : un chien de garde de durée par lecture, et une pause pendant les changements de carte.

## 0.5.0 — 24/11/2026

### Boutique : les 20 objets natifs, 5 recommandations
- Le catalogue suit la boutique réelle du client : 20 objets, 4 catégories × 5. Les noms FR/EN/DE viennent du jeu (Résilience / Resilience / Ohne Grenzen…).
  - Retirés : Cauterize, Illuminate, Kill to Heal (absents de cette boutique).
  - Ajoutés : Blindage (Guardian), Amassage (Hoard), Cavalier, Méditation, Bain de sang (Bloodbath), Élan funeste (Lethality), Frénésie (Trigger Scent).
- Chaque objet porte son `ITEM_ID`, ses identifiants alias (doublons de `assembly.dat`), sa classe d'inventaire et son index d'icône (`DATA_SET_ICONS.ICON_INDEX` = image du sprite `ItemCards`).
- Fin de la limite « 1 par catégorie » :
  - le build affiche toujours **5 objets** triés par priorité, plusieurs par catégorie possibles (décroissance ×0,7 par objet de plus dans une catégorie) ;
  - sous le seuil (40 % du meilleur ou 8 points), l'emplacement est **facultatif** : en bleu, « opt. », niveau I.
- Sans anti-soin en 8.1, le sustain adverse se contre en tuant vite (Frénésie, Mains agiles). La furtivité se contre avec Havre. Amassage vaut surtout en début de partie, Blindage pour les champions à bouclier.

### Achats en direct et adaptation
- Lecture des objets toutes les 0,25 s (0,5 s avant). Les identifiants alias et leurs classes sont reconnus : une montée de rang (Bulldozer I → II) met la pastille à jour aussitôt.
- Un objet acheté garde toujours sa place. S'il n'est pas recommandé, il est marqué **hors méta**.
- Les emplacements libres sont recalculés contre la compo adverse **et** en synergie avec ce qui est possédé : `SYNERGY`, rang possédé × 2. Exemple : Arrache-vie III fait entrer Mains agiles.
- Couleurs selon le rang : gris = pas acheté, ambre = rang en cours, vert = rang conseillé atteint.
- Le repli manuel devient une grille 4 × 5 avec un rang de 0 à III par objet.

### Menaces par compétence
- `extract_loc.py` lit les 5 compétences des 59 champions, avec leurs noms EN/FR/DE et leurs effets tirés des descriptions du jeu : 295 compétences, 149 avec un effet reconnu.
- La menace affiche la compétence du champion au lieu de « grappin » : « Makoa : Ancre de drague (étourdit) », « Inara : … (étourdit) ».

### Interface
- Raccourci **Ctrl+K** : bascule compact / détaillé (réassignable).
- Icônes de la boutique devant chaque pastille, avec une infobulle au survol (nom et description du jeu). Les icônes sont générées par `engine/make_icons.ps1` depuis `GameUI_SF.upk`.
- Libellés raccourcis :
  - « Ordre d'achat » ;
  - « Contres conseillés » ;
  - en vue détaillée, seule la raison du prochain achat est affichée (toutes dans le menu).
- Polices :
  - chargement hors du dessin, via `tempest.queue` ;
  - si le fichier TTF échoue, police intégrée à la bonne taille ;
  - si tout échoue, mise à l'échelle de la police par défaut. La 0.4 restait à « 0/6 ».

### Langues
- **Auto** suit la langue Steam (`appmanifest_444090.acf`), puis `ChaosEngine.ini`. Un client français restait en anglais parce que l'ini dit `INT`.
- Textes FR/DE sans anglais : « panneau » / « Einblendung », « dégâts explosifs », « tir instantané », « harcèlement », « Contres conseillés », « Konterwahl »… `check_lua.py` refuse désormais ces mots anglais.
- Les erreurs sont traduites à l'affichage. « Choisis ton champion » n'apparaît plus deux fois.
- Les données Lua ne gardent que EN/FR/DE : les noms PL/TR contenaient des caractères que la police ne dessine pas.

### Crédit et outils
- Auteur : **Machi Konno**, dans le manifeste, le menu, le README du Launcher et Aide → À propos.
- Nouvelle commande `smartcounter_dumpsdk` : liste des classes du jeu, pour trouver les vrais champs d'inventaire. `smartcounter_probe` donne aussi la source de la langue, la police, les icônes et le champ de rang utilisé.
- Tests :
  - Python : 69/69 ;
  - `check_lua.py` : OK ;
  - `sc_expected.lua` : 20 scénarios, dont achat hors méta, montée de rang et plus de 5 objets possédés.

## 0.4.0 — 24/11/2026

### Noms natifs du jeu (aucune traduction à la main)
- Les noms d'objets, leurs descriptions, les catégories de la boutique et les rôles viennent des tables de localisation de la 8.1 : `ChaosGame\Localization\<LOC>\Lang_<LOC>.dat` et `assembly.dat` (`DATA_SET_ITEMS.NAME_MSG_ID / DESC_MSG_ID`, `DATA_SET_BOTS.NAME_MSG_ID`, messages `PALADINS_ARCHETYPE_*`, `PALADINS_DEFENSE`…).
- Chaîne de génération : `engine/extract_loc.py` → `loc_8_1.json` → `build_champions_data.py` → `export_lua.py` → `sc_data.lua`.
- Résultat : 99 textes mappés en EN/FR/DE, plus ES/PT/PL gardés en référence. 0 repli sur l'anglais, 0 clé non mappée. Exemples : Resilience = Résilience / Ohne Grenzen ; Haven = Havre / Refugium. Les noms de champions sont identiques dans toutes les langues du jeu.
- Nouvelle langue **Auto**, par défaut pour une nouvelle installation. Elle suit `Language=` dans `Documents\My Games\Paladins\ChaosGame\Config\ChaosEngine.ini` : INT → en, FRA → fr, DEU → de, sinon anglais.

### Objets possédés (état live)
- Nouveau `lib/sc_player.lua`. Il lit, en lecture seule, 2 fois par seconde et sous `pcall`, les objets achetés par le joueur et leur rang.
  - Il passe par `Pawn.InvManager.InventoryChain`, puis par des listes candidates sur le PRI ou le pion.
  - Un objet est reconnu par un identifiant égal à l'`ITEM_ID` 8.1, ou par sa classe d'inventaire.
- **Ces noms de champs n'ont pas été vérifiés en jeu**, faute de dump SDK de la 8.1. `smartcounter_probe` écrit maintenant dans le log ce que chaque source expose réellement.
- Repli manuel dans l'onglet Partie : un objet et un rang (I à III) par catégorie. Il est remis à zéro à chaque nouvelle sélection de champion.
- Le build se met à jour à l'achat :
  - un objet possédé prend la place de sa catégorie, et le conseil d'origine reste affiché ;
  - chaque objet a un statut : acheté, à monter (II → III), pas acheté, ou possédé avec un autre conseil ;
  - le prochain achat est encadré.
- Le moteur Python a la même logique (`apply_owned`). L'autotest en jeu couvre 3 scénarios avec objets possédés, soit 15 au total.
- Le deck et le loadout ne sont pas lus : aucun champ n'est connu pour eux.

### Overlay
- Chaque objet est une « pastille » avec une barre de rang : verte pour le rang possédé par rapport au rang conseillé, rouge pour un objet pas encore acheté.
  - Les pastilles ne se coupent jamais : un numéro ne reste plus seul en bout de ligne.
- La largeur est calculée à partir du texte mesuré dans la langue active, avec des bornes selon l'écran. La hauteur s'ajuste au contenu, sans défilement, et la fenêtre reste dans l'écran.
- **Auto** n'est plus un simple choix fixe :
  - détaillé en sélection de champion et hors partie ;
  - en match, détaillé pendant 8 s après chaque changement (nouvel ennemi, achat, phase), puis compact ;
  - toujours compact sous 1280 px de large.
- **Vue détaillée allégée :** une seule raison par objet, 2 menaces, et plus de prévision de compo ni de ligne « vs » (elles restent dans le menu). Les descriptions officielles des objets sont dans le menu.
- Un badge indique le contexte :
  - **SÉLECTION** : tu peux encore choisir ou changer, et les contre-picks sont affichés ;
  - **EN MATCH** : champion verrouillé, seuls les objets sont proposés ;
  - **PRÉPARATION** : hors partie.

### Corrections
- Polices : `ui.add_font` était appelé au chargement, avant `ui.ready()`, ce que montrait le log de 0.3.0. Elles sont maintenant chargées à la première image prête, puis utilisées à l'image suivante, et le log l'indique.

## 0.3.0 — 24/11/2026
Corrige les retours d'une partie réelle en 8.1 : Io (Support) contre Makoa, Dredge, Evie, Furia et Androxus.

### Langues
- Anglais par défaut ; français et allemand disponibles. La langue se choisit dans Paramètres et dans la 1ʳᵉ étape du tutoriel. Elle s'applique tout de suite et est enregistrée (`lang`).
- Tous les textes, y compris les raisons, menaces, archétypes et contre-picks, sont dans `sc_lang.lua`. Le moteur Lua renvoie des clés, pas du texte.
- **Les « ? » sont corrigés :** les tirets longs, points de suspension, flèches et signes « ≤ » n'ont pas de glyphe dans la police ImGui par défaut. Tous les textes sont maintenant en Latin-1, et `L.sanitize` corrige ce qui passerait encore. Les valeurs inconnues affichent un texte explicite (« not detected », « mode unknown ») au lieu de « ? ».

### Objets (Io et Supports)
- **Un objet par catégorie, comme dans la boutique 8.1.** Avant, Io recevait Haven + Resilience + Blast Shields, trois objets de Défense impossibles à acheter ensemble.
- Sentinel passe en Utilitaire : grille 4×4, Master Riding absent des données 8.1.
- Nouvelle valeur pour le kit du joueur, avec des styles **tank / dps / flank / heal / aggro**. Un Support choisit Soin ou Agressif. Petits bonus par champion : Io, Jenos, Seris, Grohk.
- Support : Haven ×0,95, Blast Shields ×0,95, Resilience ×1,1 (avant 1,1 / 1,1 / 1,2). Resilience reste prioritaire contre le grappin et les contrôles de Makoa.
- Pour un soigneur, Sentinel ×0,5 et Kill to Heal ×0,6 : il fait peu d'éliminations.

### Interface
- Police Segoe UI, ou Arial si elle manque, en trois tailles réglables, plus une variante grasse pour les titres. Les polices sont gardées en mémoire entre deux rechargements.
- Thème sombre avec accents dorés : boutons, onglets, champs et barres arrondis.
- **Compact :** une ligne « BUY 1… 2… 3… 4… », une ligne « WATCH » avec la menace n°1, puis le nom de la n°2.
- **Détaillé :** plus condensé, tout le texte passe à la ligne et rien ne dépasse à droite. Largeur adaptée à la résolution et à la taille du texte.
- **Menu :** les ennemis sont en tableau sur 2 colonnes, les touches en tableau, et le style de jeu apparaît pour les Supports. Pied de page avec version et crédit.

### Clarté
- Nouvelle section **Menaces adverses**, avec la couleur selon le danger. Exemple : « Makoa : contrôle lourd (grappin / étourdissement), bouclier déployé -> Resilience ». Elle indique quand la réponse n'est pas dans ton build.
- Les **contre-picks sont « pour TOI »**, avec une phrase d'explication. Les **rôles conseillés** sont « les meilleurs rôles à jouer contre cette équipe ».
- **Pendant un match, les contre-picks sont masqués** : on ne peut plus changer de champion. Ils restent visibles en sélection, au lobby et en mode manuel.

### Crédit
- « Made by Machi Konno » apparaît dans Aide & infos → À propos, en pied de page du menu, et dans le README du Launcher.

### Vérifications
- `test_predictor.py` : 53/53, avec une nouvelle section 5 (boutique 4×4, build Io soin et agressif, menace Makoa, styles).
- Nouveau `check_lua.py`, sans interpréteur Lua. Il vérifie :
  - la structure de tous les fichiers ;
  - que les 188 clés sont présentes dans les 3 langues ;
  - les arguments de format ;
  - que toutes les clés utilisées existent ;
  - l'absence de caractères hors Latin-1.
- `sc_expected.lua` contient 12 scénarios, dont 3 pour Io, et vérifie aussi le build et la menace n°1.
- **Non vérifié :** l'exécution du Lua en jeu. Lancer `smartcounter_selftest`, qui doit donner 12/12.

## 0.2.0 — 24/11/2026
- Port Lua du moteur, détection automatique légère, overlay compact et détaillé, réglages persistants, touches modifiables, astuce et tutoriel, commandes `smartcounter_probe` et `smartcounter_selftest`.

## 0.1.0
- Squelette du mod et moteur Python (`engine\`).
