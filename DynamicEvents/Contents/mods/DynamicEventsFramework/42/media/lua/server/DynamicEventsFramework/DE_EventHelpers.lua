DE = DE or {}

local EH = {}

local function cell()
    local c = getCell()
    if not c then DE.warn("DE_EventHelpers: no cell available") end
    return c
end

local function squareAt(x, y, z)
    local c = cell()
    return c and c:getOrCreateGridSquare(x, y, z)
end

-- ============================================================================
-- Ownership tags
--
-- Every world thing an event creates carries its owning event's uid in modData.
-- That tag is the identity cleanup goes by: the manager only remembers *where*
-- an event is, and the sweep removes whatever inside that footprint is stamped
-- with the uid. Nothing untagged is ever touched.
--
-- modData rides along with the object into the chunk save (IsoObject),
-- the item save (InventoryItem) and the vehicle save (BaseVehicle), so the tag
-- survives a restart where a runtime id or a square coordinate would not.
--
-- Zombies are the exception: they are pooled and virtualized (IsoZombie has
-- resetForReuse), so a tag on one does not survive its chunk unloading. They
-- stay tracked as a bare count — see cleanupZombies.
-- ============================================================================

local TAG_KEY = "de_uid"

function EH.tag(obj, uid)
    if not obj or not uid then return end
    DE.guard("tag object", function() obj:getModData()[TAG_KEY] = uid end)
end

-- The uid stamped on `obj`, or nil. Checks hasModData first on purpose:
-- getModData() *creates* the table, and the cleanup sweep probes every object in
-- the footprint — allocating (and then saving) a modData table for each one.
function EH.tagOf(obj)
    if not obj then return nil end
    return DE.guard("read tag", function()
        if not obj:hasModData() then return nil end
        return obj:getModData()[TAG_KEY]
    end)
end

-- Like tagOf, but for a world object also falls back to the item it wraps: a
-- dropped item's tag lives durably on the InventoryItem, and a player who picks
-- it up and puts it back down gets a fresh IsoWorldInventoryObject that only the
-- InventoryItem still carries the tag through.
function EH.ownerOf(obj)
    local uid = EH.tagOf(obj)
    if uid then return uid end
    if instanceof(obj, "IsoWorldInventoryObject") then
        return EH.tagOf(obj:getItem())
    end
    return nil
end

-- ============================================================================
-- Spawn helpers — EH.spawnX(x, y, z, ..., uid). Whatever they create is stamped
-- with the owning event's uid so cleanup can find it again by tag.
-- ============================================================================

-- Applies optional per-item customisation before the item is placed:
--   opts.name    display name (setName)
--   opts.note    text written onto a writable item (Literature pages)
--   opts.modData arbitrary modData keys stamped onto the item
local function customiseItem(item, opts)
    if not opts then return end
    DE.guard("customiseItem", function()
        if opts.name then item:setName(opts.name) end
        if opts.note and instanceof(item, "Literature") then
            item:setCustomPages(nil)   -- clear any default pages first
            item:addPage(1, opts.note)
            item:setBookName(opts.name or item:getName())
        end
        if opts.modData then
            local md = item:getModData()
            for k, v in pairs(opts.modData) do md[k] = v end
        end
    end)
end

-- Drops one item on the ground. `opts` is optional per-item customisation
-- (name/note/modData); see customiseItem.
function EH.spawnItem(x, y, z, itemType, uid, opts)
    local sq = itemType and squareAt(x, y, z)
    if not sq then return end

    local item = instanceItem(itemType)
    if not item then return end

    customiseItem(item, opts)

    -- Tag the item as well as the world object: the item is the durable half,
    -- it keeps the tag through a save/reload and a pick-up and re-drop. (A player
    -- who keeps the item carries the dead tag; harmless — cleanup only ever
    -- scans ground squares, never inventories.)
    EH.tag(item, uid)
    EH.tag(sq:AddWorldInventoryItem(item, 0.3, 0.3, 0), uid)
end

function EH.spawnLoot(x, y, z, items, radius, chance, uid)
    local r = radius or 2
    local pct = chance or 30
    for dx = -r, r do
        for dy = -r, r do
            if DE.chance(pct) then
                EH.spawnItem(x + dx, y + dy, z, DE.pick(items), uid)
            end
        end
    end
