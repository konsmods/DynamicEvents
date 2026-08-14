if isClient() then return end

DE = DE or {}

-- ============================================================================
-- Deferred work parked against a grid square. Only used for spawning events
-- whose chosen location hasn't streamed in yet; clearing is always done
-- on-site by an admin, so it never needs to be parked.
--
-- PZ streams chunks around players and there is no Lua API to force one in
-- (ServerMap isn't exposed). So instead of requiring a player to be nearby,
-- work is parked against a square and run the moment that square streams in,
-- via the vanilla Events.LoadGridsquare hook. IsoChunk.doLoadGridsquare fires
-- it for every square it loads, ungated by client/server, so it works on a
-- dedicated server.
--
-- This is the same trick Expanded Helicopter Events uses through its
-- TargetSquareOnLoad dependency, implemented here without the extra mod.
-- ============================================================================

local SQ = {
    handlers = {},   -- command name -> function(entry)
}

-- Nested x/y/z tables rather than an "x,y,z" string key: LoadGridsquare fires
-- for every square of every chunk that streams in, so the lookup on that path
-- must not allocate.
local byX = {}
local count = 0

-- Entries whose square has loaded but which haven't run yet. Work is drained
-- on the scheduler's upkeep pass rather than inside the chunk-load callback,
-- so we never spawn vehicles half way through IsoChunk loading itself.
local ready = {}

function SQ.count() return count end

-- A square holds a LIST of commands, not one: two events could park a spawn on
-- the same tile and overwriting would silently drop one.
function SQ.add(x, y, z, command, args)
    x, y, z = math.floor(x), math.floor(y), math.floor(z or 0)
    args = args or {}

    local col = byX[x]
    if not col then col = {}; byX[x] = col end
    local row = col[y]
    if not row then row = {}; col[y] = row end
    local list = row[z]
    if not list then list = {}; row[z] = list end

    local entry = { x = x, y = y, z = z, command = command, args = args }

    list[#list + 1] = entry
    count = count + 1
    DE.dbg("queued '%s' at (%d, %d, %d) — %d parked", command, x, y, z, count)
    return true
end

function SQ.forEach(fn)
    for _, col in pairs(byX) do
        for _, row in pairs(col) do
            for _, list in pairs(row) do
                for i = 1, #list do fn(list[i]) end
            end
        end
    end
end

-- ============================================================================
-- The hot path
-- ============================================================================

Events.LoadGridsquare.Add(function(square)
    if count == 0 or not square then return end

    local col = byX[square:getX()]
    if not col then return end
    local row = col[square:getY()]
    if not row then return end
    local z = square:getZ()
    local list = row[z]
    if not list then return end

    row[z] = nil
    for i = 1, #list do
        ready[#ready + 1] = list[i]
        count = count - 1
    end
end)

-- Called from the scheduler's upkeep pass.
function SQ.drain()
    if #ready == 0 then return end

    local batch = ready
    ready = {}

    for _, entry in ipairs(batch) do
        local handler = SQ.handlers[entry.command]
        if handler then
            DE.dbg("running queued '%s' at (%d, %d, %d)", entry.command, entry.x, entry.y, entry.z)
            DE.guard("queued " .. tostring(entry.command), function() handler(entry) end)
        else
            DE.warn("no handler for queued command '%s' at (%d, %d, %d)",
                tostring(entry.command), entry.x, entry.y, entry.z)
        end
    end

    DE.EventManager._dirty = true
end

-- ============================================================================
-- Persistence — parked work has to survive a restart or it is lost forever.
-- ============================================================================

function SQ.serialize()
    local out = {}
    SQ.forEach(function(entry)
        out[#out + 1] = {
            x = entry.x, y = entry.y, z = entry.z,
            command = entry.command,
            args = entry.args or {},
        }
    end)
    return out
end

function SQ.deserialize(list)
    byX, count, ready = {}, 0, {}
    for _, entry in ipairs(list or {}) do
        if entry.x and entry.y and entry.command then
            SQ.add(entry.x, entry.y, entry.z, entry.command, entry.args)
        end
    end
end

-- ============================================================================
-- Commands. Registered here because this file loads after DE_EventManager, so
-- everything it delegates to already exists by the time anything runs.
-- ============================================================================

SQ.handlers.spawn = function(entry)
    DE.EventManager.runQueuedSpawn(entry.args)
end

DE.SquareQueue = SQ
