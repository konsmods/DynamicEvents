-- Clients load media/lua/server/ too, so bail out there: spawning and state
-- are server-authoritative, and running this loop on a client would both
-- duplicate work and touch server-only modules it never loaded.
if isClient() then return end

DE = DE or {}

-- Upkeep (pending spawns, radio, state save) is cheap but pointless to run
-- every tick. The event fire check is folded into the same pass because a
-- sub-second difference is irrelevant for an hours-scale interval.
local UPKEEP_INTERVAL_TICKS = 10

-- Exposed so DE_DebugCommands can report what the scheduler is waiting for.
DE.Scheduler = {
    gameStartHour = nil,  -- in-game hour the world started / was loaded
    nextFireHour  = nil,  -- in-game hour the next event is due
}

local tickCount = 0
local initialized = false

local function refreshConfig()
    local vars = SandboxVars.DynamicEvents
    for _, opt in ipairs(DE.CONFIG_SPEC) do
        local val = vars and vars[opt.sandbox]
        -- Explicit nil check: `false` is a valid value for the boolean options.
        if val == nil then val = opt.default end
        DE.Config[opt.key] = val
    end
end

DE._pendingSpawns = DE._pendingSpawns or {}

-- Warning delays are short and purely cosmetic (radio chatter before the
-- event lands); an unloaded site no longer needs special handling here,
-- because spawnOrQueue parks it.
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

-- Fires one event if the interval has elapsed: pick a weighted-random event
-- type, then a random location it can actually use, and queue the spawn. The
-- timer is re-armed afterwards either way, so a round where nothing was
-- eligible (or every location was blocked) simply retries next interval.
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

-- Initialise once the world is ready. We deliberately do NOT use
-- Events.OnGameStart: on a dedicated server it fires before mod files load, so
-- a handler registered in this file would never run. The tick loop is always
-- registered, so we lazily initialise on the first tick where game time exists
-- (which also covers single-player and a server reloading an old save).
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

    -- Nothing expires on its own: events persist until an admin clears them.
    -- SquareQueue.drain runs work whose chunk just streamed in, off the
    -- LoadGridsquare callback itself.
    if tickCount % UPKEEP_INTERVAL_TICKS == 0 then
        -- Re-read sandbox options each pass: an admin can apply new settings
        -- mid-game, and PZ updates the live SandboxVars table then.
        refreshConfig()

        DE.SquareQueue.drain()
        processPendingSpawns()
        fireDueEvent()
        DE.broadcastRadios()
        DE.EventManager.saveState()
    end
end

-- Register the tick loop immediately, not inside OnGameStart.
-- On dedicated servers, OnGameStart can fire before mod files are loaded,
-- so deferring registration there would never run the scheduler.
Events.OnTick.Add(onTick)
