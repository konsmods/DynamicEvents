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

-- True only when the chunk holding (x,y,z) is streamed in. On a server this
-- goes through ServerMap, which returns nothing for unloaded chunks — that is
-- how cleanup tells "already gone" apart from "can't reach it yet".
local function isLoaded(x, y, z)
    local c = getCell()
    return c ~= nil and c:getGridSquare(x, y, z) ~= nil
end

-- ============================================================================
-- Spawn helpers — all follow: EH.spawnX(x, y, z, ...) → tracked objects[]
-- ============================================================================

-- Drops one item on the ground. Returns its tracking record, or nil.
function EH.spawnItem(x, y, z, itemType)
    local sq = itemType and squareAt(x, y, z)
    if not sq then return nil end

    local item = instanceItem(itemType)
    if not item then return nil end

    sq:AddWorldInventoryItem(item, 0.3, 0.3, 0)
    return {
        type = "item",
        sqx = sq:getX(), sqy = sq:getY(), sqz = sq:getZ(),
        itemType = itemType,
    }
end

function EH.spawnLoot(x, y, z, items, radius, chance)
    local objects = {}
    local r = radius or 2
    local pct = chance or 30

    for dx = -r, r do
        for dy = -r, r do
            if DE.chance(pct) then
                local record = EH.spawnItem(x + dx, y + dy, z, DE.pick(items))
                if record then objects[#objects + 1] = record end
            end
        end
    end
    return objects
end

function EH.spawnSprite(x, y, z, spriteName)
    local objects = {}
    local sq = squareAt(x, y, z)
    if not sq then return objects end

    DE.guard("spawnSprite " .. spriteName, function()
        local obj = IsoObject.new(sq, spriteName, "", false)
        if obj then
            sq:FileObject(obj)
            objects[#objects + 1] = {
                type = "sprite",
                sqx = sq:getX(), sqy = sq:getY(), sqz = sq:getZ(),
                sprite = obj:getSprite():getName(),
            }
        end
    end)
    return objects
end

function EH.spawnScorchMarks(x, y, z, radius)
    local objects = {}
    local r = radius or 1
    for dx = -r, r do
        for dy = -r, r do
            if math.abs(dx) + math.abs(dy) <= r + 1 then
                local name = "floors_burnt_01_" .. DE.rand(1, 8)
                EH.merge(objects, EH.spawnSprite(x + dx, y + dy, z, name))
            end
        end
    end
    return objects
end

-- First of `partIds` that exists on the vehicle and has an item container.
local function partContainer(vehicle, ...)
    for i = 1, select("#", ...) do
        local part = vehicle:getPartById((select(i, ...)))
        local container = part and part:getItemContainer()
        if container then return container end
    end
end

local function fillContainer(container, items, chance)
    if not container or not items then return end
    for _, itemName in ipairs(items) do
        if DE.chance(chance) then
            local item = instanceItem(itemName)
            if item then
                container:AddItem(item)
                -- AddItem only updates the server's copy. The object itself is
                -- already on the clients (transmitted empty), so sync each item
                -- or clients keep seeing an empty container until reload.
                -- No-op when not on the server.
                sendAddItemToContainer(container, item)
            end
        end
    end
end

-- Places a moveable (e.g. a crate or locker) through the vanilla moveable
-- placement, so it gets a proper world object and a container created from the
-- sprite's `container` property (e.g. Mov_MilitaryCrate -> "militarycrate").
-- Returns its tracking record, or nil.
local function spawnMoveableObject(sq, item, lootItems, chance)
    local spriteName = item:getWorldSprite()
    if not spriteName then return nil end

    local moveProps = ISMoveableSpriteProps.new(spriteName)
    if not moveProps or not moveProps.isMoveable then
        DE.warn("'%s' has no moveable definition (sprite '%s')",
            item:getFullType(), tostring(spriteName))
        return nil
    end

    local obj = DE.guard("spawnMoveable " .. item:getFullType(), function()
        return moveProps:placeMoveableInternal(sq, item, spriteName)
    end)
    if not obj then return nil end

    local container = obj:getContainerByIndex(0)
    if container then
        fillContainer(container, lootItems, chance or 100)
    else
        DE.warn("moveable '%s' placed but has no container (sprite '%s' lacks a container property)",
            item:getFullType(), spriteName)
    end

    return {
        type = "moveable",
        sqx = sq:getX(), sqy = sq:getY(), sqz = sq:getZ(),
        sprite = spriteName,
    }
end

-- Spawns a loot container and fills it with loot. Handles two kinds:
--   * container items (ItemType = base:container) like "Base.Bag_Military" —
--     dropped in the world and their ItemContainer filled.
--   * moveables like "Base.Mov_MilitaryCrate" — placed via the vanilla moveable
--     placement so they get a crate object with a real container.
-- Returns its tracking record, or nil.
function EH.spawnContainer(x, y, z, containerType, lootItems, chance)
    local sq = containerType and squareAt(x, y, z)
    if not sq then return nil end

    local item = instanceItem(containerType)
    if not item then return nil end

    if instanceof(item, "Moveable") then
        return spawnMoveableObject(sq, item, lootItems, chance)
    end

    local container = item:getItemContainer()
    if not container then
        DE.warn("'%s' is not a container item; cannot spawn loot container", containerType)
        return nil
    end

    sq:AddWorldInventoryItem(item, 0.5, 0.5, 0)
    fillContainer(container, lootItems, chance or 100)

    return {
        type = "item",
        sqx = sq:getX(), sqy = sq:getY(), sqz = sq:getZ(),
        itemType = containerType,
    }
end

function EH.spawnVehicle(x, y, z, vehicleType, lootItems, direction, skinIndex, tag)
    local objects = {}
    local sq = squareAt(x, y, z)
    if not sq then return objects end

    DE.guard("spawnVehicle " .. (vehicleType or "nil"), function()
        local vehicle = addVehicle(vehicleType, x, y, z)
        if not vehicle then
            DE.dbg("addVehicle failed, trying addVehicleDebug for %s", vehicleType)
            vehicle = addVehicleDebug(vehicleType, IsoDirections.N, skinIndex, sq)
        end
        if not vehicle then
            DE.warn("both addVehicle and addVehicleDebug returned nil for %s at (%d, %d, %d)", vehicleType or "?", x, y, z)
            return
        end

        if direction then
            vehicle:setAngles(0, direction, 0)
        end

        if skinIndex then
            vehicle:setSkinIndex(skinIndex)
            vehicle:updateSkin()
        end

        -- Tag as well as record the id: ids don't always survive (or arrive),
        -- and the tag lets cleanup find the vehicle by sweeping the area.
        if tag then
            DE.guard("tag vehicle", function() vehicle:getModData().de_event = tag end)
        end

        local vId = vehicle:getId()
        DE.dbg("spawned vehicle id=%d type=%s tag=%s at (%d, %d, %d)",
            vId, vehicleType, tostring(tag), x, y, z)
        objects[#objects + 1] = { type = "vehicle", ref = vId, tag = tag, x = x, y = y, z = z }

        fillContainer(partContainer(vehicle, "TruckBed", "Trunk"), lootItems, 40)
        fillContainer(partContainer(vehicle, "GloveBox"), lootItems, 20)

        local engine = vehicle:getPartById("Engine")
        if engine then engine:setCondition(DE.rand(0, 15)) end
        local gasTank = vehicle:getPartById("GasTank")
        if gasTank then gasTank:setContainerContentAmount(DE.rand(0, 5)) end
        for _, partId in ipairs({"Windshield", "WindowFrontLeft", "HeadlightLeft", "HeadlightRight", "WindowFrontRight"}) do
            local part = vehicle:getPartById(partId)
            if part and DE.chance(60) then part:setCondition(DE.rand(0, 10)) end
        end
    end)
    return objects
end

-- Spawns zombies near the site and returns how many were actually spawned.
-- They are NOT tracked individually: zombies lose whatever identity we give
-- them the moment their chunk unloads (the engine virtualizes them, dropping
-- modData tags and reassigning online ids). Cleanup instead removes the same
-- number of loaded zombies from around the site.
function EH.spawnZombies(x, y, z, count, radius, outfit)
    local r = radius or 2
    local spawnedCount = 0

    -- NOT addZombiesInOutfitArea: that resolves squares through
    -- IsoCell.getInstance(), which isn't the live cell on a dedicated server,
    -- so it logs "No IsoSquare selected. Cannot spawn." and returns nothing.
    -- RandomizedWorldBase takes an explicit square and is what the vanilla
    -- road stories use, so it works server-side.
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
-- Utility
-- ============================================================================

function EH.merge(target, source)
    if not source then return target end
    for i = 1, #source do
        target[#target + 1] = source[i]
    end
    return target
end

-- ============================================================================
-- Cleanup
-- ============================================================================

-- Removes the topmost object on (x,y,z) that `matches`, if any.
local function removeFromSquare(x, y, z, matches)
    local c = cell()
    local sq = c and c:getGridSquare(x, y, z)
    if not sq then return end

    local objects = sq:getObjects()
    for i = objects:size() - 1, 0, -1 do
        local obj = objects:get(i)
        if obj and matches(obj) then
            sq:transmitRemoveItemFromSquare(obj)
            return
        end
    end
end

local MATCHERS = {
    item = function(objData)
        return function(obj)
            if not instanceof(obj, "IsoWorldInventoryObject") then return false end
            local invItem = obj:getItem()
            return invItem ~= nil and invItem:getFullType() == objData.itemType
        end
    end,
    sprite = function(objData)
        return function(obj)
            local sprite = obj:getSprite()
            return sprite ~= nil and sprite:getName() == objData.sprite
        end
    end,
}

local function cleanupOne(objData)
    local makeMatcher = MATCHERS[objData.type]
    if not makeMatcher then return end
    removeFromSquare(objData.sqx, objData.sqy, objData.sqz, makeMatcher(objData))
end

-- Removes a placed moveable (a tile object) by its sprite name, following the
-- vanilla pickup removal pattern (RemoveTileObject + transmit). Moveables are
-- added with AddSpecialObject, not FileObject, so they need this path rather
-- than the plain removeFromSquare used for items and decorative sprites.
local function cleanupMoveable(objData)
    local c = cell()
    local sq = c and c:getGridSquare(objData.sqx, objData.sqy, objData.sqz)
    if not sq then return end

    local objects = sq:getObjects()
    for i = objects:size() - 1, 0, -1 do
        local obj = objects:get(i)
        if obj and obj:getSprite() and obj:getSprite():getName() == objData.sprite then
            if isClient() then sq:transmitRemoveItemFromSquare(obj) end
            if isServer() then sq:transmitRemoveItemFromSquareOnClients(obj) end
            sq:RemoveTileObject(obj)
            return
        end
    end
end

-- Removes up to `count` loaded zombies within a radius of the event site.
-- Zombies lose whatever identity we give them the moment their chunk unloads
-- (the engine virtualizes them, dropping modData tags and reassigning online
-- ids), so we can't match specific survivors after a player leaves and returns.
-- We do know how many the event spawned, and they stay near the site, so
-- sweeping the area and removing that many is close enough.
local ZOMBIE_CLEANUP_RADIUS = 20

local function cleanupZombies(x, y, count)
    if not count or count <= 0 then return end
    if not DE.Config.cleanupZombies then return end

    local list = cell() and cell():getZombieList()
    if not list then return end

    local radiusSq = ZOMBIE_CLEANUP_RADIUS * ZOMBIE_CLEANUP_RADIUS
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

-- The convoy event's vehicles reach about +/-15 tiles from the site centre
-- (+/-12 spacing plus vehicle length), which is the worst case this needs to
-- find. 15 keeps the grid at 31x31 (~960 squares) instead of 51x51 (~2600).
local VEHICLE_SWEEP_RADIUS = 15

-- Clearing always runs server-side (it is an admin action), so there is no
-- client path here: detach the vehicle from the world, then delete it from the
-- save so it does not reappear on reload.
local function removeVehicle(v)
    DE.guard("cleanupVehicle world", function() v:removeFromWorld() end)
    DE.guard("cleanupVehicle perm", function() v:permanentlyRemove() end)
end

-- Fallback for vehicles whose recorded id no longer resolves: sweep the site
-- for vehicles carrying one of this event's tags. Catches ids that were never
-- assigned at spawn time or were reassigned since.
local function sweepTaggedVehicles(x, y, z, tags)
    local c = getCell()
    if not c then return 0 end

    local seen, removed = {}, 0
    for dx = -VEHICLE_SWEEP_RADIUS, VEHICLE_SWEEP_RADIUS do
        for dy = -VEHICLE_SWEEP_RADIUS, VEHICLE_SWEEP_RADIUS do
            local sq = c:getGridSquare(x + dx, y + dy, z)
            local veh = sq and sq:getVehicleContainer()
            if veh then
                local id = veh:getId()
                if not seen[id] then
                    seen[id] = true
                    if veh:hasModData() then
                        local tag = veh:getModData().de_event
                        if tag and tags[tag] then
                            removeVehicle(veh)
                            removed = removed + 1
                        end
                    end
                end
            end
        end
    end
    return removed
end

-- Removes everything an event left behind. Clearing requires admin presence,
-- so the site is streamed in; anything not reachable from here is left to the
-- game. Returns nothing.
function EH.cleanupEvent(x, y, z, objects)
    if not objects then return end

    local vehicles, vehicleTags = {}, {}
    local zombieCount = 0

    for _, objData in ipairs(objects) do
        if objData.type == "vehicle" then
            -- Look the vehicle up first: a player may have driven it somewhere
            -- still loaded, in which case we can remove it wherever it is.
            local v = (objData.ref and objData.ref > 0) and getVehicleById(objData.ref) or nil
            if v then
                vehicles[#vehicles + 1] = v
            elseif isLoaded(objData.x, objData.y, objData.z) and objData.tag then
                -- Loaded but the id didn't resolve: sweep by tag.
                vehicleTags[objData.tag] = true
            end

        elseif objData.type == "zombies" then
            zombieCount = zombieCount + (objData.count or 0)

        -- Legacy per-zombie records (pre-count) are ignored: cleanup is by
        -- count now, and these carry no square to anchor a removal on.
        elseif objData.type == "zombie" then

        else
            if isLoaded(objData.sqx, objData.sqy, objData.sqz) then
                if objData.type == "moveable" then
                    cleanupMoveable(objData)
                else
                    cleanupOne(objData)
                end
            end
        end
    end

    -- Remove vehicles collected above, then zombies, then the tag sweep. The
    -- sweep is the only grid walk, so it runs last.
    for _, v in ipairs(vehicles) do
        removeVehicle(v)
    end
    cleanupZombies(x, y, zombieCount)
    local hasVehicleTags = false
    for _ in pairs(vehicleTags) do hasVehicleTags = true break end
    if hasVehicleTags then
        local swept = sweepTaggedVehicles(x, y, z, vehicleTags)
        if swept > 0 then
            DE.log("swept %d vehicle(s) by tag whose recorded ids no longer resolved", swept)
        end
    end
end

DE.EventHelpers = EH

-- ============================================================================
-- Event context — the `e` object passed to spawn functions.
-- ============================================================================

local EventContext = {}
EventContext.__index = EventContext

function EventContext.new(x, y, z, rot, uid)
    return setmetatable({
        _objects = {},
        x = x, y = y, z = z,
        rot = rot or 0,
        uid = uid,   -- owning event's uid; stamped onto spawned zombies
    }, EventContext)
end

function EventContext:objects()
    return self._objects
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
local function place(self, dx, dy, opts)
    opts = opts or {}
    local wx, wy = self:_worldPos(dx, dy, opts.radius)
    return wx, wy, opts
end

function EventContext:SpawnVehicle(vehicleType, dx, dy, opts)
    local wx, wy, o = place(self, dx, dy, opts)
    EH.merge(self._objects,
        EH.spawnVehicle(wx, wy, self.z, vehicleType, o.loot, o.rot, o.skin, self.uid))
end

function EventContext:SpawnZombies(count, outfit, dx, dy, opts)
    local wx, wy, o = place(self, dx, dy, opts)
    local spawned = EH.spawnZombies(wx, wy, self.z, count, o.spread or 3, outfit) or 0
    if spawned <= 0 then return end

    -- Accumulate into a single count record, not one per zombie. Cleanup can't
    -- find individual zombies after they've been virtualized, so it just
    -- removes this many from around the site.
    for i = 1, #self._objects do
        if self._objects[i].type == "zombies" then
            self._objects[i].count = self._objects[i].count + spawned
            return
        end
    end
    self._objects[#self._objects + 1] = { type = "zombies", count = spawned }
end

function EventContext:SpawnItem(itemType, dx, dy, opts)
    local wx, wy = place(self, dx, dy, opts)
    local record = EH.spawnItem(wx, wy, self.z, itemType)
    if record then self._objects[#self._objects + 1] = record end
end

function EventContext:SpawnLootScatter(items, dx, dy, opts)
    local wx, wy, o = place(self, dx, dy, opts)
    EH.merge(self._objects,
        EH.spawnLoot(wx, wy, self.z, items, o.spread or 2, o.chance or 30))
end

-- Spawns a loot-filled container (bag/case/toolbox) at an offset. opts.chance
-- is the per-item fill chance (default 100, i.e. every item).
function EventContext:SpawnContainer(containerType, lootItems, dx, dy, opts)
    local wx, wy, o = place(self, dx, dy, opts)
    local record = EH.spawnContainer(wx, wy, self.z, containerType, lootItems, o.chance)
    if record then self._objects[#self._objects + 1] = record end
end

function EventContext:SpawnFire(count, dx, dy, opts)
    local wx, wy = place(self, dx, dy, opts)
    EH.spawnFire(wx, wy, self.z, count)
end

function EventContext:SpawnSmoke(count, dx, dy, opts)
    local wx, wy = place(self, dx, dy, opts)
    EH.spawnSmoke(wx, wy, self.z, count)
end

function EventContext:SpawnScorch(dx, dy, opts)
    local wx, wy, o = place(self, dx, dy, opts)
    EH.merge(self._objects,
        EH.spawnScorchMarks(wx, wy, self.z, o.spread or 1))
end

DE.EventContext = EventContext
