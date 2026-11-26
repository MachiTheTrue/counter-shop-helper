# Changelog — Counter & Shop Helper

Target game build: **8.1.5839.0** (Wekono's Wake Hotfix 1). Author: **Machi Konno** (Discord: **machi.konno**).

One `## X.Y.Z — YYYY-MM-DD` section per version, newest first. Each section is used as-is as the notes of the matching GitHub Release (`vX.Y.Z`); see [RELEASE.md](RELEASE.md). The mod was called "SmartCounter" before 0.6.1, so older entries use that name.

## 0.7.0 — 2026-11-26
Rework after the 0.6.2 QC review: game facts read live from the game and from its own data files through Tempest's Game Data API, no game stats or text in the package, the documented Tempest API used directly, less code to review. The live fields were checked first in a real 8.1 session (lobby, champion select, TDM, Siege) with a separate dev-only probe that is never published.

**Requires Tempest Scripting 1.1.0** (`dependencies = ["tempest-scripting>=1.1.0"]`): the Game Data API (`assembly`, `lang`) is new in that version.

### Game Data API (Tempest Scripting 1.1.0)
- **New `lib/sc_gamedata.lua`**: once, when the script loads (the quiet moment the API docs advise), the mod asks `assembly.dat` about the champions and items it has rules for, by their ids: the champion's **role** (its "Roles" tag, `BOTS.DATA_SET_BOT_TAGS`), its **name** (`BOTS.NAME_MSG_ID`), its **ability names** per slot (`BOTS.DATA_SET_BOT_DEVICES` -> `DEVICES.NAME_MSG_ID`), each item's **name and description** (`ITEMS.NAME_MSG_ID` / `DESC_MSG_ID`) and its **shop ranks** (one device mode per rank, `DEVICES.DATA_SET_DEVICE_MODES`). Role and shop-category labels are Lang messages found by name (`lang.find`). Then the file is freed (`assembly.unload`). Checked offline: the same answers as the old baked data for all 59 champions and 20 items.
- **Texts from the game's Lang files** (`lib/sc_text.lua`): `lang.message(id, ext)` turns the message ids into text. A language's texts are read all at once the first time it is shown, kept, and the file is freed (`lang.unload`): nothing is looked up while the panel draws. The HUD translator (`UIMoviePlayer.usc_TranslateMsgId`), its retries and its `pcall` are gone.
- **Names in the language the mod shows**, from that language's Lang file: an English panel on a French client now shows the game's English names and descriptions (before: internal keys and no description). The *Game names in the client's language* setting keeps the champion, item and ability names in the client's language. A language the game has no file for (Italian) uses the mod's own words.
- All or nothing: if the game data cannot be read, the mod stays off and says why in a toast and in the log.
- **The client's language** (*Auto* UI language, names with *Game names in the client's language*) is the engine's own answer, `Object.GetLanguage()` on `tempest.engine()`, looked at once per second. Paladins takes its language from Steam's game language when it starts: the engine config still says `INT` and `lang.language()` only knows a `-language=` start argument (else `INT`), so both said English on a French client. Fix after the second 0.7.0 test, where *Auto* chose English on a French client. `lang.language()` is only used when the engine gives no answer. The report button now writes both values and the UI setting.

