# Counter & Shop Helper

**Paladins 8.1 (8.1.5839.0) · Lua mod · requires Tempest Scripting 1.0.0 or later**

An in-game helper that reads the enemy team and tells you what to buy and who to watch.

## What it does
- **Shop plan:** 4 items to buy in order, plus 1 optional 5th item (blue, dashed border) that
  depends on how the match goes. Each item shows its advised rank and a short reason
  ("200 HP shield", "heavy CC: shorter stuns and pulls"...).
- **Live progress:** your items and ranks are read from the game. Grey = not bought, amber = rank
  in progress, green = advised rank reached. Buying something off-plan re-plans the free slots
  around it. If live reading is not available, set your items by hand in the Match tab (they start
  at 0 every session).
- **Enemy threats:** the enemy champions' own abilities, e.g. "Makoa: Dredge Anchor (stuns)".
- **Champion select:** counter-picks and the best roles against the enemy team.
- **8 languages:** English, Français, Deutsch, Italiano, Русский, 简体中文, 日本語, 한국어,
  or Auto (follows your Steam / game language). Item, role and ability names are the game's own
  8.1 names; icons are the shop's own art.

## Keys (all changeable in the menu, all on a 60% keyboard)
- `Ctrl+J`: menu (match, settings, help)
- `Ctrl+H`: show / hide the panel
- `Ctrl+K`: switch compact / detailed
- `Ctrl+O`: settings
- `Ctrl+L`: lock the panel

With the menu open, drag the panel to move it or drag its edge to resize it.

## Safe by design
Read-only: the mod never buys, never sends anything to the server and changes no game file.
Automatic buying is disabled on purpose: Tempest offers no safe shop function (see Help in game).

## Console
`smartcounter` (menu), `smartcounter_probe` (detection report), `smartcounter_items`,
`smartcounter_items_watch` (live item reading), `smartcounter_selftest`, `smartcounter_dumpsdk`.
Reports go to `%TEMP%\tempest-scripting.log`.

Made by Machi Konno · Discord: machi.konno
