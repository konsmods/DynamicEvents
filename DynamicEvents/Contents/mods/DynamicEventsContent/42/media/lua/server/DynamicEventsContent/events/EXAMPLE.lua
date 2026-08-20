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
    -- lifetimeHours = 72,                      -- auto-clear this long after spawn
    -- zombieCleanupRadius = 20,                -- tiles around centre cleanup clears spawned zombies from (default 20)

    -- radio = {                                -- periodic emergency broadcasts
    --     frequency = 105600,                  -- kHz (105.6 MHz)
    --     interval  = 7200,                    -- in-game seconds between broadcasts
    --     range     = 200,                     -- tiles of clear signal; -1 = global
    --     messages  = { "Help near {name} ({x},{y})!" }, -- {name}/{x}/{y}/%s
    -- },

    -- Where this event can spawn (each can override rot)
    locations = {
        { name = "North-south road", x = 10000, y = 10000, z = 0, rot = 0   },
        { name = "East-west road",   x = 10500, y = 10000, z = 0, rot = 90  },
    },

    -- All e:Spawn* methods take (dx, dy) offsets from the location, rotated by
    -- e.rot; any opts table accepts `radius` for position jitter, and
    -- `permanent = true` to spawn something cleanup will never remove.
    spawn = function(x, y, z, e)

        e:SpawnVehicle("Base.PickUpTruck_Camo", 0, 5, {
            rot  = e.rot + DE.rand(-10, 10),
            skin = 1,
            loot = { "Base.Pistol", "Base.9mmClip" },   -- list, "vanilla", or
            -- loot = { distribution = "ArmyStorageGuns" }, -- a vanilla loot table
            -- working = true,  -- leave drivable; omit for a wrecked look
        })

        -- Themed zombies, tracked and removed on cleanup. outfit is optional.
        e:SpawnZombies(4, 0, 0, { outfit = "ArmyCamoGreen", radius = 3 })

        e:SpawnItem("Base.Crowbar", 1, 0)
        e:SpawnLoot({ "Base.Pistol", "Base.Shotgun" }, 0, 0, { spread = 3, chance = 35 })

        -- A readable note carrying lore / a frequency to tune into. `note` writes
        -- text onto a writable item; `permanent` keeps it after the event clears.
        e:SpawnItem("Base.Note", -1, 0, {
            name = "Scrawled Note",
            note = "They broadcast on 88.4 when it's safe to move. Wait for it.",
            permanent = true,
        })

        -- A crate filled from a vanilla loot table instead of a hand-picked list.
        e:SpawnContainer("Base.Mov_MilitaryCrate", { distribution = "ArmyStorageGuns" }, 1, 0)
        -- or a hand-picked bag: e:SpawnContainer("Base.Bag_Military",
        --     { "Base.Pistol", "Base.9mmClip", "Base.Bandage" }, 0, 1, { chance = 100 })

        e:SpawnFire(2, 0, 0)
        e:SpawnSmoke(2, 0, 0)
        e:SpawnScorch(0, 0, { spread = 1 })
    end,

    -- Optional recurring tick while the event is active. Here it draws nearby
    -- zombies toward a town centre — pair with SpawnHorde for repopulation.
    -- pulse = {
    --     intervalSeconds = 120,
    --     fn = function(x, y, z, ev)
    --         DE.attractZombies(x, y, 200, 10550, 10900)
    --     end,
    -- },
}

DE.EventManager.register(EVENT)
