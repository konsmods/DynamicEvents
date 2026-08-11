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
-- Spawn helpers — all follow: EH.spawnX(x, y, z, ...) → tracked objects[]
-- ============================================================================

function EH.spawnLoot(x, y, z, items, radius, chance)
    local objects = {}
    local r = radius or 2
    local pct = chance or 30

    for dx = -r, r do
        for dy = -r, r do
            local sq = squareAt(x + dx, y + dy, z)
            if sq and DE.chance(pct) then
                local itemType = DE.pick(items)
                local item = instanceItem(itemType)
                if item then
                    sq:AddWorldInventoryItem(item, 0.3, 0.3, 0)
                    objects[#objects + 1] = {
                        type = "item",
                        sqx = sq:getX(), sqy = sq:getY(), sqz = sq:getZ(),
                        itemType = itemType,
                    }
                end
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
            sq:AddTileObject(obj)
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

function EH.spawnVehicle(x, y, z, vehicleType, lootItems, direction, skinIndex)
    local objects = {}
    local sq = squareAt(x, y, z)
    if not sq then return objects end

    DE.guard("spawnVehicle " .. (vehicleType or "nil"), function()
        local vehicle = addVehicle(vehicleType, x, y, z)
        if not vehicle then return end

        if direction then
            vehicle:setAngles(0, direction, 0)
        end

        if skinIndex then
            vehicle:setSkinIndex(skinIndex)
            vehicle:updateSkin()
        end

        local vId = 0
        local ok, result = pcall(vehicle.getId, vehicle)
        if ok then
            vId = result
        else
            DE.warn("vehicle:getId() failed for %s, cleanup may not work", vehicleType)
        end
        DE.dbg("spawned vehicle id=%d type=%s at (%d, %d, %d)", vId, vehicleType, x, y, z)
        objects[#objects + 1] = { type = "vehicle", ref = vId, x = x, y = y, z = z }

        local storage = vehicle:getPartById("TruckBed") or vehicle:getPartById("Trunk")
        if storage and storage:getItemContainer() and lootItems then
            local container = storage:getItemContainer()
            for _, itemName in ipairs(lootItems) do
                if DE.chance(40) then
                    local item = instanceItem(itemName)
                    if item then container:AddItem(item) end
                end
            end
        end

        local gloveBox = vehicle:getPartById("GloveBox")
        if gloveBox and gloveBox:getItemContainer() and lootItems then
            local gContainer = gloveBox:getItemContainer()
            for _, itemName in ipairs(lootItems) do
                if DE.chance(20) then
                    local item = instanceItem(itemName)
                    if item then gContainer:AddItem(item) end
                end
            end
        end

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

function EH.spawnZombies(x, y, z, count, radius, outfit)
    local r = radius or 2
    addZombiesInOutfitArea(x - r, y - r, x + r, y + r, z, count or 3, outfit, nil)
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

function EH.spawnFire(x, y, z, count)
    local c = cell()
    if not c then return end
    for i = 1, (count or 1) do
        local fx, fy = x + DE.rand(-1, 1), y + DE.rand(-1, 1)
        local sq = squareAt(fx, fy, z)
        if sq then
            DE.guard("spawnFire", function()
                IsoFireManager.StartFire(c, sq, true, 100, 200)
            end)
        end
    end
end

function EH.spawnSmoke(x, y, z, count)
    local c = cell()
    if not c then return end
    for i = 1, (count or 2) do
        local sx, sy = x + DE.rand(-1, 1), y + DE.rand(-1, 1)
        local sq = squareAt(sx, sy, z)
        if sq then
            DE.guard("spawnSmoke", function()
                IsoFireManager.StartSmoke(c, sq, true, 100, 200)
            end)
        end
    end
end

-- ============================================================================
-- Utility
-- ============================================================================

function EH.merge(target, source)
    if not source then return end
    for i = 1, #source do
        table.insert(target, source[i])
    end
end

-- ============================================================================
-- Cleanup
-- ============================================================================

local function cleanupOne(objData)
    local c = cell()
    if not c then return end

    if objData.type == "vehicle" then
        local v = getVehicleById(objData.ref)
        if v then
            DE.guard("cleanupVehicle", function()
                v:permanentlyRemove()
                v:removeFromWorld()
            end)
        else
            DE.warn("cleanup: vehicle %d not found", objData.ref)
        end
    elseif objData.type == "item" then
        local sq = c:getGridSquare(objData.sqx, objData.sqy, objData.sqz)
        if sq then
            for i = sq:getObjects():size() - 1, 0, -1 do
                local obj = sq:getObjects():get(i)
                if instanceof(obj, "IsoWorldInventoryObject") then
                    local invItem = obj:getItem()
                    if invItem and invItem:getFullType() == objData.itemType then
                        sq:transmitRemoveItemFromSquare(obj)
                        break
                    end
                end
            end
        end
    elseif objData.type == "sprite" then
        local sq = c:getGridSquare(objData.sqx, objData.sqy, objData.sqz)
        if sq then
            for i = sq:getObjects():size() - 1, 0, -1 do
                local obj = sq:getObjects():get(i)
                if obj and obj:getSprite() and obj:getSprite():getName() == objData.sprite then
                    sq:transmitRemoveItemFromSquare(obj)
                    break
                end
            end
        end
    end
end

function EH.cleanupEvent(x, y, z, objects)
    DE.dbg("cleanupEvent at (%d,%d,%d) with %d objects", x, y, z, objects and #objects or 0)
    if objects then
        for _, objData in ipairs(objects) do
            cleanupOne(objData)
        end
    end
end

DE.EventHelpers = EH

-- ============================================================================
-- Event context — the `e` object passed to spawn functions.
-- ============================================================================

local EventContext = {}
EventContext.__index = EventContext

function EventContext.new(x, y, z, rot)
    return setmetatable({
        _objects = {},
        x = x, y = y, z = z,
        rot = rot or 0,
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

function EventContext:SpawnVehicle(vehicleType, dx, dy, opts)
    opts = opts or {}
    local wx, wy = self:_worldPos(dx, dy, opts.radius)
    local spawned = EH.spawnVehicle(wx, wy, self.z, vehicleType,
        opts.loot, opts.rot, opts.skin)
    EH.merge(self._objects, spawned)
end

function EventContext:SpawnZombies(count, outfit, dx, dy, opts)
    opts = opts or {}
    local wx, wy = self:_worldPos(dx, dy, opts.radius)
    local spread = opts.spread or 3
    EH.spawnZombies(wx, wy, self.z, count, spread, outfit)
end

function EventContext:SpawnItem(itemType, dx, dy, opts)
    opts = opts or {}
    local wx, wy = self:_worldPos(dx, dy, opts.radius)
    local sq = squareAt(wx, wy, self.z)
    if sq then
        local item = instanceItem(itemType)
        if item then
            sq:AddWorldInventoryItem(item, 0.3, 0.3, 0)
            self._objects[#self._objects + 1] = {
                type = "item",
                sqx = wx, sqy = wy, sqz = self.z,
                itemType = itemType,
            }
        end
    end
end

function EventContext:SpawnLootScatter(items, dx, dy, opts)
    opts = opts or {}
    local wx, wy = self:_worldPos(dx, dy, opts.radius)
    local radius = opts.spread or 2
    local chance = opts.chance or 30
    EH.merge(self._objects,
        EH.spawnLoot(wx, wy, self.z, items, radius, chance))
end

function EventContext:SpawnFire(count, dx, dy, opts)
    opts = opts or {}
    local wx, wy = self:_worldPos(dx, dy, opts.radius)
    EH.spawnFire(wx, wy, self.z, count)
end

function EventContext:SpawnSmoke(count, dx, dy, opts)
    opts = opts or {}
    local wx, wy = self:_worldPos(dx, dy, opts.radius)
    EH.spawnSmoke(wx, wy, self.z, count)
end

function EventContext:SpawnScorch(dx, dy, opts)
    opts = opts or {}
    local wx, wy = self:_worldPos(dx, dy, opts.radius)
    EH.merge(self._objects,
        EH.spawnScorchMarks(wx, wy, self.z, opts.spread or 1))
end

DE.EventContext = EventContext
