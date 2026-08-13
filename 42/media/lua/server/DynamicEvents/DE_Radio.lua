DE = DE or {}

-- Emergency radio broadcasts for active events.
-- signalStrength from event's radio.range (default 200 tiles). Messages
-- degrade with distance. Note: the engine skips broadcasts when the
-- listener stands at the exact source coordinates.
-- Channel 105.6 MHz (105600 kHz), category "Emergency".

local function ensureChannel()
    if DE._radioChannel and DE._radioChannel > 0 then return end
    local ok, radio = pcall(getZomboidRadio)
    if not ok or not radio then
        DE._radioChannel = 0
        return
    end
    DE._radioChannel = 105600
    radio:addChannelName("[DE] Emergency Broadcast", DE._radioChannel, "Emergency", true)
    DE.log("radio channel %d registered", DE._radioChannel)
end

local function broadcast(def, data, locName)
    if not DE._radioChannel or DE._radioChannel <= 0 then return end
    local ok, radio = pcall(getZomboidRadio)
    if not ok or not radio then return end

    local msg = DE.pick(def.radio.messages)
    local location = locName and (locName .. " (" .. data.x .. ", " .. data.y .. ")")
                             or ("(" .. data.x .. ", " .. data.y .. ")")
    local text = string.gsub(msg, "%%s", location)

    local range = def.radio.range or 200
    local bcastOk, err = pcall(radio.SendTransmission, radio,
        data.x, data.y, DE._radioChannel,
        text, "", "", 1.0, 0.2, 0.2, range, false)
    if not bcastOk then
        DE.warn("radio broadcast failed: %s", err)
    else
        DE.dbg("broadcast on ch %d: %s", DE._radioChannel, text)
    end
end

-- Called every tick by the scheduler. Iterates active events with a radio
-- config and broadcasts messages at the configured interval (seconds).
function DE.broadcastRadios()
    if not DE._radioChannel or DE._radioChannel <= 0 then
        ensureChannel()
    end
    if not DE._radioChannel or DE._radioChannel <= 0 then return end

    local now = DE.gameHours() * 3600

    for uid, data in pairs(DE.EventManager.active) do
        local def = DE.EventManager.get(data.typeId)
        if def and def.radio then
            data._lastRadioBroadcast = data._lastRadioBroadcast or 0
            local interval = def.radio.interval or 7200
            if now - data._lastRadioBroadcast >= interval then
                local locName = "unknown"
                if def.locations then
                    for _, loc in ipairs(def.locations) do
                        if loc.x == data.x and loc.y == data.y then
                            locName = loc.name
                            break
                        end
                    end
                end
                broadcast(def, data, locName)
                data._lastRadioBroadcast = now
            end
        end
    end
end
