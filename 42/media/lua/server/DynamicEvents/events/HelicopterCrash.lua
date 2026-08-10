DE = DE or {}

local EH = DE.EventHelpers

-- Custom Helicopter Model:
-- Replace the vehicle line with:
--   EH.spawnSprite(x, y, z, "helicopter_wreck")  -- or place as IsoWorldInventoryObject

local loot = {
    "Base.HuntingKnife", "Base.Pistol", "Base.9mmClip",
    "Base.Bag_ALICEpack_Army", "Base.CannedFruitCocktail",
    "Base.WaterBottle", "Base.Bandage", "Base.FirstAidKit",
    "Base.AssaultRifle", "Base.556Clip",
}

local EVENT = {
    id             = "heli_crash",
    name           = "Helicopter Crash",
    weight         = 10,
    cooldownHours  = 48,
    lifetimeHours  = 48,
    minDaysSurvived = 1,

    locations = {
        { name = "Muldraugh field",    x = 10600, y = 9300,  z = 0 },
        { name = "Muldraugh N field",  x = 10800, y = 9500,  z = 0 },
        { name = "Riverside farm",     x =  8400, y = 5400,  z = 0 },
        { name = "Riverside field",    x =  8200, y = 5600,  z = 0 },
        { name = "West Point field",   x = 11500, y = 8000,  z = 0 },
        { name = "West Point woods",   x = 11700, y = 8200,  z = 0 },
        { name = "Rosewood field",     x =  9000, y = 11000, z = 0 },
        { name = "Rosewood S field",   x =  9200, y = 11200, z = 0 },
    },

    warning = {
        ambient = { sound = "HeliCrashDistant", radius = 200 },
        delay = 90,
    },

    spawn = function(x, y, z)
        local objects = {}

        -- Wreck placeholder
        EH.merge(objects, EH.spawnVehicle(x, y, z, "Base.PickUpTruckLights", nil))

        -- Scorched ground
        EH.merge(objects, EH.spawnScorchMarks(x, y, z, 1))

        -- Loot
        EH.merge(objects, EH.spawnLoot(x, y, z, loot, 2, 35))

        -- Zombies
        EH.spawnZombies(x, y, z, 3, 2)

        DE.log("heli_crash spawned at (%d, %d, %d)", x, y, z)
        return objects
    end,

    cleanup = function(x, y, z, objects)
        EH.cleanupEvent(x, y, z, objects)
    end,
}

DE.EventManager.register(EVENT)
