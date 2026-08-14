# DynamicEvents — AI Assistant Guide

## Critical: Deploy after every edit

PZ loads mods from `~/Zomboid/mods/`, NOT from the git repo. There are TWO mods:

**After every file edit, run BOTH:**
```
rsync -av --delete /home/top/Projects/Games/ProjectZomboid/DynamicEvents/42/ ~/Zomboid/mods/DynamicEvents/42/
rsync -av --delete /home/top/Projects/Games/ProjectZomboid/DynamicEvents/42-content/ ~/Zomboid/mods/DynamicEventsContent/42/
```

This is mandatory — never skip it. The game can't see changes without this sync.

## Project structure

- `42/` — **framework mod** (id `DynamicEvents`): core engine only, no events
  - `42/media/lua/server/DynamicEvents/` — core framework (Core, EventManager, EventHelpers, Scheduler, Radio, DebugCommands)
  - `42/media/sandbox-options.txt` — global sandbox options (page `DynamicEvents`)
  - `42/media/lua/shared/Translate/EN/` — sandbox option labels (`Sandbox.json` + `Sandbox_EN.txt`)
- `42-content/` — **content mod** (id `DynamicEventsContent`, `require=DynamicEvents`): individual event definitions
  - `42-content/media/lua/server/DynamicEventsContent/events/` — event .lua files
  - `42-content/media/sandbox-options.txt` — per-event on/off toggles (page `DynamicEventsContent`)

## Sandbox options

Options are real sandbox options, declared in `media/sandbox-options.txt` and
labelled in the `Translate/EN` files. Never assign `SandboxVars.DynamicEvents`
from Lua — that overwrites what the server config set.

`DE.CONFIG_SPEC` in `DE_Core.lua` maps each `SandboxVars.DynamicEvents.*` key to
its `DE.Config` key and default; add new global options in both places.

Per-event toggles are declared by the content mod, and the event points at one
with `enabledVar = "DynamicEventsContent.YourEvent"`.

## Key files

| File | Purpose |
|------|---------|
| `DE_Core.lua` | Logging, RNG, utilities |
| `DE_EventManager.lua` | Event registration, eligibility, persistence |
| `DE_EventHelpers.lua` | Spawn/cleanup helpers AND event context |
| `DE_Scheduler.lua` | Tick loop, spawn rolls, pending spawns |
| `DE_DebugCommands.lua` | Console + admin commands |
| `DE_Radio.lua` | Emergency radio broadcasts |

## Event lifecycle

Events spawn **anywhere on the map and stay forever**, like a vanilla wreck or
Helicopter Event Expanded. Nothing expires on a timer.

There is still no way to force-load a chunk from Lua (`ServerMap` isn't
exposed). Instead, `DE_SquareQueue.lua` parks a *spawn* against a square and
runs it when that square streams in, via the vanilla `Events.LoadGridsquare`
hook — `IsoChunk.doLoadGridsquare` fires it ungated by client/server, so it
works on a dedicated server. This is what EHE gets from its `TargetSquareOnLoad`
dependency; we do it in-house.

So `EM.spawnOrQueue` either spawns immediately (site loaded) or parks the spawn
and lets it materialise when a player arrives. `EM.locationBlockedBy` gates on:
no event already standing within `MinDistanceBetweenEvents` (parked spawns
count), the optional `MaxEventsPerArea` cluster limit, and `SpawnMinDistance`
so nothing pops into view of someone standing there. Spawn rate is governed by
`MinHoursBetweenEvents` (the interval between spawns) and each event's
`cooldownHours`.

The vehicle check can only see loaded chunks, so for a parked spawn it is
re-run for real in `EM.runQueuedSpawn` at materialisation time, along with a
re-check that nothing else claimed the spot.

`SQ.drain()` runs on the scheduler's upkeep pass rather than inside the
`LoadGridsquare` callback, so nothing heavy happens mid chunk-load. The queue
persists with the rest of the state.

## Clearing events (admin only)

`EM.active` is a permanent registry of spawned-but-not-cleared events. Clearing
is manual. If the site's chunk is loaded, `EM.clearEvent` runs the event's
`cleanup` (default `EH.cleanupEvent`) and drops the event from the registry,
freeing the location for reuse. If it is **not** loaded (e.g. right after a
restart, before anyone goes there), the clear is parked against the square via
`DE.SquareQueue` and runs the moment a player streams that chunk in — the same
deferred mechanism the spawn queue uses. `clearEvent` returns `true, "parked"`
in that case.

- `DE.ListEvents()` — every tracked event, nearest first, with uid and coords
- `DE.GoTo(uid)` — teleport to an event so its chunks load (nearest if uid omitted)
- `DE.ClearEvent(uid)` — clear one event (parked if its chunks aren't loaded)
- `DE.ClearNearby(radius)` — clear everything within radius (default 100)
- `DE.Clean()` — clear every tracked event
- `DE.Pending()` — spawns/clears parked against a square, waiting on a chunk load

`EH.cleanupEvent` removes whatever it can reach and silently leaves the rest to
the game: vehicles by id, falling back to a proximity sweep around each
recorded spawn position (a vehicle's runtime id is a 16-bit `short` that gets
reassigned on reload, so the id alone does not survive a restart). Items,
sprites and moveables are removed by square. Zombies are matched by **count**,
not identity — they lose their modData tag and online id the moment their chunk
unloads (the engine virtualizes them), so cleanup removes the same number of
loaded zombies it spawned, from within `ZOMBIE_CLEANUP_RADIUS` (20) of the site.
Dead corpses (`IsoDeadBody`) in that radius are removed too. A custom
`def.cleanup(x, y, z, objects)` replaces the default entirely.

## Creating events

Copy `42-content/media/lua/server/DynamicEventsContent/events/EXAMPLE.lua`, fill in:
- `id`, `name`, `locations` (required)
- `rot` — default rotation, can be overridden per-location
- `enabledVar` — sandbox toggle path; also add the option to `42-content/media/sandbox-options.txt`
- `spawn = function(x, y, z, e)` — use `e:SpawnVehicle()`, `e:SpawnZombies()`, etc.
- No `cleanup` needed, and no lifetime — events are permanent

Everything spawned through the `e` context is tracked so an admin can remove it:
vehicles by id (with a proximity sweep around each recorded spawn position as
fallback, since ids are runtime `short`s that change on reload), items, sprites
and moveables by square. Zombies are tracked as a bare count (`e:SpawnZombies`
returns how many it spawned); on clear the mod removes that many loaded zombies
from around the site.

## Server setup

- Parent framework mod: `~/Zomboid/mods/DynamicEvents/`
- Content mod: `~/Zomboid/mods/DynamicEventsContent/`
- Both listed in `~/Zomboid/Server/ZeroZomboid.ini` Mods line

## Debug

Enable `Debug = true` in sandbox options for verbose logging.