end

function EH.spawnSprite(x, y, z, spriteName, uid)
    local sq = squareAt(x, y, z)
    if not sq then return end
    DE.guard("spawnSprite " .. spriteName, function()
        local obj = IsoObject.new(sq, spriteName, "", false)
        if obj then
            sq:FileObject(obj)
            EH.tag(obj, uid)
        end
    end)
end

function EH.spawnScorchMarks(x, y, z, radius, uid)
    local r = radius or 1
    for dx = -r, r do
        for dy = -r, r do
            if math.abs(dx) + math.abs(dy) <= r + 1 then
                EH.spawnSprite(x + dx, y + dy, z, "floors_burnt_01_" .. DE.rand(1, 8), uid)
            end
        end
    end
end

-- First of `partIds` that exists on the vehicle and has an item container.
local function partContainer(vehicle, ...)
    for i = 1, select("#", ...) do
        local part = vehicle:getPartById((select(i, ...)))
        local container = part and part:getItemContainer()
        if container then return container end
    end
end

-- Rolls a vanilla loot table (a ProceduralDistributions entry, e.g.
-- "GunStoreDisplayCase" or "ArmyStorageGuns") into the container. This is the
-- same data the game fills world containers from, so any table defined by the
-- base game or another mod's distributions works by name.
local function fillFromDistribution(container, distName)
    local list = ProceduralDistributions and ProceduralDistributions.list
    local dist = list and list[distName]
    if not dist then
        DE.warn("no loot distribution named '%s'", tostring(distName))
        return
    end
    DE.guard("rollItem " .. distName, function()
        -- Same call the mod's vehicle loot uses; junk sub-table first if present.
        if dist.junk then ItemPickerJava.rollItem(dist.junk, container, true, nil, nil) end
        ItemPickerJava.rollItem(dist, container, true, nil, nil)
    end)
end

local function fillFromList(container, items, chance)
    for _, itemName in ipairs(items) do
        if DE.chance(chance) then
            local item = instanceItem(itemName)
            if item then
                container:AddItem(item)
                -- AddItem is server-local; sync or clients see an empty container.
                sendAddItemToContainer(container, item)
            end
        end
    end
end

-- Fills a container from `loot`, which is either:
--   * a plain list of item types    -> each rolled at `chance`%
--   * { distribution = "TableName" } -> a vanilla loot table, rolled by the game
local function fillContainer(container, loot, chance)
    if not container or not loot then return end
    if loot.distribution then
        fillFromDistribution(container, loot.distribution)
    else
        fillFromList(container, loot, chance)
    end
end

-- Place a moveable (crate/locker) via the vanilla moveable placement, so it gets
-- a real world object and a container from the sprite's `container` property.
local function spawnMoveableObject(sq, item, lootItems, chance, uid)
    local spriteName = item:getWorldSprite()
    if not spriteName then return end

    local moveProps = ISMoveableSpriteProps.new(spriteName)
    if not moveProps or not moveProps.isMoveable then
        DE.warn("'%s' has no moveable definition (sprite '%s')",
            item:getFullType(), tostring(spriteName))
        return
    end

    local obj = DE.guard("spawnMoveable " .. item:getFullType(), function()
        return moveProps:placeMoveableInternal(sq, item, spriteName)
    end)
    if not obj then return end

    -- Only the placed object is tagged, not `item`: picking the crate back up
    -- builds a fresh Moveable from the sprite, so a tag on this one is dead
    -- weight. Contents are deliberately left untagged — loot a player pulled out
    -- and stashed nearby is theirs, and cleanup should not take it back.
    EH.tag(obj, uid)

    local container = obj:getContainerByIndex(0)
    if container then
        fillContainer(container, lootItems, chance or 100)
    else
        DE.warn("moveable '%s' placed but has no container (sprite '%s' lacks a container property)",
            item:getFullType(), spriteName)
    end
end

