DE = DE or {}

local EVENT = {
    id             = "simple_horde",
    name           = "Simple Horde",
    enabledVar     = "DynamicEventsContent.SimpleHorde",
    weight         = 6,
    cooldownHours  = 120,
    minDaysSurvived = 5,

    locations = {
        { name = "Fiddler's Trail",   x = 10488, y = 12324,  z = 0, rot = 90 },
        { name = "Route 31W",    x = 10588, y = 12438,  z = 0, rot = 0 },
    },

    spawn = function(x, y, z, e)
        e:SpawnZombies(DE.rand(25, 50), nil, 0, 0, { spread = 15 })
    end,
}

DE.EventManager.register(EVENT)
