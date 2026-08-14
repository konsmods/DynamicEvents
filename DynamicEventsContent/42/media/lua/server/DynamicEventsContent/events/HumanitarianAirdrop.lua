DE = DE or {}

local crateLoot = {
    -- food
    "Base.CannedCorn", "Base.CannedChili", "Base.CannedBolognese",
    "Base.CannedSardines", "Base.TunaTin", "Base.CannedPeaches",
    "Base.CannedMushroomSoup", "Base.CannedFruitCocktail",
    -- water
    "Base.WaterBottle", "Base.Sportsbottle", "Base.PopBottle",
    -- seeds
    "Base.CabbageSeed", "Base.CarrotSeed", "Base.TomatoSeed",
    "Base.PotatoSeed", "Base.BroccoliSeed",
    -- tools
    "Base.Hammer", "Base.Saw", "Base.Screwdriver", "Base.Wrench",
    "Base.Crowbar", "Base.KitchenKnife", "Base.Torch", "Base.Axe",
    "Base.WateredCan",
    -- basic medicine
    "Base.Bandage", "Base.Pills", "Base.FirstAidKit",
}

local EVENT = {
    id             = "humanitarian_airdrop",
    name           = "Humanitarian Airdrop",
    enabledVar     = "DynamicEventsContent.HumanitarianAirdrop",
    weight         = 10,
    cooldownHours  = 72,
    minDaysSurvived = 1,

    locations = {
        { name = "Fiddler's Trail",   x = 10488, y = 12324,  z = 0, rot = 90 },
        { name = "Route 31W",    x = 10588, y = 12438,  z = 0, rot = 0 },
    },

    spawn = function(x, y, z, e)
        local crates = DE.rand(2, 3)
        for i = 1, crates do
            e:SpawnContainer("Base.Mov_MilitaryCrate", crateLoot,
                DE.rand(-3, 3), DE.rand(-3, 3), { chance = 70 })
        end
    end,
}

DE.EventManager.register(EVENT)
