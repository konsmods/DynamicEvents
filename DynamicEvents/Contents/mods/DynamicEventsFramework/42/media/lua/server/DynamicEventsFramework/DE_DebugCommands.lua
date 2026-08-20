if isClient() then return end

DE = DE or {}

-- ============================================================================
-- Debug commands. Each takes an optional `player` so OnClientCommand can pass
-- the requesting admin; otherwise getSpecificPlayer(0) is used (SP/console).
-- ============================================================================

local function getPlayer(override)
    return override or getSpecificPlayer(0)
end

-- Log to the server console and echo to the requesting player, if any.
local function report(p, fmt, ...)
    local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    DE.log(msg)
    if p then p:Say(msg) end
end

function DE.Spawn(eventId, x, y, z, rot, player)
    local def = DE.EventManager.get(eventId)
    if not def then
        DE.log("Unknown event: %s", eventId)
        return
    end

    local p = getPlayer(player)
    if not x then
        if p then
            x, y, z = p:getX(), p:getY(), p:getZ()
        else
            DE.log("No player found, using first location")
            local loc = def.locations[1]
            x, y, z = loc.x, loc.y, loc.z or 0
        end
    end
    local sx, sy, sz = x, y or 0, z or 0

    local nearVeh = DE.EventManager.countVehiclesNear(sx, sy, sz)
    if nearVeh > 0 then
        DE.log("WARNING: %d vehicle(s) already within range of (%d, %d) — forced spawn", nearVeh, sx, sy)
    end

    -- Go through spawnOrQueue, not runSpawn: spawning at coordinates whose
    -- chunk isn't loaded has to park, exactly like a scheduled event.
    local result = DE.EventManager.spawnOrQueue(def, sx, sy, sz, rot)
    if result == "queued" then
        report(p, "Parked %s at (%d, %d, %d) — appears when that area loads", def.name or def.id, sx, sy, sz)
    else
        report(p, "Spawned %s at (%d, %d, %d)", def.name or def.id, sx, sy, sz)
    end
end

function DE.SpawnHere(eventId, player)
    local p = getPlayer(player)
    if not p then DE.log("No player found"); return end
    DE.Spawn(eventId, p:getX(), p:getY(), p:getZ(), nil, player)
end

function DE.SpawnRandom(player)
    local all = DE.EventManager.all()
    if #all == 0 then DE.log("No events registered"); return end
    DE.Spawn(DE.pick(all).id, nil, nil, nil, nil, player)
end

