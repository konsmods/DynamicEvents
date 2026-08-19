DE = DE or {}

local vehicleTypes = {
    "Base.67commandoBurnt",
    "Base.86oshkoshP19ABurnt",
    "Base.82oshkoshM911Burnt",
    "Base.92amgeneralM998Burnt",
}

local crateLoot = {
    "Base.Pistol", "Base.9mmClip",
    "Base.Revolver_Long", "Base.Bullets44",
    "Base.Shotgun", "Base.ShotgunShellsBox",
}

local medicalLoot = {
    "Base.Bandage", "Base.FirstAidKit", "Base.SutureNeedle",
}

local EVENT = {
    id             = "convoy_crash_ki5",
    name           = "KI5 Military Convoy Crash",
    enabledVar     = "DynamicEventsContent.ConvoyCrashKI5",
    weight         = 14,
    sound          = "MetaAssaultRifle1",
    cooldownHours  = 0,
    minDaysSurvived = 1,

    -- Clear vehicles in the way rather than skipping this location.
    clearObstacles = true,
    clearRadius    = 20,

    -- Mod IDs, not vehicle script names ("Burnt" is a vehicle variant).
    dependencies = { "82oshkoshM911", "86oshkoshP19A", "92amgeneralM998", "67commando" },

    locations       = {
        { name = "Fiddler's Trail",   x = 10488, y = 12324,  z = 0, rot = 90 },
        { name = "Route 31W",    x = 10588, y = 12438,  z = 0, rot = 0 },
    },

    warning = {
        delay = 900,
    },

    radio           = {
        frequency = 99000,
        interval = 1440,
        range    = 1000,
        messages = {
            "MAYDAY! Military convoy under fire near {name}, coordinates {x},{y}! Requesting immediate backup!",
            "Emergency! Convoy ambushed at {name}, coordinates {x},{y} — heavy casualties!",
            "This is an emergency broadcast from {name}, coordinates {x},{y}! Convoy is down, repeat, convoy is down!",
        },
    },

    spawn = function(x, y, z, e)
        local spacing = 8
        local n = 4
        for i = 1, n do
            e:SpawnVehicle(vehicleTypes[i], 0, (i - (n + 1) / 2) * spacing, {
                rot = e.rot + DE.rand(-10, 10),
            })
        end

        e:SpawnContainer("Base.Mov_MilitaryCrate", crateLoot, 2, 0, { chance = 100 })
        e:SpawnContainer("Base.Mov_MilitaryCrate", crateLoot, -2, 0, { chance = 100 })

        e:SpawnLoot(medicalLoot, 0, 0, { spread = 3, chance = 40 })

        e:SpawnZombies(DE.rand(10, 25), 0, 0, { outfit = "ArmyCamoGreen", radius = 3 })
    end,
}

DE.EventManager.register(EVENT)
