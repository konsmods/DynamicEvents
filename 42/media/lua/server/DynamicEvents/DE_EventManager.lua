DE = DE or {}

DE.EventManager = {
    types = {},
    order = {},
    active = {},
    cooldowns = {},
    usedLocations = {},
    _nextId = 0,
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
    DE.dbg("cooldown for '%s' until hour %.1f", id, EM.cooldowns[id])
end

function EM.getEligible()
    local now = DE.gameHours()
    local daysSurvived = DE.gameDays()
    local eligible = {}

    for _, def in ipairs(EM.all()) do
        if not EM.isOnCooldown(def.id) and daysSurvived >= (def.minDaysSurvived or 0) then
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
    DE.log("event '%s' [%s] now active at (%d, %d, %d) with %d objects", typeId, uid, x, y, z, #objects)
    return uid
end

function EM.removeActive(uid)
    EM.active[uid] = nil
    DE.log("event [%s] removed from active", uid)
end

function EM.isActive(typeId)
    for _, data in pairs(EM.active) do
        if data.typeId == typeId then return true end
    end
    return false
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
    DE.dbg("marked location '%s' used for event '%s'", loc.name or makeLocKey(loc), id)
end

function EM.unmarkLocationUsed(id, loc)
    if EM.usedLocations[id] then
        EM.usedLocations[id][makeLocKey(loc)] = nil
    end
end

function EM.hasUnusedLocations(id)
    local def = EM.get(id)
    if not def or not def.locations then return false end
    local used = EM.usedLocations[id] or {}
    for _, loc in ipairs(def.locations) do
        if not used[makeLocKey(loc)] then return true end
    end
    return false
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
