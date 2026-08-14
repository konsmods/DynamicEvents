-- ============================================================================
-- Example event template — copy to events/YourEvent.lua and fill in the blanks.
-- Full API reference: DOCS.md
-- ============================================================================

local EVENT = {

    id             = "example_event",
    name           = "Example Event",
    enabledVar     = "DynamicEventsContent.ExampleEvent", -- sandbox toggle

    -- Tuning (defaults shown)
    weight          = 10,   -- higher = picked more often
    cooldownHours   = 48,   -- hours before this type can fire again (0 = never)
    minDaysSurvived = 0,    -- in-game days before eligible

    -- rot          = 0,                        -- default rotation (degrees)
    -- dependencies = { "SomeModID" },          -- mods that must be active
    -- clearObstacles = true, clearRadius = 25, -- clear vehicles instead of skipping
    -- warning     = { delay = 60 },            -- in-game seconds before spawn
    -- sound       = "MetaShotgun1",            -- played at spawn

    -- radio = {                                -- periodic emergency broadcasts
    --     frequency = 105600,                  -- kHz (105.6 MHz)
    --     interval  = 7200,                    -- in-game seconds
    --     range     = 200,                     -- tiles of clear signal
    --     messages  = { "Help near {name} ({x},{y})!" }, -- {name}/{x}/{y}/%s
    -- },

    -- Where this event can spawn (each can override rot)
    locations = {
        { name = "North-south road", x = 10000, y = 10000, z = 0, rot = 0   },
        { name = "East-west road",   x = 10500, y = 10000, z = 0, rot = 90  },
    },

    -- All e:Spawn* methods take (dx, dy) offsets from the location, rotated by
    -- e.rot; any opts table accepts `radius` for position jitter.
    spawn = function(x, y, z, e)

        e:SpawnVehicle("Base.PickUpTruck_Camo", 0, 5, {
            rot  = e.rot + DE.rand(-10, 10),
            skin = 1,
            loot = { "Base.Pistol", "Base.9mmClip" },   -- or loot = "vanilla"
            -- working = true,  -- leave drivable; omit for a wrecked look
        })

        e:SpawnZombies(4, "ArmyCamoGreen", 0, 0, { radius = 3 })

        e:SpawnItem("Base.Crowbar", 1, 0)
        e:SpawnLootScatter({ "Base.Pistol", "Base.Shotgun" }, 0, 0, { spread = 3, chance = 35 })

        e:SpawnContainer("Base.Bag_Military",
            { "Base.Pistol", "Base.9mmClip", "Base.Bandage" }, 0, 1, { chance = 100 })
        -- or a real crate: e:SpawnContainer("Base.Mov_MilitaryCrate", { "Base.Axe" }, 1, 0)

        e:SpawnFire(2, 0, 0)
        e:SpawnSmoke(2, 0, 0)
        e:SpawnScorch(0, 0, { spread = 1 })
    end,
}

DE.EventManager.register(EVENT)
