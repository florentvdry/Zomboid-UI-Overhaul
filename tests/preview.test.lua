-- Expected result of each tab, rendered with the real vanilla windows (inventory
-- pages, health panel, skills panel) under the N26 redesign. Snapshots only;
-- the 3D characters are drawn by the game (placeholder here).

local F = dofile(HARNESS_DIR .. "/hub_fixture.lua")
local playerInv, chr, noHookErrors = F.playerInv, F.chr, F.noHookErrors

-- a few vanilla strings in French so the previews read like the game
local VANILLA_FR = {
    IGUI_invpanel_Type = "Nom", IGUI_invpanel_Category = "Catégorie",
    IGUI_ItemCat_FirstAid = "Premiers soins", IGUI_ItemCat_Food = "Nourriture", IGUI_ItemCat_Tool = "Outil",
    IGUI_ItemCat_Weapon = "Arme", IGUI_ItemCat_Material = "Matériau", IGUI_ItemCat_Clothing = "Vêtement",
    IGUI_ItemCat_Container = "Conteneur", IGUI_health_Cut = "Coupure", IGUI_health_Bleeding = "Saignement",
    IGUI_health_Scratched = "Égratignure", IGUI_health_Bandaged = "Pansé", IGUI_health_Overall_Body_Status = "État général",
    IGUI_health_RightClickTreatement = "Clic droit sur une zone pour la soigner", ContextMenu_Fitness = "Exercice physique",
    UI_N26_Health_Pain = "Douleur", UI_N26_Health_Wet = "Mouillé", UI_N26_Health_Endurance = "Endurance",
    UI_N26_Health_Injuries = "Blessures",
}
local baseGetText = getText
getText = function(key, ...)
    if VANILLA_FR[key] then return VANILLA_FR[key] end
    return baseGetText(key, ...)
end

-- full body for the health panel
local NAMES = { "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R", "UpperArm_L", "UpperArm_R", "Torso_Upper",
    "Torso_Lower", "Head", "Neck", "Groin", "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R", "Foot_L", "Foot_R" }
local FR = { Hand_L = "Main gauche", Hand_R = "Main droite", ForeArm_L = "Avant-bras gauche", ForeArm_R = "Avant-bras droit",
    UpperArm_L = "Bras gauche", UpperArm_R = "Bras droit", Torso_Upper = "Haut du torse", Torso_Lower = "Bas du torse",
    Head = "Tête", Neck = "Cou", Groin = "Aine", UpperLeg_L = "Cuisse gauche", UpperLeg_R = "Cuisse droite",
    LowerLeg_L = "Jambe gauche", LowerLeg_R = "Jambe droite", Foot_L = "Pied gauche", Foot_R = "Pied droit" }
local function part(name, health, o)
    o = o or {}
    local fixed = {
        getType = function() return name end, getHealth = function() return health end,
        HasInjury = function() return o.injured or false end, bleeding = function() return o.bleeding or false end,
        isCut = function() return o.cut or false end, bandaged = function() return o.bandaged or false end,
        scratched = function() return o.scratched or false end, getBandageLife = function() return 1 end,
    }
    return setmetatable({ typeName = name }, { __index = function(_, k)
        if fixed[k] then return fixed[k] end
        if k:sub(1, 3) == "get" then return function() return 0 end end
        return function() return false end
    end })