-- Spawn a loot-filled container. Handles two kinds:
--   * container items (ItemType = base:container) like "Base.Bag_Military"
--   * moveables like "Base.Mov_MilitaryCrate" (placed as a real crate)
function EH.spawnContainer(x, y, z, containerType, lootItems, chance, uid)
    local sq = containerType and squareAt(x, y, z)
    if not sq then return end

    local item = instanceItem(containerType)
    if not item then return end

    if instanceof(item, "Moveable") then
        spawnMoveableObject(sq, item, lootItems, chance, uid)
        return
    end

    local container = item:getItemContainer()
    if not container then
        DE.warn("'%s' is not a container item; cannot spawn loot container", containerType)
        return
    end

    EH.tag(item, uid)
    EH.tag(sq:AddWorldInventoryItem(item, 0.5, 0.5, 0), uid)
    fillContainer(container, lootItems, chance or 100)
end

-- Fill a vehicle with its vanilla loot tables (same as a road-story car).
local function fillVehicleVanillaLoot(vehicle)
    local scriptName = vehicle:getScriptName()
    if not scriptName then return end

    -- Distribution keys are the bare vehicle name (no "Base." prefix),
    -- optionally suffixed with the skin index.
    local bareName = string.match(scriptName, "%.(.+)$") or scriptName
    local skinIndex = vehicle:getSkinIndex()

    local map = ItemPickerJava and ItemPickerJava.VehicleDistributions
    if not map then return end

    local vehicleDist = map[bareName .. tostring(skinIndex)] or map[bareName]
    if not vehicleDist or not vehicleDist.normal or not vehicleDist.normal.containers then
        DE.warn("no vanilla vehicle distribution for '%s'", scriptName)
        return
    end

    local room = vehicleDist.normal
    local parts = vehicle:getParts()
    for i = 0, parts:getPartCount() - 1 do
        local part = parts:getPartByIndex(i)
        local container = part and part:getItemContainer()
        if container then
            local containerDist = room.containers[part:getId()]
            if containerDist then
                ItemPickerJava.rollItem(containerDist, container, false, nil, room)
            end
        end
    end
end

function EH.spawnVehicle(x, y, z, vehicleType, opts, uid)
    opts = opts or {}
    local sq = squareAt(x, y, z)
    if not sq then return end

    DE.guard("spawnVehicle " .. (vehicleType or "nil"), function()
        local vehicle = addVehicle(vehicleType, x, y, z)
        if not vehicle then
            DE.dbg("addVehicle failed, trying addVehicleDebug for %s", vehicleType)
            vehicle = addVehicleDebug(vehicleType, IsoDirections.N, opts.skin, sq)
        end
        if not vehicle then
            DE.warn("both addVehicle and addVehicleDebug returned nil for %s at (%d, %d, %d)", vehicleType or "?", x, y, z)
            return
        end

        if opts.rot then
            vehicle:setAngles(0, opts.rot, 0)
        end

        if opts.skin then
            vehicle:setSkinIndex(opts.skin)
            vehicle:updateSkin()
        end

        -- The tag is how cleanup finds this vehicle again. A vehicle's runtime id
        -- is a 16-bit short that gets reassigned on reload, so it is useless
        -- across a restart; modData is saved with the vehicle and is not.
        EH.tag(vehicle, uid)
        DE.dbg("spawned vehicle id=%d type=%s tag=%s at (%d, %d, %d)",
            vehicle:getId(), vehicleType, tostring(uid), x, y, z)

        -- Loot: either the vanilla vehicle-specific tables, or a manual list.
        if opts.loot == "vanilla" then
            fillVehicleVanillaLoot(vehicle)
        else
            fillContainer(partContainer(vehicle, "TruckBed", "Trunk"), opts.loot, 40)
            fillContainer(partContainer(vehicle, "GloveBox"), opts.loot, 20)
        end

        -- Wrecks get beaten up; "working" vehicles are left drivable.
        if not opts.working then
            local engine = vehicle:getPartById("Engine")
            if engine then engine:setCondition(DE.rand(0, 15)) end
            local gasTank = vehicle:getPartById("GasTank")
            if gasTank then gasTank:setContainerContentAmount(DE.rand(0, 5)) end
            for _, partId in ipairs({"Windshield", "WindowFrontLeft", "HeadlightLeft", "HeadlightRight", "WindowFrontRight"}) do
                local part = vehicle:getPartById(partId)
                if part and DE.chance(60) then part:setCondition(DE.rand(0, 10)) end
            end
        end
    end)
