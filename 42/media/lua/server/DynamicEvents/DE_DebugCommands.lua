if isClient() then return end

DE = DE or {}

local function announceCoords(def, x, y, z)
    local msg = string.format("[DE] Spawned %s at (%d, %d, %d)", def.name or def.id, x, y, z)
    DE.log(msg)
    local p = getSpecificPlayer(0)
    if p then p:Say(msg) end
end

function DE.Spawn(eventId, x, y, z)
    local def = DE.EventManager.get(eventId)
    if not def then
        DE.log("[DE] Unknown event: %s", eventId)
        return
    end

    if not x then
        local p = getSpecificPlayer(0)
        if p then
            x, y, z = p:getX(), p:getY(), p:getZ()
        else
            DE.log("[DE] No player found, using first location")
            x, y, z = def.locations[1].x, def.locations[1].y, def.locations[1].z or 0
        end
    end
    local sx, sy, sz = x, y or 0, z or 0

    announceCoords(def, sx, sy, sz)

    if def.warning and def.warning.ambient and def.warning.ambient.sound then
        local emitter = getWorld():getFreeEmitter(sx, sy, sz)
        if emitter then emitter:playSound(def.warning.ambient.sound) end
    end

    local objects = nil
    DE.guard(def.id .. " spawn", function()
        objects = def.spawn(sx, sy, sz)
    end)
    DE.EventManager.addActive(def.id, sx, sy, sz, objects)
end

function DE.SpawnHere(eventId)
    local def = DE.EventManager.get(eventId)
    if not def then
        DE.log("[DE] Unknown event: %s", eventId)
        return
    end
    local p = getSpecificPlayer(0)
    if not p then DE.log("[DE] No player found"); return end
    local px, py, pz = p:getX(), p:getY(), p:getZ()
    DE.Spawn(eventId, px, py, pz)
end

function DE.SpawnRandom()
    local all = DE.EventManager.all()
    if #all == 0 then DE.log("[DE] No events registered"); return end
    local def = all[DE.rand(1, #all)]
    DE.Spawn(def.id)
end

function DE.ListEvents()
    local p = getSpecificPlayer(0)
    local active = DE.EventManager.getActiveEvents()
    local msg
    if #active == 0 then
        msg = "[DE] No active events."
    else
        msg = string.format("[DE] %d active events: ", #active)
        for _, ev in ipairs(active) do
            local d = p and math.floor(math.sqrt((ev.x - p:getX())^2 + (ev.y - p:getY())^2)) or "?"
            msg = msg .. string.format("%s at (%d,%d) ~%stiles  ", ev.id, ev.x, ev.y, tostring(d))
        end
    end
    DE.log(msg)
    if p then p:Say(msg) end
end

function DE.WhereAmI()
    local p = getSpecificPlayer(0)
    if not p then DE.log("[DE] No player"); return end
    local msg = string.format("[DE] You are at (%d, %d, %d)", p:getX(), p:getY(), p:getZ())
    DE.log(msg)
    p:Say(msg)
end

function DE.CleanupNow()
    if not DE.Config.eventCleanup then
        DE.log("[DE] eventCleanup is disabled, nothing to expire")
        local p = getSpecificPlayer(0)
        if p then p:Say("[DE] Cleanup is OFF (EventCleanup=false)") end
        return
    end

    local now = DE.gameHours()
    local expired = 0
    local toExpire = {}
    for id, data in pairs(DE.EventManager.active) do
        local def = DE.EventManager.get(id)
        local lifetime = (def and def.lifetimeHours) or 48
        if now - data.spawnedAt >= lifetime then
            toExpire[id] = { data = data, def = def, lifetime = lifetime }
        end
    end

    for id, info in pairs(toExpire) do
        DE.log("[DE] Expiring '%s' (lifetime %.0fh, spawned %.1fh ago)",
            id, info.lifetime, now - info.data.spawnedAt)
        if info.def and info.def.cleanup then
            DE.guard(id .. " cleanup", function()
                info.def.cleanup(info.data.x, info.data.y, info.data.z, info.data.objects)
            end)
        end
        DE.EventManager.removeActive(id)
        expired = expired + 1
    end

    if expired == 0 then
        DE.log("[DE] No events ready for expiry (lifetimes: heli=48h, convoy=36h, train=60h)")
    end

    local p = getSpecificPlayer(0)
    if p then p:Say(string.format("[DE] Cleaned up %d expired events", expired)) end
end

function DE.CleanupAll()
    local count = 0
    for id, data in pairs(DE.EventManager.active) do
        local def = DE.EventManager.get(id)
        DE.log("[DE] Force-cleaning '%s'", id)
        if def and def.cleanup then
            DE.guard(id .. " cleanup", function()
                def.cleanup(data.x, data.y, data.z, data.objects)
            end)
        end
        DE.EventManager.removeActive(id)
        count = count + 1
    end
    local p = getSpecificPlayer(0)
    if p then p:Say(string.format("[DE] Force-cleaned all %d events", count)) end
    DE.log("[DE] Force-cleaned %d events", count)
end

function DE.ToggleCleanup()
    DE.Config.eventCleanup = not DE.Config.eventCleanup
    local msg = string.format("[DE] EventCleanup set to: %s", tostring(DE.Config.eventCleanup))
    DE.log(msg)
    local p = getSpecificPlayer(0)
    if p then p:Say(msg) end
end

DE.log("debug console: DE.Spawn, DE.SpawnHere, DE.SpawnRandom, DE.ListEvents, DE.WhereAmI, DE.CleanupNow, DE.CleanupAll, DE.ToggleCleanup")
