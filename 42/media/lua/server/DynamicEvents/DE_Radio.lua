DE = DE or {}

-- Emergency radio broadcasts for active events.
-- signalStrength comes from the event's radio.range (default 200 tiles) and
-- messages degrade with distance. Note: the engine skips broadcasts when the
-- listener stands at the exact source coordinates.
-- Channel 105.6 MHz (105600 kHz), category "Emergency".

local CHANNEL_FREQ = 105600
local DEFAULT_INTERVAL = 7200  -- in-game seconds (2 in-game hours)
local DEFAULT_RANGE = 200      -- tiles

-- Returns the radio object, registering our channel on first use. nil while
-- the radio subsystem isn't up yet, in which case we retry on the next call.
local function getRadio()
    local ok, radio = pcall(getZomboidRadio)
    if not ok or not radio then return nil end

    if not DE._radioChannel then
        DE._radioChannel = CHANNEL_FREQ
        radio:addChannelName("[DE] Emergency Broadcast", CHANNEL_FREQ, "Emergency", true)
        DE.log("radio channel %d registered", CHANNEL_FREQ)
    end
    return radio
end

-- The location name is fixed for the life of an active event, so resolve it
-- once and cache it on the event (runtime-only; saveState doesn't persist it).
local function locationLabel(def, data)
    if not data._radioLocName then
        local label = "unknown"
        for _, loc in ipairs(def.locations or {}) do
            if loc.x == data.x and loc.y == data.y then
                label = loc.name or label
                break
            end
        end
        data._radioLocName = label
    end
    return data._radioLocName
end

local function broadcast(radio, def, data)
    local msg = DE.pick(def.radio.messages)
    if not msg then return end

    local where = string.format("%s (%d, %d)", locationLabel(def, data), data.x, data.y)
    local text = string.gsub(msg, "%%s", where)

    local ok, err = pcall(radio.SendTransmission, radio,
        data.x, data.y, CHANNEL_FREQ,
        text, "", "", 1.0, 0.2, 0.2, def.radio.range or DEFAULT_RANGE, false)

    if ok then
        DE.dbg("broadcast on ch %d: %s", CHANNEL_FREQ, text)
    else
        DE.warn("radio broadcast failed: %s", tostring(err))
    end
end

-- Called from the scheduler's upkeep pass. Broadcasts for each active event
-- that declares a radio config, at its configured interval (in-game seconds).
function DE.broadcastRadios()
    local radio = getRadio()
    if not radio then return end

    local now = DE.gameHours() * 3600

    for _, data in pairs(DE.EventManager.active) do
        local def = DE.EventManager.get(data.typeId)
        if def and def.radio then
            local interval = def.radio.interval or DEFAULT_INTERVAL
            if now - (data._lastRadioBroadcast or 0) >= interval then
                broadcast(radio, def, data)
                data._lastRadioBroadcast = now
            end
        end
    end
end
