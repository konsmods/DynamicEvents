# DynamicEvents — AI Assistant Guide

## Critical: Deploy after every edit

PZ loads mods from `~/Zomboid/mods/DynamicEvents/`, NOT from the git repo.

**After every file edit, run:**
```
rsync -av --delete /home/top/Projects/Games/ProjectZomboid/DynamicEvents/42/ ~/Zomboid/mods/DynamicEvents/42/
```

This is mandatory — never skip it. The game can't see changes without this sync.

## Project structure

- `42/` — the actual PZ B42 mod (mod.info, media/lua/, media/scripts/, media/models/)
- `42/media/lua/server/DynamicEvents/` — core framework
- `42/media/lua/server/DynamicEvents/events/` — individual event definitions
- `42/media/lua/shared/Sandbox/` — sandbox options

## Key files

| File | Purpose |
|------|---------|
| `DE_Core.lua` | Logging, RNG, utilities |
| `DE_EventManager.lua` | Event registration, eligibility, persistence |
| `DE_EventHelpers.lua` | Spawn/cleanup helpers AND event context |
| `DE_Scheduler.lua` | Tick loop, firing, expiry |
| `DE_DebugCommands.lua` | Console commands (.Spawn, .Clean, .Outfits) |

## Creating events

Copy `events/EXAMPLE.lua`, fill in:
- `id`, `name`, `locations` (required)
- `rot` — default rotation, can be overridden per-location
- `spawn = function(x, y, z, e)` — use `e:SpawnVehicle()`, `e:SpawnZombies()`, etc.
- Cleanup is automatic, no need to define

## Debug

Enable `Debug = true` in sandbox options for verbose logging.