end
local parts = {}
for _, n in ipairs(NAMES) do parts[#parts + 1] = part(n, 100) end
parts[14] = part("LowerLeg_L", 58, { injured = true, bleeding = true, cut = true })
parts[2] = part("Hand_R", 86, { injured = true, scratched = true, bandaged = true })
local bd = { getBodyParts = function() return MockList(parts) end, getHealth = function() return 74 end,
    getOverallBodyHealth = function() return 74 end,
    getBodyPart = function(_, t) for _, p in ipairs(parts) do if p.typeName == t then return p end end end }
chr.getBodyDamage = function() return bd end
chr.isLocalPlayer = function() return true end
chr.getMoodles = function() return { getMoodleLevel = function(_, t) return t == "PAIN" and 2 or 0 end } end
chr.getReduceInfectionPower = function() return 0 end
chr.isFemale = function() return false end
BodyPartType = { getDisplayName = function(t) return FR[t] or t end, FromIndex = function(i) return NAMES[i + 1] end }
MoodleType = { PAIN = "PAIN", ENDURANCE = "ENDURANCE", WET = "WET" }

-- skills
local function perk(name, ptype, parent, passive)
    return { getName = function() return name end, getType = function() return ptype end,
             getParent = function() return parent end, isPassiv = function() return passive == true end,
             getId = function() return ptype end, getXpForLevel = function() return 300 end,
             getTotalXpForLevel = function() return 300 end,
             getXp1 = function() return 75 end, getXp2 = function() return 150 end, getXp3 = function() return 300 end,
             getXp4 = function() return 750 end, getXp5 = function() return 1500 end, getXp6 = function() return 3000 end,
             getXp7 = function() return 4500 end, getXp8 = function() return 6000 end, getXp9 = function() return 7500 end,
             getXp10 = function() return 9000 end }
end
Perks = { None = "None", Crafting = "Crafting", Survivalist = "Survivalist", Combat = "Combat", Passiv = "Passiv" }
local PARENTS = {
    Crafting = perk("Artisanat", "Crafting", "None"), Survivalist = perk("Survie", "Survivalist", "None"),
    Combat = perk("Combat", "Combat", "None"), Passiv = perk("Physique", "Passiv", "None", true),
}
local LEVELS = { Mechanics = 4, Woodwork = 3, Cooking = 1, Electricity = 0, Doctor = 2, PlantScavenging = 1,
    Fishing = 0, Trapping = 0, Blunt = 3, Axe = 1, SmallBlade = 0, Strength = 6, Fitness = 5, Sprinting = 2, Sneak = 1 }
local CHILDREN = {
    perk("Mécanique", "Mechanics", "Crafting"), perk("Menuiserie", "Woodwork", "Crafting"),
    perk("Cuisine", "Cooking", "Crafting"), perk("Électricité", "Electricity", "Crafting"),
    perk("Premiers soins", "Doctor", "Survivalist"), perk("Cueillette", "PlantScavenging", "Survivalist"),
    perk("Pêche", "Fishing", "Survivalist"), perk("Pièges", "Trapping", "Survivalist"),
    perk("Contondant", "Blunt", "Combat"), perk("Hache", "Axe", "Combat"), perk("Lame courte", "SmallBlade", "Combat"),
    perk("Force", "Strength", "Passiv", true), perk("Forme", "Fitness", "Passiv", true),
    perk("Sprint", "Sprinting", "Passiv", true), perk("Furtivité", "Sneak", "Passiv", true),
}
PerkFactory = { PerkList = MockList(CHILDREN), getPerk = function(t) return PARENTS[t] end }
chr.getPerkLevel = function(_, p) return LEVELS[type(p) == "table" and p:getType() or p] or 0 end
chr.getXp = function()
    return { getPerkBoost = function(_, t) return (t == "Mechanics" or t == "Woodwork") and 1 or 0 end,
             getMultiplier = function() return 0 end, getXP = function() return 120 end }
end
chr.getPlayerNum = function() return 0 end
chr.getVehicle = function() return nil end
chr.getX = function() return 10500 end
chr.getY = function() return 9600 end
chr.getZ = function() return 0 end
chr.getCurrentSquare = function() return nil end
chr.getDir = function() return "S" end
getPerformance = function() return { getUIRenderFPS = function() return 30 end } end

require "XpSystem/ISUI/ISHealthPanel"
require "XpSystem/ISUI/ISCharacterInfo"
require "XpSystem/ISUI/ISSkillProgressBar"

local Hub = N26.Hub

-- ------------------------------------------------------------------ real windows

getPlayerLoot = function() return { inventoryPane = { selected = {} } } end
getPlayerInventory = getPlayerLoot
getPlayerInfoPanel = function() return nil end
ContainerButtonIcons = ContainerButtonIcons or {}

local function realPage(inv, onChar, title, extra)
    local page = ISInventoryPage:new(100, 100, 420, 600, inv, onChar, 1)
    page.player = 0
    -- the loot page normally scans the world squares around the player
    if not onChar then page.refreshBackpacks = function() end end
    page:initialise()
    local ok, err = pcall(function() page:addToUIManager() end)
    if not ok then print("page create: " .. tostring(err)) end
    page.title = title
    page.capacity = inv:getCapacity()
    page.isCollapsed = false
    page.buttonPool = page.buttonPool or {}
    page.backpacks = page.backpacks or {}
    if #page.backpacks == 0 then
        page:addContainerButton(inv, getTexture("media/ui/Icon_InventoryBasic.png"), title, nil)
        for _, c in ipairs(extra or {}) do
            page:addContainerButton(c, getTexture("media/ui/Icon_InventoryBasic.png"), "Conteneur", nil)
        end
    end
    page.inventoryPane:refreshContainer()
    page:setVisible(false)
    return page
end

local lootInv = MockContainer({
    MockItem("Planche", "Material", 3), MockItem("Clous", "Material", 0.2), MockItem("Clous", "Material", 0.2),
    MockItem("Couteau de cuisine", "Weapon", 0.3), MockItem("Pull", "Clothing", 0.6), MockItem("Chips", "Food", 0.2),
}, 50, "floor")
local invPage = realPage(playerInv, true, "Inventaire", { MockContainer({}, 12, "backpack") })
local lootPage = realPage(lootInv, false, "Sol", { MockContainer({}, 30, "crate") })
getPlayerInventory = function() return invPage end
getPlayerLoot = function() return lootPage end

-- vanilla info window stand-in hosting the real health and skills views
xpSystemText = { skills = "Compétences", health = "Santé", info = "Info", lvl = "Niv." }
local info = ISCollapsableWindow:new(100, 100, 620, 560)
info:initialise()
info:setTitle("Personnage")
info:addToUIManager()
info:setVisible(false)
local healthView = ISHealthPanel:new(chr, 0, info:titleBarHeight(), 620, 520)
healthView:initialise()
info:addChild(healthView)
do -- the Java body silhouette: a plain peer that also answers the status string
    local jo = UIElement.new(healthView.healthPanel)
    jo.getDamageStatusString = function() return "Blessures légères" end
    healthView.healthPanel.javaObject = jo
end
local skillsView = ISCharacterInfo:new(0, info:titleBarHeight(), 620, 640, 0)
skillsView:initialise()
info:addChild(skillsView)
info.healthView = healthView
info.panel = {
    y = info:titleBarHeight(), tabHeight = 0,
    setWidth = function(self, w) self.width = w end,
    setHeight = function(self, h) self.height = h end,
    active = skillsView,
    getActiveView = function(self) return self.active end,
    activateView = function(self, name)
        self.active = (name == xpSystemText.health) and healthView or skillsView
        healthView:setVisible(self.active == healthView)
        skillsView:setVisible(self.active == skillsView)
    end,
}
info.close = function(self) self:setVisible(false) end
getPlayerInfoPanel = function() return info end

local function fitPages()
    for _, p in ipairs({ invPage, lootPage }) do
        p:onInventoryContainerSizeChanged()
        local pane = p.inventoryPane
        pane:setHeight(p.height - pane.y - 24)
        p.containerButtonPanel:setHeight(pane.height)
    end
end

local function placeholder(el, text)
    ISUIElement.drawTextCentre(el, text, el.width / 2, el.height / 2, 0.55, 0.58, 0.55, 1, UIFont.Small)
end

local function shot(name, wins)
    local h = Hub.instance
    renderTree(h)
    for _, w in ipairs(wins) do renderTree(w) end
    resetDrawLog()
    renderTree(h)
    for _, w in ipairs(wins) do renderTree(w) end
    if h.tab == "inventory" then placeholder(h.equip.model, "[ personnage 3D ]") end
    if h.tab == "character" then placeholder(h.ident.model, "[ personnage 3D ]") end
    if h.tab == "health" and healthView.n26Body then placeholder(healthView.n26Body, "[ personnage 3D ]") end
    if h.tab == "crafting" and wins[1] then
        local w = wins[1]
        placeholder(w, "[ fenêtre de fabrication du jeu (XUI), avec la refonte N26 : à vérifier en jeu ]")
    end
    snapshot(name, 1920, 1080)
end

test("preview: inventory tab", function()
    Hub.watch()
    Hub.open("inventory")
    fitPages()
    invPage.inventoryPane.selected[2] = invPage.inventoryPane.itemslist[2].items[1]
    shot("20_onglet_inventaire", { invPage, lootPage })
    noHookErrors()
end)

test("preview: health tab", function()
    for _, it in ipairs(playerInv.items) do
        if it.name == "Bandage" then it.getBandagePower = function() return 2 end end
    end
    local splint = MockItem("Attelle", "FirstAid", 0.5)
    splint.type = "Splint"
    table.insert(lootInv.items, splint)
    local pills = MockItem("Antidouleurs", "FirstAid", 0.1)
    pills.type = "Pills"
    table.insert(playerInv.items, pills)
    Hub.setTab("health")
    healthView.listbox:clear()
    healthView.listbox:addItem("dummy", { bodyPart = parts[14] })
    healthView.listbox:addItem("dummy", { bodyPart = parts[2] })
    healthView.listbox.selected = 1
    info:setTitle("Santé")
    shot("21_onglet_sante", { info })
    noHookErrors()
end)

test("preview: character tab", function()
    Hub.setTab("character")
    info:setTitle("Compétences")
    info:setHeight(skillsView.height + info:titleBarHeight())
    shot("22_onglet_personnage", { info })
    noHookErrors()
end)

-- Crafting now has its own rendered page and engine interaction tests in
-- hub_pages.test.lua (13_hub_crafting.png), replacing the old empty frame.
