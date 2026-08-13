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
  - `42/media/lua/shared/Sandbox/` — sandbox options
- `42-content/` — **content mod** (id `DynamicEventsContent`, `require=DynamicEvents`): individual event definitions
  - `42-content/media/lua/server/DynamicEventsContent/events/` — event .lua files

## Key files

| File | Purpose |
|------|---------|
| `DE_Core.lua` | Logging, RNG, utilities |
| `DE_EventManager.lua` | Event registration, eligibility, persistence |
| `DE_EventHelpers.lua` | Spawn/cleanup helpers AND event context |
| `DE_Scheduler.lua` | Tick loop, firing, expiry |
| `DE_DebugCommands.lua` | Console commands (.Spawn, .Clean, .Outfits) |
| `DE_Radio.lua` | Emergency radio broadcasts |

## Creating events

Copy `42-content/media/lua/server/DynamicEventsContent/events/EXAMPLE.lua`, fill in:
- `id`, `name`, `locations` (required)
- `rot` — default rotation, can be overridden per-location
- `spawn = function(x, y, z, e)` — use `e:SpawnVehicle()`, `e:SpawnZombies()`, etc.
- Cleanup is automatic, no need to define

## Server setup

- Parent framework mod: `~/Zomboid/mods/DynamicEvents/`
- Content mod: `~/Zomboid/mods/DynamicEventsContent/`
- Both listed in `~/Zomboid/Server/ZeroZomboid.ini` Mods line

## Debug

Enable `Debug = true` in sandbox options for verbose logging.
