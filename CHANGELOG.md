# nocat.extension Changelog

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
