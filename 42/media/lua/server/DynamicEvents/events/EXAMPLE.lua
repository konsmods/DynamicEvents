-- ============================================================================
-- Example Event Template
-- Copy this file to events/YourEvent.lua and fill in the blanks.
-- ============================================================================

local EVENT = {

    -- Required: unique string ID (used for sandbox toggle, debug commands)
    id = "example_event",

    -- Required: display name
    name = "Example Event",

    -- Optional: default rotation in degrees (0=North, 90=East)
    -- Individual locations can override this with their own rot.
    rot = 0,

    -- Optional: mod IDs that must be active for this event to fire
    -- dependencies = { "SomeModID", "AnotherModID" },

    -- Optional tuning (shown with defaults)
    weight         = 10,    -- higher = more likely to be chosen
    cooldownHours  = 48,    -- hours before this event can fire again
    lifetimeHours  = 48,    -- hours before the event auto-expires
    minDaysSurvived = 0,    -- in-game days before this event is eligible

    -- Optional: sound effect played at the event location
    -- sound = "MetaShotgun1",

    -- Optional: delay before the event spawns (warning period)
    -- warning = { delay = 60 },

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

    -- cleanup is automatic — no need to define it
}

DE.EventManager.register(EVENT)
