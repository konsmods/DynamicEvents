-- ============================================================================
-- Military Convoy Crash — vanilla vehicles, scattered formation
-- For a clean in-line convoy, see ConvoyCrashKI5.lua as a reference.
-- ============================================================================

local cargoLoot = {
    "Base.Pistol", "Base.9mmClip", "Base.ShotgunShellsBox",
    "Base.Bandage", "Base.FirstAidKit", "Base.HuntingKnife",
}

local vehicleTypes = { "Base.PickUpTruck_Camo", "Base.OffRoad", "Base.PickUpTruckLightsRanger" }
local vehicleOffsets = {
    { dx = -2, dy =  2 },
    { dx =  1, dy = -1 },
    { dx =  3, dy =  1 },
}

local EVENT = {
    id             = "convoy_crash",
    name           = "Military Convoy Crash",
    weight         = 12,
    sound          = "MetaAssaultRifle1",
    cooldownHours  = 36,
    lifetimeHours  = 36,

    locations = {
        { name = "Muldraugh highway",   x = 10700, y = 9200,  z = 0 },
        { name = "Muldraugh N road",    x = 10900, y = 9400,  z = 0 },
        { name = "West Point road",     x = 11600, y = 7900,  z = 0 },
        { name = "West Point N road",   x = 11800, y = 8100,  z = 0 },
        { name = "Riverside road",      x =  7000, y = 5500,  z = 0 },
        { name = "Riverside N road",    x =  7200, y = 5700,  z = 0 },
        { name = "Rosewood road",       x =  9000, y = 11300, z = 0 },
        { name = "Rosewood S road",     x =  9200, y = 11500, z = 0 },
    },

    warning = { delay = 60 },

    spawn = function(x, y, z, e)
        for i, offset in ipairs(vehicleOffsets) do
            e:SpawnVehicle(vehicleTypes[i] or vehicleTypes[1], offset.dx, offset.dy, {
                rot  = e.rot + DE.rand(-10, 10),
                loot = cargoLoot,
            })
        end

        e:SpawnLootScatter({
            "Base.Pistol", "Base.9mmClip", "Base.Shotgun",
            "Base.ShotgunShellsBox", "Base.AssaultRifle", "Base.556Clip",
            "Base.BulletsBox", "Base.HuntingKnife", "Base.Axe",
            "Base.Bag_ALICE_BeltSus", "Base.Bag_ALICEpack_Army",
            "Base.Bandage", "Base.BandageDirty", "Base.FirstAidKit",
            "Base.Pills", "Base.PillsAntiDep", "Base.AlcoholBandage",
            "Base.SutureNeedle", "Base.Tweezers",
        }, 0, 0, { spread = 2, chance = 30 })

        e:SpawnZombies(4, "ArmyCamoGreen", 0, 0, { radius = 2 })
    end,
}

DE.EventManager.register(EVENT)
