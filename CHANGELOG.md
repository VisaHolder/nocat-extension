# nocat.extension Changelog

## 1.2.2 — 2026-06-11

### Housekeeping
- Removed the unused **AceLocale-3.0** library from `libs/` — it was never listed
  in the `.toc` (so the game never loaded it) and the addon has no localization
  layer. Pure dead weight in the packaged zip; gone now.
- Removed a dead `_applyModelLight()` function left over from the Bestiary
  model-rendering debugging. The shipped render path uses `SetDisplayInfo`, so
  this `SetLight` helper was never called.

No behaviour changes — this is a leanness/cleanup release.

## 1.2.1 — 2026-06-11

### Fixed
- **Bestiary 3D models now render.** `_modelLoadGen` was declared *after* the
  `ClearPreview` function that uses it, so during pedestal setup it hit a nil
  global and `nil + 1` threw — the whole model frame got discarded and the
  pedestal stayed black. Declared it at the top of the file.
- **Pet auto-summon no longer silently fails.** `summonBlocker` called
  `UnitIsControlling`, which isn't a real API on 12.0.x — it threw inside the
  summon ticker (no visible error) and aborted every auto-summon. Nil-guarded.
- **Model rendering** uses `SetDisplayInfo` (resolved from the NPC id) instead
  of `SetCreature`, which stopped drawing in UI frames on 12.0.7.
- The auto-spin **`o`** button works again — it sat under the mouse-enabled
  model frame so clicks never reached it (raised its frame level), and the
  toggle now persists instead of resetting to ON on every preview.
- Guarded `C_UnitAuras`, tracked the pet safety-net ticker, fixed the
  "Showing X of Y" count, and hid a stale XP line in the preview.

