DE = DE or {}

local CHECK_INTERVAL_TICKS = 100
local ticksSinceLastCheck = 0
local gameStartHour = nil

local function getSandboxOption(key, default)
    if not SandboxVars.DynamicEvents then return default end
    local val = SandboxVars.DynamicEvents[key]
    return val ~= nil and val or default
end

local function refreshConfig()
    DE.Config.enabled              = getSandboxOption("Enabled", true)
    DE.Config.maxActive            = getSandboxOption("MaxActiveEvents", 3)
    DE.Config.minTimeBetweenEvents = getSandboxOption("MinHoursBetweenEvents", 1.0)
    DE.Config.eventChance          = getSandboxOption("EventChance", 50)
    DE.Config.gracePeriodHours     = getSandboxOption("GracePeriodHours", 1.0)
    DE.Config.eventCleanup         = getSandboxOption("EventCleanup", true)
    DE.Config.minDistanceBetweenEvents = getSandboxOption("MinDistanceBetweenEvents", 20)
    DE.Config.debug                = getSandboxOption("Debug", false)
end

local function isEventEnabled(id)
    if not SandboxVars.DynamicEvents then return true end
    local toggles = SandboxVars.DynamicEvents.EventToggles
    if not toggles then return true end
    return toggles[id] ~= false
end

local function doSpawn(def, x, y, z, rot)
    DE.log("%s appeared at (%d, %d, %d)", def.name or def.id, x, y, z)
    DE.EventHelpers.playSound(x, y, z, def.sound)

    local ctx = DE.EventContext.new(x, y, z, rot or def.rot or 0)
    local ok, result = pcall(def.spawn, x, y, z, ctx)
    if not ok then
        DE.err("%s spawn failed: %s", def.id, tostring(result))
        return ctx:objects()
    end
    local objects = ctx:objects()
    if result and type(result) == "table" and result ~= objects then
        DE.EventHelpers.merge(objects, result)
    end
    DE.dbg("%s spawn returned %d tracked objects", def.id, #objects)
    return objects
end

DE._pendingSpawns = DE._pendingSpawns or {}

local function processPendingSpawns()
    local now = DE.gameHours()
    local toRemove = {}
    for i, pending in ipairs(DE._pendingSpawns) do
        if now >= pending.atTime then
            local objects = doSpawn(pending.def, pending.x, pending.y, pending.z, pending.rot)
            DE.EventManager.addActive(pending.def.id, pending.x, pending.y, pending.z, objects)
            toRemove[i] = true
        end
    end
    local filtered = {}
    for i, p in ipairs(DE._pendingSpawns) do
        if not toRemove[i] then
            filtered[#filtered + 1] = p
        end
    end
    DE._pendingSpawns = filtered
end

local function scheduleSpawn(def, x, y, z, delay, rot)
    if not delay or delay <= 0 then
        local objects = doSpawn(def, x, y, z, rot)
        DE.EventManager.addActive(def.id, x, y, z, objects)
        return
    end

    local atTime = DE.gameHours() + (delay / 3600)
    DE._pendingSpawns[#DE._pendingSpawns + 1] = {
        def = def,
        x = x, y = y, z = z,
        rot = rot,
        atTime = atTime,
    }
    DE.dbg("scheduled spawn for '%s' in %d seconds (at hour %.2f)", def.id, delay, atTime)
end

local function tryFireEvent()
    refreshConfig()

    if not DE.Config.enabled then return end

    if not DE.EventManager._wasRestored then
        if gameStartHour and DE.gameHours() - gameStartHour < (DE.Config.gracePeriodHours or 1) then
            return
        end
    end

    if DE.EventManager.getActiveCount() >= DE.Config.maxActive then
        DE.dbg("max active events reached (%d)", DE.Config.maxActive)
        return
    end

    if not DE.chance(DE.Config.eventChance) then
        DE.dbg("event chance roll failed")
        return
    end

    local eligible = DE.EventManager.getEligible()
    if #eligible == 0 then
        DE.dbg("no eligible events (all on cooldown or day requirements not met)")
        return
    end

    local filtered = {}
    for _, def in ipairs(eligible) do
        if isEventEnabled(def.id) then
            filtered[#filtered + 1] = def
        end
    end

    if #filtered == 0 then
        DE.dbg("all eligible events are disabled in sandbox")
        return
    end

    local skipUsed = not DE.Config.eventCleanup

    local attempts = {}
    for _, def in ipairs(filtered) do
        attempts[#attempts + 1] = def
    end

    while #attempts > 0 do
        local idx = DE.rand(1, #attempts)
        local def = attempts[idx]
        table.remove(attempts, idx)

        local location = DE.EventManager.pickRandomLocation(def, skipUsed)
        if location then
            local lz = location.z or 0
            if DE.EventManager.isLocationOccupied(location.x, location.y, lz) then
                DE.dbg("'%s' location '%s' too close to an active event, skipping", def.id, location.name)
            else
                DE.log("firing event '%s' at (%d, %d, %d)", def.id, location.x, location.y, lz)
                DE.EventManager.markLocationUsed(def.id, location)

                local delay = 0
                if def.warning and def.warning.delay then
                    delay = def.warning.delay
                end

                scheduleSpawn(def, location.x, location.y, lz, delay,
                    location.rot or def.rot or 0)
                DE.EventManager.startCooldown(def.id, def.cooldownHours)
                return
            end
        elseif skipUsed then
            DE.dbg("'%s' has no unused locations, skipping", def.id)
        else
            DE.warn("'%s' has no valid locations", def.id)
        end
    end

    DE.dbg("no viable event/location combination found")
end

local function expireActiveEvents()
    if not DE.Config.eventCleanup then return end

    local now = DE.gameHours()
    local toExpire = {}
    for id, data in pairs(DE.EventManager.active) do
        local def = DE.EventManager.get(data.typeId)
        local lifetime = (def and def.lifetimeHours) or 48
        if now - data.spawnedAt >= lifetime then
            toExpire[id] = data
        end
    end
    for id, data in pairs(toExpire) do
        local def = DE.EventManager.get(data.typeId)
        DE.log("event '%s' [%s] expired (lifetime %.0fh)", data.typeId, id, def and def.lifetimeHours or 48)
        if def and def.cleanup then
            DE.guard(id .. " cleanup", function()
                def.cleanup(data.x, data.y, data.z, data.objects)
            end)
        end
        DE.EventManager.removeActive(id)
    end
end

local function onTick()
    processPendingSpawns()
    expireActiveEvents()
    DE.EventManager.saveState()
    ticksSinceLastCheck = ticksSinceLastCheck + 1
    if ticksSinceLastCheck >= CHECK_INTERVAL_TICKS then
        ticksSinceLastCheck = 0
        tryFireEvent()
    end
    DE.broadcastRadios()
end

Events.OnGameStart.Add(function()
    gameStartHour = DE.gameHours()
    local restored = DE.EventManager.loadState()
    if restored then
        DE.log("scheduler started (restored from save, %d active events)",
            DE.EventManager.getActiveCount())
    else
        DE.log("scheduler started (fresh, grace period: %.1fh)", DE.Config.gracePeriodHours or 1)
    end
    Events.OnTick.Add(onTick)
end)
