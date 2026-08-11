DE = DE or {}

local EH = DE.EventHelpers

local cargoLoot = {
    "Base.Pistol", "Base.9mmClip", "Base.ShotgunShellsBox",
    "Base.Bandage", "Base.FirstAidKit", "Base.HuntingKnife",
}

local loot = {
    "Base.Pistol", "Base.9mmClip", "Base.9mmBulletsMolds",
    "Base.Shotgun", "Base.ShotgunShellsBox", "Base.AssaultRifle",
    "Base.223Bullets", "Base.223Box", "Base.556Bullets", "Base.556Box",
    "Base.BulletsBox", "Base.HuntingKnife", "Base.Axe",
    "Base.Bag_ALICE_BeltSus", "Base.Bag_ALICEpack_Army",
    "Base.Bag_Military", "Base.Bandage", "Base.BandageDirty",
    "Base.FirstAidKit", "Base.Pills", "Base.PillsAntiDep",
    "Base.AlcoholBandage", "Base.SutureNeedle", "Base.Tweezers",
    "Base.MilitaryBackpack", "Base.WeldingMask", "Base.PropaneTank",
}

local vehicleTypes = {
    "Base.82oshkoshM911Burnt",
    "Base.86oshkoshP19ABurnt",
    "Base.82oshkoshM911Burnt",
    "Base.86oshkoshP19ABurnt",
}

local vehicleOffsets = {
    { dx = 0, dy =  12 },
    { dx = 0, dy =   4 },
    { dx = 0, dy =  -4 },
    { dx = 0, dy = -12 },
}

local EVENT = {
    id             = "convoy_crash_ki5",
    name           = "KI5 Military Convoy Crash",
    weight         = 14,
    sound          = "MetaAssaultRifle1",
    cooldownHours  = 48,
    lifetimeHours  = 42,
    minDaysSurvived = 1,

    dependencies = { "82oshkoshM911", "86oshkoshP19A" },

    locations = {
        { name = "Muldraugh highway",   x = 10600, y = 9300,  z = 0 },
        { name = "Muldraugh N road",    x = 10900, y = 9550,  z = 0 },
        { name = "West Point road",     x = 11900, y = 7850,  z = 0 },
        { name = "West Point N road",   x = 11800, y = 8250,  z = 0 },
        { name = "Riverside E road",    x =  7500, y = 5450,  z = 0 },
        { name = "Riverside N road",    x =  7200, y = 5550,  z = 0 },
        { name = "Rosewood road",       x =  8800, y = 11300, z = 0 },
        { name = "Rosewood S road",     x =  9350, y = 11500, z = 0 },
    },

    warning = {
        delay = 90,
    },

    spawn = function(x, y, z)
        local objects = {}

        for i, offset in ipairs(vehicleOffsets) do
            local vx, vy = x + offset.dx, y + offset.dy
            local vtype = vehicleTypes[i] or vehicleTypes[1]
            local angle = ZombRand(21) - 10
            EH.merge(objects, EH.spawnVehicle(vx, vy, z, vtype, cargoLoot, angle))
        end

        EH.merge(objects, EH.spawnLoot(x, y, z, loot, 3, 35))

        EH.spawnZombies(x, y, z, 6, 4, "ArmyCamoGreen")

        return objects
    end,

    cleanup = function(x, y, z, objects)
        EH.cleanupEvent(x, y, z, objects)
    end,
}

DE.EventManager.register(EVENT)