end

-- Spawns zombies near the site; returns how many actually spawned. Tracked as a
-- count, not individually, because zombies lose their identity when their chunk
-- unloads (the engine virtualizes them).
function EH.spawnZombies(x, y, z, count, radius, outfit)
    local r = radius or 2
    local spawnedCount = 0

    -- NOT addZombiesInOutfitArea: it resolves squares via IsoCell.getInstance(),
    -- which isn't the live cell on a dedicated server. RandomizedWorldBase takes
    -- an explicit square (what road stories use), so it works server-side.
    local rwb = getWorld():getRandomizedWorldBase()
    if not rwb then
        DE.warn("no RandomizedWorldBase available; cannot spawn zombies at (%d, %d, %d)", x, y, z)
        return 0
    end

    -- One at a time so they scatter across the radius the way the old
    -- area-based call did.
    for _ = 1, (count or 3) do
        local sq = squareAt(x + DE.rand(-r, r), y + DE.rand(-r, r), z)
        local spawned = sq and DE.guard("spawnZombies", function()
            return rwb:addZombiesOnSquare(1, outfit, nil, sq)
        end)
        if spawned then spawnedCount = spawnedCount + spawned:size() end
    end

    DE.dbg("spawned %d zombies at (%d, %d, %d)", spawnedCount, x, y, z)
    return spawnedCount
end

function EH.playSound(x, y, z, soundName)
    if not soundName then return end
    DE.guard("playSound " .. soundName, function()
        local emitter = getWorld():getFreeEmitter(x, y, z)
        if emitter then
            emitter:playSound(soundName)
            DE.dbg("played sound '%s' at (%d, %d, %d)", soundName, x, y, z)
        end
    end)
end

-- Scatters `count` fire/smoke sources within one tile of (x, y, z).
local function scatterEffect(label, count, x, y, z, start)
    local c = cell()
    if not c then return end
    for _ = 1, count do
        local sq = squareAt(x + DE.rand(-1, 1), y + DE.rand(-1, 1), z)
        if sq then
            DE.guard(label, function() start(c, sq) end)
        end
    end
end

function EH.spawnFire(x, y, z, count)
    scatterEffect("spawnFire", count or 1, x, y, z, function(c, sq)
        IsoFireManager.StartFire(c, sq, true, 100, 200)
    end)
end

function EH.spawnSmoke(x, y, z, count)
    scatterEffect("spawnSmoke", count or 2, x, y, z, function(c, sq)
        IsoFireManager.StartSmoke(c, sq, true, 100, 200)
    end)
end

-- ============================================================================
-- Cleanup
-- ============================================================================

-- Widest footprint a sweep will ever walk, in tiles. Caps the cost of one clear
-- at 81x81 squares even if an event reports a nonsense radius.
EH.MAX_SWEEP_RADIUS = 40

-- Slack added to an event's recorded footprint, for things that drifted a tile
-- or two (a wreck nudged, an item kicked over).
local SWEEP_PADDING = 2

-- Takes obj off sq. Dropped items go out through the world-item path; sprites
-- and moveables are filed tile objects and need the explicit tile removal too.
local function removeObject(sq, obj)
    DE.guard("removeObject", function()
        if isServer() then sq:transmitRemoveItemFromSquareOnClients(obj) end
        sq:transmitRemoveItemFromSquare(obj)
        if not instanceof(obj, "IsoWorldInventoryObject") then
            sq:RemoveTileObject(obj)
        end
    end)
end

-- A vehicle's runtime id is a 16-bit `short`, reassigned on reload, so it does
-- not survive a restart. Detach it from the world, then delete it from the save.
function EH.removeVehicle(v)
    DE.guard("cleanupVehicle world", function() v:removeFromWorld() end)
    DE.guard("cleanupVehicle perm", function() v:permanentlyRemove() end)
end

