DE = DE or {}

local vehicleTypes = {
    "Base.67commandoBurnt",
    "Base.86oshkoshP19ABurnt",
    "Base.82oshkoshM911Burnt",
    "Base.92amgeneralM998Burnt",
}

local cargoLoot = {
    "Base.Pistol", "Base.9mmClip", "Base.ShotgunShellsBox",
    "Base.Bandage", "Base.FirstAidKit", "Base.HuntingKnife",
}

local EVENT = {
    id             = "convoy_crash_ki5",
    name           = "KI5 Military Convoy Crash",
    enabledVar     = "DynamicEventsContent.ConvoyCrashKI5",
    weight         = 14,
    sound          = "MetaAssaultRifle1",
    cooldownHours  = 0,
    minDaysSurvived = 1,

    -- The convoy wants a clear stretch of road: if vehicles are in the way,
    -- clear them and spawn anyway instead of skipping this location.
    clearObstacles = true,
    clearRadius    = 25,

    -- Mod IDs, not vehicle script names: the "Burnt" suffix belongs to the
    -- vehicle variant (Base.92amgeneralM998Burnt), not to the mod that adds it.
    dependencies = { "82oshkoshM911", "86oshkoshP19A", "92amgeneralM998", "67commando" },

    locations       = {
        { name = "Muldraugh highway",   x = 10715, y = 9834,  z = 0, rot = 0 },
        { name = "Muldraugh N road",    x = 10743, y = 9860,  z = 0, rot = 90 },
    },

    warning = {
        delay = 90,
    },

    radio = {
        interval = 30,
        range    = 500,
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
            "Base.Pistol", "Base.9mmClip", "Base.Bullets9mm", "Base.Bullets9mmBox",
            "Base.Shotgun", "Base.ShotgunShellsBox", "Base.AssaultRifle",
            "Base.556Bullets", "Base.556Box", "Base.556Clip",
            "Base.HuntingKnife", "Base.Axe",
            "Base.Bag_ALICE_BeltSus", "Base.Bag_ALICEpack_Army",
            "Base.Bag_Military", "Base.Bandage", "Base.BandageDirty",
            "Base.FirstAidKit", "Base.Pills", "Base.PillsAntiDep",
            "Base.AlcoholBandage", "Base.SutureNeedle", "Base.Tweezers",
            "Base.Bag_ProtectiveCaseMilitary", "Base.WeldingMask", "Base.PropaneTank",
        }, 0, 0, { spread = 3, chance = 35 })

        -- Supply crates: one proper military crate (moveable, real container)
        -- and one carry-able duffel, so both container paths get exercised.
        e:SpawnContainer("Base.Mov_MilitaryCrate", {
            "Base.Shotgun", "Base.ShotgunShellsBox", "Base.AssaultRifle",
            "Base.556Bullets", "Base.556Box", "Base.FirstAidKit",
        }, 2, 0, { chance = 100 })

        e:SpawnContainer("Base.Bag_Military", {
            "Base.Pistol", "Base.9mmClip", "Base.Bandage",
        }, -2, 0, { chance = 100 })

        e:SpawnZombies(6, "ArmyCamoGreen", 0, 0, { radius = 2 })
    end,
}

DE.EventManager.register(EVENT)
