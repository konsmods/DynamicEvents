DE = DE or {}

DE.EventManager = {
    types = {},
    order = {},
    active = {},
    cooldowns = {},
    usedLocations = {},
    _nextId = 0,
    _dirty = false,
    _wasRestored = false,
}

local EM = DE.EventManager

function EM.register(def)
    assert(type(def) == "table", "event definition must be a table")
    assert(type(def.id) == "string" and def.id ~= "", "event must have an id")
    assert(type(def.name) == "string", "event must have a name")
    assert(type(def.locations) == "table" and #def.locations > 0, "event must have locations")
    assert(type(def.spawn) == "function", "event must have a spawn function")

    if EM.types[def.id] then
        DE.warn("overwriting previously registered event '%s'", def.id)
    end

    def.cooldownHours = def.cooldownHours or 24
    def.minDaysSurvived = def.minDaysSurvived or 0
    def.weight = def.weight or 10
    def.dependencies = def.dependencies or {}

    EM.types[def.id] = def
    if not EM.order[def.id] then
        EM.order[#EM.order + 1] = def.id
    end

    EM.usedLocations[def.id] = EM.usedLocations[def.id] or {}

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

function EM.getEligible()
    local now = DE.gameHours()
    local daysSurvived = DE.gameDays()
    local eligible = {}

    for _, def in ipairs(EM.all()) do
        if not EM.isOnCooldown(def.id)
            and daysSurvived >= (def.minDaysSurvived or 0)
            and EM.dependenciesMet(def) then
            eligible[#eligible + 1] = def
        end
    end

    return eligible
end

function EM.getActiveCount()
    local count = 0
    for _ in pairs(EM.active) do count = count + 1 end
    return count
end

function EM.addActive(typeId, x, y, z, objects)
    EM._nextId = EM._nextId + 1
    local uid = typeId .. "_" .. tostring(EM._nextId)
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
        out[#out + 1] = { id = data.typeId, uid = uid, x = data.x, y = data.y, z = data.z }
    end
    return out
end

local function makeLocKey(loc)
    return string.format("%d,%d,%d", loc.x, loc.y, loc.z or 0)
end

function EM.markLocationUsed(id, loc)
    EM.usedLocations[id] = EM.usedLocations[id] or {}
    EM.usedLocations[id][makeLocKey(loc)] = true
    EM._dirty = true
    DE.dbg("marked location '%s' used for event '%s'", loc.name or makeLocKey(loc), id)
end

function EM.pickRandomLocation(def, skipUsed)
    if not def.locations or #def.locations == 0 then return nil end

    if skipUsed then
        local unused = {}
        local used = EM.usedLocations[def.id] or {}
        for _, loc in ipairs(def.locations) do
            if not used[makeLocKey(loc)] then
                unused[#unused + 1] = loc
            end
        end
        if #unused == 0 then return nil end
        return unused[DE.rand(1, #unused)]
    end

    return def.locations[DE.rand(1, #def.locations)]
end

-- ============================================================================
-- Persistence
-- ============================================================================

function EM.saveState()
    if not EM._dirty then return end
    EM._dirty = false

    local data = {}
    data.active = {}
    for uid, ev in pairs(EM.active) do
        data.active[uid] = {
            typeId = ev.typeId,
            x = ev.x, y = ev.y, z = ev.z,
            spawnedAt = ev.spawnedAt,
            objects = ev.objects or {},
        }
    end
    data.cooldowns = {}
    for id, untilHour in pairs(EM.cooldowns) do
        data.cooldowns[id] = untilHour
    end
    data.usedLocations = {}
    for id, locs in pairs(EM.usedLocations) do
        data.usedLocations[id] = {}
        for locKey in pairs(locs) do
            data.usedLocations[id][locKey] = true
        end
    end
    data._nextId = EM._nextId

    getGameTime():getModData().DynamicEvents = data
    DE.dbg("saved state: %d active, %d event types", EM.getActiveCount(), #EM.order)
end

function EM.loadState()
    local modData = getGameTime():getModData()
    local data = modData and modData.DynamicEvents
    if not data then return false end

    if data.active then
        for uid, ev in pairs(data.active) do
            EM.active[uid] = {
                typeId = ev.typeId,
                x = ev.x, y = ev.y, z = ev.z,
                spawnedAt = ev.spawnedAt,
                objects = ev.objects or {},
            }
        end
    end
    if data.cooldowns then
        for id, untilHour in pairs(data.cooldowns) do
            EM.cooldowns[id] = untilHour
        end
    end
    if data.usedLocations then
        for id, locs in pairs(data.usedLocations) do
            EM.usedLocations[id] = EM.usedLocations[id] or {}
            for locKey in pairs(locs) do
                EM.usedLocations[id][locKey] = true
            end
        end
    end
    if data._nextId then
        EM._nextId = data._nextId
    end

    EM._wasRestored = true
    DE.log("loaded state: %d active events, %d event types restored",
        EM.getActiveCount(), EM.count())
    return true
end
