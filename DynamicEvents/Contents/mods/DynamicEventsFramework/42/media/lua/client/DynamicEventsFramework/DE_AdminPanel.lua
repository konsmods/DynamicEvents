-- The admin panel window. A resizable, tabbed ISCollapsableWindow that renders
-- whatever snapshot DE_PanelPlumbing feeds it (:setData) and drives actions back
-- through the existing DE.* commands. It holds no state of its own beyond the
-- last snapshot — the server is the source of truth.
--
-- Widgets are created once in createChildren and (re)positioned in layout(),
-- which runs on create and whenever the window is resized. That one place owns
-- every coordinate, so nothing overlaps at any size.
--
-- NOTE: no `if not isClient()` guard on purpose. This must run in single-player
-- too (where isClient() is false); a dedicated server never loads client/ Lua.

require "ISUI/ISCollapsableWindow"

DEAdminPanel = ISCollapsableWindow:derive("DEAdminPanel")

local FONT       = UIFont.Small
local PAD        = 8
local BTN_H      = 24
local REFRESH_MS = 2000
local MIN_W      = 460
local MIN_H      = 340

-- ----------------------------------------------------------------------------
-- Construction
-- ----------------------------------------------------------------------------

function DEAdminPanel:new()
    local w, h = 560, 500
    local x = getCore():getScreenWidth() / 2 - w / 2
    local y = getCore():getScreenHeight() / 2 - h / 2
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    o.title = "Dynamic Events"
    o.minimumWidth = MIN_W
    o.minimumHeight = MIN_H
    o.snapshot = nil
    o.lastRefresh = 0
    o.lastTypeSel = nil
    o.lastEventSel = nil
    o.lastW, o.lastH = w, h
    return o
end

function DEAdminPanel:createChildren()
    ISCollapsableWindow.createChildren(self)
    self:setResizable(true)

    local tabs = ISTabPanel:new(1, self:titleBarHeight(), self.width - 2, 100)
    tabs:initialise()
    tabs.equalTabWidth = true
    self.tabs = tabs
    self:addChild(tabs)

    self.activeTab = self:buildActiveTab()
    self.spawnTab  = self:buildSpawnTab()
    self.schedTab  = self:buildSchedTab()

    tabs:addView("Active Events", self.activeTab)
    tabs:addView("Spawn", self.spawnTab)
    tabs:addView("Scheduler", self.schedTab)

    -- The base created its resize widgets before our tabs, so the tabs now sit
    -- on top of them and swallow the drag. Re-add them last so they're the
    -- topmost children again and can receive the resize mouse events.
    self:bringResizeWidgetsToFront()

    self:layout()
end

function DEAdminPanel:bringResizeWidgetsToFront()
    for _, w in ipairs({ self.resizeWidget, self.resizeWidget2 }) do
        if w then
            self:removeChild(w)
            self:addChild(w)
        end
    end
end

-- ----------------------------------------------------------------------------
-- Widget factories (position is set later in layout)
-- ----------------------------------------------------------------------------

local function makeList()
    local list = ISScrollingListBox:new(0, 0, 10, 10)
    list:initialise()
    list:instantiate()
    list.drawBorder = true
    list:setFont(FONT, 4)
    return list
end

-- Button reports clicks to `win` (the window) so handlers run with self == win,
-- but lives under `parent` (a tab) so it shows/hides with it.
local function makeButton(parent, win, onclick, label)
    local b = ISButton:new(0, 0, 10, BTN_H, label, win, onclick)
    b:initialise()
    b:instantiate()
    b.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    parent:addChild(b)
    return b
end

local function makeTabPanel()
    local p = ISPanel:new(0, 0, 10, 10)
    p:initialise()
    p.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    return p
end

-- A read-only details panel: clipped rich text with a border. clip=true stencils
-- the text to the box so it can never spill past its bounds (wheel scrolls it).
local function makeDetail()
    local rt = ISRichTextPanel:new(0, 0, 10, 10)
    rt:initialise()
    rt.background = true
    rt.backgroundColor = { r = 0, g = 0, b = 0, a = 0.4 }
    rt.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    rt.autosetheight = false
    rt.clip = true
    rt.marginLeft = PAD
    rt.marginTop = PAD
    rt.marginRight = PAD
    rt.defaultFont = FONT
    return rt
end

function DEAdminPanel:buildActiveTab()
    local panel = makeTabPanel()
    self.eventList = makeList()
    self.eventDetail = makeDetail()
    panel:addChild(self.eventList)
    panel:addChild(self.eventDetail)
    self.activeBtns = {
        makeButton(panel, self, self.onGoTo,      "Go To"),
        makeButton(panel, self, self.onClearSel,  "Clear"),
        makeButton(panel, self, self.onClearNear, "Clear Near"),
        makeButton(panel, self, self.onClearAll,  "Clear All"),
        makeButton(panel, self, self.onRefresh,   "Refresh"),
    }
    return panel
