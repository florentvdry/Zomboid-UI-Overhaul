-- Shared fixture for the tactical-screen tests: French strings, key bindings,
-- a mocked survivor (worn items, injuries, stats, traits, profession, actions).
-- Returns { playerInv, chr, worn, noHookErrors }.

dofile(HARNESS_DIR .. "/mocks_game.lua")

getText = function(key, ...)
    local s = TRANSLATIONS_FR[key] or key
    local args = { ... }
    for i = 1, #args do s = s:gsub("%%" .. i, tostring(args[i])) end
    return s
end

Keyboard = { KEY_ESCAPE = 1001, KEY_TAB = 15 }
KeybindId = { TOGGLE_INVENTORY = 1, TOGGLE_SKILL_PANEL = 2, TOGGLE_HEALTH_PANEL = 3, CRAFTING_UI = 4, MAP = 5, BUILDING_UI = 6 }
local KEYNAMES = { "Tab", "L", "H", "B", "M", "N" }
getCore().getKey = function(_, id) return id end
getCore().isKey = function(_, id, key) return id == key end
getCore().getOptionDisplayAsCelsius = function() return true end
getKeyName = function(c) return KEYNAMES[c] end
getGameTime = function() return { getHour = function() return 2 end, getMinutes = function() return 40 end } end
getClimateManager = function() return { getTemperature = function() return 19 end } end
getSoundManager = function() return { playUISound = function() end } end
getGameSpeed = function() return 1 end

require "N26/N26_Boot"
require "ISUI/ISScrollBar"
require "ISUI/ISButton"
require "ISUI/ISResizeWidget"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISContextMenu"
require "ISUI/ISInventoryPaneContextMenu"

local function noHookErrors()
    for key, h in pairs(N26.Hooks) do
        if h.errors > 0 then error("hook " .. key .. " errored: " .. tostring(h.lastError)) end
    end
end

-- ------------------------------------------------------------------ player

local function worn(name, loc, cat)
    local item = MockItem(name, cat or "Clothing", 0.4)
    item.getBodyLocation = function() return loc end
    return { getItem = function() return item end, getLocation = function() return loc end, item = item }
end
local WORN = {
    worn("Casquette", "Hat"), worn("T-shirt", "Tshirt"), worn("Veste en cuir", "Jacket"),
    worn("Jean", "Pants"), worn("Baskets", "Shoes"), worn("Chaussettes", "Socks"),
    worn("Gants de travail", "Hands"), worn("Sac à dos", "Back", "Container"),
    worn("Ceinture", "Belt"), worn("Montre", "RightWrist"),
}
local bat = MockItem("Batte de baseball", "Weapon", 1.5)

local function bodyPart(name, health, cond)
    cond = cond or {}
    return setmetatable({}, { __index = function(_, k)
        if k == "getType" then return function() return name end end
        if k == "getHealth" then return function() return health end end
        if cond[k] ~= nil then return function() return cond[k] end end
        if k:sub(1, 3) == "get" then return function() return 0 end end
        return function() return false end
    end })
end
local PARTS = {
    bodyPart("Head", 100), bodyPart("Torso_Upper", 100),
    bodyPart("LowerLeg_L", 58, { bleeding = true }),
    bodyPart("Hand_R", 86, { scratched = true, bandaged = true }),
}
local FR_PARTS = { Head = "Tête", Torso_Upper = "Haut du torse", LowerLeg_L = "Jambe gauche", Hand_R = "Main droite" }
BodyPartType = { getDisplayName = function(t) return FR_PARTS[t] or t end }

local playerInv = MockContainer({
    MockItem("Bandage", "FirstAid", 0.1), MockItem("Bandage", "FirstAid", 0.1),
    MockItem("Conserve de haricots", "Food", 0.5), MockItem("Marteau", "Tool", 1.0),
    MockItem("Lampe torche", "Tool", 0.6), MockItem("Bouteille d'eau", "Food", 1.0),
}, 20)
local chr = MockPlayer(playerInv)
chr.getWornItems = function() return MockList(WORN) end
chr.getPrimaryHandItem = function() return bat end
chr.getSecondaryHandItem = function() return bat end
chr.getInventoryWeight = function() return 12.4 end
chr.getBodyDamage = function()
    return { getBodyParts = function() return MockList(PARTS) end, getOverallBodyHealth = function() return 74 end }
end
chr.getDescriptor = function()
    return { getForename = function() return "Marcus" end, getSurname = function() return "Doyle" end,
             getCharacterProfession = function() return "mechanic" end }
