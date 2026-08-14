-- ============================================================================
-- Example Event Template
-- Copy this file to events/YourEvent.lua and fill in the blanks.
-- ============================================================================

local EVENT = {

    -- Required: unique string ID (used for sandbox toggle, debug commands)
    id = "example_event",

    -- Required: display name
    name = "Example Event",

    -- Optional: sandbox option that switches this event on and off, given as
    -- a dotted SandboxVars path. Declare the matching option in this mod's
    -- media/sandbox-options.txt and give it a label in
    -- media/lua/shared/Translate/EN/Sandbox.json (and Sandbox_EN.txt).
    -- Without this field the event is always eligible.
    enabledVar = "DynamicEventsContent.ExampleEvent",

    -- Optional: default rotation in degrees (0=North, 90=East)
    -- Individual locations can override this with their own rot.
    rot = 0,

    -- Optional: mod IDs that must be active for this event to fire
    -- dependencies = { "SomeModID", "AnotherModID" },

    -- Optional tuning (shown with defaults)
    weight         = 10,    -- higher = more likely to be chosen
    cooldownHours  = 48,    -- hours before this event can fire again
    minDaysSurvived = 0,    -- in-game days before this event is eligible
    --
    -- Events are permanent: once spawned they stay in the world like a vanilla
    -- wreck, until an admin clears them with DE.ClearEvent / DE.ClearNearby.
    -- A location is blocked while its event is still standing, and becomes
    -- available again once cleared.

    -- Optional: clear vehicles in the spawn area instead of skipping a blocked
    -- location. clearRadius is how much space to clear (defaults to the global
    -- MinDistanceFromVehicles). Set both when the event must fit a specific spot.
    -- clearObstacles = true,
    -- clearRadius    = 25,

    -- Optional: sound effect played at the event location
    -- sound = "MetaShotgun1",

    -- Optional: delay before the event spawns (warning period)
    -- warning = { delay = 60 },

    -- Optional: radio broadcasts sent periodically from the event location.
    -- Players with radios tuned to the emergency frequency will hear them.
    -- %s is replaced with the location name and coordinates.
    -- interval defaults to 7200 seconds (2 in-game hours).
    -- range defaults to 200 tiles.
    -- radio = {
    --     interval = 7200,
    --     range    = 200,
    --     messages = {
    --         "MAYDAY! Convoy under fire near %s!",
    --         "Emergency broadcast from %s — requesting immediate support!",
    --     },
    -- },

    -- =========================================================================
    -- Locations: where this event can spawn.
    -- Each can have its own rot to match road/terrain orientation.
    -- Use DE.WhereAmI() in-game to get coordinates.
    -- =========================================================================
    locations = {
        { name = "North-south road", x = 10000, y = 10000, z = 0, rot = 0   },
        { name = "East-west road",   x = 10500, y = 10000, z = 0, rot = 90  },
    },

    -- =========================================================================
    -- SPAWN: called when the event fires at a chosen location.
    --
    -- The context `e` provides:
    --   e.x, e.y, e.z  — world coordinates of the chosen location
    --   e.rot          — rotation from the chosen location (or def.rot fallback)
    --
    -- All e:Spawn* methods take (dx, dy) as offsets from (e.x, e.y),
    -- automatically rotated by e.rot.
    --
    -- Add { radius = N } to any opts table to jitter the spawn position
    -- within N tiles (less grid-aligned).
    --
    -- You DO NOT need to track objects or return anything — the context
    -- handles tracking and cleanup automatically.
    -- =========================================================================
    spawn = function(x, y, z, e)

        -- --- Vehicles --------------------------------------------------------
        -- e:SpawnVehicle(scriptName, dx, dy, opts)
        --   opts: rot (vehicle rotation override), skin, loot, radius
        --
        e:SpawnVehicle("Base.PickUpTruck_Camo", 0, 5, {
            rot    = e.rot + DE.rand(-10, 10),  -- slight random rotation
            skin   = 1,
            loot   = { "Base.Pistol", "Base.9mmClip" },
            radius = 1,  -- jitter position up to 1 tile
        })

        -- Multiple vehicles in a line (e.g. convoy):
        -- for i = 1, 4 do
        --     e:SpawnVehicle("Base.CarNormal", 0, (i - 2.5) * 8, {
        --         rot  = e.rot + DE.rand(-10, 10),
        --         skin = DE.rand(0, 2),
        --     })
        -- end

        -- --- Zombies ---------------------------------------------------------
        -- e:SpawnZombies(count, outfit, dx, dy, opts)
        --   opts: radius (position jitter), spread (zombie scatter radius, default 3)
        --
        -- Use .Outfits() in the console to list all available outfit names.
        -- Use .Outfits("army") to filter by keyword.
        --
        -- Zombies are NOT tracked individually. On cleanup the mod removes the
        -- same number of loaded zombies from around the site, when the "Remove
        -- event zombies on cleanup" sandbox option is on. Zombies that wandered
        -- off or were killed are left to the game.
        --
        e:SpawnZombies(4, "ArmyCamoGreen", 0, 0, { radius = 3 })

        -- --- Single items ----------------------------------------------------
        -- e:SpawnItem(itemType, dx, dy, opts)
        --   opts: radius (position jitter)
        --
        e:SpawnItem("Base.Crowbar", 1, 0)
        e:SpawnItem("Base.Sledgehammer", -1, 1, { radius = 2 })

        -- --- Loot scatter ----------------------------------------------------
        -- e:SpawnLootScatter(items, dx, dy, opts)
        --   opts: radius (center jitter), spread (scatter radius, default 2), chance (default 30)
        --
        e:SpawnLootScatter(
            { "Base.Pistol", "Base.Shotgun", "Base.HuntingKnife" },
            0, 0,
            { spread = 3, chance = 35 }
        )

        -- --- Loot container (airdrop-style crate/bag) -------------------------
        -- e:SpawnContainer(containerType, lootItems, dx, dy, opts)
        --   containerType: either a container item (ItemType = base:container)
        --     e.g. "Base.Bag_Military", "Base.Bag_ALICEpack_Army", "Base.Toolbox",
        --     "Base.Bag_ProtectiveCaseMilitary" — OR a moveable crate:
        --     "Base.Mov_MilitaryCrate", "Base.Mov_MilitaryLocker"
        --   opts: radius (position jitter), chance (per-item fill chance, default 100)
        --
        e:SpawnContainer("Base.Bag_Military",
            { "Base.Pistol", "Base.9mmClip", "Base.Bandage", "Base.FirstAidKit" },
            0, 1, { chance = 100 })

        e:SpawnContainer("Base.Mov_MilitaryCrate",
            { "Base.Shotgun", "Base.ShotgunShellsBox", "Base.Axe" },
            1, 0, { chance = 100 })

        -- --- Fire, smoke, scorch marks --------------------------------------
        -- e:SpawnFire(count, dx, dy, opts)        -- opts: radius
        -- e:SpawnSmoke(count, dx, dy, opts)       -- opts: radius
        -- e:SpawnScorch(dx, dy, opts)             -- opts: radius, spread
        --
        e:SpawnFire(2, 0, 0)
        e:SpawnSmoke(2, 0, 0)
        e:SpawnScorch(0, 0, { spread = 1 })

        -- --- Custom logic ----------------------------------------------------
        -- You can still use raw EH helpers for anything not covered:
        -- local EH = DE.EventHelpers
        -- local objects = EH.spawnSprite(x, y, z, "floors_burnt_01_3")
        -- ...
        -- return objects   -- merged into tracked objects automatically
    end,

    -- Cleanup is automatic — no need to define it.
    --
    -- If you do supply your own `cleanup = function(x, y, z, objects)`, it
    -- replaces the default. Clearing requires admin presence, so only remove
    -- objects in loaded chunks; anything out of reach is left to the game.
}

DE.EventManager.register(EVENT)
