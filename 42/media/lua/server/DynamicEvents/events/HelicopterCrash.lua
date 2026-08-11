-- ============================================================================
-- Helicopter Crash Event
--
-- TODO: custom helicopter wreck 3D model
--   Place helicopter_wreck.fbx and .png in 42/media/models/ and media/textures/
--   Then replace the SpawnVehicle line with:
--     e:SpawnItem("Base.HelicopterWreck", 0, 0)
-- ============================================================================

local militaryLoot = {
    "Base.HuntingKnife", "Base.Pistol", "Base.9mmClip",
    "Base.Bag_ALICEpack_Army", "Base.CannedFruitCocktail",
    "Base.WaterBottle", "Base.Bandage", "Base.FirstAidKit",
    "Base.AssaultRifle", "Base.556Clip",
}

local zombieOutfits = { "ArmyCamoGreen", "Police", "Ranger" }

local EVENT = {
    id             = "heli_crash",
    name           = "Helicopter Crash",
    weight         = 10,
    sound          = "Helicopter",
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

    warning = { delay = 90 },

    spawn = function(x, y, z, e)
        -- TODO: replace with custom HelicopterWreck model when ready
        -- e:SpawnItem("Base.HelicopterWreck", 0, 0)
        e:SpawnVehicle("Base.AmbulanceBurnt", 0, 0, { rot = e.rot + DE.rand(-15, 15) })

        e:SpawnScorch(0, 0, { spread = 1 })

        e:SpawnFire(2, 0, 0)
        e:SpawnSmoke(2, 0, 0)

        e:SpawnLootScatter(militaryLoot, 0, 0, { spread = 2, chance = 35 })

        e:SpawnZombies(6, DE.pick(zombieOutfits), 0, 0, { radius = 2 })
    end,
}

DE.EventManager.register(EVENT)
