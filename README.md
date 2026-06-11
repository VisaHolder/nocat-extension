<div align="center">

# nocat.extension

**A personal grab-bag of grinding tools for retail World of Warcraft.**

Lua · Ace3 · The War Within (12.0.x)

</div>

---

> **Personal addon.** Built piece-by-piece every time something in WoW bugged me.
> Not on Curse / Wago — grab the latest drag-and-drop build from
> [Releases](../../releases/latest), or clone the source below.

---

## Features

### Kill tracker — the Bestiary

Counts everything you kill, per-character and account-wide. The list window is a full **Bestiary**: searchable, sortable, with a **live 3D model** of whatever you hover.

- Per-mob counts saved to a global DB (one number per NPC ID across every character) and a per-character mirror.
- Bestiary window (`/nocat list`): NPC ID / Name / Char / Total columns, click to sort, search by name or id.
- **Trophy pedestal** on the right: hover any row → that mob's 3D model loads on a pedestal and auto-spins. **Drag** to rotate, **mouse-wheel** to zoom, **`o`** to toggle spin.
- Flavour **bestiary rank** that climbs as you farm a mob (Acquainted → Hunter → Slayer → Nemesis → Executioner → Annihilator → Worldbane).
- Live **milestone progress bar** to your next kill threshold.
- Optional hover tooltip on real mobs in the world: how many you've killed (char + total).
- Optional XP/kill estimate in the tooltip (rested-bonus aware; hidden at max level since it's not actionable).
- Configurable milestone alerts ("you just hit 5,000 of these!") with a big on-screen popup.
- A floating instant counter window — drag it anywhere — that ticks up as you grind. Threshold alerts + optional name filter.
- Pauses tracking inside dungeons or raids if you want it to.
- Per-target **kill timer** with KPM / KPH at the end.
- Session stats (kills, KPM, KPH) and top-N most-killed list.
- "Purge junk" command to wipe entries below a kill threshold so your database stays clean.

### Pet companion

Keeps a battle pet out without you having to think about it.

- Auto-summons whenever you become eligible (out of combat, not mounted, not stealthed, no restricted UI open, etc.).
- Pick a specific pet from the dropdown, or roll random from your favorites — uses `C_PetJournal.SummonRandomPet(true)` so a journal filter can't accidentally hide them.
- Validates the saved pet GUID; if the pet was caged or released it falls back to a random favorite instead of silently failing.
- Bounded retry burst on login / zone change (the journal often isn't loaded the instant `PLAYER_ENTERING_WORLD` fires).
- Respects restricted UI states (flight master / merchant / mailbox / etc.) so you never see "blocked from an action" popups.
- `/nocat pet debug` reports the exact blocker if it's not summoning.

### Weapon stance

Re-draws **or** keeps sheathed — your choice.

- Two stance modes: **drawn** (weapon always out) or **sheathed** (weapon always put away). Pick one in the options panel; the other auto-clears.
- Reliable triggers: combat end, loot/merchant/quest close, dismount (via `PLAYER_MOUNT_DISPLAY_CHANGED`), vehicle exit, ghost/alive transitions.
- Optional "stay drawn while resting in cities/inns."
- Per-spec on/off — play Holy on one spec but want the weapon out on Ret? Fine.
- `/nocat unsheathe debug` runs a live `ToggleSheath` test so you can see whether the call works in your current context.

> **Limitation:** melee vs ranged pose is *not* selectable — WoW has no `SetSheathState` API. The game itself picks which weapon shows when drawn.

### Minimap button

LibDBIcon-1.0 backed. Click to open settings, right-click to open the Bestiary, drag to move. Plays nice with square minimaps from Leatrix Plus / ElvUI / MoveAny.

---

## Tech

| Layer | Stack |
|---|---|
| Game | World of Warcraft Retail — The War Within (12.0.5, 12.0.7) |
| Language | Lua 5.1 (WoW dialect) |
| Framework | Ace3 — `AceAddon-3.0`, `AceDB-3.0`, `AceEvent-3.0` |
| Bundled libs | `LibStub`, `CallbackHandler-1.0`, `LibDataBroker-1.1`, `LibDBIcon-1.0` |
| Saved variables | `NocatExtensionDB` (global tables + per-character mirrors) |

## Project layout

```
nocat.extension/
├── nocat.extension.toc      # AddOn manifest — interface versions + load order
├── Core.lua                 # AceAddon init, DB defaults, kill-tracker core, tooltip
├── Weapon.lua               # Unsheathe / stance enforcement
├── PetCompanion.lua         # Auto-summon companion pet
├── MobList.lua              # Bestiary window — 3D model pedestal + sortable table
├── Timer.lua                # Per-target kill timer (KPM/KPH)
├── ImmediateFrame.lua       # Floating session counter
├── ExpTracker.lua           # XP-per-kill estimator (rested-aware)
├── Options.lua              # Settings panel
├── MinimapButton.lua        # LDBI-backed minimap icon
├── Command.lua              # /nocat slash command dispatcher
├── CHANGELOG.md
├── LICENSE                  # MIT
├── docs/                    # Screenshots (optional)
└── libs/                    # Bundled Ace3 + LDB + LDBI (no externals)
```

## Install

Download the latest **`nocat.extension-x.y.z.zip`** from [Releases](../../releases/latest)
and unzip it, then drop the `nocat.extension/` folder (the one containing
`nocat.extension.toc`) into:

```
World of Warcraft/_retail_/Interface/AddOns/
```

…then `/reload` or restart the client. The minimap cat-face icon means it loaded.

> Prefer to clone? The repo root *is* the `nocat.extension/` folder — clone it
> straight into `AddOns/nocat.extension/`.

---

## Commands

Type `/nocat` to open settings, or `/nocat help` for the full list. Also available as `/nce`.

### General

| Command | What it does |
|---|---|
| `/nocat` | Opens the settings panel |
| `/nocat help` *or* `/nocat ?` | Prints this list in chat |
| `/nocat options` | Opens settings (same as no args) |
| `/nocat loadmessage` | Toggle the chat message that prints on login |
| `/nocat data` | Prints session stats: kills, KPM, KPH |
| `/nocat minimap` | Show/hide the minimap button |
| `/nocat mmreset` | Resets the minimap button to its default position |
| `/nocat debug` | Diagnostic: event counts, init errors, last kill, etc. |

### Kill tracker — viewing

| Command | What it does |
|---|---|
| `/nocat list` | Opens the Bestiary window |
| `/nocat target` *or* `/nocat t` | Prints kill count for whatever you're targeting |
| `/nocat lookup <name or id>` | Prints kill count for a specific mob |
| `/nocat top [N]` | Prints your top-N most-killed mobs (default 5, max 25) |
| `/nocat announce [channel]` | Posts session stats to chat (default: SAY) |

### Kill tracker — toggles

| Command | What it does |
|---|---|
| `/nocat print` | Toggle per-kill chat message |
| `/nocat printnew` | Toggle "you killed a new mob!" announcements |
| `/nocat tooltip` | Toggle kill count in mob tooltips |
| `/nocat showexp` *or* `/nocat xp` | Toggle XP/kill in tooltips |
| `/nocat dungeons` | Toggle disabling tracking inside 5-mans |
| `/nocat raids` | Toggle disabling tracking inside raids |
| `/nocat threshold [N]` | Set milestone kill threshold (0 = off) |

### Kill tracker — instant counter

| Command | What it does |
|---|---|
| `/nocat imm` | Show/hide the floating counter |
| `/nocat imm threshold <N>` | Alert every N kills (0 = off) |
| `/nocat imm filter <pattern>` | Only count mobs whose names contain this text |
| `/nocat imm clearfilter` | Removes the filter |

### Kill tracker — kill timer

| Command | What it does |
|---|---|
| `/nocat timer <dur>` | Start a timer. Accepts `5m`, `3m30s`, `90` (seconds) |
| `/nocat stop` | Stop the running timer |

### Kill tracker — editing data

| Command | What it does |
|---|---|
| `/nocat set <id> <name> <global> <char>` | Manually set kill counts for a mob |
| `/nocat delete <id>` | Removes a mob entry from your database |
| `/nocat purge [N]` | Remove all mobs with fewer than N global kills (default 2) |
| `/nocat reset` | Wipe **all** kill data (asks first) |

### Pet companion

| Command | What it does |
|---|---|
| `/nocat pet` | Toggle auto pet summon |
| `/nocat pet now` | Force-summon the currently selected pet right now |
| `/nocat pet debug` | Diagnose why auto pet summon is blocked |

### Weapon stance

| Command | What it does |
|---|---|
| `/nocat unsheathe` | Toggle the feature on/off |
| `/nocat unsheathe pose <drawn\|sheathed>` | Pick the stance (or cycle with no arg) |
| `/nocat unsheathe city` | Toggle staying drawn in cities/inns |
| `/nocat unsheathe spec` | Toggle for your current spec |
| `/nocat unsheathe status` | Print current settings |
| `/nocat unsheathe debug` | Live ToggleSheath test + named blocker |

---

## Settings panel

Everything's also reachable from `/nocat`. The panel has tabs on the left:

- **Kill Tracker** — every toggle and threshold for the tracker, plus quick-action buttons (Mob List, Kill Counter, Announce, Target Kills, Purge Junk, Reset All).
- **Pet Companion** — auto-summon toggle and pet picker dropdown with a Summon Now button.
- **Weapon** — stance radio (drawn / sheathed), in-cities override, per-spec toggle.
- **General** — startup behaviour.

Every checkbox, input, and button shows a description tooltip on hover. No mystery boxes.

---

## Saved variables

- `NocatExtensionDB` — all settings, kill counts, mob names, panel state.

Stored globally (shared across characters) with a per-character mirror for char-only counts. Kill data is keyed by **NPC ID**, not name, so future patch renames don't lose your data.

---

## Notes / gotchas

- Pet auto-summon and weapon enforcement both respect restricted UI states (flight masters, merchants, mailbox, etc.) so you won't see "blocked from an action" popups.
- Weapon enforcement defers by a fraction of a second after frame-close events so the secure frame actually hides before the addon re-checks.
- XP-per-kill is an **estimate** — it subtracts the rested bonus but can't separate War Mode / heirloom / buff inflation from a raw `UnitXP` delta.
- The `.toc` declares multiple Interface versions so Blizzard's minor patches (e.g. 12.0.5 → 12.0.7) don't auto-flag the addon out-of-date.

---

## Releasing a new version

Bump `## Version:` in `nocat.extension.toc`, add a `CHANGELOG.md` entry, then tag:

```bash
git commit -am "vX.Y.Z release notes"
git tag vX.Y.Z
git push origin main --tags
```

Pushing a `v*` tag triggers [`.github/workflows/release.yml`](.github/workflows/release.yml)
(BigWigs packager), which builds `nocat.extension-vX.Y.Z.zip` and publishes the
GitHub release automatically — no manual zipping.
