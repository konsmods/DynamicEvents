DE = DE or {}

DE.EventManager = {
    types = {},
    order = {},
    active = {},
    cooldowns = {},
    _nextId = 0,
    _dirty = false,
    _wasRestored = false,
}

local EM = DE.EventManager

EM.DEFAULT_WEIGHT = 10

function EM.register(def)
    assert(type(def) == "table", "event definition must be a table")
    assert(type(def.id) == "string" and def.id ~= "", "event must have an id")
    assert(type(def.name) == "string", "event must have a name")
    assert(type(def.locations) == "table" and #def.locations > 0, "event must have locations")
    assert(type(def.spawn) == "function", "event must have a spawn function")

    if EM.types[def.id] then
        DE.warn("overwriting previously registered event '%s'", def.id)
    else
        -- EM.order is a plain array, so only append ids we haven't seen.
        EM.order[#EM.order + 1] = def.id
    end

    def.cooldownHours = def.cooldownHours or 24
    def.minDaysSurvived = def.minDaysSurvived or 0
    def.weight = def.weight or EM.DEFAULT_WEIGHT
    def.dependencies = def.dependencies or {}
    def.rot = def.rot or 0
    def.cleanup = def.cleanup or DE.EventHelpers.cleanupEvent

    EM.types[def.id] = def

    DE.dbg("registered event type '%s' (weight=%d)", def.id, def.weight)
end

function EM.get(id)
    return EM.types[id]
end

function EM.all()
    local out = {}
    for i = 1, #EM.order do
        out[#out + 1] = EM.types[EM.order[i]]
    end
    return out
end

function EM.count()
    return #EM.order
end

function EM.isOnCooldown(id)
    local untilHour = EM.cooldowns[id]
    if not untilHour then return false end
    return DE.gameHours() < untilHour
end

function EM.startCooldown(id, hours)
    EM.cooldowns[id] = DE.gameHours() + (hours or EM.get(id).cooldownHours)
    EM._dirty = true
    DE.dbg("cooldown for '%s' until hour %.1f", id, EM.cooldowns[id])
end

-- Resets every type's cooldown, making them immediately eligible again.
-- Clearing an event deliberately does NOT do this: the cooldown is a separate
-- throttle from whether the event is still standing in the world.
function EM.clearCooldowns()
    EM.cooldowns = {}
    EM._dirty = true
    DE.log("cleared all event cooldowns")
end

function EM.dependenciesMet(def)
    if not def.dependencies or #def.dependencies == 0 then return true end
    local activeMods = getActivatedMods()
    for _, modId in ipairs(def.dependencies) do
        if not activeMods:contains(modId) then
            DE.dbg("event '%s' skipped: required mod '%s' not active", def.id, modId)
            return false
        end
    end
    return true
end

-- Resolves a dotted SandboxVars path, e.g. "DynamicEventsContent.ConvoyCrashKI5".
-- Returns nil if any step is missing, which callers treat as "not configured".
local function sandboxValue(path)
    local node = SandboxVars
    for part in string.gmatch(path, "[^.]+") do
        if node == nil then return nil end
        local ok, child = pcall(function() return node[part] end)
        if not ok then return nil end
        node = child
    end
    return node
end

-- An event is gated by the sandbox option named in def.enabledVar, if it
-- declares one. Events without one (or whose option is missing, e.g. an older
-- save) are always eligible.
function EM.isEnabledInSandbox(def)
    if not def.enabledVar then return true end

    local val = sandboxValue(def.enabledVar)
    if val == nil then
        DE.dbg("event '%s': sandbox option '%s' not found, treating as enabled", def.id, def.enabledVar)
        return true
    end
    return val ~= false
end

function EM.getEligible()
    local daysSurvived = DE.gameDays()
    local eligible = {}

    for i = 1, #EM.order do
        local def = EM.types[EM.order[i]]
        if def
            and EM.isEnabledInSandbox(def)
            and not EM.isOnCooldown(def.id)
            and daysSurvived >= (def.minDaysSurvived or 0)
            and EM.dependenciesMet(def) then
            eligible[#eligible + 1] = def
        end
    end

    return eligible
end

-- Picks a def from `defs` proportional to def.weight. Returns the def and its
-- index, so callers can remove it and retry with the rest.
function EM.pickWeighted(defs)
    local total = 0
    for i = 1, #defs do
        total = total + (defs[i].weight or EM.DEFAULT_WEIGHT)
    end
    if total <= 0 then return nil, nil end

    local roll = DE.rand(1, total)
    for i = 1, #defs do
        roll = roll - (defs[i].weight or EM.DEFAULT_WEIGHT)
        if roll <= 0 then return defs[i], i end
    end
    return defs[#defs], #defs
end

function EM.getActiveCount()
    local count = 0
    for _ in pairs(EM.active) do count = count + 1 end
    return count
end

local function distanceTo(data, x, y)
    local dx, dy = data.x - x, data.y - y
    return math.sqrt(dx * dx + dy * dy)
end

-- Walks every claimed site — spawned-but-not-cleared events plus spawns parked
-- against a square waiting to materialise — and calls fn(data) until it
-- returns true. Parked spawns count, otherwise two events could book the same
-- spot while the first is still waiting for its chunk.
local function anyTrackedSite(fn)
    for _, data in pairs(EM.active) do
        if fn(data) then return true end
    end

    -- DE_SquareQueue.lua loads after this file, so tolerate it not being up yet.
    if not DE.SquareQueue then return false end

    local hit = false
    DE.SquareQueue.forEach(function(entry)
        if not hit and entry.command == "spawn" and fn(entry.args) then hit = true end
    end)
    return hit
end

-- A site stays occupied until an admin clears it, which is what frees the
-- location for reuse — there is no separate used-location bookkeeping.
function EM.isLocationOccupied(x, y, z)
    local radius = DE.Config.minDistanceBetweenEvents or 20
    return anyTrackedSite(function(data)
        return distanceTo(data, x, y) <= radius
    end)
end

-- Optional anti-cluster limit: refuse a spot that already has maxEventsPerArea
-- tracked events within areaRadius tiles. Disabled when maxEventsPerArea is 0.
function EM.isAreaCrowded(x, y)
    local limit = DE.Config.maxEventsPerArea or 0
    if limit <= 0 then return false end

    local radius = DE.Config.areaRadius or 300
    local count = 0
    anyTrackedSite(function(data)
        if distanceTo(data, x, y) <= radius then count = count + 1 end
        return false   -- never short-circuit; we want the full count
    end)
    return count >= limit
end

-- True when any player is close enough that a spawn would visibly pop into
-- existence in front of them. Only matters when the site is already loaded;
-- an unloaded site gets parked and materialises as the chunk streams in,
-- which happens beyond view distance anyway.
function EM.playerTooClose(x, y)
    local minD = DE.Config.spawnMinDistance or 0
    if minD <= 0 then return false end

    local function tooClose(p)
        if not p then return false end
        local dx, dy = p:getX() - x, p:getY() - y
        return math.sqrt(dx * dx + dy * dy) < minD
    end

    local players = getOnlinePlayers()
    local n = players and players:size() or 0

    -- Single-player runs the server code path but has no online-player list.
    if n == 0 then return tooClose(getSpecificPlayer(0)) end

    for i = 0, n - 1 do
        if tooClose(players:get(i)) then return true end
    end
    return false
end

-- Hard guarantee that the site is streamed in, so everything the event spawns
-- exists in the live world rather than in a chunk nobody has loaded.
function EM.isSiteLoaded(x, y, z)
    local c = getCell()
    return c ~= nil and c:getGridSquare(x, y, z) ~= nil
end

-- Checks whether any vehicle (vanilla traffic-jam, wreck, or our own) is
-- already within `radius` tiles of (x, y). Only checks loaded squares, so it
-- works once the chunk is streamed in (which is when spawning matters anyway).
function EM.isVehicleNear(x, y, z, radius)
    radius = radius or (DE.Config.minDistanceFromVehicles or 15)
    local c = getCell()
    if not c then return false end

    for dx = -radius, radius do
        for dy = -radius, radius do
            local sq = c:getGridSquare(x + dx, y + dy, z)
            if sq and sq:getVehicleContainer() then
                return true
            end
        end
    end
    return false
end

-- Debug helper: returns the number of vehicles within `radius` tiles of (x,y).
function EM.countVehiclesNear(x, y, z, radius)
    radius = radius or (DE.Config.minDistanceFromVehicles or 15)
    local c = getCell()
    if not c then return 0 end
    -- A vehicle spans several squares, so dedupe by id instead of summing.
    local seen, count = {}, 0
    for dx = -radius, radius do
        for dy = -radius, radius do
            local sq = c:getGridSquare(x + dx, y + dy, z)
            local veh = sq and sq:getVehicleContainer()
            if veh then
                local id = veh:getId()
                if not seen[id] then
                    seen[id] = true
                    count = count + 1
                end
            end
        end
    end
    return count
end

-- Why a given location can't be used right now, or nil if it can.
--
-- Distance to players is deliberately NOT a requirement: an unloaded site is
-- parked and materialises when someone arrives. The only proximity rule is
-- that we don't pop a wreck into view of someone already standing there.
--
-- Note the vehicle check only sees loaded chunks, so for a parked spawn it is
-- re-run for real at materialisation time in runQueuedSpawn.
function EM.locationBlockedBy(loc)
    local z = loc.z or 0
    if EM.isLocationOccupied(loc.x, loc.y, z) then return "an event is already here" end
    if EM.isAreaCrowded(loc.x, loc.y)         then return "area already has enough events" end
    if EM.playerTooClose(loc.x, loc.y)        then return "a player is standing too close" end
    if EM.isSiteLoaded(loc.x, loc.y, z) and EM.isVehicleNear(loc.x, loc.y, z) then
        return "existing vehicles too close"
    end
    return nil
end

-- Picks a usable location for `def`, trying them in random order. Returns the
-- location, or nil plus the reason the last candidate was rejected.
function EM.pickSpawnableLocation(def)
    if not def.locations or #def.locations == 0 then return nil, "no locations defined" end

    local candidates = {}
    for i = 1, #def.locations do candidates[i] = def.locations[i] end

    local lastReason = "no locations defined"
    while #candidates > 0 do
        local idx = DE.rand(1, #candidates)
        local loc = candidates[idx]
        table.remove(candidates, idx)

        local blocked = EM.locationBlockedBy(loc)
        if not blocked then return loc, nil end
        lastReason = blocked
    end
    return nil, lastReason
end

-- Allocates the uid an event will be filed under. Split out from addActive so
-- a spawn can tag the assets it creates (zombies) before the event exists.
function EM.reserveUid(typeId)
    EM._nextId = EM._nextId + 1
    EM._dirty = true
    return typeId .. "_" .. tostring(EM._nextId)
end

function EM.addActive(typeId, x, y, z, objects, uid)
    uid = uid or EM.reserveUid(typeId)
    objects = objects or {}
    EM.active[uid] = {
        typeId = typeId,
        x = x, y = y, z = z,
        spawnedAt = DE.gameHours(),
        objects = objects
    }
    EM._dirty = true
    DE.log("event '%s' [%s] now active at (%d, %d, %d) with %d objects", typeId, uid, x, y, z, #objects)
    return uid
end

function EM.removeActive(uid)
    EM.active[uid] = nil
    EM._dirty = true
    DE.log("event [%s] removed from active", uid)
end

function EM.getActiveEvents()
    local out = {}
    for uid, data in pairs(EM.active) do
        out[#out + 1] = {
            id = data.typeId, uid = uid,
            x = data.x, y = data.y, z = data.z,
            spawnedAt = data.spawnedAt,
            objectCount = data.objects and #data.objects or 0,
        }
    end
    return out
end

-- Tracked events sorted nearest-first from (x, y). Used by the admin tools.
-- Spawns parked against a square, waiting for their chunk to stream in. These
-- have no uid and nothing exists in the world yet, but they already hold their
-- location and have started their event's cooldown, so admin listings should
-- show them alongside real events.
function EM.getParkedSpawns(x, y)
    local out = {}
    if not DE.SquareQueue then return out end

    DE.SquareQueue.forEach(function(entry)
        if entry.command == "spawn" and entry.args then
            out[#out + 1] = {
                id = entry.args.defId,
                x = entry.x, y = entry.y, z = entry.z,
                distance = x and math.sqrt((entry.x - x) ^ 2 + (entry.y - y) ^ 2) or nil,
            }
        end
    end)

    if x then
        table.sort(out, function(a, b) return a.distance < b.distance end)
    end
    return out
end

function EM.getActiveEventsNear(x, y)
    local out = EM.getActiveEvents()
    for _, ev in ipairs(out) do
        ev.distance = math.sqrt((ev.x - x) ^ 2 + (ev.y - y) ^ 2)
    end
    table.sort(out, function(a, b) return a.distance < b.distance end)
    return out
end

-- Events are permanent: nothing expires on its own. Clearing is an explicit
-- admin action that must happen on-site (the chunks have to be loaded for Lua
-- to remove anything), and it is what frees the location for reuse.
function EM.clearEvent(uid)
    local data = EM.active[uid]
    if not data then return false, "no such event" end

    local def = EM.get(data.typeId)
    if def and def.cleanup then
        DE.guard(uid .. " cleanup", function()
            def.cleanup(data.x, data.y, data.z, data.objects)
        end)
    end

    EM.removeActive(uid)
    return true, nil
end

-- Runs def.spawn inside an EventContext, merges anything the spawn function
-- returned on top of what the context tracked, and registers the result as an
-- active event. Shared by the scheduler and the .Spawn debug command.
function EM.runSpawn(def, x, y, z, rot)
    -- Reserve the uid up front: the context stamps it onto spawned zombies so
    -- cleanup can find them again later.
    local uid = EM.reserveUid(def.id)

    DE.EventHelpers.playSound(x, y, z, def.sound)

    local ctx = DE.EventContext.new(x, y, z, rot or def.rot or 0, uid)
    local objects = ctx:objects()

    local ok, result = pcall(def.spawn, x, y, z, ctx)
    if not ok then
        DE.err("%s spawn failed: %s", def.id, tostring(result))
    elseif type(result) == "table" and result ~= objects then
        DE.EventHelpers.merge(objects, result)
    end

    DE.dbg("%s spawn produced %d tracked objects", def.id, #objects)
    return EM.addActive(def.id, x, y, z, objects, uid)
end

-- Spawns now if the site is streamed in, otherwise parks the spawn against the
-- square so it materialises the moment a player brings that chunk in.
function EM.spawnOrQueue(def, x, y, z, rot)
    if EM.isSiteLoaded(x, y, z) then
        DE.log("%s appeared at (%d, %d, %d)", def.name or def.id, x, y, z)
        EM.runSpawn(def, x, y, z, rot)
        return "spawned"
    end

    DE.SquareQueue.add(x, y, z, "spawn", { defId = def.id, x = x, y = y, z = z, rot = rot })
    DE.log("%s parked at (%d, %d, %d) — will appear when that area loads",
        def.name or def.id, x, y, z)
    EM._dirty = true
    return "queued"
end

-- Runs a parked spawn once its chunk has streamed in.
function EM.runQueuedSpawn(args)
    local def = EM.get(args.defId)
    if not def then
        DE.warn("parked spawn for unknown event '%s' dropped", tostring(args.defId))
        return
    end

    -- The world moved on while this was parked, and the vehicle check at queue
    -- time couldn't see anything. Now the chunk is real, check it properly.
    if EM.isVehicleNear(args.x, args.y, args.z) then
        DE.warn("parked spawn for '%s' at (%d, %d) abandoned: vehicles now occupy the spot",
            def.id, args.x, args.y)
        return
    end
    if EM.isLocationOccupied(args.x, args.y, args.z) then
        DE.warn("parked spawn for '%s' at (%d, %d) abandoned: another event took the spot",
            def.id, args.x, args.y)
        return
    end

    DE.log("%s materialised at (%d, %d, %d)", def.name or def.id, args.x, args.y, args.z)
    EM.runSpawn(def, args.x, args.y, args.z, args.rot)
end

-- ============================================================================
-- Persistence
-- ============================================================================

local function shallowCopy(src)
    local out = {}
    for k, v in pairs(src) do out[k] = v end
    return out
end

-- Active events are copied field by field rather than stored by reference, so
-- runtime-only state (e.g. _lastRadioBroadcast) stays out of the save.
local function persistableEvent(ev)
    return {
        typeId = ev.typeId,
        x = ev.x, y = ev.y, z = ev.z,
        spawnedAt = ev.spawnedAt,
        objects = ev.objects or {},
    }
end

function EM.saveState()
    if not EM._dirty then return end
    EM._dirty = false

    local active = {}
    for uid, ev in pairs(EM.active) do
        active[uid] = persistableEvent(ev)
    end

    getGameTime():getModData().DynamicEvents = {
        active        = active,
        cooldowns     = shallowCopy(EM.cooldowns),
        squareQueue   = DE.SquareQueue.serialize(),
        _nextId       = EM._nextId,
    }
    DE.dbg("saved state: %d tracked events, %d parked, %d event types",
        EM.getActiveCount(), DE.SquareQueue.count(), #EM.order)
end

function EM.loadState()
    local modData = getGameTime():getModData()
    local data = modData and modData.DynamicEvents
    if not data then return false end

    for uid, ev in pairs(data.active or {}) do
        EM.active[uid] = persistableEvent(ev)
    end
    for id, untilHour in pairs(data.cooldowns or {}) do
        EM.cooldowns[id] = untilHour
    end
    -- Migration: saves from when there was a deferred-cleanup queue still hold
    -- real, un-cleaned wreckage. Fold those back into the tracked list so an
    -- admin can still find and clear them instead of them becoming orphans.
    local migrated = 0
    for uid, entry in pairs(data.pendingCleanup or {}) do
        if not EM.active[uid] then
            EM.active[uid] = {
                typeId    = entry.typeId,
                x = entry.x, y = entry.y, z = entry.z,
                spawnedAt = entry.queuedAt or DE.gameHours(),
                objects   = entry.objects or {},
            }
            migrated = migrated + 1
        end
    end
    if migrated > 0 then
        EM._dirty = true
        DE.log("migrated %d event(s) from the old deferred-cleanup queue into tracked events", migrated)
    end

    DE.SquareQueue.deserialize(data.squareQueue)

    EM._nextId = data._nextId or EM._nextId

    EM._wasRestored = true
    DE.log("loaded state: %d tracked events, %d parked, %d event types restored",
        EM.getActiveCount(), DE.SquareQueue.count(), EM.count())
    return true
end