end

function DEAdminPanel:buildSpawnTab()
    local panel = makeTabPanel()
    self.typeList   = makeList()
    self.typeDetail = makeDetail()
    self.locList    = makeList()
    panel:addChild(self.typeList)
    panel:addChild(self.typeDetail)
    panel:addChild(self.locList)
    self.spawnBtns = {
        makeButton(panel, self, self.onSpawnHere,   "Spawn Here"),
        makeButton(panel, self, self.onSpawnLoc,    "At Location"),
        makeButton(panel, self, self.onForceHere,   "Force Here"),
        makeButton(panel, self, self.onSpawnRandom, "Random"),
    }
    return panel
end

function DEAdminPanel:buildSchedTab()
    local panel = makeTabPanel()
    local rt = makeDetail()
    self.schedText = rt
    panel:addChild(rt)
    self.schedBtn = makeButton(panel, self, self.onClearCooldowns, "Clear Cooldowns")
    return panel
end

-- ----------------------------------------------------------------------------
-- Layout — the one place that owns coordinates. Safe to call any time.
-- ----------------------------------------------------------------------------

-- Distributes `buttons` evenly across the row at `y`, spanning the content width.
local function layoutButtonRow(buttons, vw, y)
    local n = #buttons
    local bw = (vw - PAD * 2 - PAD * (n - 1)) / n
    for i, b in ipairs(buttons) do
        b:setX(PAD + (i - 1) * (bw + PAD))
        b:setY(y)
        b:setWidth(bw)
    end
end

function DEAdminPanel:layout()
    local top = self:titleBarHeight()
    self.tabs:setX(1)
    self.tabs:setY(top)
    self.tabs:setWidth(self.width - 2)
    self.tabs:setHeight(self.height - top - 1)

    local vw = self.tabs.width
    local vh = self.tabs.height - self.tabs.tabHeight
    for _, view in ipairs({ self.activeTab, self.spawnTab, self.schedTab }) do
        view:setWidth(vw)
        view:setHeight(vh)
    end

    -- Keep the button row clear of the bottom resize band (the corner/edge
    -- widgets live in the last resizeWidgetHeight() pixels of the window), plus
    -- a little extra breathing room beneath the buttons.
    local bottomReserve = math.max(PAD, self:resizeWidgetHeight() + 2) + 6
    local rowY   = vh - bottomReserve - BTN_H   -- top of the button row
    local listH  = rowY - PAD * 2                -- content fills above it

    -- Left column (lists) / right column (details) split.
    local leftW  = math.floor((vw - PAD * 3) * 0.45)
    local rightX = PAD * 2 + leftW
    local rightW = vw - PAD - rightX

    -- Active tab: event list (left) + details (right) + button row.
    self.eventList:setX(PAD); self.eventList:setY(PAD)
    self.eventList:setWidth(leftW); self.eventList:setHeight(listH)
    self.eventDetail:setX(rightX); self.eventDetail:setY(PAD)
    self.eventDetail:setWidth(rightW); self.eventDetail:setHeight(listH)
    self.eventDetail:paginate()
    layoutButtonRow(self.activeBtns, vw, rowY)

    -- Spawn tab: type list (left) + details (top-right) + locations (bottom-right).
    self.typeList:setX(PAD); self.typeList:setY(PAD)
    self.typeList:setWidth(leftW); self.typeList:setHeight(listH)
    local detailH = math.floor((listH - PAD) / 2)
    self.typeDetail:setX(rightX); self.typeDetail:setY(PAD)
    self.typeDetail:setWidth(rightW); self.typeDetail:setHeight(detailH)
    self.typeDetail:paginate()
    local locY = PAD + detailH + PAD
    self.locList:setX(rightX); self.locList:setY(locY)
    self.locList:setWidth(rightW); self.locList:setHeight(PAD + listH - locY)
    layoutButtonRow(self.spawnBtns, vw, rowY)

    -- Scheduler tab: full-width rich text + one button.
    self.schedText:setX(PAD); self.schedText:setY(PAD)
    self.schedText:setWidth(vw - PAD * 2); self.schedText:setHeight(listH)
    self.schedText:paginate()
    self.schedBtn:setX(PAD); self.schedBtn:setY(rowY); self.schedBtn:setWidth(180)

    self.lastW, self.lastH = self.width, self.height
end

-- ----------------------------------------------------------------------------
-- Data → widgets
-- ----------------------------------------------------------------------------

local function selectedKey(list, field)
    local it = list and list.items[list.selected]
    return it and it.item and it.item[field] or nil
end

