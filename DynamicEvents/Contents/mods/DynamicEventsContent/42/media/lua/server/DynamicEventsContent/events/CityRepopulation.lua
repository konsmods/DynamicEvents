DE = DE or {}

-- Repopulates a cleared-out town by spawning a horde on its outskirts and,
-- every pulse, nudging any nearby zombies toward a target. The horde is spawned
-- with SpawnHorde, so it's world-owned: it persists and wanders, and is never
-- removed by cleanup or the event's lifetime.

-- Fixed destination the horde is drawn toward. Leave nil to draw them toward the
-- nearest player instead — that way an ad-hoc "spawn here" still herds them
-- somewhere sensible, like a heli event, instead of walking off to a fixed spot.
local TARGET_X, TARGET_Y = nil, nil

-- How far from the spawn point zombies get pulled in on each pulse.
local PULL_RADIUS = 250

local EVENT = {
    id             = "city_repopulation",
    name           = "Wandering Horde",
    enabledVar     = "DynamicEventsContent.CityRepopulation",
    weight         = 6,
    cooldownHours  = 48,
    minDaysSurvived = 10,

    -- Event tracking clears after 6 in-game hours. The horde itself is not
    -- tracked, so it keeps wandering — only the pulse/record stop.
    lifetimeHours  = 6,

    -- Outskirts of the town, on the approaches in.
    locations = {
        { name = "North approach", x = 10520, y = 12200, z = 0 },
        { name = "South approach", x = 10520, y = 12520, z = 0 },
    },

    spawn = function(x, y, z, e)
        e:SpawnHorde(DE.rand(30, 60), 0, 0, { spread = 20 })
    end,

    -- Draw loaded zombies near the spawn toward the target (or nearest player).
    pulse = {
        intervalSeconds = 120,
        fn = function(x, y, z, ev)
            local tx, ty = TARGET_X, TARGET_Y
            if not tx then
                local p = DE.nearestPlayer(x, y)
                if not p then return end
                tx, ty = p:getX(), p:getY()
            end
            DE.attractZombies(x, y, PULL_RADIUS, tx, ty)
        end,
    },
}

DE.EventManager.register(EVENT)