end
chr.getHoursSurvived = function() return 318 end
chr.getZombieKills = function() return 312 end
chr.getNutrition = function() return { getWeight = function() return 78 end } end
chr.getCharacterTraits = function()
    return { getKnownTraits = function() return MockList({ "strong", "handy", "clumsy" }) end }
end
CharacterStat = { HUNGER = "HUNGER", THIRST = "THIRST", FATIGUE = "FATIGUE", ENDURANCE = "ENDURANCE" }
local STATS = { HUNGER = 0.35, THIRST = 0.6, FATIGUE = 0.2, ENDURANCE = 0.8 }
chr.getStats = function() return { get = function(_, k) return STATS[k] end } end
getSpecificPlayer = function() return chr end

local TRAITS = {
    strong = { "Costaud", "Porte plus lourd, frappe plus fort.", 10 },
    handy = { "Bricoleur", "Fabrique et répare plus vite.", 6 },
    clumsy = { "Maladroit", "Fait plus de bruit en marchant.", -2 },
}
CharacterTraitDefinition = { getCharacterTraitDefinition = function(id)
    local t = TRAITS[id]
    return { getLabel = function() return t[1] end, getDescription = function() return t[2] end,
             getCost = function() return t[3] end, getTexture = function() return nil end }
end }
CharacterProfessionDefinition = { getCharacterProfessionDefinition = function()
    return { getUIName = function() return "Mécanicien" end, getTexture = function() return nil end }
end }

Perks = { None = "None", MAX = "MAX", Crafting = "Crafting", Survivalist = "Survivalist",
    Combat = "Combat", Firearm = "Firearm", Passiv = "Passiv", Agility = "Agility",
    PhysicalCategory = "PhysicalCategory" }
local samplePerks = {
    { "Mechanics", "Mécanique", "Crafting", 4 }, { "Woodwork", "Menuiserie", "Crafting", 3 },
    { "Cooking", "Cuisine", "Crafting", 1 }, { "Electricity", "Électricité", "Crafting", 0 },
    { "Doctor", "Premiers soins", "Crafting", 2 }, { "PlantScavenging", "Cueillette", "Survivalist", 1 },
    { "Fishing", "Pêche", "Survivalist", 0 }, { "Trapping", "Piégeage", "Survivalist", 0 },
    { "Blunt", "Contondant", "Combat", 3 }, { "Axe", "Hache", "Combat", 2 },
    { "SmallBlade", "Lame courte", "Combat", 0 }, { "Strength", "Force", "PhysicalCategory", 6 },
    { "Fitness", "Forme", "PhysicalCategory", 5 }, { "Sprinting", "Sprint", "PhysicalCategory", 2 },
    { "Sneak", "Furtivité", "PhysicalCategory", 1 },
}
local perkObjects, levels = {}, {}
for _, spec in ipairs(samplePerks) do
    local p = { getType = function() return spec[1] end, getId = function() return spec[1] end,
        getName = function() return spec[2] end, getParent = function() return spec[3] end }
    for n = 1, 10 do p["getXp" .. n] = function() return 100 end end
    p.getXpForLevel = function() return 100 end
    perkObjects[#perkObjects + 1], levels[spec[1]] = p, spec[4]
end
PerkFactory = { PerkList = MockList(perkObjects) }
chr.getPerkLevel = function(_, p) return levels[p] or 0 end
chr.getXp = function() return {
    getXP = function(_, p) return (levels[p] or 0) * 100 + 60 end,
    getMultiplier = function() return 3 end, getPerkBoost = function() return 1 end,
} end
getTextOrNull = function(key)
    if key == "IGUI_perks_Mécanique_Description" then return "Entretenez et réparez les véhicules pour progresser en mécanique." end
    return nil
end

ISTimedActionQueue = ISTimedActionQueue or {}
ISTimedActionQueue.getTimedActionQueue = function()
    return { queue = {
        { Type = "ISInventoryTransferAction", item = MockItem("Bandage", "FirstAid", 0.1), action = { getJobDelta = function() return 0.45 end } },
        { Type = "ISWearClothing", item = MockItem("Veste en cuir", "Clothing", 1) },
        { Type = "ISEatFoodAction", item = MockItem("Conserve de haricots", "Food", 0.5) },
    } }
end


return { playerInv = playerInv, chr = chr, worn = worn, noHookErrors = noHookErrors }
