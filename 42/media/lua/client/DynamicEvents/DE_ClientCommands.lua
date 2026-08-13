-- ============================================================================
-- Client-side command shim for DynamicEvents.
--
-- The server-only DE_DebugCommands.lua cannot be reached from a client's
-- in-game debug console. These functions forward to the server via
-- sendClientCommand, where Events.OnClientCommand executes the real logic.
-- The server gates all commands to admin access level only.
-- Works in single-player too (SP runs the server code path).
-- ============================================================================

if not isClient() then return end

DE = DE or {}

local function send(command, args)
    local player = getSpecificPlayer(0)
    if not player then return end
    sendClientCommand(player, "DynamicEvents", command, args or {})
end

function DE.Spawn(eventId, x, y, z, rot)
    send("Spawn", { id = eventId, x = x, y = y, z = z, rot = rot })
end

function DE.SpawnHere(eventId)
    send("SpawnHere", { id = eventId })
end

function DE.SpawnRandom()
    send("SpawnRandom", {})
end

function DE.Clean()
    send("Clean", {})
end

function DE.CleanupNow()
    send("CleanupNow", {})
end

function DE.ListEvents()
    send("ListEvents", {})
end

function DE.WhereAmI()
    send("WhereAmI", {})
end

function DE.VehicleInfo()
    send("VehicleInfo", {})
end

function DE.CheckSpot(radius)
    send("CheckSpot", { radius = radius })
end

function DE.Outfits(keyword)
    send("Outfits", { keyword = keyword })
end

function DE.ToggleCleanup()
    send("ToggleCleanup", {})
end

function DE.Info()
    send("Info", {})
end

print("[DynamicEvents][CLI] client command shim loaded")