### Changed
- **Pet & Weapon now activate anywhere it's possible.** The pet auto-summons in
  every valid state (flying, resting, cities, …) — only combat, vehicles, death,
  secure frames, **stealth/invisibility** (so it won't blow your cover), and
  "already out" hold it back. The weapon also draws everywhere (resting / being
  in a city no longer blocks it).
- **Click-to-select** in the Bestiary: clicking a row pins it with a gold
  highlight that persists as you scroll; hovering is a temporary peek that snaps
  back to your selection. Opening the list always sorts by Total (high → low)
  and auto-selects the top mob so the pedestal shows it immediately.

## 1.2.0 — 2026-06-02

### Bestiary — the mob database is now a trophy room
- The Mob List is rebuilt as a **Bestiary**. The sortable/searchable kill table
  lives on the left; the right half is a **trophy pedestal** that shows the
  selected creature's actual in-game 3D model.
- **Hover any mob** in the list to inspect it: the model loads on a dark
  pedestal and slowly auto-spins. **Drag** the model to rotate it by hand,
  **mouse-wheel** to zoom, and the **o** button toggles auto-spin.
- Each mob gets a flavour **Bestiary rank** that climbs as you farm it
  (Acquainted → Hunter → Slayer → Nemesis → Executioner → Annihilator →
  Worldbane), plus this-character / all-character kill counts, XP per kill,
  and a **progress bar toward your next kill milestone**.
- Clicking a row pins it in the pedestal; the panel keeps its numbers live as
  kills roll in (the model itself only reloads when you pick a different mob).
- All model calls are guarded, so a creature without a cached model just shows
  the stats instead of erroring.

## 1.1.0 — 2026-06-02

### Pet Companion — reliability overhaul
- Random favourites now use the built-in, filter-immune
  `C_PetJournal.SummonRandomPet(true)`. Fixes the case where an active Pet
  Journal filter silently hid your favourites so auto-summon did nothing while
  the manual button still worked.
- A saved "specific pet" selection is now validated; if that pet was caged or
  released the stale entry is cleared and a random favourite is summoned instead
  of silently failing.
- Login/zone now fire a short self-cancelling retry burst (up to ~10s) to catch
  the moment the Pet Journal finishes loading — fixes "only summons sometimes
  after logging in".
- Added re-summon triggers: resurrect / release (PLAYER_UNGHOST, PLAYER_ALIVE).
- Turning the feature on now summons immediately.
- New: `/nocat pet debug` reports exactly what is blocking a summon.

### Weapon Unsheathe — reliability overhaul
- Reliable re-draw on dismount via PLAYER_MOUNT_DISPLAY_CHANGED (replaces the
  fragile aura-based mount detection).
- Added re-draw triggers for resurrect/release and more closed frames.
- New: `/nocat unsheathe debug` names the exact blocking condition and runs a
  live ToggleSheath test so you can see whether the draw call works in your
  current context.

### Notes
- Verified against Midnight 12.0.5: `ToggleSheath` is unprotected and
  `C_PetJournal.SummonPetByGUID` is only combat-restricted, so both are safe to
  call from the addon's timers/events outside combat.

## 1.0.0 — 2026-05-15

### Initial release

**Pet Companion**
- Auto-summons a random favourite companion pet
- Listens to 7 events: PLAYER_STARTED_MOVING, PLAYER_STOPPED_MOVING,
  PLAYER_REGEN_ENABLED, UPDATE_STEALTH, UNIT_EXITED_VEHICLE,
  ZONE_CHANGED_NEW_AREA, PLAYER_ENTERING_WORLD
- Longer delay on zone/login events to let game state settle
- Zero CPU cost at idle — fully event-driven

**Map Zoom**
- Remembers zoom level and pan position per zone across sessions
- Optional follow-player mode centres the map on your character
- Default zoom setting for first-time zone visits
- Hooks WorldMapFrame via ADDON_LOADED for Blizzard_WorldMap compatibility
- Capture ticker (0.25s) only runs while the map is open
- Follow ticker (0.25s) only runs while map is open AND follow is enabled

**Kill Tracker**
- Tracks global and per-character kill counts for every NPC
- Searchable, sortable mob database with FauxScrollFrame virtual scroll
- Kill timer with countdown progress bar (green → yellow → red)
- Floating instant kill counter with name filter and threshold alerts
- XP-per-kill tracker using a 3-second attribution window with running average
- Mob tooltips show kill count and optionally XP/kills-to-level
- Milestone alerts shown as large on-screen raid-boss popups
- Party/raid kill credit (optional), dungeon/raid tracking disable (optional)
- Per-kill and new-mob chat announcements

**Weapon Unsheathe**
- Keeps weapon drawn at all times outside of blocked conditions
- Per-specialisation enable/disable toggle
- City/resting zone toggle
- Mutes sheathe/unsheathe sound effects to hide re-sheathe noise
- Full pseudo-vehicle aura blocklist (gliders, Divine Steed, toys, etc.)
- UNIT_AURA filtered to player unit only
- Single 3s fallback ticker — no redundant polling
- All logic is local/scoped — no global namespace pollution

**Options panel**
- Single unified Blizzard settings panel under /nocat options
- Sections: Pet Companion, Map Zoom, Kill Tracker, Weapon Unsheathe, General
- All checkboxes have hover tooltips explaining each setting
- Quick action buttons: Mob List, Kill Counter, Announce, Target Kills, Purge, Reset

**Commands**
- /nocat (or /nce) — main command
- /nocat pet — toggle pet companion
- /nocat zoom — toggle map zoom memory
- /nocat follow — toggle map follow mode
- /nocat unsheathe [city|mute|spec|status] — weapon unsheathe controls
- Full kill tracker commands: list, timer, stop, imm, target, lookup, set,
  delete, announce, purge, reset, print, printnew, countmode, tooltip,
  showexp, threshold, dungeons, raids, data

---

### Thanks

Big thanks to the authors of PetPet, KeepMyZoom, MobKillCount, and
StayUnsheathed for their open-source work, and to the wider WoW addon
community for years of shared knowledge, open APIs, and keeping the
game fun.
