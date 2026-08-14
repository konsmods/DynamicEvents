-- Server-authoritative; clients load this file too, so bail out there.
if isClient() then return end

DE = DE or {}

-- Cheap upkeep (pending spawns, radio, state save) every 10 ticks; the event
-- fire check rides the same pass.
local UPKEEP_INTERVAL_TICKS = 10

-- Exposed so DE_DebugCommands can report what the scheduler is waiting for.
DE.Scheduler = {
    gameStartHour = nil,  -- in-game hour the world started / was loaded
    nextFireHour  = nil,  -- in-game hour the next event is due
}

local tickCount = 0
local initialized = false

local function refreshConfig()
    local vars = SandboxVars.DynamicEventsFramework
    for _, opt in ipairs(DE.CONFIG_SPEC) do
        local val = vars and vars[opt.sandbox]
        -- Explicit nil check: `false` is a valid value for the boolean options.
        if val == nil then val = opt.default end
        DE.Config[opt.key] = val
    end
end

DE._pendingSpawns = DE._pendingSpawns or {}

-- Warning delays are cosmetic; spawnOrQueue parks any site that isn't loaded.
local function processPendingSpawns()
    local now = DE.gameHours()
    for i = #DE._pendingSpawns, 1, -1 do
        local pending = DE._pendingSpawns[i]
        if now >= pending.atTime then
            table.remove(DE._pendingSpawns, i)
            DE.EventManager.spawnOrQueue(pending.def, pending.x, pending.y, pending.z, pending.rot)
        end
    end
end

local function scheduleSpawn(def, x, y, z, delay, rot)
    if not delay or delay <= 0 then
        DE.EventManager.spawnOrQueue(def, x, y, z, rot)
        return
    end

    -- `delay` is in in-game seconds; convert to the hour units used by
    -- DE.gameHours() so the pending check below compares like with like.
    local atTime = DE.gameHours() + (delay / 3600)
    DE._pendingSpawns[#DE._pendingSpawns + 1] = {
        def = def,
        x = x, y = y, z = z,
        rot = rot,
        atTime = atTime,
    }
    DE.dbg("scheduled spawn for '%s' in %d seconds (at hour %.2f)", def.id, delay, atTime)
end

-- Fire one event per interval: weighted pick, then a usable location. Re-arm
-- afterwards either way, so a blocked round just retries next interval.
local function fireDueEvent()
    if not DE.Config.enabled then return end
    if not DE.Scheduler.nextFireHour or DE.gameHours() < DE.Scheduler.nextFireHour then return end

    local now = DE.gameHours()
    local interval = DE.Config.intervalHours or 1
    if interval <= 0 then interval = 1 end   -- a zero interval would fire constantly

    local candidates = DE.EventManager.getEligible()
    if #candidates == 0 then
        DE.log("event roll due, but no eligible events (cooldown, day requirement, dependency or sandbox toggle)")
    else
        while #candidates > 0 do
            local def, idx = DE.EventManager.pickWeighted(candidates)
            if not def then break end
            table.remove(candidates, idx)

            local location, reason = DE.EventManager.pickSpawnableLocation(def)
            if location then
                local lz = location.z or 0
                DE.log("firing event '%s' at (%d, %d, %d)", def.id, location.x, location.y, lz)

                local delay = def.warning and def.warning.delay or 0
                scheduleSpawn(def, location.x, location.y, lz, delay,
                    location.rot or def.rot or 0)

                DE.EventManager.startCooldown(def.id, def.cooldownHours)
                break
            end
            DE.dbg("'%s' has no usable location right now (%s)", def.id, reason)
        end
    end

    DE.Scheduler.nextFireHour = now + interval
end

-- Lazy init on the first tick with game time. Not Events.OnGameStart: on a
-- dedicated server that fires before mod files load, so this handler would
-- never run.
local function tryInit()
    if initialized then return end
    if not getGameTime() then return end

    initialized = true
    refreshConfig()

    local startHour = DE.gameHours()
    local restored = DE.EventManager.loadState()
    DE.Scheduler.gameStartHour = startHour

    local interval = DE.Config.intervalHours or 1
    if restored then
        -- Wait one full interval from now so a restart never fires an event
        -- the moment the world comes back up.
        DE.Scheduler.nextFireHour = DE.gameHours() + interval
    else
        -- Fresh world: wait out the grace period plus one interval before the
        -- first event, then keep that cadence.
        DE.Scheduler.nextFireHour = startHour + (DE.Config.gracePeriodHours or 0) + interval
    end

    if restored then
        DE.log("scheduler started (restored %d active events)", DE.EventManager.getActiveCount())
    else
        DE.log("scheduler started (fresh)")
    end
end

local function onTick()
    tickCount = tickCount + 1
    tryInit()

    -- Nothing expires on its own; events persist until cleared. SquareQueue
    -- drain runs work whose chunk just streamed in, off the chunk-load hook.
    if tickCount % UPKEEP_INTERVAL_TICKS == 0 then
        -- Re-read sandbox options so admin changes apply mid-game.
        refreshConfig()

        DE.SquareQueue.drain()
        processPendingSpawns()
        fireDueEvent()
        DE.broadcastRadios()
        DE.EventManager.saveState()
    end
end

-- Register immediately, not inside OnGameStart (see tryInit).
Events.OnTick.Add(onTick)
