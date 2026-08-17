# Dynamic Event Framework

A framework for quick and easy custom world events in Project Zomboid (B42).

Two mods:

- **Dynamic Event Framework** (`DynamicEventsFramework`) — the engine.
- **Dynamic Event Framework - Content** (`DynamicEventsContent`) — the event definitions (requires `DynamicEventsFramework`).

Events spawn anywhere on the map and stay forever, like vanilla wrecks, until an
admin clears them. Clearing needs the site's chunks loaded; otherwise it parks
and runs the moment a player loads the area.

## Setup

Enable both in the server/sandbox mods:

```
Mods=DynamicEventsFramework;DynamicEventsContent
```

## Sandbox options

Global page **Dynamic Events**:

| Option | Default | Meaning |
|---|---|---|
| Enabled | true | master switch for new events |
| Hours between events | 1.0 | in-game hours between spawns |
| Grace period | 0 | hours after a fresh start before the first event |
| Spawn min distance | 40 | tiles from a player |
| Max events per area | 0 | anti-cluster limit (0 = off) |
| Area radius | 300 | tiles, for the cluster limit |
| Min distance between events | 20 | tiles between event centers |
| Min distance from vehicles | 15 | tiles from any existing vehicle |
| Remove event zombies when clearing | true | |
| Debug logging | false | verbose console output |

Per-event on/off toggles live on page **Dynamic Events - Events**.

## Admin commands

In-game debug console (`.Command`) or server console. All admin-gated.

| Command | Purpose |
|---|---|
| `DE.Spawn(id, x, y, z, rot)` | spawn an event (parks if area not loaded) |
| `DE.SpawnHere(id)` | spawn at your position |
| `DE.SpawnRandom()` | spawn a random event type |
| `DE.SpawnForce(id, x, y, z, rot)` | spawn, clearing vehicles in the area first |
| `DE.ListEvents()` | tracked events, nearest first, with uids |
| `DE.Pending()` | spawns/clears waiting on a chunk load |
| `DE.GoTo(uid)` | teleport to an event (nearest if omitted) |
| `DE.ClearEvent(uid)` | clear one event |
| `DE.ClearNearby(radius)` | clear events within radius (default 100) |
| `DE.Clean()` | clear every event |
| `DE.Purge(radius)` | remove leftovers of events the mod forgot (default 30) |
| `DE.ClearCooldowns()` | reset all event cooldowns |
| `DE.SchedulerInfo()` | what the scheduler is waiting for |
| `DE.Info()` | config + registered events |
| `DE.WhereAmI()` | your coordinates |
| `DE.VehicleInfo()` | vehicle on your square |
| `DE.TagHere()` | event tags on your square |
| `DE.CheckSpot(radius)` | count vehicles around you |
| `DE.Outfits(keyword)` | list zombie outfit names |

## Event definition

Copy `DynamicEventsContent/42/media/lua/server/DynamicEventsContent/events/EXAMPLE.lua`.

Required:

- `id` — unique string, e.g. `"my_event"`.
- `name` — display name.
- `locations` — `{ { name=, x=, y=, z=, rot= } }`.
- `spawn = function(x, y, z, e)` — build the event with `e:...` (see below).

Optional:

- `enabledVar` — sandbox toggle path (`"DynamicEventsContent.MyEvent"`); also add
  the option to the content mod's `media/sandbox-options.txt`.
- `weight` (10) — weighted-random pick chance.
- `cooldownHours` (24) — hours before this type can fire again (0 = never).
- `minDaysSurvived` (0) — in-game days before eligible.
- `dependencies` — mod IDs that must be active.
- `rot` (0) — default rotation in degrees.
- `clearObstacles = true`, `clearRadius = N` — clear vehicles in the spawn area
  instead of skipping the location.
- `warning = { delay = 60 }` — in-game seconds of warning before the spawn.
- `sound` — sound played at spawn.
- `radio = { ... }` — periodic broadcasts (see below).

No `cleanup` and no lifetime — events are permanent and clean up automatically.

### Radio

```lua
radio = {
    frequency = 105600,   -- kHz (105.6 MHz)
    interval  = 7200,     -- in-game seconds between broadcasts
    range     = 200,      -- tiles of clear signal
    messages  = { "Convoy under fire near {name}!" },
}
```

Message placeholders: `{name}` (location), `{x}`/`{y}` (coordinates), or legacy
`%s` for `"name (x, y)"`. Each can be used on its own or together.

## Spawn context `e`

All methods take `(dx, dy)` offsets from the location centre, rotated by `e.rot`;
any `opts` table accepts `radius` for position jitter.

| Method | Notes |
|---|---|
| `e:SpawnVehicle(script, dx, dy, opts)` | `opts`: `rot`, `skin`, `loot`, `working` |
| `e:SpawnZombies(count, outfit, dx, dy, opts)` | `opts.spread` = scatter radius |
| `e:SpawnItem(itemType, dx, dy, opts)` | single ground item |
| `e:SpawnLootScatter(items, dx, dy, opts)` | `opts.spread`, `opts.chance` |
| `e:SpawnContainer(type, loot, dx, dy, opts)` | bag/case or moveable crate |
| `e:SpawnFire(n, dx, dy)` / `e:SpawnSmoke(n, dx, dy)` | |
| `e:SpawnScorch(dx, dy, opts)` | burnt floor marks |

`SpawnVehicle` opts:

- `loot` — a table of item types, or `"vanilla"` to roll the vehicle's own loot.
- `working` — true leaves the vehicle drivable (otherwise wrecked).

`SpawnContainer` types: any `ItemType = base:container` (e.g. `Base.Bag_Military`,
`Base.Toolbox`) or moveables (`Base.Mov_MilitaryCrate`, `Base.Mov_MilitaryLocker`).

## Ownership and cleanup

Everything spawned through `e` is stamped with the event's id in its `modData`,
so an admin clear sweeps the event's footprint and removes exactly what the event
put there. Your car parked on top of a wreck, or a bag you dropped on the site,
is left alone. Tags are saved with the object, so they survive a server restart.

Two exceptions:

- **Zombies** can't be tagged — the engine recycles them once their chunk
  unloads. They're counted instead, and a clear removes that many walkers (and
  any corpses) from within 20 tiles of the site.
- **Loot inside a spawned crate** is untagged on purpose. Take it out and stash
  it nearby and it's yours to keep; leave it in and it goes with the crate.

`DE.Purge(radius)` mops up tagged leftovers from events the mod no longer tracks
(a rolled-back save, an interrupted clear). It never touches an event that is
still listed by `DE.ListEvents()` — use `DE.ClearEvent(uid)` for those.
