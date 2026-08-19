DE = DE or {}

-- Emergency radio broadcasts. Messages degrade with distance (range) and
-- weather; the engine skips broadcasts at the exact source. Frequency is in kHz
-- (default 105600 = 105.6 MHz). A range of -1 is passed straight through to the
-- engine as a rangeless (effectively global) transmission.
-- Placeholders in messages: {name} (location), {x}/{y} (coords); legacy %s.

local DEFAULT_FREQ = 105600   -- kHz (105.6 MHz)
local DEFAULT_INTERVAL = 7200 -- in-game seconds (2 in-game hours)
local DEFAULT_RANGE = 200     -- tiles; -1 = rangeless/global

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

-- Fill {name}/{x}/{y} (and legacy %s) placeholders in a message.
local function resolve(msg, name, x, y)
    name = name or "unknown"
    local text = string.gsub(msg, "{name}", function() return name end)
    text = string.gsub(text, "{x}", function() return tostring(x or "?") end)
    text = string.gsub(text, "{y}", function() return tostring(y or "?") end)
    text = string.gsub(text, "%%s", function()
        return string.format("%s (%s, %s)", name, tostring(x or "?"), tostring(y or "?"))
    end)
    return text
end

-- Send one transmission on `freq` from (x, y). Public so events and other
-- systems can broadcast directly, not only the periodic active-event upkeep.
--   opts = {
--     message   = "...",        -- required; {name}/{x}/{y} placeholders
--     frequency = 105600,       -- kHz
--     range     = 200,          -- tiles; -1 = rangeless/global
--     x, y      = coords,       -- broadcast origin (default 0,0)
--     name      = "location",   -- for the {name} placeholder
--   }
function DE.broadcast(opts)
    opts = opts or {}
    local msg = opts.message
    if not msg then return false end

    local radio = getRadio()
    if not radio then return false end

    local freq = opts.frequency or DEFAULT_FREQ
    local range = opts.range or DEFAULT_RANGE
    local x = opts.x or 0
    local y = opts.y or 0

    ensureChannel(radio, freq)

    local text = resolve(msg, opts.name, x, y)

    local ok, err = pcall(radio.SendTransmission, radio,
        x, y, freq,
        text, "", "", 1.0, 0.2, 0.2, range, false)

    if ok then
        DE.dbg("broadcast on ch %d (range %d): %s", freq, range, text)
    else
        DE.warn("radio broadcast failed: %s", tostring(err))
    end
    return ok
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

-- Called from the scheduler's upkeep pass; broadcasts each active event with a
-- radio block on its own interval.
function DE.broadcastRadios()
    if not getRadio() then return end

    local now = DE.gameHours() * 3600

    for _, data in pairs(DE.EventManager.active) do
        local def = DE.EventManager.get(data.typeId)
        if def and def.radio then
            local interval = def.radio.interval or DEFAULT_INTERVAL
            if now - (data._lastRadioBroadcast or 0) >= interval then
                DE.broadcast({
                    message   = DE.pick(def.radio.messages),
                    frequency = def.radio.frequency or DEFAULT_FREQ,
                    range     = def.radio.range or DEFAULT_RANGE,
                    x = data.x, y = data.y,
                    name = locationLabel(def, data),
                })
                data._lastRadioBroadcast = now
            end
        end
    end
end
