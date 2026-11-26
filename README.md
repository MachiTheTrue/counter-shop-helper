<p align="center">
  <img src="src/icon.png" width="112" alt="Counter & Shop Helper logo">
</p>

<h1 align="center">Counter & Shop Helper</h1>

<p align="center">
  A Lua mod for <b>Paladins 8.1</b> (Wekono's Wake, build 8.1.5839.0) · by <b>Machi Konno</b> · Discord: <code>machi.konno</code><br>
  Requires <b>Tempest Scripting</b> 1.1.0 or later · <a href="../../releases">Download</a> · <a href="CHANGELOG.md">Changelog</a>
</p>

> 🇫🇷 **En français :** le mod est entièrement traduit en jeu (8 langues, dont le français). Les notes techniques sont en français dans [DEVELOPPEMENT.md](DEVELOPPEMENT.md).

---

**Contents:** [Overview](#overview) · [Features](#features) · [Hotkeys & usage](#hotkeys--usage) · [Installation](#installation) · [Updates & changelog](#updates--changelog) · [Credits](#credits)

## Overview
Counter & Shop Helper reads the enemy team and tells you **what to buy, in which order, and who to watch out for**. It shows a small in-game panel in your language. Champion, item, ability, role and shop category names are asked from the game while it runs, so they are the game's own names, and the panel stays in one language (see [Names and languages](#names-and-languages)).

> 🔒 **Read-only.** The mod reads the game state, computes advice and draws it. It never buys anything, never sends anything to the server and changes no game file. There is no auto-buy, on purpose: buying stays your decision.

## Features
| | |
|---|---|
| 🛒 **4 core items + 1 optional** | Paladins holds 4 items: 4 core items in buying order, each with its advised rank and a short reason, and the item count shows out of 4. A **5th optional item** (soft blue outline) is a swap that depends on how the match goes; once your 4 slots are full it is dimmed and marked *slots full*, and it is never shown as the next purchase. The next purchase has a gold outline; a small coloured mark inside each item gives its shop category. |
| 📈 **Live item & rank reading** | Your items and ranks are read from the game. Grey = not bought, amber = rank in progress, green = advised rank reached. Buy something off-plan and the free slots are re-planned around it. Hover an item (menu open) for the game's own description. |
| ⚠️ **Enemy threats** | Based on the enemies' own abilities, e.g. "Makoa: Dredge Anchor (stuns)". |
| 🎯 **Champion select** | Counter-picks and the best roles against the enemy team (hidden once you're locked in). |
| 🌍 **8 languages** | English, Français, Deutsch, Italiano, Русский, 简体中文, 日本語, 한국어, or Auto (follows the game's language). |
| ✋ **Manual fallback** | If live reading isn't available, set your champions and items by hand in the Match tab (4 items at most, like the game). Manual item ranks reset to 0 every session and every new match. |

The panel header shows your champion, your playstyle and the game mode when it is known. The game phase is only shown when you set it by hand.

### Names and languages
- When the mod shows the game's language (Auto, or the same language picked by hand), every name is the game's own, in that language.
- When the mod shows another language (for example English on a French client), the panel stays in that language: champions and items keep their English names, roles, shop categories and ability effects use the mod's own words, and item descriptions are hidden. *Settings → Game names in the client's language* keeps the game's champion, item and ability names instead (useful if you know the shop by its names in your game's language but read the mod in another one); roles, categories, effects and descriptions still follow the mod's language. Names inside the mod's sentences ("Shield-heavy (Wrecker value)") follow the same rule.
- Before the game has loaded its interface (the first seconds after launch), English names are shown.

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
- **Console command** (Tempest console): `smartcounter` opens or closes the menu.

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

> The package is signed by the author (signer `machi-konno-v2`). The Launcher may show the signer as unofficial, which is normal for community mods.
> `--replace` updates an existing install. The mod ID (`paladins-smartcounter-81`) never changes, so updates always replace the previous version.

## Updates & changelog
- **What changed:** [CHANGELOG.md](CHANGELOG.md), one section per version, newest first.
- **Downloads:** [GitHub Releases](../../releases). Each `vX.Y.Z` tag has the signed `.tempest` package and that version's notes.
- **Current version:** 0.7.0.

## Credits
- **Made by Machi Konno** · Discord: `machi.konno`.
- **Paladins** and its names and game data belong to **Hi-Rez Studios**. This is an unofficial fan mod, not affiliated with or endorsed by Hi-Rez Studios. The mod ships no game art and no game text: names are read from the running game.
- Built on **Tempest** and **Tempest Scripting** by LowRez Studio.
- The mod logo is original artwork.
- For developers: [RELEASE.md](RELEASE.md) (publishing to Tempest and GitHub) · [DEVELOPPEMENT.md](DEVELOPPEMENT.md) (architecture, data sources, tests; in French).