-- Walks every square within `radius` of (x,y,z), handing each vehicle to
-- onVehicle(veh) and each tile object to onObject(sq, obj). Either may be nil to
-- skip that half. Shared by the removal sweeps and the read-only tag scan behind
-- DE.Purge, so they can't drift apart.
local function sweep(x, y, z, radius, onVehicle, onObject)
    local c = getCell()
    if not c then return end

    local r = math.min(math.max(radius or 0, 1), EH.MAX_SWEEP_RADIUS)
    local seenVehicles = {}

    for dx = -r, r do
        for dy = -r, r do
            local sq = c:getGridSquare(x + dx, y + dy, z)
            if sq then
                -- A vehicle spans several squares, so dedupe by id.
                if onVehicle then
                    local veh = sq:getVehicleContainer()
                    if veh then
                        local id = veh:getId()
                        if not seenVehicles[id] then
                            seenVehicles[id] = true
                            onVehicle(veh)
                        end
                    end
                end

                if onObject then
                    -- Backwards: onObject may remove from this list.
                    local objects = sq:getObjects()
                    for i = objects:size() - 1, 0, -1 do
                        local obj = objects:get(i)
                        if obj then onObject(sq, obj) end
                    end
                end
            end
        end
    end
end

-- Removes everything within `radius` of (x,y,z) tagged with `uid`, and nothing
-- else. Returns how many things it removed.
function EH.cleanupByTag(x, y, z, uid, radius)
    if not uid then return 0 end

    local removed = 0
    sweep(x, y, z, (radius or 0) + SWEEP_PADDING,
        function(veh)
            if EH.tagOf(veh) == uid then
                EH.removeVehicle(veh)
                removed = removed + 1
            end
        end,
        function(sq, obj)
            if EH.ownerOf(obj) == uid then
                removeObject(sq, obj)
                removed = removed + 1
            end
        end)
    return removed
end

-- Read-only: uid -> number of tagged things found within `radius`. Backs
-- DE.Purge, which needs to know which events are lying around before it removes
-- anything.
function EH.findTags(x, y, z, radius)
    local found = {}
    local function note(uid)
        if uid then found[uid] = (found[uid] or 0) + 1 end
    end

    sweep(x, y, z, radius or 30,
        function(veh) note(EH.tagOf(veh)) end,
        function(_, obj) note(EH.ownerOf(obj)) end)
    return found
end

-- Removes loaded vehicles within `radius` tiles (capped at MAX_SWEEP_RADIUS).
-- With `uid`, only vehicles tagged as belonging to that event; without it, every
-- vehicle in range — which is what events that clear obstacles before spawning
-- want.
function EH.clearVehicles(x, y, z, radius, uid)
    local removed = 0
    sweep(x, y, z, radius, function(veh)
        if uid and EH.tagOf(veh) ~= uid then return end
        EH.removeVehicle(veh)
        removed = removed + 1
    end, nil)
    return removed
end

-- ----------------------------------------------------------------------------
-- Zombies and corpses. Not tag-based and never will be: IsoZombie has
-- resetForReuse and the engine virtualizes zombies whose chunk unloads, so a
-- modData tag on one does not survive. Both go by radius instead.
-- ----------------------------------------------------------------------------

-- Default radius (tiles) around an event centre that its spawned zombies and
-- their corpses are cleared from. An event overrides it with
-- def.zombieCleanupRadius.
local DEFAULT_ZOMBIE_CLEANUP_RADIUS = 20

