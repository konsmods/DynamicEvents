-- Server-authoritative. Builds a plain, serializable snapshot of everything the
-- admin panel shows. The client reads state only through this — in SP it calls
-- getStateSnapshot directly (server code is in-process); in MP it asks via the
-- RequestState command and we reply with a StateSnapshot server command.
if isClient() then return end

DE = DE or {}

local function schedulerState()
    local now = DE.gameHours()
    local sched = DE.Scheduler or {}
    return {
        enabled       = DE.Config.enabled,
        worldAge      = now,
        interval      = DE.Config.intervalHours or 1,
        grace         = DE.Config.gracePeriodHours or 0,
        nextFireHour  = sched.nextFireHour,
        remaining     = sched.nextFireHour and (sched.nextFireHour - now) or nil,
        pendingSpawns = DE._pendingSpawns and #DE._pendingSpawns or 0,
        parked        = DE.SquareQueue and DE.SquareQueue.count() or 0,
        restored      = DE.EventManager._wasRestored or false,
    }
end

-- `player` may be nil (server console); coords/distances are then omitted.
function DE.getStateSnapshot(player)
    local EM = DE.EventManager
    local now = DE.gameHours()

    local px, py
    if player then px, py = player:getX(), player:getY() end

    local events = px and EM.getActiveEventsNear(px, py) or EM.getActiveEvents()
    for _, ev in ipairs(events) do
        local data = EM.active[ev.uid]
        local def = EM.get(ev.id)
        ev.name      = def and def.name or ev.id
        ev.ageH      = now - (ev.spawnedAt or now)
        ev.expiresAt = data and data.expiresAt or nil
        ev.expiresInH = ev.expiresAt and (ev.expiresAt - now) or nil
    end

    local types = {}
    for _, def in ipairs(EM.all()) do
        local reason = EM.eligibilityReason(def)
        types[#types + 1] = {
            id              = def.id,
            name            = def.name or def.id,
            weight          = def.weight,
            cooldownHours   = def.cooldownHours,
            minDaysSurvived = def.minDaysSurvived,
            eligible        = reason == nil,
            reason          = reason,
            -- Copied (not the live table) so the network payload is self-
            -- contained and can't be mutated by the client.
            locations       = def.locations,
        }
    end

    return {
        scheduler = schedulerState(),
        events    = events,
        parked    = EM.getParkedSpawns(px, py),
        types     = types,
    }
end

-- Called by the RequestState handler. In MP, ships the snapshot back to the
-- requesting client; in SP the caller uses the return value directly.
function DE.sendStateSnapshot(player)
    local snap = DE.getStateSnapshot(player)
    if isServer() and player then
        sendServerCommand(player, "DynamicEventsFramework", "StateSnapshot", snap)
    end
    return snap
end
