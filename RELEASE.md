# Counter & Shop Helper — fiche de publication

Ces champs ne vont **pas** dans `manifest.toml` : Tempest les prend au moment de `mod publish` (options `--summary`, `--tags`, `--patch`, `--changelog`). Le manifeste ne porte que `id`, `name`, `version`, `icon`, `readme`, `dependencies` et `[[mod.authors]]` (`name`, `link`), comme les mods publiés installés sur l'instance. La description longue est `src/README.md`, intégrée au paquet et affichée par le Launcher.

| Champ | Valeur |
|---|---|
| id | `paladins-smartcounter-81` (inchangé, pour que les mises à jour remplacent l'installation) |
| Nom | Counter & Shop Helper |
| Version | 0.6.2 |
| Auteur | Machi Konno (lien : `Discord: machi.konno`) |
| Type (`kind`) | scripts (Lua, dépend de `tempest-scripting>=1.0.0`) |
| Compatibilité | patch `8.1` (build 8.1.5839.0, « Wekono's Wake Hotfix 1 », d'après `tempest-cli build identify`) |
| Icône | `src/icon.png`, 512 × 512 (même format que les mods WOLPER et Tempest Scripting) |
| Paquet | `dist\Paladins-SmartCounter-8.1-0.6.2.tempest` |

**Résumé (une ligne, `--summary`) :**
> Shop and counter helper: 4 items to buy in order + 1 optional, live rank progress, enemy threats and counter-picks. 8 languages.

**Tags (`--tags`), au format du dépôt (minuscules, comme `ui,hud`, `quality-of-life`) :**
`ui,overlay,hud,items,shop,counter,quality-of-life`

**Changelog (`--changelog`) :**
> First public release. 4 core items + 1 optional, live item/rank reading, enemy ability threats, counter-picks in champion select, 8 languages with the game's own names. Read-only: no automatic buying.

## Comment fonctionnent publication, comptes et confiance (relevé local, tempest-cli 1.0.0)
- **Compte créateur** : il se crée sur le site `mods.lowrezstudio.com`. La CLI n'en crée pas. Une clé d'API `tm_live_...` se crée sur le site, sous *Settings*, et `mod login` l'enregistre sur ce PC.
- **Publication** : `mod publish` envoie un paquet **signé** au dépôt. Chaque version a un statut (`approved` pour toutes celles listées, donc il y a une modération). `--summary` est obligatoire pour un nouveau mod.
- **Signature** : chaque paquet est signé avec une clé PGP/RSA (`mod gen-key`). Le nom affiché du signataire est l'`--id` de la clé : la clé actuelle s'appelle `testmod81-dev`.
- **Vérification de la clé** : le site envoie un texte défi. `mod sign-text` le signe pour prouver que la clé est à toi.
- **Confiance (`trust`)** :
  - `first-party` seulement pour les clés de la liste officielle `https://cdn.lowrezstudio.com/keys/trusted.keys`, tenue par LowRez (`just keys-publish`) et intégrée à la CLI. Elle porte la mention « keys whose signature makes a mod's DLLs and Lua scripts trusted ». Aucune commande ne permet à un créateur d'y ajouter sa clé : il faut le demander à LowRez.
  - Les autres mods de la communauté sont publiés et `approved` avec `trust=unknown` (omega, LAMPOPO, Peluche, Mabci…).
  - Ta clé `testmod81-dev` n'est de confiance que **sur ce PC** (dossier `keys` du Launcher et `<jeu>\.tempest\keys`).
- **Révocation** : une clé ajoutée à `untrusted.keys` fait refuser ses mods à l'installation et les désactive au lancement. D'où : ne jamais diffuser le fichier `.key`.
- **Non vérifiable ici** :
  - l'écran exact du site ;
  - ce que voient les joueurs pour un mod Lua `trust=unknown` ;
  - le délai de modération.

  Documentation officielle (non lue ici) : `docs.lowrezstudio.com`.

## Publier, pas à pas (non fait : à lancer toi-même)
```powershell
$T="C:\FiF Project\Tools\TempestStudio\1.0.0-alpha.10"; $C="$T\tempest-cli.exe"
$G="D:\SteamLibrary\steamapps\common\Paladins"
$M="C:\FiF Project\Mods\Paladins-8.1\Mods\Paladins-SmartCounter-8.1"
$P="$M\dist\Paladins-SmartCounter-8.1-0.6.2.tempest"
$K="$env:USERPROFILE\.tempest-keys\machi-konno"   # nouvelle clé publique (étape 2)

# 1. Compte + clé d'API : sur mods.lowrezstudio.com (Settings -> créer une clé tm_live_...), puis :
& $C mod login tm_live_XXXXXXXX          # la clé reste sur ce PC ; ne la colle nulle part ailleurs

# 2. Clé de signature publique au nom de l'auteur (une seule fois ; garder une copie de sauvegarde du .key) :
& $C mod gen-key $K --id "Machi Konno" --game-path $G
& $C mod fingerprint "$K.pub"

# 3. Vérifier la clé sur le site : coller le texte défi affiché par le site, renvoyer la signature imprimée :
& $C mod sign-text "TEXTE_DU_DEFI" --key "$K.key"

# 4. Re-signer le paquet avec cette clé, puis contrôler :
& $C mod sign $P --key "$K.key"
& $C mod verify $P --game-path $G
& $C mod install $G $P --replace --defer   # « can be installed; nothing was written » = OK

# 5. Publier :
& $C mod publish $P --patch 8.1 --summary "Shop and counter helper: 4 items to buy in order + 1 optional, live rank progress, enemy threats and counter-picks. 8 languages." --tags "ui,overlay,hud,items,shop,counter,quality-of-life" --changelog "First public release. 4 core items + 1 optional, live item/rank reading, enemy ability threats, counter-picks in champion select, 8 languages with the game's own names. Read-only: no automatic buying."

# 6. Suivre le statut (pending / approved) et le niveau de confiance du signataire :
& $C mod search "paladins-smartcounter-81" --json
```

**Mises à jour suivantes :**
- monter `version` dans `src/manifest.toml` et `VERSION` dans `main.lua` ;
- `mod pack "$M\src" <nouveau paquet> --key "$K.key"`, puis `mod verify` ;
- `mod publish <paquet> --patch 8.1 --changelog "..."` : le résumé n'est plus obligatoire.

Toujours le même `id`, toujours la même clé.

**Statut first-party :** demander à LowRez d'ajouter l'empreinte de `machi-konno.pub` à `trusted.keys`. `mod sign-key-lists` est réservé aux signataires de LowRez : ne pas l'utiliser.

## GitHub : premier envoi et routine de mise à jour
Ce dossier est la racine du dépôt.
- `.gitignore` exclut les clés (`*.key`), les jetons et secrets, `dist/` et `*.tempest`, les caches Python, `Work/` et les fichiers temporaires.
- Les paquets signés ne vont **pas** dans git : ils sont joints aux GitHub Releases.
- Les clés restent dans `%USERPROFILE%\.tempest-keys\`, hors du dépôt.

### 0. Outils (une seule fois)
```powershell
winget install --id Git.Git -e
winget install --id GitHub.cli -e
# rouvrir PowerShell, puis :
gh auth login                      # connexion GitHub dans le navigateur
git config --global user.name "Machi Konno"
git config --global user.email "ID+PSEUDO@users.noreply.github.com"   # adresse « noreply » de GitHub (Settings > Emails)
```

### 1. Premier envoi
```powershell
Set-Location "C:\FiF Project\Mods\Paladins-8.1\Mods\Paladins-SmartCounter-8.1"
git init -b main
git add .
git status                         # contrôle : aucun .key, aucun .tempest, aucun __pycache__
git ls-files | Select-String '\.key$|\.tempest$|token|secret'   # doit ne rien afficher
git commit -m "Counter & Shop Helper 0.6.2"
gh repo create counter-shop-helper --public --source . --remote origin --push
git tag -a v0.6.2 -m "Counter & Shop Helper 0.6.2"
git push origin v0.6.2
$v="0.6.2"; $c=Get-Content -Raw -Encoding utf8 CHANGELOG.md
[regex]::Match($c,"(?ms)^## $([regex]::Escape($v)) .*?(?=^## |\z)").Value.Trim() | Set-Content -Encoding utf8 "$env:TEMP\notes-$v.md"
gh release create "v$v" "dist\Paladins-SmartCounter-8.1-$v.tempest" --title "Counter & Shop Helper $v" --notes-file "$env:TEMP\notes-$v.md"
```

Sans `gh` : créer un dépôt **vide** sur github.com (sans README ni .gitignore), puis :
```powershell
git remote add origin https://github.com/PSEUDO/counter-shop-helper.git
git push -u origin main
```
Joindre ensuite le `.tempest` à la Release depuis la page *Releases* du site.

### 2. À chaque nouvelle version (exemple : 0.6.3)
1. Dans le code :
   - monter `version` dans `src/manifest.toml` et `VERSION` dans `src/scripts/main.lua` ;
   - ajouter une section `## 0.6.3 — JJ/MM/AAAA` en haut de `CHANGELOG.md`.
2. Tests : dans `engine\`, lancer `build_champions_data.py`, `test_predictor.py`, `export_lua.py` et `check_lua.py`.
3. Paquet : `mod pack` avec **la même clé**, puis `mod verify`. Voir « Publier, pas à pas » plus haut.
4. Git et GitHub Release : voir ci-dessous.
```powershell
Set-Location "C:\FiF Project\Mods\Paladins-8.1\Mods\Paladins-SmartCounter-8.1"
$v="0.6.3"
git status
git add -A
git commit -m "v$($v): résumé en une ligne"
git push
git tag -a "v$v" -m "Counter & Shop Helper $v"
git push origin "v$v"
$c=Get-Content -Raw -Encoding utf8 CHANGELOG.md
[regex]::Match($c,"(?ms)^## $([regex]::Escape($v)) .*?(?=^## |\z)").Value.Trim() | Set-Content -Encoding utf8 "$env:TEMP\notes-$v.md"
gh release create "v$v" "dist\Paladins-SmartCounter-8.1-$v.tempest" --title "Counter & Shop Helper $v" --notes-file "$env:TEMP\notes-$v.md"
```
5. Tempest : `mod publish` du **même fichier** `.tempest` avec `--patch 8.1 --changelog "..."`. Le mod garde le même `id` (`paladins-smartcounter-81`) et la même clé.

> Si tu changes de clé de signature (étape 2 de « Publier, pas à pas »), re-signe le paquet **avant** de créer le tag et la Release : le fichier joint sur GitHub doit être exactement celui publié sur Tempest.
