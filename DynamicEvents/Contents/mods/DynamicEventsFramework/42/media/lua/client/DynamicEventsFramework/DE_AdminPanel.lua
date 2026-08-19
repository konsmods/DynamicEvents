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

    self:layout()
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

function DEAdminPanel:buildActiveTab()
    local panel = makeTabPanel()
    self.eventList = makeList()
    panel:addChild(self.eventList)
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
    self.typeList = makeList()
    self.locList  = makeList()
    panel:addChild(self.typeList)
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
    local rt = ISRichTextPanel:new(0, 0, 10, 10)
    rt:initialise()
    rt.background = true
    rt.backgroundColor = { r = 0, g = 0, b = 0, a = 0.4 }
    rt.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    rt.autosetheight = false
    rt.marginLeft = PAD
    rt.marginTop = PAD
    rt.defaultFont = FONT
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

    local rowY   = vh - PAD - BTN_H       -- top of the button row
    local listH  = rowY - PAD * 2          -- lists fill above it

    -- Active tab: one full-width list + button row.
    self.eventList:setX(PAD); self.eventList:setY(PAD)
    self.eventList:setWidth(vw - PAD * 2); self.eventList:setHeight(listH)
    layoutButtonRow(self.activeBtns, vw, rowY)

    -- Spawn tab: two side-by-side lists + button row.
    local half = (vw - PAD * 3) / 2
    self.typeList:setX(PAD); self.typeList:setY(PAD)
    self.typeList:setWidth(half); self.typeList:setHeight(listH)
    self.locList:setX(PAD * 2 + half); self.locList:setY(PAD)
    self.locList:setWidth(half); self.locList:setHeight(listH)
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
        local dist = ev.distance and string.format(" ~%dt", ev.distance) or ""
        local exp  = ev.expiresInH and string.format(", exp %.1fh", ev.expiresInH) or ""
        self.eventList:addItem(string.format(
            "%s  |  %s @ (%d,%d)  |  %dz  %dr  %.1fh old%s%s",
            ev.uid, ev.name or ev.id, ev.x, ev.y,
            ev.zombies or 0, ev.radius or 0, ev.ageH or 0, dist, exp), ev)
    end
    for _, pk in ipairs(snap.parked or {}) do
        local dist = pk.distance and string.format(" ~%dt", pk.distance) or ""
        self.eventList:addItem(string.format("(parked) %s @ (%d,%d)%s",
            tostring(pk.id), pk.x, pk.y, dist), { parked = true })
    end
    reselect(self.eventList, "uid", keepUid)

    local keepId = selectedKey(self.typeList, "id")
    self.typeList:clear()
    for _, t in ipairs(snap.types or {}) do
        local mark = t.eligible and "[+]" or "[-]"
        local why  = t.reason and ("  (" .. t.reason .. ")") or ""
        self.typeList:addItem(string.format("%s %s  w%d  cd%dh%s",
            mark, t.name, t.weight or 0, t.cooldownHours or 0, why), t)
    end
    reselect(self.typeList, "id", keepId)
    self.lastTypeSel = self.typeList.selected
    self:refreshLocations()

    self.schedText:setText(self:schedulerText(snap.scheduler, snap.types))
    self.schedText:paginate()
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

    -- Selecting a different event type swaps the location list.
    if self.typeList and self.typeList.selected ~= self.lastTypeSel then
        self.lastTypeSel = self.typeList.selected
        self:refreshLocations()
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
