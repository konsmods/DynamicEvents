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

function EH.spawnVehicle(x, y, z, vehicleType, lootItems)
    local objects = {}
    local sq = squareAt(x, y, z)
    if not sq then return objects end

    DE.guard("spawnVehicle " .. (vehicleType or "nil"), function()
        local vehicle = addVehicle(vehicleType, x, y, z)
        if not vehicle then return end

        objects[#objects + 1] = { type = "vehicle", ref = vehicle:getId() }

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

function EH.spawnZombies(x, y, z, count, radius)
    local r = radius or 2
    addZombiesInOutfitArea(x - r, y - r, x + r, y + r, z, count or 3, nil, nil)
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
                v:getScript():setScriptName(nil)
            end)
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

function EH.cleanupEvent(x, y, z, objects, customFn)
    if customFn then
        DE.guard("customCleanup", function()
            customFn(x, y, z, objects)
        end)
    end
    if objects then
        for _, objData in ipairs(objects) do
            cleanupOne(objData)
        end
    end
end

DE.EventHelpers = EH
