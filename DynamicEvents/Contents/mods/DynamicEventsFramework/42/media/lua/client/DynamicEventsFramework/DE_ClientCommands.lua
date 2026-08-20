-- ============================================================================
-- Client shim: forwards the console commands to the server via sendClientCommand,
-- where OnClientCommand runs the real (admin-gated) logic. Works in SP too.
-- ============================================================================

if not isClient() then return end

DE = DE or {}

local function send(command, args)
    local player = getSpecificPlayer(0)
    if not player then return end
    sendClientCommand(player, "DynamicEventsFramework", command, args or {})
end

-- Command name → the argument names its wrapper accepts, in order. Must stay
-- in sync with the HANDLERS table in DE_DebugCommands.lua.
local COMMANDS = {
    { name = "Spawn",         args = { "id", "x", "y", "z", "rot" } },
    { name = "SpawnHere",     args = { "id" } },
    { name = "SpawnRandom" },
    { name = "SpawnForce",    args = { "id", "x", "y", "z", "rot" } },
    { name = "Clean" },
    { name = "ClearEvent",    args = { "uid" } },
    { name = "ClearNearby",   args = { "radius" } },
    { name = "ClearCooldowns" },
    { name = "Purge",         args = { "radius" } },
    { name = "GoTo",          args = { "uid" } },
    { name = "Pending" },
    { name = "ListEvents" },
    { name = "WhereAmI" },
    { name = "VehicleInfo" },
    { name = "TagHere" },
    { name = "CheckSpot",     args = { "radius" } },
    { name = "Outfits",       args = { "keyword" } },
    { name = "Info" },
    { name = "SchedulerInfo" },
}

for _, cmd in ipairs(COMMANDS) do
    local command, argNames = cmd.name, cmd.args
    DE[command] = function(...)
        local args = {}
        for i = 1, (argNames and #argNames or 0) do
            args[argNames[i]] = select(i, ...)
        end
        send(command, args)
    end
end

-- The server can't move a player directly in MP, so DE.GoTo asks us to do it.
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "DynamicEventsFramework" or command ~= "Teleport" then return end

    if args and args.x and args.y then
        -- Use the authoritative server command; a client-side move doesn't stick.
        SendCommandToServer(string.format("/teleportto %d,%d,%d",
            args.x, args.y, args.z or 0))
    end
end)

print("[DynamicEventsFramework][CLI] client command shim loaded")
