-- Adds a "Dynamic Events" entry to the vanilla multiplayer admin panel (the
-- gear button on the left, admins only). Single-player has no such panel, so
-- the keybind in DE_PanelPlumbing.lua is what opens the window there.
--
-- Done by wrapping ISAdminPanelUI's create/onOptionMouseDown rather than editing
-- them, so the vanilla layout stays intact and other mods can hook too.

if not ISAdminPanelUI then return end

local SPACING = 10  -- matches the panel's own UI_BORDER_SPACING

-- After the panel builds and lays itself out, drop our button in above Cancel
-- (Cancel is always last, centred at the bottom) and grow the panel to fit.
local originalCreate = ISAdminPanelUI.create
function ISAdminPanelUI:create()
    originalCreate(self)

    if not self.cancel then return end
    local x, y = self.cancel:getX(), self.cancel:getY()
    local w, h = self.cancel:getWidth(), self.cancel:getHeight()

    local btn = ISButton:new(x, y, w, h, "Dynamic Events", self, ISAdminPanelUI.onOptionMouseDown)
    btn.internal = "DYNAMICEVENTS"
    btn:initialise()
    btn:instantiate()
    btn.borderColor = self.buttonBorderColor
    self:addChild(btn)
    self.deEventsBtn = btn

    -- Push Cancel down a row and stretch the window by the same amount.
    self.cancel:setY(y + h + SPACING)
    self:setHeight(self.cancel:getBottom() + SPACING + 1)
end

-- Handle our button; hand everything else to the original handler.
local originalMouseDown = ISAdminPanelUI.onOptionMouseDown
function ISAdminPanelUI:onOptionMouseDown(button, x, y)
    if button and button.internal == "DYNAMICEVENTS" then
        DE.OpenPanel()
        return
    end
    return originalMouseDown(self, button, x, y)
end