### Read live from the game
- **Champions by their bot id**: every champion pawn is asked `TgPawn.GetBotId()` (Buck 2147, Maeve 2338... in the probe's log); the list of pawn classes is gone from the data. Fix after the first 0.7.0 match test: `GetArchetypeBotId()` names the role archetype (2573 Front Line to 2576 Flank), so no ally or enemy was found and nothing was advised. Illusions (`TgPawn_Illusion`) and the Siege payload (`TgPawn_SiegeEngine_*`) appear among the players in a match: they are never taken for a champion and never asked for a bot id. An id 0 while a pawn is being set up or torn down is not remembered: it is asked again at the next read.
- **Enemy max health** from `TgRepInfo_Player.r_nHealthMaximum` (cards and talents included) is the only health the predictor uses: the "squishy" rule (Sentinel) counts the enemies whose live max health is 2200 or less. An enemy picked by hand has no live value and is not counted.
- **Game mode from the game-info class**: `TgRepInfo_Game_TeamDeathMatch` (and its Roulette subclass) is TDM, `TgRepInfo_Game_Payload` is Siege. The modes on the base `TgRepInfo_Game` class come from the 8.1 map prefixes: Siege `SG_` / `SGA_` / `SGB_` / `S_` (the first match test on `sg_icemines_p` showed no mode), onslaught `ON_` and King of the Hill `KOTH_`, TDM `TD_` / `TDM_`, the range.
- **Items from the player info only** (`TgRepInfo_Player.r_PlayerDevices` for which items, `r_TempItems[].nRank` for their rank), the path checked in game. The pawn's inventory chain, which the client never gets in a match, is no longer read. Only owned items teach how the game counts ranks: a sold item can stay in `r_TempItems`.

### No game data in the package
- `sc_data.lua` ships only the mod's own rules (tags, tiers, counter weights, archetypes, styles, shop categories) and the ids that link them to the game: a bot id per champion, an item id per shop item. No name, message id, role, health, shield or deployable health, cost, rank count, pawn class or device id. One short table per line: 1318 lines instead of 4305 (43 KB instead of 88 KB).
- The shield and deployable reasons no longer quote a health number. The hand-typed item stats (Resilience, Bulldozer, Sentinel notes, × 8 languages) are gone: the game's own item description is shown instead.

### Proper API, cleaner code
- **New `lib/sc_game.lua`**: game properties are read with `Object:has(name)` first, so an undeclared property is never looked up and no read needs a `pcall`. Struct entries (shop items, scoreboard slots) have no `has()` and are read directly, as checked in game; a plain value (number, string) is never indexed. Functions are called as methods, only on the classes that declare them (`is_a` first: `GetTaskForceNumber` on `TgRepInfo_Player`, `IsFriendlyWithLocalPawn` and `GetBotId` on `TgPawn`). The home-made `try` / `get` readers are gone; a read is protected once as a whole by its poll, which logs errors.
- **Tempest's `ui` API called directly**, like Tempest Scripting's own `core.lua`: no guarded proxy of the `ui` table, no `pcall` around draw-list calls, tooltips, window sizes, `ui.capture` or `tempest.toast`, no "does this `ui` function exist?" checks (every one the mod calls is declared in `tempest.d.lua`), and `tempest.queue` is called directly. The theme and font helpers still pop what they pushed if the panel raises, then raise again.
- LuaJIT's `bit.bor` is used directly (no fallback for a Lua without `bit`).
- The item reader is half its size: one source, one rank counting, one log line per change (`items [PRI]: Nimble=2 (shop rank 2)`).
- **Report button for bug reports** (Match tab, open with Ctrl+J, *Write item details to the log*): one short block built from what the mod already holds: version, status, map, mode and why, champions, enemy max health, each player as read (pawn class, bot id, team number, champion, side), the game-info class, what the game data gave (champions, items, max rank, text languages), item source and ranks, the last raw item line, read errors, the plan's inputs. Nothing more is read from the game for it.
- `check_lua.py` now refuses a `ui` proxy, a `pcall` around a `ui` / draw call (except `ui.add_font`: a Windows font may be missing), a `ui` existence check, a raw field dump, a home-made protected reader, the dev probe, the HUD translator, any game data field in `sc_data.lua` (stats, message ids, roles, rank count), a hand-typed item stat in `sc_lang.lua`, and a manifest without `tempest-scripting>=1.1.0`.

### Tests
- `run_lua_tests.ps1`: 1480 checks. The `assembly` and `lang` mocks answer from `engine/tests/game_ids.lua`, a test fixture of ids only written by `export_lua.py` (never packaged); mock rows are strict like the real ones (a mistyped field raises). New: roles, names, ability names and ranks from the game data, the all-or-nothing load, texts read once per language and freed, a language without Lang file, an id without text, champions by `GetBotId` with `GetArchetypeBotId` answering the role archetype, an illusion that answers a champion's bot id, a French Steam client (the engine says `FRA`, `lang.language()` says `INT`) and a language the engine sets late, Siege / onslaught / TDM by 8.1 map prefix, the per-player report. `check_lua.py`: 236 keys × 8 languages. `test_predictor.py`: 79/79.

## 0.6.4 — 2026-11-25
Fixes from the first in-game screenshots of 0.6.3: item chip drawing, the 4-item limit, header noise, champion select timing and mixed languages.

### Item chips
- The chips are now drawn with ImGui's draw list instead of a progress bar. The category mark sits inside the chip, 6 px from its left edge, so the gold outline of the next purchase (2 px) can no longer cover it or touch it. The label starts after the mark, and is cut with "..." if the panel is too narrow.
- Calmer palette: darker chip background with a thin outline, muted amber / green fills so the label stays readable on them.
- The optional 5th item has a soft blue outline and background instead of the dashed box.

### 4 items, like the game
- Paladins holds 4 items. The item count now reads "items n/4" (it said "/5", counting the optional item).
- Once 4 items are owned (off-meta ones included), the optional item cannot be bought without selling one: it is dimmed, marked "slots full" (with the explanation in the detailed view and the tooltip), and it is never the next purchase. `blocked` is a new slot field of the engine, in `predictor.py` and its Lua port (parity checked on a new 4-item scenario).
- The manual item grid accepts 4 items at most; the others are locked until one goes back to 0.

### Less noise in the header
- "mode unknown" is no longer shown: the mode appears only when it is known (the `mode_unknown` text is removed).
- The game phase ("early*", "mid*", "late*") is no longer shown when it is automatic: it is a guess from the match clock that tunes the advice. A phase set by hand in the Match tab is shown, without "*".

### Champion select and loading
- Detection reads 4 times a second in champion select and while the match loads (once a second otherwise), so a quick pick is not missed.
- Between champion select and the match (no player, or a map without match state yet) the status is now "loading the match", with the pick kept and counter-picks hidden; it used to read "not in a game" or "match over". The pick is read again from the roster while loading, and used in the match until your character exists.
- A new map without match state and without a champion select before it (training) also reads "loading", not "match over".

### One language on screen
- Game names were shown in the game's language even when the mod showed another one (French item names in an English panel). Now the game's names are used only when the game runs in the language the mod shows. Otherwise champions and items keep their English names, roles / categories / ability effects use the mod's words, and item descriptions are hidden.
- New setting *Game names in the client's language* (off by default) for players who know the shop by its names in their game's language but read the mod in another one (English mod on a French client, for example). It changes names only (champions, items, abilities): roles, categories, effects and item descriptions always follow the mod's language, so no French sentence appears in an English panel. Settings shows a tooltip, a hint and a live line "Now: game in …, mod in …, names in …"; the Help tab explains when to use it.
- Audit of the 8 UI string tables: no French (or other language) text left in another table.

### No game names typed in the mod's sentences
- The archetype labels ("Shield-heavy (Wrecker value)"...), the special-shield reason and the Wrecker note had item and champion names typed in each language (an English "Wrecker" in the English table, a "Broyeur" typed in the French one). They now have `%s` placeholders filled with the names from `sc_text.lua`: the game's names in the game's language, or the English internal names when the mod shows another language. They always match the shop and follow the names setting.
- The deployables reason gives the biggest deployable's HP ("deployables (up to 2500 HP)") instead of the objects' English names; `champions_data.json` keeps only a kind and the HP of each deployable.
- `check_lua.py` now fails if a champion or item name is typed in `sc_lang.lua`.

### Header without repeats
- The role and the playstyle could show the same word ("Damage (Damage) · Damage"). The playstyle is shown only when the champion has 2 or more playstyles and its label differs from the role, in every language.

### Item ranks
- Max ranks checked against the game data: every 8.1 shop item (Agile / Nimble included) has 3 ranks, the 3 modes of the item's device. `extract_ids.py` now records `ranks` per item (no fixed 3 any more), and the Python predictor and its Lua port cap owned, read and advised ranks at each item's own max.
- **Live rank-ups were not followed** (seen in a match: Resilience bought at I, upgraded to III, the panel stayed on "Resilience I/II"). The mod read the inventory object's `m_InventoryData.nLevel` first, and the device's `r_nDeviceLevel` only when `nLevel` was missing. `nLevel` belongs to the purchase record (next to `fAcquiredDatetime` and `nInstanceCount`) and keeps the rank the item was bought at; an upgrade goes through `TgInventoryManager_Player.ChangeDeviceLevel`, which raises the device's `r_nDeviceLevel`. Now the three level fields of the game are read at every poll (device level, scoreboard slot `r_PlayerDevices[].Level` when Tempest lists it, purchase record), each is turned into a rank on its own, and the highest wins: an owned item's rank never goes down, so a stale field can only be lower. The owned rank, the item count, the next target and the plan update within a second of the upgrade.
- **No more log spam** (`%TEMP%\tempest-scripting.log`, one line per second): Tempest logs every read of a property the object's class does not declare.
  - `PlayerReplicationInfo ... has no property r_PlayerDevices`: in the lobby the player's PRI is a plain `Engine.PlayerReplicationInfo`; the scoreboard slots are only on `TgRepInfo_Player`. They are now read only on that class (`is_a`), and a slot array Tempest cannot list is not asked again.
  - `TgPawn_SiegeEngine_CaptureAndPayload ... has no property GetArchetypeBotId`: the Siege payload has a PRI in the match list, and every pawn was asked for its champion's bot id. Champions are now known by their pawn class first (each champion has its own class in the data); a class the data does not list is asked once, only if it is a character (`TgPawn_Character`), and the answer is cached per class. Siege engines / payloads are never asked and never count as enemies.
  - Device fields (`r_nDeviceLevel`, `CurrentFireMode`) are read only on inventory objects that are `TgDevice`s, the purchase record only on `TgInventoryObject`s.
- **One log line per item change** for in-game checks: `[smartcounter] items [<class>]: Resilience=2 (dev 2, slot -, buy 1, mode 1); ...` gives, for each item, the rank kept and what each game field said (device level, scoreboard slot, purchase record, device mode). It is written when a value changes (purchase, upgrade, sale), never at every read.
- **Ranks in a real match come from the shop items (`r_TempItems`)** — found with the diagnostic button in a live match (TDM, Io): the client has **no inventory chain** in a match (`chain none`), so items came from the scoreboard slots `TgRepInfo_Player.r_PlayerDevices`, whose `Level` is the deck cards' level (a card at 5) and stays at **0 for shop items whatever their rank**: Nimble showed 2 pips on the scoreboard and "Agile I" in the panel. The 8.1 declarations have `TgRepInfo_Player.r_TempItems`, an array of `TempItemInfo { nDevId, nRank, nCost }`: the match's shop items with their rank. Now the slots say which items are owned and `r_TempItems[].nRank` gives their rank (counting from 0 or 1 learnt as before); the slot `Level` is no longer read as a rank. The source shown in the Match tab is "PRI.r_PlayerDevices + r_TempItems". The `items [PRI]` log line is written in a match too (it was only written for the inventory chain), with the shop rank, the slot level and count of each item.
- **Diagnostic block**: also lists the shop items (`r_TempItems`: device, item, rank, cost), the slot count / last known device / power of each scoreboard slot, the size of the shop undo queue and the equipped item modes (`TgPawn.r_EquipDeviceInfo`).
- **Items read on practice maps** (training, the range): a map without match state and without a champion select before it is shown as "loading", and item reading was paused for every "loading", so items and ranks were never read there and no `items` line was written. Reading is now paused only while a match really loads after a champion select.
- **The log says why nothing is read**: one line when it changes, never at every read: `status: <status> (map <map>)` (with "practice map" or "item reading paused" when it applies), `items: live from the game (InvManager)`, `items: nothing to read: no character / the character has no inventory / no local player`, and `items: read failed: <error>` once per different error (read errors used to be counted silently).
- **Diagnostic button** in the menu's Match tab (*Write item details to the log*): one press writes one short block to `tempest-scripting.log` with what the reader sees right now: status, character and player-info classes, each inventory object (class, item id and name, purchase level, device level, mode, device id), the scoreboard slots when they can be listed, the ranks kept and the counting learnt. Only declared fields are read; nothing is written without a press.
- **Rank on the chips without fractions**: an item owned below its advised rank read "Resilience I/II", which looked like a fraction ("1/2"). It now reads "Resilience I → II" (owned rank → advised rank); "Resilience II" once the advised rank is reached, the advised rank alone for an item to buy. A rank is always clamped to I–III before it is shown.
- Live ranks: the game's level fields do not say whether they count from 0 or 1. The mod learns it during the session, for each field (a 0 means it counts from 0, a value equal to the max rank means it counts from 1), so a rank is no longer one off; nothing conclusive → counts from 1.
- Sentinel note fixed: 200 / 400 / 600 HP shield for 5 s on an elimination, stacks 3 times.

### Tests
- `test_predictor.py`: 79/79 (4-item cases, max ranks, a 2-rank item capped). `check_lua.py`: OK (235 keys × 8 languages, no typed game name). `run_lua_tests.ps1`: 1449 checks (a live match shape: no chain, 49 slots with a deck card at level 5 and items at level 0, Hoard and Nimble bought then Nimble I → II → III through `r_TempItems` counting from 1 and from 0, sold and bought again, one log line per change; the same end to end in the panel and the Match tab; `r_TempItems` that cannot be listed asked once; items read and upgraded on a practice map, loading after champion select paused and said once, the diagnostic button and its block; buy / upgrade / sell / buy again / two items upgraded in the same second with one log line per change; read errors logged once; Wrecker, Nimble and Morale Boost bought at I and upgraded to II and III on a French client with the mod in English and in French: chip rank, items 3/4, one log line per purchase / upgrade / sale and none while nothing changes; chip labels for every rank / target pair without "/" or digits; no lookup of missing properties: Siege payload pawn, lobby PRI, slot array that cannot be listed, inventory objects that are not devices; raw levels logged once per change; chip geometry, dimmed blocked chip, "n/4", header without repeats, names per UI language and setting, names inside sentences, ranks counted from 0 or 1, an item bought at I and upgraded to II and III next to 2 other items: reader, plan and panel, with the device level counting from 0 or 1, with the scoreboard slots only, and with the purchase record left at I as in the game, quick pick / loading / training, 4-item manual grid, polling pace).

## 0.6.3 — 2026-11-25
Resubmission after review: names are asked from the game instead of being shipped, no game art or game text in the package, game reading through Tempest's reflection API only, and the code split into small modules.

### Names from the running game
- Champion, item, ability, role and shop category names, and item descriptions, are now asked from the game while it runs (`UIMoviePlayer.usc_TranslateMsgId` on the HUD movie, new `lib/sc_text.lua`). They are always in the game's own language and cached per message id.
- Until the game has loaded its interface (first seconds after launch), the English internal names are shown; roles and categories use the mod's own words.
- Auto language follows `GetLanguage()` from the game. The mod no longer reads Steam's `appmanifest_444090.acf` or the game's `ChaosEngine.ini`.
- `sc_data.lua` holds only ids (bot ids, pawn classes, item ids, message ids) and the mod's strategy data: 201 KB → 88 KB, ASCII only.

### No game assets shipped
- The 20 shop icons (`src/icons/`) are removed. Each item chip has a small coloured mark for its shop category instead, drawn with ImGui.
- `engine/extract_loc.py` and its `loc_8_1.json` (game texts in 12 languages) are replaced by `engine/extract_ids.py` and `game_ids_8_1.json`, which hold message ids only. `engine/make_icons.ps1` is removed. `champions_data.json` no longer carries the English shop texts.

### Game reading through the proper APIs
- My champion and the enemies: `TgPawn_Character.GetArchetypeBotId()`, with the pawn class as fallback.
- Teams: `TgRepInfo_Player.GetTaskForceNumber()`. Fix: the old code read `r_TaskForce`, which is the team object and not a number, so teams always came from the fallback.
- Owned items: `Pawn.InvManager.InventoryChain` → `m_InventoryData { nItemId, nLevel }`, else the replicated device slots. The guessed field lists and the raw memory reads are removed.
- Fonts: `ui.add_font` through `tempest.queue` only; the raw ImGui FFI (`ui.C`) font-scaling fallback is removed.
- Settings: `tempest.config` / `tempest.save_config`, saved once a second after the last change.

### Debug helpers removed
- Only the `smartcounter` console command is left. `smartcounter_probe`, `smartcounter_selftest`, `smartcounter_items`, `smartcounter_items_watch` and `smartcounter_dumpsdk` are removed, with their texts in the 8 languages.
- `lib/sc_expected.lua` (reference results shipped for the in-game selftest) moves out of the package to `engine/tests/expected.lua`; the parity test now runs offline.

### Code split for review
- `main.lua` goes from 1,694 to about 200 lines: it only wires the modules and runs the frame.
- New modules: `sc_text` (game names), `sc_config` (settings), `sc_keys` (hotkeys and rebinding), `sc_match` (inputs → prediction), `sc_fonts`, `sc_gui` (guarded ImGui, palette, theme), `sc_view` (panel), `sc_menu` (menu and tutorial).
- Fixed: after a match, the menu's status line showed the raw key `st_match_over`; it now reads "match over" in all 8 languages.
- Fixed: game placeholders like `{10|-1}s` showed as "10/-1s"; they now show the value only ("10s").
- The unused `lvl` text is removed.
- Help, "Automatic buying": corrected. Tempest *can* hook game functions (0.6.1 said it couldn't); the mod still never buys and never sends anything. The sentence about the game's own auto-buy option is removed, since it was not verified.

### Fixed in the verification pass (late, empty or changing game answers)
- A name the game had not loaded yet (empty answer) stayed in English for the whole session. It is now asked again after 5 s, at most 3 times per id, and again when a new HUD appears; a language change forgets the names of the old language.
- Game text cleaning: `<br>` becomes a space, `&amp;` / `&lt;` / `&gt;` / `&quot;` / `&apos;` / `&nbsp;` are decoded.
- Fonts: a load still queued when the mod was reloaded stayed "loading" forever; it now starts again. A `tempest.queue` that never runs is retried (3 times), then the default font is used; `ui.add_font` is never called while drawing. A Japanese / Korean / Chinese font set built before the game's names arrived is rebuilt (at most twice) once they are known, and the previous set is used until the new one is ready.
- After a match, the HUD keeps the last roster: back in the lobby this was read as a new champion select. A roster already seen in a match now stays "lobby"; a new roster (new match id or names) is a new champion select.
- The champion cache by player (PRI) is dropped when the map changes, so a PRI at a reused address cannot keep the last match's champion.
- While dead (no pawn), my champion and the items read live are kept instead of falling back to "not detected" and the manual grid.
- Manual item ranks belong to one game: they are emptied when a new champion select starts, and are no longer saved to the config file.
- Saved manual champion picks are checked at load: unknown names are dropped, aliases become the canonical name.
- Hotkeys and the console command only queue their action; the next frame runs it on the draw thread (`ui.capture` and toasts were called from the key callback).
- Escape while rebinding a key cancels the rebinding without also closing the menu.
- Champion lists in the Match tab are sorted by the name shown (the game's, in its language), not by the internal English name.

### Tests
- New `engine/tests/run_lua_tests.ps1`: runs `lua_tests.lua` with the game's own `Lua51.dll`, with `tempest`, `ui` and the game objects simulated. 815 checks: Lua/Python predictor parity on 20 scenarios, the text, item and detection modules, and `main.lua` end to end (every game state, the 8 languages, the 3 tabs, key rebinding, debounced saving, hot reload), and the edge cases above: late / empty / missing translator, HUD loss and language change, font queue never run and CJK rebuild, lobby after a match, PRI reuse across maps, death, new game. Every frame checks balanced ImGui stacks, no draw error, no raw text key / format code / game markup on screen and no global variable created.
- `check_lua.py`: checks the text keys used by every module, that `sc_data.lua` is ASCII only, and that no icon, debug command, raw memory read, FFI call or Steam / game file read is left.
- `test_predictor.py`: 74/74 (new checks: no game text copied, every message id present).

### Not verified in game yet
- `usc_TranslateMsgId`, `GetLanguage`, `GetArchetypeBotId`, `GetTaskForceNumber` and the inventory chain are used as the 8.1 classes declare them, but have only been run against simulated objects so far. If one of them does not answer, the fallbacks listed above apply.
- Also to confirm in game: that `m_Match.dwMatchId` changes between matches (it names a game), that `nLevel` counts ranks from 1, and that a font set queued with `tempest.queue` is ready on the next frame.

## 0.6.2 — 2026-11-25
Public release preparation.

### Author & credits
- The author is now **Machi Konno** everywhere:
  - the manifest (`[[mod.authors]] name = "Machi Konno"`, `link = "Discord: machi.konno"`);
  - the Launcher README, the Help & About tab, the footer and the docs.
- A single translated credit line, `about_credit = "Made by %s  ·  Discord: %s"`, filled in by `main.lua` with `AUTHOR = "Machi Konno"` and `DISCORD = "machi.konno"`.
  - It shows in the Help & About tab and in the menu footer, in the selected language.
  - The separate Discord line and its `about_discord` key are removed.
- `check_lua.py` rejects the old author spelling in any displayed text, and checks that `about_credit` contains both the author and the Discord handle.

### Public metadata
- Checked in `tempest-cli` and in all 19 installed mods: the manifest only supports `id`, `name`, `version`, `icon`, `readme`, `dependencies` and `[[mod.authors]]` (`name`, `link`).
- Summary, tags, compatibility and changelog are given when publishing (`mod publish --summary --tags --patch --changelog`). They're ready in `RELEASE.md`, along with the full command.
  - Compatibility: patch `8.1` (`build identify`: 8.1, "Wekono's Wake Hotfix 1").
  - Tags: `ui,overlay,hud,items,shop,counter,quality-of-life`, in the repository's format.
- `src/README.md` is rewritten as the public description: features, keys, 8 languages, read-only / no auto-buy, console commands and the credit line.

### Logo
- New `src/icon.png`: 512 × 512, original artwork, no game assets. Generated by `engine/make_logo.py` (Pillow, drawn at 4× then downscaled).
  - A navy tile with a gold shield and three rank chevrons in the mod's progress colours: green = rank reached, amber = in progress, grey = not bought.
  - A blue dashed "+" badge for the optional 5th item.
- Added to the manifest with `icon = "icon.png"`, like the other mods. The package signs and verifies cleanly.

## 0.6.1 — 2026-11-25

### New name: "Counter & Shop Helper"
- The display name changes everywhere: menu title, startup tip, notifications, tutorial, Help, footer, `manifest.toml` (`name`) and the Launcher README. The name stays the same in all 8 languages, like a proper noun.
- Nothing changes internally, for compatibility:
  - the ID `paladins-smartcounter-81`, so `--replace` updates the existing install;
  - the `smartcounter*` console commands;
  - the `[smartcounter]` log prefix;
  - the ImGui window IDs (`###smartcounter_menu`, `##smartcounter_overlay`), so the panel keeps its position;
  - the folder and package names, `Paladins-SmartCounter-8.1-<version>.tempest`.
- `check_lua.py` rejects the old name "SmartCounter" in displayed text, and doesn't count "Counter & Shop Helper" as an English word in translated tables.
- The Discord credit **machi.konno** is unchanged: it shows in the Help & About tab and in the footer.

### Automatic buying: disabled, explained in Help
- Checked again: Tempest Scripting exposes no shop function and no way to intercept a game function (only `on_key` and `on_game_thread`). Buying would mean calling the raw server functions `ServerPurchaseItem` / `ServerUpgradeItem` with loot-table IDs that can't be verified.
  - *Correction (0.6.3): wrong. Tempest Scripting does have game-function hooks (`tempest.on` / `tempest.before`). The decision stays the same: the mod never buys.*
- There is no automatic-buy setting in Settings (there never was one in the code).
- Help, in all 8 languages: the section is titled "Automatic buying: disabled". It explains that the feature was dropped and has no setting, because there is no safe shop function, and that the mod only reads the game.

### Unchanged (checked)
- Manual items at 0 on start; compact width with no empty right margin; 4 items + 1 optional in blue dashed, without numbers; colours by rank; off-meta adaptation; 8 native languages. Tests: 71/71, `check_lua.py` OK.

## 0.6.0 — 2026-11-25

### Items: 4 core + 1 optional
- The build shows 4 core items, then a 5th **optional** one that depends on the match. It has a blue background, a blue dashed border and an "optional" label. The detailed view says "optional 5th item: swap it in depending on the match".
- Items you already own keep a place among the 4 core items (`CORE_SLOTS = 4`, in both the Python and Lua engines). Two new tests: 71/71.
- The `1 2 3 4 5` order numbers are removed from the item badges, since reading order is enough.

### Manual setting & width
- Manually set ranks start at 0 (`-`) every session and every new match, unless live reading is active.
- Compact view: the width follows how the item badges actually wrap (200 px minimum). The threat text no longer widens it, so there's no empty space on the right in any language.
- Manual resizing: the width you drag to is remembered per view (`overlay_w`). The "Automatic width" button in Settings goes back to the computed width.

### Languages: 8
- Added Italian, Russian, Simplified Chinese, Japanese and Korean, alongside EN / FR / DE. The language picker is now a drop-down list.
- Item, category, role and champion names come from the game's own tables: `Lang_RUS`, `Lang_CHN`, `Lang_JPN` and `Lang_KOR`.
  - RU and JA are complete.
  - In ZH and KO, about 120 texts are missing from the client's tables (newer champions and items) and stay in English.
  - The 8.1 client has no Italian table: in IT, game names stay in English.
- Fonts: one font set per script.
  - Latin, Greek and Cyrillic: Segoe UI.
  - ZH, JA and KO: a merged Windows CJK font (Microsoft YaHei, Yu Gothic, Malgun Gothic, or their fallbacks), limited to the glyphs actually used to keep the atlas small.
- `check_lua.py` checks:
  - the same keys in all 8 tables;
  - no text left in English;
  - no English words in the RU / ZH / JA / KO tables;
  - that every glyph can be drawn.
- Language detection via Steam or the game: `italian`, `russian`, `schinese`, `japanese`, `koreana` / ITA, RUS, CHN, JPN, KOR.

### Automatic buying: not included
- 8.1 does have the server functions (`TgPlayerController.ServerPurchaseItem(nLootTableId, nLootTableItemId, nItemCount)`, `ServerUpgradeItem`, `ServerSellItem`), but:
  - they take loot-table IDs (`DATA_SET_LOOT_TABLES`) that don't map one-to-one to the 20 shop items, and the mapping can't be checked outside a match;
  - a wrong ID would go to the official server, which has anti-flood protection;
  - Tempest can't intercept game functions (only `on_key` and `on_game_thread`), so the real values of a manual purchase can't be recorded to check them.
- The mod stays read-only and sends nothing to the server. Help says so and points to the game's own auto-purchase option (`SetAutoPurchase`).

### Credits
- "Discord: machi.konno" in the Help & About tab and in the footer, next to "Made by Machi Konno".

## 0.5.2 — 2026-11-24
Live reading of purchased items and their ranks, using the real 8.1 fields found in the script table of `TgGame.upk`. In 8.1, a shop item is a device: `ITEM_ID` = `DEVICE_ID` (Resilience = 11683).
- Sources, in order:
  1. `PRI.r_PlayerDevices` (array of `DeviceTeamInfo`: `CurrentDeviceId`, `Level`, `Power`…), the main replicated source;
  2. `InvManager` → `TgInventoryObject.m_InventoryData` (`nItemId`, `nLevel`);
  3. `PC.r_LastPurchasedItems` (`nItemId`, `nCount`);
  4. `PRI.r_TempItems` (`nDevId`, `nRank`) as a fallback. Purchases made during the current shop visit can raise the rank.
- Static arrays are read through the Struct view of the first element. The layout is checked against the named fields before any raw read, and every read is bounded by `memory.readable`. The array size comes from the UProperty (ArrayDim), otherwise capped at 16.
- Rank: `Level` 1–3. If a known item has `Level` 0, the field is treated as 0-based (+1).
- A source counts as "available" as soon as its layout is verified, even before any purchase: "Your items" then shows "Read live from the game" instead of the manual editor. Otherwise the manual fallback stays, with "Live reading starts once your champion is in the match".
- Read once per second, and immediately when the menu opens.
- New commands: `smartcounter_items` (logs every source with its properties and values) and `smartcounter_items_watch` (one log line per change).

## 0.5.1 — 2026-11-24
Robustness fixes after an end-of-match freeze (black screen, sound still playing, Esc not responding). The freeze happened on 0.4.0 and no Lua error was logged; the cause isn't proven (other script mods were installed).
- `ui.on_draw` runs on the game thread, so any object read there is risky while the world is being torn down.
- Guarded ImGui: every window, table and tab runs its content under `pcall`, so an error no longer skips the matching `End`. Colour / style / font / ID / indent stacks are counted and restored on error.
- End of match (`GRI.bMatchIsOver`) or missing GRI: new `match_over` state. Detection stops walking PRIs and pawns, and item reading pauses (same with no local player).
- Team: the `r_TaskForce` field is read first; the `GetTaskForceNumber()` call is only a fallback.
- Still to do: a per-read time watchdog, and a pause during map changes.

## 0.5.0 — 2026-11-24

### Shop: the 20 native items, 5 recommendations
- The catalogue follows the client's real shop: 20 items, 4 categories × 5. FR/EN/DE names come from the game (Résilience / Resilience / Ohne Grenzen…).
  - Removed: Cauterize, Illuminate, Kill to Heal (not in this shop).
  - Added: Guardian, Hoard, Cavalier, Meditation, Bloodbath, Lethality, Trigger Scent.
- Each item carries its `ITEM_ID`, its alias IDs (duplicates in `assembly.dat`), its inventory class and its icon index (`DATA_SET_ICONS.ICON_INDEX` = frame of the `ItemCards` sprite).
- No more "1 per category" limit:
  - the build always shows **5 items** sorted by priority, several per category allowed (×0.7 decay for each extra item in a category);
  - below the threshold (40% of the best score or 8 points), a slot is **optional**: blue, "opt.", rank I.
- 8.1 has no anti-heal, so enemy sustain is countered by killing fast (Trigger Scent, Deft Hands). Stealth is countered with Haven. Hoard is mostly worth it early, Guardian for shield champions.

### Live purchases & adaptation
- Items are read every 0.25 s (was 0.5 s). Alias IDs and their classes are recognised, so a rank-up (Bulldozer I → II) updates the badge right away.
- A purchased item always keeps its slot. If it isn't recommended, it's marked **off-meta**.
- Free slots are re-planned against the enemy comp **and** for synergy with what you own (`SYNERGY`, owned rank × 2). Example: Life Rip III brings in Deft Hands.
- Colours by rank: grey = not bought, amber = rank in progress, green = advised rank reached.
- The manual fallback becomes a 4 × 5 grid with a rank from 0 to III per item.

### Ability-based threats
- `extract_loc.py` reads the 5 abilities of all 59 champions, with their EN/FR/DE names and effects taken from the game's descriptions: 295 abilities, 149 with a recognised effect.
- Threats show the champion's ability instead of a generic word: "Makoa: Dredge Anchor (stuns)", "Inara: … (stuns)".

### Interface
- **Ctrl+K** shortcut: switch compact / detailed (rebindable).
- Shop icons in front of each badge, with a tooltip on hover (the game's name and description). Icons are generated by `engine/make_icons.ps1` from `GameUI_SF.upk`.
- Shorter labels:
  - "Buy order";
  - "Counter-picks";
  - in the detailed view, only the next purchase's reason is shown (all of them are in the menu).
- Fonts:
  - loaded outside the draw callback, through `tempest.queue`;
  - if the TTF file fails, the built-in font at the right size;
  - if everything fails, the default font is scaled. 0.4 stayed at "0/6".

### Languages
- **Auto** follows the Steam language (`appmanifest_444090.acf`), then `ChaosEngine.ini`. A French client stayed in English because the ini says `INT`.
- FR/DE texts without English words ("panneau" / "Einblendung", "dégâts explosifs", "tir instantané", "Contres conseillés", "Konterwahl"…). `check_lua.py` now rejects those English words.
- Errors are translated when displayed. "Pick your champion" no longer appears twice.
- The Lua data keeps only EN/FR/DE: the PL/TR names had characters the font can't draw.

### Credit & tools
- Author: **Machi Konno**, in the manifest, the menu, the Launcher README and Help → About.
- New `smartcounter_dumpsdk` command: lists the game's classes, to find the real inventory fields. `smartcounter_probe` also reports the language source, the font, the icons and the rank field in use.
- Tests:
  - Python: 69/69;
  - `check_lua.py`: OK;
  - `sc_expected.lua`: 20 scenarios, including off-meta purchases, rank-ups and more than 5 owned items.

## 0.4.0 — 2026-11-24

### Native game names (no hand translation)
- Item names and descriptions, shop categories and roles come from the 8.1 localisation tables: `ChaosGame\Localization\<LOC>\Lang_<LOC>.dat` and `assembly.dat` (`DATA_SET_ITEMS.NAME_MSG_ID / DESC_MSG_ID`, `DATA_SET_BOTS.NAME_MSG_ID`, `PALADINS_ARCHETYPE_*` and `PALADINS_DEFENSE` messages…).
- Build chain: `engine/extract_loc.py` → `loc_8_1.json` → `build_champions_data.py` → `export_lua.py` → `sc_data.lua`.
- Result: 99 texts mapped in EN/FR/DE, plus ES/PT/PL kept for reference. 0 English fallbacks, 0 unmapped keys. Examples: Resilience = Résilience / Ohne Grenzen; Haven = Havre / Refugium. Champion names are the same in every game language.
- New **Auto** language, the default for new installs. It follows `Language=` in `Documents\My Games\Paladins\ChaosGame\Config\ChaosEngine.ini`: INT → en, FRA → fr, DEU → de, otherwise English.

### Owned items (live state)
- New `lib/sc_player.lua`. It reads the player's purchased items and their rank, read-only, twice per second, under `pcall`.
  - It goes through `Pawn.InvManager.InventoryChain`, then through candidate lists on the PRI or the pawn.
  - An item is recognised by an ID equal to its 8.1 `ITEM_ID`, or by its inventory class.
- **These field names weren't verified in game** (no 8.1 SDK dump yet). `smartcounter_probe` now logs what each source really exposes.
- Manual fallback in the Match tab: one item and one rank (I to III) per category, reset at each new champion select.
- The build updates on purchase:
  - an owned item takes its category's slot, and the original advice stays visible;
  - each item has a status: bought, to upgrade (II → III), not bought, or owned with a different advice;
  - the next purchase is outlined.
- The Python engine has the same logic (`apply_owned`). The in-game self-test covers 3 scenarios with owned items, 15 in total.
- Deck and loadout aren't read: no field is known for them.

### Overlay
- Each item is a "badge" with a rank bar: green for the owned rank against the advised rank, red for an item not yet bought.
  - Badges never break across lines: a number is no longer left alone at the end of a line.
- The width is computed from the text measured in the active language, within limits based on the screen. The height fits the content without scrolling, and the window stays on screen.
- **Auto** is no longer a fixed choice:
  - detailed in champion select and outside a match;
  - in a match, detailed for 8 s after each change (new enemy, purchase, phase), then compact;
  - always compact below 1280 px wide.
- **Lighter detailed view:** one reason per item, 2 threats, no comp forecast or "vs" line (both stay in the menu). The official item descriptions are in the menu.
- A badge shows the context:
  - **DRAFT**: you can still pick or swap, and counter-picks are shown;
  - **IN MATCH**: champion locked, items only;
  - **PLANNING**: not in a game.

### Fixes
- Fonts: `ui.add_font` was called at load time, before `ui.ready()`, as the 0.3.0 log showed. They're now loaded on the first ready frame and used from the next one, and the log says so.

## 0.3.0 — 2026-11-24
Fixes from a real 8.1 match: Io (Support) against Makoa, Dredge, Evie, Furia and Androxus.

### Languages
- English by default; French and German available. The language is chosen in Settings and in the first tutorial step, applies immediately and is saved (`lang`).
- Every text, including reasons, threats, archetypes and counter-picks, lives in `sc_lang.lua`. The Lua engine returns keys, not text.
- **"?" characters fixed:** em dashes, ellipses, arrows and "≤" have no glyph in ImGui's default font. All texts are now Latin-1, and `L.sanitize` fixes anything that slips through. Unknown values show explicit text ("not detected", "mode unknown") instead of "?".

### Items (Io and supports)
- **One item per category, like the 8.1 shop.** Before, Io got Haven + Resilience + Blast Shields, three Defense items that can't be bought together.
- Sentinel moves to Utility: 4×4 grid, Master Riding isn't in the 8.1 data.
- New value for the player's own kit, with **tank / dps / flank / heal / aggro** playstyles. Supports choose Heal or Aggro. Small per-champion bonuses: Io, Jenos, Seris, Grohk.
- Support: Haven ×0.95, Blast Shields ×0.95, Resilience ×1.1 (was 1.1 / 1.1 / 1.2). Resilience stays the priority against Makoa's hook and CC.
- For a healer, Sentinel ×0.5 and Kill to Heal ×0.6: healers get few eliminations.

### Interface
- Segoe UI font (Arial as a fallback) in three adjustable sizes, plus a bold variant for titles. Fonts are kept in memory across reloads.
- Dark theme with gold accents: rounded buttons, tabs, fields and bars.
- **Compact:** a "BUY 1… 2… 3… 4…" line, a "WATCH" line with threat no. 1, then the name of no. 2.
- **Detailed:** more condensed; all text wraps and nothing overflows on the right. The width adapts to the resolution and text size.
- **Menu:** enemies in a 2-column table, keys in a table, and the playstyle shown for supports. Footer with version and credit.

### Clarity
- New **Enemy threats** section, coloured by danger. Example: "Makoa: heavy CC (hook / stun), deployable shield -> Resilience". It says when the answer isn't in your build.
- **Counter-picks are "for YOU"**, with a one-line explanation. **Suggested roles** are "the best roles to play against this team".
- **Counter-picks are hidden during a match**, since you can't change champion anymore. They stay visible in champion select, in the lobby and in manual mode.

### Credit
- "Made by Machi Konno" in Help & About → About, in the menu footer and in the Launcher README.

### Checks
- `test_predictor.py`: 53/53, with a new section 5 (4×4 shop, Io heal and aggro builds, Makoa threat, playstyles).
- New `check_lua.py`, without a Lua interpreter. It checks:
  - the structure of every file;
  - that all 188 keys exist in all 3 languages;
  - format arguments;
  - that every key in use exists;
  - that no character is outside Latin-1.
- `sc_expected.lua` has 12 scenarios, 3 of them for Io, and also checks the build and threat no. 1.
- **Not verified:** running the Lua in game. Run `smartcounter_selftest`, which should report 12/12.

## 0.2.0 — 2026-11-24
- Lua port of the engine, light auto-detection, compact and detailed overlay, persistent settings, rebindable keys, startup tip and tutorial, `smartcounter_probe` and `smartcounter_selftest` commands.

## 0.1.0
- Mod skeleton and Python engine (`engine\`).