-- Removes up to `count` loaded zombies within `radius` tiles of the site.
-- Zombies can't be matched individually after virtualization, so we remove this
-- many from around the site.
local function cleanupZombies(x, y, count, radius)
    if not count or count <= 0 then return end
    if not DE.Config.cleanupZombies then return end

    local list = cell() and cell():getZombieList()
    if not list then return end

    local r = radius or DEFAULT_ZOMBIE_CLEANUP_RADIUS
    local radiusSq = r * r
    local doomed = {}
    for i = 0, list:size() - 1 do
        local zed = list:get(i)
        if zed then
            local dx, dy = zed:getX() - x, zed:getY() - y
            if dx * dx + dy * dy <= radiusSq then
                doomed[#doomed + 1] = zed
                if #doomed >= count then break end
            end
        end
    end

    for _, zed in ipairs(doomed) do
        DE.guard("cleanupZombie", function()
            zed:removeFromWorld()
            zed:removeFromSquare()
        end)
    end

    DE.dbg("cleaned up %d of %d spawned zombie(s)", #doomed, count)
end

-- Removes dead zombie corpses in the same radius. No cell-level corpse list
-- exists, so walk the radius; corpses can't be attributed, so all are removed.
local function cleanupCorpses(x, y, z, radius)
    if not DE.Config.cleanupZombies then return end

    local c = cell()
    if not c then return end

    local r = radius or DEFAULT_ZOMBIE_CLEANUP_RADIUS
    local removed = 0
    for dx = -r, r do
        for dy = -r, r do
            local sq = c:getGridSquare(x + dx, y + dy, z)
            if sq then
                local movables = sq:getStaticMovingObjects()
                for i = movables:size() - 1, 0, -1 do
                    local obj = movables:get(i)
                    if obj and instanceof(obj, "IsoDeadBody") then
                        DE.guard("cleanupCorpse", function() sq:removeCorpse(obj, false) end)
                        removed = removed + 1
                    end
                end
            end
        end
    end

    if removed > 0 then
        DE.dbg("cleaned up %d corpse(s)", removed)
    end
end

-- Removes everything an event left behind; only reaches loaded chunks. `ev` is
-- the manager's record for the event: uid, radius, zombies, zombieCleanupRadius.
function EH.cleanupEvent(x, y, z, ev)
    ev = ev or {}

    local removed = EH.cleanupByTag(x, y, z, ev.uid, ev.radius)
    DE.dbg("cleanup [%s]: removed %d tagged object(s) within %d tiles",
        tostring(ev.uid), removed, (ev.radius or 0) + SWEEP_PADDING)

    local zr = ev.zombieCleanupRadius or DEFAULT_ZOMBIE_CLEANUP_RADIUS
    cleanupZombies(x, y, ev.zombies or 0, zr)
    cleanupCorpses(x, y, z, zr)
end

DE.EventHelpers = EH

-- ============================================================================
-- Event context — the `e` object passed to spawn functions.
-- ============================================================================

local EventContext = {}
EventContext.__index = EventContext

-- A vehicle is placed by its centre square but covers several, so count a few
-- tiles past it when measuring the footprint.
local VEHICLE_FOOTPRINT = 2

function EventContext.new(x, y, z, rot, uid)
    return setmetatable({
        _radius  = 0,    -- widest offset touched; cleanup sweeps this far out
        _zombies = 0,
        x = x, y = y, z = z,
        rot = rot or 0,
        uid = uid,   -- owning event's uid; stamped into everything spawned
    }, EventContext)
end

-- How far from the centre this event reached, in tiles. The manager stores it
-- and cleanup sweeps that radius looking for the uid tag, so every Spawn* has
-- to widen it or its objects become unreachable.
function EventContext:radius()
    return self._radius
end

function EventContext:zombieCount()
    return self._zombies
end

-- Chebyshev, not euclidean: the sweep walks a square grid.
function EventContext:_reach(wx, wy, extra)
    local d = math.max(math.abs(wx - self.x), math.abs(wy - self.y)) + (extra or 0)
    if d > self._radius then self._radius = d end
end

function EventContext:_worldPos(dx, dy, radius)
    if radius then
        dx = dx + DE.rand(-radius, radius)
        dy = dy + DE.rand(-radius, radius)
    end
    local rad = math.rad(self.rot)
    local cosA = math.cos(rad)
    local sinA = math.sin(rad)
    return self.x + math.floor(dx * cosA - dy * sinA + 0.5),
           self.y + math.floor(dx * sinA + dy * cosA + 0.5)
end

-- Every Spawn* method resolves (dx, dy) + opts.radius into world coords the
-- same way, so do it in one place and hand back a normalised opts table.
-- `extra` is how far past that point the spawn itself scatters.
local function place(self, dx, dy, opts, extra)
    opts = opts or {}
    local wx, wy = self:_worldPos(dx, dy, opts.radius)
    self:_reach(wx, wy, extra)
    return wx, wy, opts
end

-- The uid to stamp into what a Spawn* creates, or nil when opts.permanent is
-- set. A permanent object carries no tag, so cleanup never removes it — it
-- outlives the event. Everything else is tagged and swept up on cleanup.
local function tagFor(self, opts)
    if opts and opts.permanent then return nil end
    return self.uid
end

function EventContext:SpawnVehicle(vehicleType, dx, dy, opts)
    local wx, wy, o = place(self, dx, dy, opts, VEHICLE_FOOTPRINT)
    EH.spawnVehicle(wx, wy, self.z, vehicleType, o, tagFor(self, o))
end

-- Themed zombies, tracked so cleanup removes them. opts.outfit is a vanilla
-- outfit name (e.g. "ArmyCamoGreen"); opts.spread widens the scatter.
function EventContext:SpawnZombies(count, dx, dy, opts)
    local o = opts or {}
    local spread = o.spread or 3
    local wx, wy = place(self, dx, dy, o, spread)

    local n = EH.spawnZombies(wx, wy, self.z, count, spread, o.outfit) or 0

    -- Counted (not tagged): a zombie loses its modData the moment its chunk
    -- unloads, so cleanup removes this many loaded zombies from around the site.
    -- Permanent zombies aren't counted, so cleanup leaves them behind.
    if not o.permanent then
        self._zombies = self._zombies + n
    end
end

-- World-owned horde for repopulation. Never tracked and never cleaned up:
-- these are meant to persist and wander (pair with a pulse + DE.attractZombies
-- to draw them toward a town). Larger default scatter than SpawnZombies.
function EventContext:SpawnHorde(count, dx, dy, opts)
    local o = opts or {}
    local spread = o.spread or 20
    -- Deliberately does not widen the footprint (like fire/smoke): the horde is
    -- not part of what cleanup sweeps.
    local wx, wy = self:_worldPos(dx, dy, o.radius)
    EH.spawnZombies(wx, wy, self.z, count, spread, o.outfit)
end

-- Drops one item. opts.name/opts.note/opts.modData customise it — note writes
-- text onto a writable item (Base.Note and similar), turning it into readable
-- lore. See customiseItem.
function EventContext:SpawnItem(itemType, dx, dy, opts)
    local wx, wy, o = place(self, dx, dy, opts)
    EH.spawnItem(wx, wy, self.z, itemType, tagFor(self, o), o)
end

function EventContext:SpawnLoot(items, dx, dy, opts)
    local o = opts or {}
    local spread = o.spread or 2
    local wx, wy = place(self, dx, dy, o, spread)
    EH.spawnLoot(wx, wy, self.z, items, spread, o.chance or 30, tagFor(self, o))
end

-- Spawns a loot-filled container (bag/case/crate) at an offset. `lootItems` is
-- a plain item list (opts.chance is the per-item fill chance, default 100) or
-- { distribution = "TableName" } to roll a vanilla loot table instead.
function EventContext:SpawnContainer(containerType, lootItems, dx, dy, opts)
    local wx, wy, o = place(self, dx, dy, opts)
    EH.spawnContainer(wx, wy, self.z, containerType, lootItems, o.chance, tagFor(self, o))
end

-- Fire and smoke are not tracked at all: they burn out, spread where they like,
-- and nothing they leave behind belongs to us. They don't widen the footprint.
function EventContext:SpawnFire(count, dx, dy, opts)
    local wx, wy = self:_worldPos(dx, dy, (opts or {}).radius)
    EH.spawnFire(wx, wy, self.z, count)
end

function EventContext:SpawnSmoke(count, dx, dy, opts)
    local wx, wy = self:_worldPos(dx, dy, (opts or {}).radius)
    EH.spawnSmoke(wx, wy, self.z, count)
end

function EventContext:SpawnScorch(dx, dy, opts)
    local o = opts or {}
    local spread = o.spread or 1
    local wx, wy = place(self, dx, dy, o, spread)
    EH.spawnScorchMarks(wx, wy, self.z, spread, tagFor(self, o))
end

DE.EventContext = EventContext