local function reselect(list, field, key)
    if not key then return end
    for i, it in ipairs(list.items) do
        if it.item and it.item[field] == key then
            list.selected = i
            return
        end
    end
end

function DEAdminPanel:setData(snap)
    self.snapshot = snap
    if not snap then return end

    local keepUid = selectedKey(self.eventList, "uid")
    self.eventList:clear()
    for _, ev in ipairs(snap.events or {}) do
        self.eventList:addItem(ev.name or ev.id or tostring(ev.uid), ev)
    end
    for _, pk in ipairs(snap.parked or {}) do
        pk.parked = true
        self.eventList:addItem("(parked) " .. tostring(pk.id or pk.name or "?"), pk)
    end
    reselect(self.eventList, "uid", keepUid)

    local keepId = selectedKey(self.typeList, "id")
    self.typeList:clear()
    for _, t in ipairs(snap.types or {}) do
        local mark = t.eligible and "[+]" or "[-]"
        self.typeList:addItem(string.format("%s %s", mark, t.name or t.id), t)
    end
    reselect(self.typeList, "id", keepId)
    self.lastTypeSel = self.typeList.selected
    self.lastEventSel = self.eventList.selected
    self:refreshLocations()
    self:updateEventDetail()
    self:updateTypeDetail()

    self.schedText:setText(self:schedulerText(snap.scheduler, snap.types))
    self.schedText:paginate()
end

-- Details panels -------------------------------------------------------------

local function kv(label, value)
    return string.format(" <RGB:0.7,0.7,0.7> %s: <RGB:1,1,1> %s <LINE> ", label, tostring(value))
end

function DEAdminPanel:updateEventDetail()
    local it = self.eventList.items[self.eventList.selected]
    local ev = it and it.item
    local out
    if not ev then
        out = " <LINE> <RGB:0.6,0.6,0.6> Select an event to see its details."
    elseif ev.parked then
        out = "<SIZE:medium> Parked spawn <SIZE:small> <LINE> <LINE> "
            .. kv("Type", ev.id or "?")
            .. kv("Position", string.format("(%d, %d)", ev.x or 0, ev.y or 0))
            .. (ev.distance and kv("Distance", string.format("~%d tiles", ev.distance)) or "")
            .. " <LINE> <RGB:0.7,0.7,0.7> Waiting for a player to stream in its chunk."
    else
        local exp = ev.expiresInH and string.format("%.1fh", ev.expiresInH) or "never"
        out = "<SIZE:medium> " .. (ev.name or ev.id or "Event") .. " <SIZE:small> <LINE> <LINE> "
            .. kv("UID", ev.uid or "?")
            .. kv("Type", ev.id or "?")
            .. kv("Position", string.format("(%d, %d)", ev.x or 0, ev.y or 0))
            .. (ev.distance and kv("Distance", string.format("~%d tiles", ev.distance)) or "")
            .. kv("Zombies", ev.zombies or 0)
            .. kv("Radius", string.format("%d tiles", ev.radius or 0))
            .. kv("Age", string.format("%.1fh", ev.ageH or 0))
            .. kv("Expires in", exp)
    end
    self.eventDetail:setText(out)
    self.eventDetail:paginate()
end

