DE = DE or {}

-- Emergency radio broadcasts for active events. Messages degrade with distance
-- (radio.range) and weather; the engine skips broadcasts at the exact source.
-- Each event sets radio.frequency (kHz); default 105600 (105.6 MHz).
-- Placeholders: {name} (location), {x}/{y} (coords); legacy %s = "name (x, y)".

local DEFAULT_FREQ = 105600   -- kHz (105.6 MHz)
local DEFAULT_INTERVAL = 7200 -- in-game seconds (2 in-game hours)
local DEFAULT_RANGE = 200     -- tiles

local function eventFrequency(def)
    return def.radio.frequency or DEFAULT_FREQ
end

-- Returns the radio object, nil while the radio subsystem isn't up yet.
local function getRadio()
    local ok, radio = pcall(getZomboidRadio)
    if not ok or not radio then return nil end
    return radio
end

-- Register a channel name for `freq` once, so it shows up in the radio UI.
local function ensureChannel(radio, freq)
    DE._radioChannels = DE._radioChannels or {}
    if DE._radioChannels[freq] then return end
    DE._radioChannels[freq] = true
    radio:addChannelName("[DE] Emergency Broadcast", freq, "Emergency", true)
    DE.log("radio channel %d registered", freq)
end

-- Location name is fixed for the life of an event; resolve once and cache.
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

local function broadcast(radio, def, data, freq)
    local msg = DE.pick(def.radio.messages)
    if not msg then return end

    ensureChannel(radio, freq)

    -- Placeholders: {name}, {x}, {y}; legacy %s = "name (x, y)".
    local name = locationLabel(def, data)
    local text = string.gsub(msg, "{name}", function() return name end)
    text = string.gsub(text, "{x}", function() return tostring(data.x) end)
    text = string.gsub(text, "{y}", function() return tostring(data.y) end)
    text = string.gsub(text, "%%s", function()
        return string.format("%s (%d, %d)", name, data.x, data.y)
    end)

    local ok, err = pcall(radio.SendTransmission, radio,
        data.x, data.y, freq,
        text, "", "", 1.0, 0.2, 0.2, def.radio.range or DEFAULT_RANGE, false)

    if ok then
        DE.dbg("broadcast on ch %d: %s", freq, text)
    else
        DE.warn("radio broadcast failed: %s", tostring(err))
    end
end

-- Called from the scheduler's upkeep pass; broadcasts each event on its interval.
function DE.broadcastRadios()
    local radio = getRadio()
    if not radio then return end

    local now = DE.gameHours() * 3600

    for _, data in pairs(DE.EventManager.active) do
        local def = DE.EventManager.get(data.typeId)
        if def and def.radio then
            local interval = def.radio.interval or DEFAULT_INTERVAL
            if now - (data._lastRadioBroadcast or 0) >= interval then
                broadcast(radio, def, data, eventFrequency(def))
                data._lastRadioBroadcast = now
            end
        end
    end
end
