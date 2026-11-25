<p align="center">
  <img src="src/icon.png" width="112" alt="Counter & Shop Helper logo">
</p>

<h1 align="center">Counter & Shop Helper</h1>

<p align="center">
  A Lua mod for <b>Paladins 8.1</b> (Wekono's Wake, build 8.1.5839.0) · by <b>Machi Konno</b> · Discord: <code>machi.konno</code><br>
  Requires <b>Tempest Scripting</b> 1.0.0 or later · <a href="../../releases">Download</a> · <a href="CHANGELOG.md">Changelog</a>
</p>

> 🇫🇷 **En français :** le mod est entièrement traduit en jeu (8 langues, dont le français). Les notes techniques sont en français dans [DEVELOPPEMENT.md](DEVELOPPEMENT.md).

---

**Contents:** [Overview](#overview) · [Features](#features) · [Hotkeys & usage](#hotkeys--usage) · [Installation](#installation) · [Updates & changelog](#updates--changelog) · [Credits](#credits)

## Overview
Counter & Shop Helper reads the enemy team and tells you **what to buy, in which order, and who to watch out for**. It shows a small in-game panel in your language, using the game's own names.

> 🔒 **Read-only.** The mod never buys anything, never sends anything to the server, and changes no game file. Automatic buying is disabled on purpose: Tempest offers no safe shop function.

## Features
| | |
|---|---|
| 🛒 **4 core items + 1 optional** | 4 core items in buying order, each with its advised rank and a short reason. A **5th optional item** (blue dashed border) is a flex pick that depends on how the match goes. |
| 📈 **Live item & rank reading** | Your items and ranks are read from the game. Grey = not bought, amber = rank in progress, green = advised rank reached. Buy something off-plan and the free slots are re-planned around it. |
| ⚠️ **Enemy threats** | Based on the enemies' own abilities, e.g. "Makoa: Dredge Anchor (stuns)". |
| 🎯 **Champion select** | Counter-picks and the best roles against the enemy team (hidden once you're locked in). |
| 🌍 **8 languages** | English, Français, Deutsch, Italiano, Русский, 简体中文, 日本語, 한국어, or Auto (follows your Steam / game language). Item, role and ability names come from the game's 8.1 text files. |
| ✋ **Manual fallback** | If live reading isn't available, set your items by hand in the Match tab. They reset to 0 every session. |

## Hotkeys & usage
| Key | Action |
|---|---|
| `Ctrl+J` | Open the menu (Match, Settings, Help) |
| `Ctrl+H` | Show / hide the panel |
| `Ctrl+K` | Switch between compact and detailed view |
| `Ctrl+O` | Open settings |
| `Ctrl+L` | Lock / unlock the panel |

- **Compact view:** a slim strip with your buy order and the main threat, made for mid-fight glances.
- **Detailed view:** adds ranks, reasons, threats and, in champion select, counter-picks.
- **Auto layout:** shows the detailed view when something changes, then goes back to compact.
- **Moving the panel:** with the menu open, drag the panel to move it or drag its edge to resize it. *Settings → Automatic width* restores the computed width.
- **Changing keys:** every key can be rebound in the menu. All defaults work on a 60% keyboard.
- **Console commands** (Tempest console): `smartcounter` (menu), `smartcounter_probe` (detection report), `smartcounter_items` / `smartcounter_items_watch` (live item reading), `smartcounter_selftest`. Reports go to `%TEMP%\tempest-scripting.log`.

## Installation
**You need:** Paladins 8.1 with Tempest and the **Tempest Scripting** mod installed.

**Option A: Tempest Launcher** (once the mod is listed on the Tempest mod repository)
Search for "Counter & Shop Helper" in the Launcher's mods and install it.

**Option B: GitHub Release package**
1. Download `Paladins-SmartCounter-8.1-<version>.tempest` from [Releases](../../releases).
2. Install it with the Tempest Launcher, or from the command line:
   ```powershell
   tempest-cli.exe mod install "<your Paladins folder>" "Paladins-SmartCounter-8.1-<version>.tempest" --replace
   ```
3. Start the game. A short "Counter & Shop Helper ready" tip appears, and `Ctrl+J` opens the menu.

> The package is signed by the author. The Launcher may show the signer as unofficial, which is normal for community mods.
> `--replace` updates an existing install. The mod ID (`paladins-smartcounter-81`) never changes, so updates always replace the previous version.

## Updates & changelog
- **What changed:** [CHANGELOG.md](CHANGELOG.md), one section per version, newest first.
- **Downloads:** [GitHub Releases](../../releases). Each `vX.Y.Z` tag has the signed `.tempest` package and that version's notes.
- **Current version:** 0.6.2.

## Credits
- **Made by Machi Konno** · Discord: `machi.konno`.
- **Paladins** and its item, ability and champion names, shop icons and game data belong to **Hi-Rez Studios**. This is an unofficial fan mod, not affiliated with or endorsed by Hi-Rez Studios.
- Built on **Tempest** and **Tempest Scripting** by LowRez Studio.
- The mod logo is original artwork.
- For developers: [RELEASE.md](RELEASE.md) (publishing to Tempest and GitHub) · [DEVELOPPEMENT.md](DEVELOPPEMENT.md) (structure, engine, tests; in French).
