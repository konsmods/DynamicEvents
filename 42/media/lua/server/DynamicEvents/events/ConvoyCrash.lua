DE = DE or {}

local EH = DE.EventHelpers

local cargoLoot = {
    "Base.Pistol", "Base.9mmClip", "Base.ShotgunShellsBox",
    "Base.Bandage", "Base.FirstAidKit", "Base.HuntingKnife",
}

local loot = {
    "Base.Pistol", "Base.9mmClip", "Base.Shotgun",
    "Base.ShotgunShellsBox", "Base.AssaultRifle", "Base.556Clip",
    "Base.BulletsBox", "Base.HuntingKnife", "Base.Axe",
    "Base.Bag_ALICE_BeltSus", "Base.Bag_ALICEpack_Army",
    "Base.Bandage", "Base.BandageDirty", "Base.FirstAidKit",
    "Base.Pills", "Base.PillsAntiDep", "Base.AlcoholBandage",
    "Base.SutureNeedle", "Base.Tweezers",
}

local vehicleTypes = { "Base.PickUpTruck_Camo", "Base.OffRoad", "Base.PickUpTruckLightsRanger" }
local vehicleOffsets = { { dx = -2, dy = 2 }, { dx = 1, dy = -1 }, { dx = 3, dy = 1 } }

local EVENT = {
    id             = "convoy_crash",
    name           = "Military Convoy Crash",
    weight         = 12,
    cooldownHours  = 36,
    lifetimeHours  = 36,
    minDaysSurvived = 0,

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

    warning = {
        ambient = { sound = "ExplosionDistant", radius = 200 },
        delay = 60,
    },

    spawn = function(x, y, z)
        local objects = {}

        -- Damaged military vehicles with cargo
        for i, offset in ipairs(vehicleOffsets) do
            local vx, vy = x + offset.dx, y + offset.dy
            local vtype = vehicleTypes[i] or vehicleTypes[1]
            EH.merge(objects, EH.spawnVehicle(vx, vy, z, vtype, cargoLoot))
        end

        -- Ground loot
        EH.merge(objects, EH.spawnLoot(x, y, z, loot, 2, 30))

        -- Zombies
        EH.spawnZombies(x, y, z, 4, 4)

        DE.log("convoy_crash spawned at (%d, %d, %d)", x, y, z)
        return objects
    end,

    cleanup = function(x, y, z, objects)
        EH.cleanupEvent(x, y, z, objects)
    end,
}

DE.EventManager.register(EVENT)
