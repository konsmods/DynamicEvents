if isClient() then return end

DE = DE or {}

-- ============================================================================
-- Deferred work parked against a grid square: spawning events whose location
-- hasn't streamed in yet, and clearing events whose chunks aren't loaded.
--
-- There is no Lua API to force a chunk in (ServerMap isn't exposed), so work is
-- parked against a square and run when that square streams in, via the vanilla
-- Events.LoadGridsquare hook (fires per square, client and server, so it works
-- on a dedicated server). Same trick Expanded Helicopter Events uses.
-- ============================================================================

local SQ = {
    handlers = {},   -- command name -> function(entry)
}

-- Nested x/y/z tables rather than an "x,y,z" string key: the LoadGridsquare
-- lookup fires per square and must not allocate.
local byX = {}
local count = 0

-- Squares that loaded but whose work hasn't run yet; drained on the upkeep pass
-- rather than inside the chunk-load callback.
local ready = {}

function SQ.count() return count end

-- A square holds a LIST of commands: two events could park on the same tile.
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
-- Persistence — parked work must survive a restart or it is lost.
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
-- Commands. This file loads after DE_EventManager, so its helpers exist.
-- ============================================================================

SQ.handlers.spawn = function(entry)
    DE.EventManager.runQueuedSpawn(entry.args)
end

SQ.handlers.cleanup = function(entry)
    DE.EventManager.runQueuedCleanup(entry.args)
end

DE.SquareQueue = SQ
