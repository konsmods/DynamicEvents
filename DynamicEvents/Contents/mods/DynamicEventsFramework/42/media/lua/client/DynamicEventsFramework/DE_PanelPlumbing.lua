-- Client-side glue for the admin panel: the keybind that opens it, the admin
-- gate, and the state round-trip that feeds it.
--
-- No `if not isClient()` guard: this must run in single-player too. A dedicated
-- server never loads client/ Lua, so there's nothing to guard against there.

DE = DE or {}

-- ----------------------------------------------------------------------------
-- State round-trip
-- ----------------------------------------------------------------------------

-- Push a snapshot into the open panel (if any). Called directly in SP and from
-- the StateSnapshot server command in MP.
function DE._onSnapshot(snap)
    if DE.Panel and DE.Panel:getIsVisible() then
        DE.Panel:setData(snap)
    end
end

-- Ask for fresh state. In SP the server code is in-process, so read it directly;
-- in MP round-trip through the (admin-gated) RequestState command.
function DE.requestState()
    local p = getSpecificPlayer(0)
    if DE.getStateSnapshot then
        DE._onSnapshot(DE.getStateSnapshot(p))
    elseif p then
        sendClientCommand(p, "DynamicEventsFramework", "RequestState", {})
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "DynamicEventsFramework" then return end
    if command == "StateSnapshot" then
        DE._onSnapshot(args)
    end
end)

-- ----------------------------------------------------------------------------
-- Opening the panel
-- ----------------------------------------------------------------------------

-- Client-side gate; the server re-checks every command, so this is only UX.
-- Single-player (isClient() == false) is always allowed.
local function isAllowed(p)
    if not isClient() then return true end
    if not p then return false end
    local level = ""
    pcall(function() level = p:getAccessLevel() end)
    return string.lower(tostring(level)) == "admin"
end

function DE.OpenPanel()
    local p = getSpecificPlayer(0)
    if not isAllowed(p) then
        if p then p:Say("[DE] Admin only") end
        return
    end

    if DE.Panel then
        DE.Panel:close()
        return
    end

    local panel = DEAdminPanel:new()
    panel:initialise()
    panel:addToUIManager()
    DE.Panel = panel
    DE.requestState()
end

-- Opened from the MP admin panel (see DE_AdminMenuHook.lua), or from the debug
-- console with DE.OpenPanel() — which is how you reach it in single-player,
-- where the admin panel doesn't exist.
print("[DynamicEventsFramework][CLI] admin panel loaded (open with DE.OpenPanel())")
