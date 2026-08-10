DE = DE or {}

local EH = DE.EventHelpers

local loot = {
    "Base.Crowbar", "Base.Hammer", "Base.Sledgehammer",
    "Base.SteelBar", "Base.SheetMetal", "Base.WeldingMask",
    "Base.PropaneTank", "Base.BlowTorch", "Base.NailsBox",
    "Base.Gloves_LeatherGloves", "Base.Toolbox",
}

local EVENT = {
    id             = "train_wreck",
    name           = "Train Wreck",
    weight         = 8,
    sound          = "MetaShotgun1",
    cooldownHours  = 72,
    lifetimeHours  = 60,
    minDaysSurvived = 2,

    locations = {
        { name = "Muldraugh railway",  x = 10500, y = 9400, z = 0 },
        { name = "Muldraugh E rail",   x = 10700, y = 9600, z = 0 },
        { name = "West Point rail",    x = 11000, y = 8500, z = 0 },
        { name = "West Point E rail",  x = 11200, y = 8700, z = 0 },
        { name = "Riverside rail",     x =  8000, y = 5700, z = 0 },
        { name = "Riverside E rail",   x =  8200, y = 5900, z = 0 },
    },

    warning = {
        delay = 60,
    },

    spawn = function(x, y, z)
        local objects = {}

        -- Industrial loot along the railway
        EH.merge(objects, EH.spawnLoot(x, y, z, loot, 3, 35))
        EH.merge(objects, EH.spawnLoot(x + 1, y, z, loot, 3, 30))
        EH.merge(objects, EH.spawnLoot(x - 1, y, z, loot, 3, 30))

        -- Zombies
        EH.spawnZombies(x, y, z, 4, 4)

        return objects
    end,

    cleanup = function(x, y, z, objects)
        EH.cleanupEvent(x, y, z, objects)
    end,
}

DE.EventManager.register(EVENT)
