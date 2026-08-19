DE = DE or {}

DE.VERSION = "0.1.0"

-- Single source of truth for tunables: DE.Config key, matching SandboxVars key,
-- and default. refreshConfig rebuilds DE.Config from this each upkeep pass, so
-- sandbox changes apply mid-game.
DE.CONFIG_SPEC = {
    { key = "enabled",                  sandbox = "Enabled",                  default = true  },
    { key = "intervalHours",            sandbox = "MinHoursBetweenEvents",    default = 1.0   }, -- in-game hours between events
    { key = "gracePeriodHours",         sandbox = "GracePeriodHours",         default = 0     }, -- after game start
    { key = "spawnMinDistance",         sandbox = "SpawnMinDistance",         default = 40    }, -- tiles: never materialise this close to a player
    { key = "maxEventsPerArea",         sandbox = "MaxEventsPerArea",         default = 0     }, -- 0 = no cluster limit
    { key = "areaRadius",               sandbox = "AreaRadius",               default = 300   }, -- tiles, for the cluster limit
    { key = "minDistanceBetweenEvents", sandbox = "MinDistanceBetweenEvents", default = 20    }, -- tiles between event centers
    { key = "minDistanceFromVehicles",  sandbox = "MinDistanceFromVehicles",  default = 15    }, -- tiles from any existing vehicle
    { key = "cleanupZombies",           sandbox = "CleanupZombies",           default = true  }, -- remove event zombies when clearing
    { key = "debug",                    sandbox = "Debug",                    default = false },
}

DE.Config = {}
for _, opt in ipairs(DE.CONFIG_SPEC) do
    DE.Config[opt.key] = opt.default
end

local function side()
    if isServer() then return "SRV"
    elseif isClient() then return "CLI"
    else return "SP" end
end

local function emit(tag, fmt, ...)
    local message = fmt
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, fmt, ...)
        message = ok and formatted or (tostring(fmt) .. " <bad log args>")
    end
    print(string.format("[DynamicEventsFramework][%s]%s %s", side(), tag, tostring(message)))
end

function DE.log(fmt, ...)  emit("", fmt, ...) end
function DE.warn(fmt, ...) emit("[WARN]", fmt, ...) end
function DE.err(fmt, ...)  emit("[ERROR]", fmt, ...) end

function DE.dbg(fmt, ...)
    if DE.Config.debug then emit("[dbg]", fmt, ...) end
end

function DE.guard(what, fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        DE.err("%s failed: %s", what, tostring(result))
        return nil
    end
    return result
end

function DE.rand(min, max)
    if max == nil then min, max = 1, min end
    if max <= min then return min end
    return ZombRand(min, max + 1)
end

function DE.chance(percent)
    return ZombRand(100) < (percent or 0)
end

function DE.pick(list)
    if not list or #list == 0 then return nil end
    return list[DE.rand(1, #list)]
end

function DE.gameHours()
    return getGameTime():getWorldAgeHours()
end

function DE.gameDays()
    return getGameTime():getWorldAgeHours() / 24
end

-- Nearest player to (x, y), or nil if nobody is on. In single-player there's no
-- online-player list, so fall back to the local player.
function DE.nearestPlayer(x, y)
    local players = getOnlinePlayers()
    local n = players and players:size() or 0
    if n == 0 then return getSpecificPlayer(0) end

    local best, bestSq
    for i = 0, n - 1 do
        local p = players:get(i)
        if p then
            local dx, dy = p:getX() - x, p:getY() - y
            local dSq = dx * dx + dy * dy
            if not bestSq or dSq < bestSq then best, bestSq = p, dSq end
        end
    end
    return best
end

-- Paths every loaded zombie within `radius` tiles of (x, y) toward (tx, ty).
-- Only touches zombies whose chunk is streamed in — virtualised ones move on
-- their own once loaded. Meant to be called from a pulse to draw a horde toward
-- a town centre (repopulation). Returns how many zombies were redirected.
function DE.attractZombies(x, y, radius, tx, ty)
    local c = getCell()
    local list = c and c:getZombieList()
    if not list then return 0 end

    local radiusSq = (radius or 100) * (radius or 100)
    local moved = 0
    for i = 0, list:size() - 1 do
        local zed = list:get(i)
        if zed then
            local dx, dy = zed:getX() - x, zed:getY() - y
            if dx * dx + dy * dy <= radiusSq then
                DE.guard("attractZombie", function()
                    zed:pathToLocationF(tx, ty, zed:getZ())
                end)
                moved = moved + 1
            end
        end
    end
    DE.dbg("attracted %d zombie(s) toward (%d, %d)", moved, tx, ty)
    return moved
end

DE.log("DynamicEventsFramework v%s loaded", DE.VERSION)
