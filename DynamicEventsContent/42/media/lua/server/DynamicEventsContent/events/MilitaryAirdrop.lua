DE = DE or {}

local crateLoot = {
    "Base.AssaultRifle", "Base.556Clip", "Base.556Box",
    "Base.AssaultRifle2", "Base.M14Clip", "Base.308Box",
    "Base.Pistol", "Base.9mmClip",
    "Base.Vest_BulletArmy", "Base.Hat_Army",
    "Base.HolsterDouble", "Base.CanteenMilitaryFull",
    "Base.FirstAidKit", "Base.Bandage", "Base.SutureNeedle",
}

local EVENT = {
    id             = "military_airdrop",
    name           = "Military Airdrop",
    enabledVar     = "DynamicEventsContent.MilitaryAirdrop",
    weight         = 8,
    cooldownHours  = 96,
    minDaysSurvived = 3,

    locations = {
        { name = "Fiddler's Trail",   x = 10488, y = 12324,  z = 0, rot = 90 },
        { name = "Route 31W",    x = 10588, y = 12438,  z = 0, rot = 0 },
    },

    spawn = function(x, y, z, e)
        local crates = DE.rand(2, 3)
        for i = 1, crates do
            e:SpawnContainer("Base.Mov_MilitaryCrate", crateLoot,
                DE.rand(-3, 3), DE.rand(-3, 3), { chance = 60 })
        end
    end,
}

DE.EventManager.register(EVENT)
