if isClient() then return end

DE = DE or {}

local function announceCoords(def, x, y, z)
    local msg = string.format("Spawned %s at (%d, %d, %d)", def.name or def.id, x, y, z)
    DE.log(msg)
    local p = getSpecificPlayer(0)
    if p then p:Say(msg) end
end

function DE.Spawn(eventId, x, y, z)
    local def = DE.EventManager.get(eventId)
    if not def then
        DE.log("Unknown event: %s", eventId)
        return
    end

    if not x then
        local p = getSpecificPlayer(0)
        if p then
            x, y, z = p:getX(), p:getY(), p:getZ()
        else
            DE.log("No player found, using first location")
            x, y, z = def.locations[1].x, def.locations[1].y, def.locations[1].z or 0
        end
    end
    local sx, sy, sz = x, y or 0, z or 0

    announceCoords(def, sx, sy, sz)
    DE.EventHelpers.playSound(sx, sy, sz, def.sound)

    local ok, objects = pcall(def.spawn, sx, sy, sz)
    if not ok then
        DE.err("%s spawn failed: %s", def.id, tostring(objects))
        objects = {}
    end
    objects = objects or {}
    DE.dbg("%s debug spawn returned %d tracked objects", def.id, #objects)
    DE.EventManager.addActive(def.id, sx, sy, sz, objects)
end

function DE.SpawnHere(eventId)
    local def = DE.EventManager.get(eventId)
    if not def then
        DE.log("Unknown event: %s", eventId)
        return
    end
    local p = getSpecificPlayer(0)
    if not p then DE.log("No player found"); return end
    local px, py, pz = p:getX(), p:getY(), p:getZ()
    DE.Spawn(eventId, px, py, pz)
end

function DE.SpawnRandom()
    local all = DE.EventManager.all()
    if #all == 0 then DE.log("No events registered"); return end
    local def = all[DE.rand(1, #all)]
    DE.Spawn(def.id)
end

function DE.ListEvents()
    local p = getSpecificPlayer(0)
    local active = DE.EventManager.getActiveEvents()
    local msg
    if #active == 0 then
        msg = "No active events."
    else
        msg = string.format("%d active events: ", #active)
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
    if not p then DE.log("No player"); return end
    local msg = string.format("You are at (%d, %d, %d)", p:getX(), p:getY(), p:getZ())
    DE.log(msg)
    p:Say(msg)
end

function DE.CleanupNow()
    if not DE.Config.eventCleanup then
        DE.log("eventCleanup is disabled, nothing to expire")
        local p = getSpecificPlayer(0)
        if p then p:Say("[DE] Cleanup is OFF (EventCleanup=false)") end
        return
    end

    local now = DE.gameHours()
    local toExpire = {}
    for id, data in pairs(DE.EventManager.active) do
        local def = DE.EventManager.get(data.typeId)
        local lifetime = (def and def.lifetimeHours) or 48
        if now - data.spawnedAt >= lifetime then
            toExpire[id] = { data = data, def = def, lifetime = lifetime }
        end
    end

    for id, info in pairs(toExpire) do
        DE.log("Expiring '%s' (lifetime %.0fh, spawned %.1fh ago)",
            id, info.lifetime, now - info.data.spawnedAt)
        if info.def and info.def.cleanup then
            DE.guard(id .. " cleanup", function()
                info.def.cleanup(info.data.x, info.data.y, info.data.z, info.data.objects)
            end)
        end
        DE.EventManager.removeActive(id)
    end

    local p = getSpecificPlayer(0)
    local count = 0
    for _ in pairs(toExpire) do count = count + 1 end
    if count == 0 then
        DE.log("No events ready for expiry")
    end
    if p then p:Say(string.format("[DE] Cleaned up %d expired events", count)) end
end

function DE.Outfits()
    local p = getSpecificPlayer(0)
    DE.log("=== Male outfits ===")
    local male = getAllOutfits(false)
    for i = 0, male:size() - 1 do
        DE.log("  %s", male:get(i))
    end
    DE.log("=== Female outfits ===")
    local female = getAllOutfits(true)
    for i = 0, female:size() - 1 do
        DE.log("  %s", female:get(i))
    end
    if p then p:Say("[DE] Outfits dumped to console") end
end

function DE.Clean()
    DE.CleanupAll()
end

function DE.CleanupAll()
    local ids = {}
    for id in pairs(DE.EventManager.active) do
        table.insert(ids, id)
    end

    for _, id in ipairs(ids) do
        local data = DE.EventManager.active[id]
        if data then
            local def = DE.EventManager.get(data.typeId)
            DE.log("Force-cleaning '%s' (%d objects)", id, data.objects and #data.objects or 0)
            if def and def.cleanup then
                DE.guard(id .. " cleanup", function()
                    def.cleanup(data.x, data.y, data.z, data.objects)
                end)
            end
            DE.EventManager.removeActive(id)
        end
    end

    local p = getSpecificPlayer(0)
    if p then p:Say(string.format("[DE] Force-cleaned all %d events", #ids)) end
    DE.log("Force-cleaned %d events", #ids)
end

function DE.ToggleCleanup()
    DE.Config.eventCleanup = not DE.Config.eventCleanup
    local msg = string.format("EventCleanup set to: %s", tostring(DE.Config.eventCleanup))
    DE.log(msg)
    local p = getSpecificPlayer(0)
    if p then p:Say(msg) end
end

function DE.Info()
    local p = getSpecificPlayer(0)

    DE.log("=== DynamicEvents Info ===")
    DE.log("Version: %s", DE.VERSION)
    DE.log("Config:")
    for k, v in pairs(DE.Config) do
        DE.log("  %s = %s", k, tostring(v))
    end
    DE.log("Registered events: %d", DE.EventManager.count())
    for _, def in ipairs(DE.EventManager.all()) do
        local locs = def.locations and #def.locations or 0
        local used = 0
        local usedLocs = DE.EventManager.usedLocations[def.id]
        if usedLocs then
            for _ in pairs(usedLocs) do used = used + 1 end
        end
        DE.log("  %s — weight=%d, locations=%d/%d used, cooldown=%dh, lifetime=%dh",
            def.id, def.weight or 10, used, locs, def.cooldownHours or 24, def.lifetimeHours or 48)
    end
    local active = DE.EventManager.getActiveEvents()
    DE.log("Active events: %d", #active)
    for _, ev in ipairs(active) do
        DE.log("  %s at (%d, %d, %d)", ev.id, ev.x, ev.y, ev.z)
    end

    if p then p:Say("[DE] Full mod info dumped to console") end
end

DE.dbg("debug console: DE.Spawn, DE.SpawnHere, DE.SpawnRandom, DE.ListEvents, DE.WhereAmI, DE.Clean, DE.CleanupNow, DE.Outfits, DE.ToggleCleanup, DE.Info")
