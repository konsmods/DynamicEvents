DE = DE or {}

local vehicleTypes = {
    "Base.82oshkoshM911Burnt",
    "Base.86oshkoshP19ABurnt",
    "Base.82oshkoshM911Burnt",
    "Base.86oshkoshP19ABurnt",
}

local cargoLoot = {
    "Base.Pistol", "Base.9mmClip", "Base.ShotgunShellsBox",
    "Base.Bandage", "Base.FirstAidKit", "Base.HuntingKnife",
}

local EVENT = {
    id             = "convoy_crash_ki5",
    name           = "KI5 Military Convoy Crash",
    weight         = 14,
    sound          = "MetaAssaultRifle1",
    cooldownHours  = 0.1,
    lifetimeHours  = 42,
    minDaysSurvived = 1,

    dependencies = { "82oshkoshM911", "86oshkoshP19A" },

    locations       = {
        { name = "Muldraugh highway",   x = 10715, y = 9834,  z = 0, rot = 0 },
        { name = "Muldraugh N road",    x = 10743, y = 9860,  z = 0, rot = 90 },
    },

    warning = {
        delay = 90,
    },

    radio = {
        interval = 30,
        range    = 200,
        messages = {
            "MAYDAY! Military convoy under fire near %s! Requesting immediate backup!",
            "Emergency! Convoy ambushed at %s — heavy casualties!",
            "This is an emergency broadcast from %s! Convoy is down, repeat, convoy is down!",
        },
    },

    spawn = function(x, y, z, e)
        local spacing = 8
        local n = 4
        for i = 1, n do
            e:SpawnVehicle(vehicleTypes[i], 0, (i - (n + 1) / 2) * spacing, {
                rot = e.rot + DE.rand(-10, 10),
                loot  = cargoLoot,
            })
        end

        e:SpawnLootScatter({
            "Base.Pistol", "Base.9mmClip", "Base.9mmBulletsMolds",
            "Base.Shotgun", "Base.ShotgunShellsBox", "Base.AssaultRifle",
            "Base.223Bullets", "Base.223Box", "Base.556Bullets", "Base.556Box",
            "Base.BulletsBox", "Base.HuntingKnife", "Base.Axe",
            "Base.Bag_ALICE_BeltSus", "Base.Bag_ALICEpack_Army",
            "Base.Bag_Military", "Base.Bandage", "Base.BandageDirty",
            "Base.FirstAidKit", "Base.Pills", "Base.PillsAntiDep",
            "Base.AlcoholBandage", "Base.SutureNeedle", "Base.Tweezers",
            "Base.MilitaryBackpack", "Base.WeldingMask", "Base.PropaneTank",
        }, 0, 0, { spread = 3, chance = 35 })

        e:SpawnZombies(6, "ArmyCamoGreen", 0, 0, { radius = 2 })
    end,
}

DE.EventManager.register(EVENT)