-- Like DE.Spawn, but clears vehicles in the spawn area first (regardless of the
-- event's clearObstacles flag).
function DE.SpawnForce(eventId, x, y, z, rot, player)
    local def = DE.EventManager.get(eventId)
    if not def then
        DE.log("Unknown event: %s", eventId)
        return
    end

    local p = getPlayer(player)
    if not x then
        if p then
            x, y, z = p:getX(), p:getY(), p:getZ()
        else
            DE.log("No player found, using first location")
            local loc = def.locations[1]
            x, y, z = loc.x, loc.y, loc.z or 0
        end
    end
    local sx, sy, sz = x, y or 0, z or 0

    local radius = DE.EventManager.clearRadiusFor(def)
    local cleared = DE.EventHelpers.clearVehicles(sx, sy, sz, radius)
    DE.log("forced spawn: cleared %d vehicle(s) within %d tiles of (%d, %d)",
        cleared, radius, sx, sy)

    local result = DE.EventManager.spawnOrQueue(def, sx, sy, sz, rot)
    if result == "queued" then
        report(p, "Parked %s at (%d, %d, %d) — appears when that area loads", def.name or def.id, sx, sy, sz)
    else
        report(p, "Spawned %s at (%d, %d, %d)", def.name or def.id, sx, sy, sz)
    end
end

-- Lists tracked events and parked spawns, nearest first.
function DE.ListEvents(player)
    local p = getPlayer(player)
    local px, py = nil, nil
    if p then px, py = p:getX(), p:getY() end

    local events = px and DE.EventManager.getActiveEventsNear(px, py)
                       or DE.EventManager.getActiveEvents()
    local parked = DE.EventManager.getParkedSpawns(px, py)

    if #events == 0 and #parked == 0 then
        report(p, "[DE] No tracked events.")
        return
    end

    local function away(d)
        return d and string.format(", ~%d tiles away", d) or ""
    end

    local now = DE.gameHours()
    if #events > 0 then
        DE.log("=== %d spawned event(s), nearest first ===", #events)
        for _, ev in ipairs(events) do
            DE.log("  %s — %s at (%d, %d, %d), %d-tile footprint, %d zombie(s), %.1fh old%s",
                ev.uid, ev.id, ev.x, ev.y, ev.z, ev.radius, ev.zombies,
                now - (ev.spawnedAt or now), away(ev.distance))
        end
    end

    if #parked > 0 then
        DE.log("=== %d parked spawn(s), waiting for their chunk to load ===", #parked)
        for _, ev in ipairs(parked) do
            DE.log("  (no uid yet) — %s at (%d, %d, %d)%s",
                tostring(ev.id), ev.x, ev.y, ev.z, away(ev.distance))
        end
    end

    if #parked == 0 then
        local n = events[1]
        report(p, "[DE] %d spawned event(s); nearest is %s at (%d, %d)%s — full list in console",
            #events, n.uid, n.x, n.y, n.distance and string.format(" ~%d tiles", n.distance) or "")
    else
        report(p, "[DE] %d spawned event(s), %d parked spawn(s) — full list in console",
            #events, #parked)
    end
end

-- Teleports the admin to a tracked event so its chunks stream in and it can
-- actually be cleared. Without a uid, goes to the nearest one.
function DE.GoTo(uid, player)
    local p = getPlayer(player)
    if not p then DE.log("No player"); return end

    local data, target
    if uid then
        data = DE.EventManager.active[uid]
        if not data then
            report(p, "[DE] No tracked event with uid '%s'", tostring(uid))
            return
        end
        target = uid
    else
        local nearest = DE.EventManager.getActiveEventsNear(p:getX(), p:getY())[1]
        if not nearest then
            report(p, "[DE] No tracked events to travel to")
            return
        end
        data, target = DE.EventManager.active[nearest.uid], nearest.uid
    end

    report(p, "[DE] Teleporting to %s at (%d, %d, %d)", target, data.x, data.y, data.z)

    if isServer() then
        -- MP: the client owns the actual move.
        sendServerCommand(p, "DynamicEventsFramework", "Teleport",
            { x = data.x, y = data.y, z = data.z })
    else
        -- SP: move directly, centred on the tile like vanilla.
        p:teleportTo(data.x + 0.5, data.y + 0.5, data.z or 0)
    end
end

-- Clears every tracked event in the world. Events whose chunks aren't loaded
-- are parked and cleared the moment a player streams the area in.
function DE.Clean(player)
    local p = getPlayer(player)

    -- Snapshot uids first: clearEvent mutates EM.active.
    local uids = {}
    for uid in pairs(DE.EventManager.active) do
        uids[#uids + 1] = uid
    end

    local cleared, parked = 0, 0
    for _, uid in ipairs(uids) do
        local ok, reason = DE.EventManager.clearEvent(uid)
        if ok and reason == "parked" then
            parked = parked + 1
        elseif ok then
            cleared = cleared + 1
        end
    end

    report(p, "[DE] Cleared %d event(s), %d parked until their area loads", cleared, parked)
end

-- Lists work parked against a square, waiting for that chunk to stream in.
function DE.Pending(player)
    local p = getPlayer(player)

    local count = 0
    DE.SquareQueue.forEach(function(entry)
        count = count + 1
        local d = ""
        if p then
            d = string.format(", ~%d tiles away",
                math.floor(math.sqrt((entry.x - p:getX())^2 + (entry.y - p:getY())^2)))
        end
        DE.log("  %s at (%d, %d, %d)%s", entry.command, entry.x, entry.y, entry.z, d)
    end)

    if count == 0 then
        report(p, "[DE] Nothing parked")
    else
        report(p, "[DE] %d item(s) parked waiting on chunk loads — details in console", count)
    end
end

-- Clears one tracked event by uid. Its location becomes available again. If the
-- site's chunks aren't loaded, the clear is parked until they stream in.
function DE.ClearEvent(uid, player)
    local p = getPlayer(player)
    if not uid then
        report(p, "[DE] Usage: DE.ClearEvent(\"convoy_crash_ki5_3\") — see DE.ListEvents()")
        return
    end

    local data = DE.EventManager.active[uid]
    if not data then
        report(p, "[DE] No tracked event with uid '%s'", tostring(uid))
        return
    end

    DE.log("Clearing '%s' (%d-tile footprint)", uid, data.radius or 0)
    local ok, reason = DE.EventManager.clearEvent(uid)
    if not ok then
        report(p, "[DE] %s: %s", uid, reason)
    elseif reason == "parked" then
        report(p, "[DE] %s parked — will clear when the area loads", uid)
    else
        report(p, "[DE] Cleared %s", uid)
    end
end

-- Clears every tracked event within `radius` tiles of the caller (default 100).
function DE.ClearNearby(radius, player)
    local p = getPlayer(player)
    if not p then DE.log("No player"); return end

    local r = radius or 100
    local cleared, parked = 0, 0
    for _, ev in ipairs(DE.EventManager.getActiveEventsNear(p:getX(), p:getY())) do
        if ev.distance <= r then
            local ok, reason = DE.EventManager.clearEvent(ev.uid)
            if ok and reason == "parked" then
                parked = parked + 1
            elseif ok then
                DE.log("Cleared '%s' at (%d, %d), ~%d tiles away", ev.uid, ev.x, ev.y, ev.distance)
                cleared = cleared + 1
            end
        end
    end

    report(p, "[DE] Cleared %d event(s), %d parked within %d tiles", cleared, parked, r)
end

-- Resets every event type's cooldown (clearing an event does not).
function DE.ClearCooldowns(player)
    local p = getPlayer(player)
    DE.EventManager.clearCooldowns()
    report(p, "[DE] Cleared all event cooldowns")
end

function DE.CheckSpot(radius, player)
    local p = getPlayer(player)
    if not p then DE.log("No player"); return end

    local r = radius or DE.Config.minDistanceFromVehicles or 15
    local count = DE.EventManager.countVehiclesNear(p:getX(), p:getY(), p:getZ(), r)
    report(p, "[DE] %d vehicle(s) within %d tiles of you", count, r)
end

function DE.VehicleInfo(player)
    local p = getPlayer(player)
    if not p then DE.log("No player"); return end
    local sq = p:getSquare()
    if not sq then DE.log("No square"); return end

    -- B42: a square maps to at most one vehicle, via getVehicleContainer().
    local v = sq:getVehicleContainer()
    if not v then
        report(p, "[DE] No vehicle on your square")
        return
    end

    report(p, "[DE] id=%d event=%s script=%s",
        v:getId(), tostring(DE.EventHelpers.tagOf(v)), v:getScriptName() or "?")
end

-- Dumps the event tag on everything on the player's square. The quick way to
-- confirm tags are actually surviving a save/reload.
function DE.TagHere(player)
    local p = getPlayer(player)
    if not p then DE.log("No player"); return end
    local sq = p:getSquare()
    if not sq then DE.log("No square"); return end

    local EH = DE.EventHelpers
    local found = 0

    local veh = sq:getVehicleContainer()
    if veh then
        found = found + 1
        DE.log("  vehicle id=%d — %s", veh:getId(), tostring(EH.tagOf(veh)))
    end

    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local uid = obj and EH.ownerOf(obj)
        if uid then
            found = found + 1
            local sprite = obj:getSprite()
            DE.log("  %s (%s) — %s",
                tostring(sprite and sprite:getName()), tostring(obj:getObjectName()), uid)
        end
    end

    if found == 0 then
        report(p, "[DE] Nothing on your square carries an event tag")
    else
        report(p, "[DE] %d tagged thing(s) on your square — details in console", found)
    end
end

-- Removes tagged leftovers from events the manager no longer knows about —
-- state lost, save rolled back, an event cleared while its chunk was unloaded.
-- Anything still tracked is reported and left alone; clear it with DE.ClearEvent.
function DE.Purge(radius, player)
    local p = getPlayer(player)
    if not p then DE.log("No player"); return end

    local EH = DE.EventHelpers
    local r = math.min(radius or 30, EH.MAX_SWEEP_RADIUS)
    local px, py, pz = p:getX(), p:getY(), p:getZ()

    local found = EH.findTags(px, py, pz, r)
    local orphans, tracked, removed = 0, 0, 0

    DE.log("=== Purge: tags within %d tiles of (%d, %d, %d) ===", r, px, py, pz)
    for uid, count in pairs(found) do
        if DE.EventManager.active[uid] then
            tracked = tracked + 1
            DE.log("  %s — %d object(s), still tracked, left alone", uid, count)
        else
            orphans = orphans + 1
            local n = EH.cleanupByTag(px, py, pz, uid, r)
            removed = removed + n
            DE.log("  %s — orphaned, removed %d object(s)", uid, n)
        end
    end

    if orphans == 0 and tracked == 0 then
        report(p, "[DE] No event leftovers within %d tiles", r)
    else
        report(p, "[DE] Purged %d orphaned event(s) (%d objects); left %d tracked event(s) alone",
            orphans, removed, tracked)
    end
end

function DE.WhereAmI(player)
    local p = getPlayer(player)
    if not p then DE.log("No player"); return end
    report(p, "You are at (%d, %d, %d)", p:getX(), p:getY(), p:getZ())
end

function DE.Outfits(keyword, player)
    local p = getPlayer(player)
    local kw = keyword and string.lower(keyword)

    for _, group in ipairs({ { label = "Male", female = false }, { label = "Female", female = true } }) do
        DE.log("=== %s outfits ===", group.label)
        local outfits = getAllOutfits(group.female)
        for i = 0, outfits:size() - 1 do
            local name = outfits:get(i)
            if not kw or string.find(string.lower(name), kw, 1, true) then
                DE.log("  %s", name)
            end
        end
    end

    if p then
        p:Say(kw and ("[DE] Outfits matching '" .. kw .. "' dumped to console")
                  or "[DE] Outfits dumped to console")
    end
end

function DE.Info(player)
    DE.log("=== DynamicEventsFramework Info ===")
    DE.log("Version: %s", DE.VERSION)

    DE.log("Config:")
    for _, opt in ipairs(DE.CONFIG_SPEC) do
        DE.log("  %s = %s", opt.key, tostring(DE.Config[opt.key]))
    end

    DE.log("Registered events: %d", DE.EventManager.count())
    for _, def in ipairs(DE.EventManager.all()) do
        DE.log("  %s — weight=%d, locations=%d, cooldown=%dh",
            def.id, def.weight, def.locations and #def.locations or 0, def.cooldownHours)
    end

    local active = DE.EventManager.getActiveEvents()
    DE.log("Tracked events: %d (permanent until cleared)", #active)
    for _, ev in ipairs(active) do
        DE.log("  %s — %s at (%d, %d, %d), %d-tile footprint, %d zombie(s)",
            ev.uid, ev.id, ev.x, ev.y, ev.z, ev.radius, ev.zombies)
    end

    local p = getPlayer(player)
    if p then p:Say("[DE] Full mod info dumped to console") end
end

-- Reports what the scheduler is waiting for, and why each event is (in)eligible.
function DE.SchedulerInfo(player)
    local p = getPlayer(player)
    local now = DE.gameHours()
    local sched = DE.Scheduler or {}

    DE.log("=== Scheduler ===")
    DE.log("Enabled: %s", tostring(DE.Config.enabled))
    DE.log("World age: %.2f hours (day %.2f)", now, now / 24)
    DE.log("Interval: %.2f in-game hours", DE.Config.intervalHours or 1)
    DE.log("Grace period: %.2f hours", DE.Config.gracePeriodHours or 0)
    DE.log("Restored save: %s", tostring(DE.EventManager._wasRestored))

    if sched.nextFireHour then
        local remaining = sched.nextFireHour - now
        if remaining <= 0 then
            DE.log("Next fire: DUE (overdue by %.2f hours)", -remaining)
        else
            DE.log("Next fire: in %.2f in-game hours", remaining)
        end
    else
        DE.log("Next fire: not armed (waiting for OnGameStart)")
    end

    DE.log("Pending spawns (warning delay): %d", #DE._pendingSpawns)

    DE.log("=== Event eligibility right now ===")
    for _, def in ipairs(DE.EventManager.all()) do
        local reason = DE.EventManager.eligibilityReason(def)
        if not reason then
            DE.log("  %s: ELIGIBLE", def.id)
        else
            DE.log("  %s: not eligible — %s", def.id, reason)
        end
    end

    report(p, "[DE] Scheduler info dumped to console")
end

-- ============================================================================
-- Client command forwarding: the client shim forwards these, we run them here.
-- ============================================================================

local HANDLERS = {
    Spawn         = function(p, a) DE.Spawn(a.id, a.x, a.y, a.z, a.rot, p) end,
    SpawnHere     = function(p, a) DE.SpawnHere(a.id, p) end,
    SpawnRandom   = function(p)    DE.SpawnRandom(p) end,
    SpawnForce    = function(p, a) DE.SpawnForce(a.id, a.x, a.y, a.z, a.rot, p) end,
    Clean         = function(p)    DE.Clean(p) end,
    ClearEvent    = function(p, a) DE.ClearEvent(a.uid, p) end,
    ClearNearby   = function(p, a) DE.ClearNearby(a.radius, p) end,
    ClearCooldowns = function(p)   DE.ClearCooldowns(p) end,
    Purge         = function(p, a) DE.Purge(a.radius, p) end,
    TagHere       = function(p)    DE.TagHere(p) end,
    GoTo          = function(p, a) DE.GoTo(a.uid, p) end,
    Pending       = function(p)    DE.Pending(p) end,
    ListEvents    = function(p)    DE.ListEvents(p) end,
    WhereAmI      = function(p)    DE.WhereAmI(p) end,
    VehicleInfo   = function(p)    DE.VehicleInfo(p) end,
    CheckSpot     = function(p, a) DE.CheckSpot(a.radius, p) end,
    Outfits       = function(p, a) DE.Outfits(a.keyword, p) end,
    Info          = function(p)    DE.Info(p) end,
    SchedulerInfo = function(p)    DE.SchedulerInfo(p) end,
    -- The admin panel's read side: gather state and send it back to the client.
    RequestState  = function(p)    DE.sendStateSnapshot(p) end,
}

local function isPlayerAuthorized(p)
    if not p then return false end
    local level = nil
    pcall(function() level = p:getAccessLevel() end)
    return level == "admin"
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "DynamicEventsFramework" then return end

    local handler = HANDLERS[command]
    if not handler then
        DE.warn("unknown client command '%s'", tostring(command))
        return
    end

    if not isPlayerAuthorized(player) then
        DE.warn("'%s' rejected — player not admin", command)
        return
    end

    handler(player, args or {})
end)

DE.dbg("debug console — spawn: DE.Spawn, DE.SpawnHere, DE.SpawnRandom, DE.SpawnForce | "
    .. "admin: DE.ListEvents, DE.GoTo(uid), DE.ClearEvent(uid), DE.ClearNearby(radius), "
    .. "DE.Clean, DE.Purge(radius), DE.Pending, DE.ClearCooldowns | "
    .. "info: DE.WhereAmI, DE.VehicleInfo, DE.TagHere, DE.CheckSpot, DE.Outfits, DE.Info, DE.SchedulerInfo")
