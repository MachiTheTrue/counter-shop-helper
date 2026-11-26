# Releasing Counter & Shop Helper

How to ship a new version to **GitHub Releases** and the **Tempest mod repository**, keeping the same mod ID and signing key every time.

**Contents:** [Listing details](#listing-details) · [How Tempest publishing works](#how-tempest-publishing-works) · [One-time setup](#one-time-setup) · [First GitHub push](#first-github-push) · [Every new version](#every-new-version) · [Safety rules](#safety-rules)

## Listing details
| Field | Value |
|---|---|
| Mod ID | `paladins-smartcounter-81`: **never change it**, so updates replace the installed version |
| Name | Counter & Shop Helper |
| Current version | 0.7.0 |
| Author | Machi Konno (link: `Discord: machi.konno`) |
| Kind | scripts (Lua), depends on `tempest-scripting>=1.1.0` (Game Data API) |
| Compatibility | patch `8.1` (build 8.1.5839.0, "Wekono's Wake Hotfix 1", from `tempest-cli build identify`) |
| Icon | `src/icon.png`, 512 × 512 (original artwork; the package ships no game art or game text) |
| Signing key | `machi-konno-v2`, fingerprint `80AD2C078946FE3019DB48BCE76DD8DAD1490829` |
| Package | `dist\Paladins-SmartCounter-8.1-<version>.tempest` |

- **Summary** (`--summary`, one line, required for the first publish): Shop and counter helper: 4 items to buy in order + 1 optional, live rank progress, enemy threats and counter-picks. 8 languages.
- **Tags** (`--tags`, lowercase like the rest of the repository): `ui,overlay,hud,items,shop,counter,quality-of-life`
- **Long description:** `src/README.md`, packed into the `.tempest` file and shown by the Launcher.

> Summary, tags, compatibility and changelog are **not** manifest fields. Tempest takes them as `mod publish` options. The manifest only has `id`, `name`, `version`, `icon`, `readme`, `dependencies` and `[[mod.authors]]` (`name`, `link`).

## How Tempest publishing works
Checked locally with `tempest-cli` 1.0.0, the Launcher's data and the public listings.
- **Creator account:** made on `mods.lowrezstudio.com`, not with the CLI. Create an API key (`tm_live_…`) under *Settings*, then `mod login` stores it on this PC.
- **Publishing:** `mod publish` uploads a **signed** package. Each version gets a review status: every listed version is `approved`, so there is moderation.
- **Signing:** packages are signed with a key made by `mod gen-key`. Its `--id` is the signer name players see. Releases are signed with `machi-konno-v2`; check its fingerprint before every pack (step 3 below).
- **Proving key ownership:** the website shows a challenge text; `mod sign-text` signs it.
- **Trust levels:**
  - `first-party`: only keys on LowRez's official list (`cdn.lowrezstudio.com/keys/trusted.keys`), described as "keys whose signature makes a mod's DLLs and Lua scripts trusted". LowRez maintains that list; there's no command to add yourself, so you have to ask them.
  - `unknown`: most community mods. They're still published and approved.
  - Your current key is trusted **only on this PC**.
- **Revocation:** a key put on `untrusted.keys` gets its mods refused at install and disabled at launch. Never share a `.key` file.
- **Not checked from here:** the website's exact screens, what players see for an `unknown`-trust Lua mod, and review times. Official docs: `docs.lowrezstudio.com`.

## One-time setup
Run once per PC. Adjust the paths in the first block if your folders differ.
```powershell
# Paths used by every command below
$T="C:\FiF Project\Tools\TempestStudio\1.0.0-alpha.10"; $C="$T\tempest-cli.exe"
$G="D:\SteamLibrary\steamapps\common\Paladins"
$M="C:\FiF Project\Mods\Paladins-8.1\Mods\Paladins-SmartCounter-8.1"
$K="$env:USERPROFILE\.tempest-keys\machi-konno-v2"   # signing key, kept OUTSIDE the repository

# 1. Git + GitHub CLI (reopen PowerShell afterwards)
winget install --id Git.Git -e
winget install --id GitHub.cli -e
gh auth login
git config --global user.name "Machi Konno"
git config --global user.email "ID+USERNAME@users.noreply.github.com"   # GitHub "noreply" address (Settings > Emails)

# 2. Signing key in the author's name: already done (machi-konno-v2). Only for a new PC without the key
#    backup; a new key makes updates look like another signer. Back up the .key file somewhere private.
& $C mod gen-key $K --id "Machi Konno" --game-path $G
& $C mod fingerprint "$K.pub"

# 3. Tempest account: create an API key on mods.lowrezstudio.com (Settings), then store it on this PC only
& $C mod login tm_live_XXXXXXXX
#    Prove key ownership: paste the website's challenge text, then paste the printed signature back on the site
& $C mod sign-text "CHALLENGE_TEXT" --key "$K.key"
```

## First GitHub push
```powershell
Set-Location $M
git init -b main
git add .
git status                                                     # check: no .key, no .tempest, no __pycache__
git ls-files | Select-String '\.key$|\.tempest$|token|secret'  # must print nothing
git commit -m "Counter & Shop Helper 0.6.2"
gh repo create counter-shop-helper --public --source . --remote origin --push
```
Without `gh`: create an **empty** repository on github.com (no README, no .gitignore), then:
```powershell
git remote add origin https://github.com/USERNAME/counter-shop-helper.git
git push -u origin main
```
Then publish by following [Every new version](#every-new-version).

## Every new version
Example: `0.6.4`. Set the paths from [One-time setup](#one-time-setup) first.

**1. Bump the version.**
- In `src/manifest.toml`, set `version`. In `src/scripts/main.lua`, set `VERSION`.
- Add a section at the **top** of `CHANGELOG.md`: `## 0.6.4 — YYYY-MM-DD`, followed by bullet points. That text becomes the GitHub Release notes.

**2. Run the tests** (in `engine\`):
```powershell
Set-Location "$M\engine"
python -I -B -X utf8 build_champions_data.py
python -I -B -X utf8 test_predictor.py
python -I -B -X utf8 export_lua.py
python -I -B -X utf8 check_lua.py          # must end with "OK"
powershell -ExecutionPolicy Bypass -File tests\run_lua_tests.ps1   # must end with "Lua tests: OK"
```
After a game update, first re-export the game data (see `DEVELOPPEMENT.md`) and run `extract_ids.py`.

**3. Build, sign and check the package** (same key, same mod ID):
```powershell
$v="0.6.4"; $P="$M\dist\Paladins-SmartCounter-8.1-$v.tempest"
& $C mod fingerprint "$K.pub"                # must print 80AD2C078946FE3019DB48BCE76DD8DAD1490829
& $C mod pack "$M\src" $P --key "$K.key"     # for an existing package: & $C mod sign $P --key "$K.key"
& $C mod verify $P --game-path $G
& $C mod install $G $P --replace --defer     # "can be installed; nothing was written" = OK
```

**4. Commit, tag and push:**
```powershell
Set-Location $M
git add -A
git status                                   # check again: no .key / .tempest listed
git commit -m "v$($v): one-line summary"
git push
git tag -a "v$v" -m "Counter & Shop Helper $v"
git push origin "v$v"
```

**5. GitHub Release**, with the signed package attached and the notes taken from `CHANGELOG.md`:
```powershell
$notes = powershell -ExecutionPolicy Bypass -File "$M\release-notes.ps1" $v
gh release create "v$v" $P --title "Counter & Shop Helper $v" --notes-file $notes
```
`release-notes.ps1` copies the `## <version>` section of `CHANGELOG.md` (without its heading line) into `%TEMP%\notes-<version>.md`. It stops with an error if that section is missing or empty.

**6. Tempest repository**, with the **same** `.tempest` file:
```powershell
& $C mod publish $P --patch 8.1 --changelog "One-line summary of this version"
#  first publish only: add --summary "..." --tags "ui,overlay,hud,items,shop,counter,quality-of-life"
& $C mod search "paladins-smartcounter-81" --json   # review status and signer trust
```

## Safety rules
- **Keys stay out of the repository.** Signing keys live in `%USERPROFILE%\.tempest-keys\`. `.gitignore` also blocks `*.key`, tokens, secrets and `.env`.
- **Packages go to Releases, never to git.** `dist/` and `*.tempest` are ignored.
- **API tokens are never typed into a file.** `mod login` stores the `tm_live_…` key in Tempest's own settings.
- **Never print or open the `.key` file.** Check the key with `mod fingerprint` on the `.pub` only.
- **Same key, same ID, every version.** Switching keys or IDs makes updates look like a different mod. If you ever change the key, re-sign **before** tagging, so the GitHub file is exactly the one published on Tempest.
- **Official trust:** to get `first-party` trust, ask LowRez to add your `.pub` fingerprint to `trusted.keys`. `mod sign-key-lists` is only for LowRez's own list signers; don't use it.
