# Changelog

## 0.2.0

- **Reliable cleanup** — every spawned vehicle, item, container and scorch mark is
  now tagged in its own modData (`de_uid`) and swept up by that tag, so a clear
  removes exactly what the event placed and nothing else. Survives server restarts.
- **Auto-clear by lifetime** — events with `lifetimeHours` set now expire and clean
  themselves up on their own (used by City Repopulation); others stay until an admin
  clears them.
- **Per-event zombie cleanup radius** — `zombieCleanupRadius` (default 20 tiles).
- **Admin panel** — resizable, tabbed window (Active Events / Spawn / Scheduler)
  with per-item detail panels; list, jump to, spawn and clear events.
- **Fixed Go To** — the button and `DE.GoTo` command now teleport correctly in both
  single-player and multiplayer.
- **Containers over loose loot** — a spawned crate's contents are left untagged, so
  loot a player keeps stays clean; loose ground items are still tagged and cleaned.
- Large internal cleanup and simplification pass.
