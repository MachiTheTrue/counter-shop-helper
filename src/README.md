# Counter & Shop Helper

**Paladins 8.1 (8.1.5839.0) · Lua mod · requires Tempest Scripting 1.1.0 or later**

An in-game helper that reads the enemy team and tells you what to buy and who to watch.

## What it does
- **Shop plan:** Paladins holds 4 items: 4 items to buy in order (count shown out of 4), plus 1
  optional 5th item (soft blue outline) to swap in depending on the match. It is dimmed and marked
  "slots full" once your 4 slots are taken. Each item shows its advised rank, a short reason and a
  coloured mark for its shop category; the next purchase has a gold outline.
- **Live progress:** your items and ranks are read from the game. Grey = not bought, amber = rank
  in progress, green = advised rank reached. Buying something off-plan re-plans the free slots
  around it. If live reading is not available, set your items by hand in the Match tab (4 at
  most; they start at 0 every session and every new match).
- **Enemy threats:** the enemy champions' own abilities, e.g. "Makoa: Dredge Anchor (stuns)".
- **Champion select:** counter-picks and the best roles against the enemy team.
- **8 languages:** English, Français, Deutsch, Italiano, Русский, 简体中文, 日本語, 한국어,
  or Auto (follows the game's language). Champion, item, ability, role and category names and
  item descriptions are read from the game's own text files (Tempest's Game Data API), in the
  language the mod shows; a setting keeps the names in the game's language instead.

## Keys (all changeable in the menu, all on a 60% keyboard)
- `Ctrl+J`: menu (match, settings, help)
- `Ctrl+H`: show / hide the panel
- `Ctrl+K`: switch compact / detailed
- `Ctrl+O`: settings
- `Ctrl+L`: lock the panel

With the menu open, drag the panel to move it or drag its edge to resize it.
Console: `smartcounter` opens or closes the menu.

## Safe by design
Read-only: the mod never buys, never sends anything to the server and changes no game file.
It ships no game art and no game text.

Made by Machi Konno · Discord: machi.konno
