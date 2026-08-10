DE = DE or {}

local EH = DE.EventHelpers

-- ============================================================================
-- Helicopter Crash Event
--
-- CUSTOM 3D MODEL SETUP:
-- 1. Export your helicopter as .fbx from Blender
--    - Apply all modifiers, triangulate, convert textures to PNG
--    - Place .fbx in 42/media/models/helicopter_wreck.fbx
--    - Place texture in 42/media/textures/helicopter_wreck.png
-- 2. Scripts at 42/media/scripts/ already set up:
--    models_heli.txt  — registers the 3D model
--    items_heli.txt   — defines the world-placed item
-- 3. Uncomment the model spawn block below and comment the vehicle line
-- ============================================================================

local militaryLoot = {
    "Base.HuntingKnife", "Base.Pistol", "Base.9mmClip",
    "Base.Bag_ALICEpack_Army", "Base.CannedFruitCocktail",
    "Base.WaterBottle", "Base.Bandage", "Base.FirstAidKit",
    "Base.AssaultRifle", "Base.556Clip",
}

local zombieOutfits = { "Soldier", "Ranger", "Police" }

local EVENT = {
    id             = "heli_crash",
    name           = "Helicopter Crash",
    weight         = 10,
    sound          = "Helicopter",
    cooldownHours  = 48,
    lifetimeHours  = 48,
    minDaysSurvived = 1,

    locations = {
        { name = "Muldraugh field",    x = 10600, y = 9300,  z = 0 },
        { name = "Muldraugh N field",  x = 10800, y = 9500,  z = 0 },
        { name = "Riverside farm",     x =  8400, y = 5400,  z = 0 },
        { name = "Riverside field",    x =  8200, y = 5600,  z = 0 },
        { name = "West Point field",   x = 11500, y = 8000,  z = 0 },
        { name = "West Point woods",   x = 11700, y = 8200,  z = 0 },
        { name = "Rosewood field",     x =  9000, y = 11000, z = 0 },
        { name = "Rosewood S field",   x =  9200, y = 11200, z = 0 },
    },

    warning = {
        delay = 90,
    },

    spawn = function(x, y, z)
        local objects = {}

        -- Wreckage: placeholder burnt vehicle
        EH.merge(objects, EH.spawnVehicle(x, y, z, "Base.AmbulanceBurnt", nil))

        -- UNCOMMENT THIS when your custom model is ready (and comment the vehicle line above):
        -- local sq = getCell():getOrCreateGridSquare(x, y, z)
        -- if sq then
        --     local item = instanceItem("Base.HelicopterWreck")
        --     if item then
        --         sq:AddWorldInventoryItem(item, 0.5, 0.5, 0)
        --         table.insert(objects, { type = "item", sqx = x, sqy = y, sqz = z, itemType = "Base.HelicopterWreck" })
        --     end
        -- end

        -- Scorched earth
        EH.merge(objects, EH.spawnScorchMarks(x, y, z, 1))

        -- Fire and smoke
        EH.spawnFire(x, y, z, 2)
        EH.spawnSmoke(x, y, z, 2)

        -- Military loot scattered around crash site
        EH.merge(objects, EH.spawnLoot(x, y, z, militaryLoot, 2, 35))

        -- Zombies in military/pilot outfits
        local outfit = DE.pick(zombieOutfits)
        EH.spawnZombies(x, y, z, 6, 2, outfit)

        DE.log("heli_crash spawned at (%d, %d, %d)", x, y, z)
        return objects
    end,

    cleanup = function(x, y, z, objects)
        EH.cleanupEvent(x, y, z, objects)
    end,
}

DE.EventManager.register(EVENT)
