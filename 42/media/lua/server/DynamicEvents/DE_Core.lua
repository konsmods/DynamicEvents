DE = DE or {}

DE.VERSION = "0.1.0"

DE.Config = {
    enabled              = true,
    maxActive            = 3,
    minTimeBetweenEvents = 1.0,   -- in-game hours
    eventChance          = 50,    -- percent chance per scheduler tick
    gracePeriodHours     = 1.0,   -- hours after game start before first event
    eventCleanup         = true,  -- false = locations are one-use, events never expire
    debug                = false,
}

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
    print(string.format("[DynamicEvents][%s]%s %s", side(), tag, tostring(message)))
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

DE.log("DynamicEvents v%s loaded", DE.VERSION)