function DEAdminPanel:updateTypeDetail()
    local t = self:selectedType()
    local out
    if not t then
        out = " <LINE> <RGB:0.6,0.6,0.6> Select an event type."
    else
        local eligible = t.eligible
            and " <RGB:0.5,1,0.5> yes <RGB:1,1,1> "
            or  string.format(" <RGB:1,0.6,0.6> no (%s) <RGB:1,1,1> ", t.reason or "?")
        out = "<SIZE:medium> " .. (t.name or t.id) .. " <SIZE:small> <LINE> <LINE> "
            .. kv("ID", t.id or "?")
            .. string.format(" <RGB:0.7,0.7,0.7> Eligible: <RGB:1,1,1> %s <LINE> ", eligible)
            .. kv("Weight", t.weight or 0)
            .. kv("Cooldown", string.format("%dh", t.cooldownHours or 0))
            .. kv("Min days survived", t.minDaysSurvived or 0)
            .. kv("Locations", t.locations and #t.locations or 0)
    end
    self.typeDetail:setText(out)
    self.typeDetail:paginate()
end

function DEAdminPanel:refreshLocations()
    self.locList:clear()
    local t = self.typeList.items[self.typeList.selected]
    t = t and t.item
    if not t or not t.locations then return end
    for _, loc in ipairs(t.locations) do
        self.locList:addItem(string.format("%s (%d,%d,%d)",
            loc.name or "?", loc.x, loc.y, loc.z or 0), { loc = loc, typeId = t.id })
    end
end

function DEAdminPanel:schedulerText(s, types)
    s = s or {}
    local function yn(v) return v and "yes" or "no" end
    local nextFire = "not armed"
    if s.remaining then
        nextFire = s.remaining <= 0
            and string.format("DUE (overdue %.2fh)", -s.remaining)
            or  string.format("in %.2f in-game hours", s.remaining)
    end

    local lines = {
        "<SIZE:medium> Scheduler <SIZE:small> <LINE> ",
        string.format(" Enabled: %s <LINE> ", yn(s.enabled)),
        string.format(" World age: %.2fh (day %.2f) <LINE> ", s.worldAge or 0, (s.worldAge or 0) / 24),
        string.format(" Interval: %.2fh   Grace: %.2fh <LINE> ", s.interval or 0, s.grace or 0),
        string.format(" Next fire: %s <LINE> ", nextFire),
        string.format(" Pending (warning delay): %d   Parked: %d <LINE> ", s.pendingSpawns or 0, s.parked or 0),
        string.format(" Restored from save: %s <LINE> <LINE> ", yn(s.restored)),
        "<SIZE:medium> Eligibility <SIZE:small> <LINE> ",
    }
    for _, t in ipairs(types or {}) do
        if t.eligible then
            lines[#lines + 1] = string.format(" <RGB:0.5,1,0.5> %s: ELIGIBLE <RGB:1,1,1> <LINE> ", t.name)
        else
            lines[#lines + 1] = string.format(" <RGB:1,0.6,0.6> %s: %s <RGB:1,1,1> <LINE> ", t.name, t.reason or "?")
        end
    end
    return table.concat(lines)
end

-- ----------------------------------------------------------------------------
-- Actions
-- ----------------------------------------------------------------------------

function DEAdminPanel:selectedEvent()
    local it = self.eventList.items[self.eventList.selected]
    it = it and it.item
    if it and it.uid then return it end
    return nil
end

function DEAdminPanel:selectedType()
    local it = self.typeList.items[self.typeList.selected]
    return it and it.item or nil
end

function DEAdminPanel:afterAction()
    self.lastRefresh = getTimestampMs()
    DE.requestState()
end

function DEAdminPanel:onGoTo()
    local ev = self:selectedEvent()
    if ev then DE.GoTo(ev.uid); self:afterAction() end
end

function DEAdminPanel:onClearSel()
    local ev = self:selectedEvent()
    if ev then DE.ClearEvent(ev.uid); self:afterAction() end
end

function DEAdminPanel:onClearNear()
    DE.ClearNearby(100)
    self:afterAction()
end

function DEAdminPanel:onClearAll()
    DE.Clean()
    self:afterAction()
end

function DEAdminPanel:onRefresh()
    self:afterAction()
end

function DEAdminPanel:onSpawnHere()
    local t = self:selectedType()
    if t then DE.SpawnHere(t.id); self:afterAction() end
end

function DEAdminPanel:onSpawnLoc()
    local it = self.locList.items[self.locList.selected]
    it = it and it.item
    if it and it.loc then
        DE.Spawn(it.typeId, it.loc.x, it.loc.y, it.loc.z or 0, it.loc.rot)
        self:afterAction()
    end
end

function DEAdminPanel:onForceHere()
    local t = self:selectedType()
    local p = getSpecificPlayer(0)
    if t and p then
        DE.SpawnForce(t.id, p:getX(), p:getY(), p:getZ())
        self:afterAction()
    end
end

function DEAdminPanel:onSpawnRandom()
    DE.SpawnRandom()
    self:afterAction()
end

function DEAdminPanel:onClearCooldowns()
    DE.ClearCooldowns()
    self:afterAction()
end

-- ----------------------------------------------------------------------------
-- Lifecycle
-- ----------------------------------------------------------------------------

function DEAdminPanel:prerender()
    ISCollapsableWindow.prerender(self)

    -- Reflow after a resize.
    if self.width ~= self.lastW or self.height ~= self.lastH then
        self:layout()
    end

    -- Selecting a different event type swaps the location list + details.
    if self.typeList and self.typeList.selected ~= self.lastTypeSel then
        self.lastTypeSel = self.typeList.selected
        self:refreshLocations()
        self:updateTypeDetail()
    end

    -- Selecting a different active event refreshes its details.
    if self.eventList and self.eventList.selected ~= self.lastEventSel then
        self.lastEventSel = self.eventList.selected
        self:updateEventDetail()
    end

    local now = getTimestampMs()
    if now - self.lastRefresh > REFRESH_MS then
        self.lastRefresh = now
        DE.requestState()
    end
end

function DEAdminPanel:close()
    ISCollapsableWindow.close(self)
    self:setVisible(false)
    self:removeFromUIManager()
    if DE.Panel == self then DE.Panel = nil end
end
