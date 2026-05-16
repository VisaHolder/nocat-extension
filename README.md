# nocat

A personal grab-bag of small fixes and grinding tools for retail WoW. Started as a kill counter, kept growing every time something bugged me.

If you've ever wanted to know exactly how many Ossuary Creepers you've killed across every character, keep your pet out without thinking about it, stop your weapon from sheathing every five seconds, or quickly check if a piece of loot is an appearance you already have — that's what this is for.

---

## What's in the box

### Kill tracker
The core feature. Counts everything you kill, both per-character and account-wide, and stops being annoying about it.

- Per-mob counts saved to a global database (one number per NPC ID across all your characters) and a per-character database (just this toon).
- Optional hover tooltip showing how many times you've killed that mob.
- Optional XP/kill estimate in the tooltip, plus how many more kills until you ding.
- Configurable milestone alerts ("you just hit 5,000 of these!") with a big on-screen popup.
- A floating instant counter window — drag it anywhere — that ticks up as you grind. Set it to alert every N kills, optionally filtered to only count mobs matching a name pattern.
- Tracks kills from group/raid members too if you turn that on.
- Pauses tracking inside dungeons or raids if you want it to.
- Per-target kill timer: start a 5-minute timer, see your KPM and KPH at the end.
- Session stats: kills this session, kills/minute, kills/hour.
- Top-N list of your most-killed mobs.
- "Purge junk" command to wipe entries below a kill threshold so your database stays clean.

### Pet companion
Keeps a battle pet out without you having to think about it.

- Auto-summons whenever you become eligible (out of combat, not mounted, not stealthed, no restricted UI open, etc.).
- Pick a specific pet from a dropdown, or let it roll random from your favorites.
- "Summon Now" button for when you want to force it without waiting for an event.
- Knows about the dumb edge cases — stealth, swimming-and-moving, dragonriding, flight master windows — and doesn't try to summon while you're in them. No "you can't do that right now" popups.

### Weapon unsheathe
Re-draws your weapon whenever the game puts it away.

- Fires on the usual triggers: combat end, loot close, merchant close, quest complete, dismount, exiting vehicles, leaving the barber.
- Optional toggle for staying drawn inside cities/inns.
- Per-spec on/off — if you play Holy on one spec but want the weapon out on Ret, that's fine.

### Map zoom — follow mode
- "Follow player" keeps the world map centered on your character as you move/fly. Smooth, no jitter, and skips redraws when you haven't actually moved (so it doesn't tank your framerate when you're flying around).

### Transmog (embedded "Can I Mog It?")
The full CanIMogIt addon is bundled inside nocat — you don't need to install it separately. It adds tooltip text and corner overlay icons telling you if you've collected an appearance.

- Red X on items you haven't learned.
- Green check on items you have.
- Cyan check for "you know this appearance from a different item."
- Grey for "your class can't learn this."
- Works on bags, loot, vendors, mail, AH, encounter journal, quest rewards, etc.
- Bag overlays show up in default Blizzard bags and in supported bag addons: AdiBags, ArkInventory, Bagnon, BetterBags, ElvUI, LiteBag, cargBags-Nivaya — plus **Baganator**, which we bridge to manually (Baganator's built-in CanIMogIt hook doesn't fire when CIMI is embedded, so nocat re-registers it).
- All settings controllable from `/nocat → Transmog`. CanIMogIt's own slash commands (`/cimi`, `/canimogit`) are disabled — use nocat's instead.

### Minimap button
A small cat-face icon next to your minimap. Click it to open the settings panel. Drag to move. Plays nice with square minimaps from Leatrix Plus / ElvUI / etc.

---

## Commands

Type `/nocat` to open settings, or `/nocat help` for the full list.

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

### Kill tracker — viewing
| Command | What it does |
|---|---|
| `/nocat list` | Opens the full mob database window |
| `/nocat target` *or* `/nocat t` | Prints kill count for whatever you're targeting |
| `/nocat lookup <name or id>` | Prints kill count for a specific mob |
| `/nocat top [N]` | Prints your top-N most-killed mobs (default 5, max 25) |
| `/nocat announce [channel]` | Posts session stats to chat (default: SAY) |

### Kill tracker — toggles
| Command | What it does |
|---|---|
| `/nocat print` | Toggle per-kill chat message |
| `/nocat printnew` | Toggle "you killed a new mob!" announcements |
| `/nocat countmode` | Toggle counting party/raid member kills as your own |
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

### Map
| Command | What it does |
|---|---|
| `/nocat follow` | Toggle "follow player on the map" |

### Weapon unsheathe
| Command | What it does |
|---|---|
| `/nocat unsheathe` | Toggle weapon unsheathe |
| `/nocat unsheathe city` | Toggle whether to stay unsheathed in cities/inns |
| `/nocat unsheathe spec` | Toggle for your current spec |
| `/nocat unsheathe status` | Print current unsheathe settings |

### Transmog
| Command | What it does |
|---|---|
| `/nocat mog` | Opens the Transmog page in settings |
| `/nocat mog unknown` | Toggle "only show on items you haven't collected" |
| `/nocat mog bag` | Toggle bag corner overlay icons |

---

## Settings panel

Everything's also reachable from `/nocat`. The panel has tabs on the left:

- **Kill Tracker** — every toggle and threshold for the tracker, plus quick-action buttons (Mob List, Kill Counter, Announce, Target Kills, Purge Junk, Reset All).
- **Pet Companion** — auto-summon toggle, pet picker dropdown, Summon Now button.
- **Map Zoom** — follow toggle.
- **Weapon** — unsheathe toggles + "toggle current spec" button.
- **Transmog** — every CanIMogIt option grouped into Filters / Display / Item Types, plus a status line for Baganator integration.
- **General** — startup behaviour.

Every checkbox, input, and button shows a description tooltip when you hover it. No mystery boxes.

---

## Saved variables

- `NocatExtensionDB` — all nocat settings, kill counts, mob names, panel state.
- `CanIMogItOptions` — the bundled CanIMogIt's settings.

Both persist across sessions. The kill database is global (shared across characters) plus a per-character mirror.

---

## Notes / gotchas

- If you've got the standalone **Can I Mog It?** addon enabled in your addon list, disable it. nocat bundles the full CanIMogIt source inside itself, so running both at once causes a name collision and you'll get red errors at login. nocat prints a chat warning if it detects this.
- Pet auto-summon respects restricted UI states (flight masters, merchants, mailbox, etc.) so you won't see "blocked from an action" popups.
- Weapon unsheathe defers by a fraction of a second after merchant/quest close so the frame actually hides before nocat checks — without this, the unsheathe gets blocked.
- All kill counts use **NPC ID** as the key, not name. Renames in future patches don't lose your data.
- Map follow throttles its scroll updates so flying around doesn't cause stuttering. You can move and the map keeps up; you stand still and nocat does nothing.

---

## Why "nocat"

There's no good reason. It started as a joke, the name stuck.
