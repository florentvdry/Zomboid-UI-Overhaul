-- Behaviour tests for the custom pages, with explicit engine doubles.
local F = dofile(HARNESS_DIR .. "/hub_fixture.lua")
local Hub, chr = N26.Hub, F.chr

local inv = ISCollapsableWindow:new(0, 0, 400, 600)
inv:initialise(); inv:setVisible(false)
getPlayerInventory = function() return inv end
getPlayerLoot = function() return nil end
local info = ISCollapsableWindow:new(0, 0, 400, 600)
info:initialise(); info:setVisible(false); info.playerNum = 0
xpSystemText = { health = "Santé", skills = "Compétences" }
info.healthView = ISPanel:new(0, 30, 400, 500)
info.healthView:initialise()
info.panel = {
    y = 20, tabHeight = 30,
    getActiveView = function(self) return self.active end,
    activateView = function(self) self.active = info.healthView end,
    setWidth = function(self, w) self.width = w end,
    setHeight = function(self, h) self.height = h end,
}
getPlayerInfoPanel = function() return info end
Hub.watch()

test("native skill and health shortcuts open custom pages and toggle closed", function()
    ISCharacterInfoWindow.toggleView(info, xpSystemText.skills)
    expect(Hub.isOpen() and Hub.instance.tab == "character", "custom character opened")
    expect(not info:isVisible(), "native character sheet never shown")
    ISCharacterInfoWindow.toggleView(info, xpSystemText.health)
    expectEq(Hub.instance.tab, "health", "health selected")
    expect(info:isVisible(), "treatment panel visible")
    ISCharacterInfoWindow.toggleView(info, xpSystemText.health)
    expect(not Hub.isOpen(), "same shortcut closes")
    F.noHookErrors()
end)

test("custom character groups use live levels and XP; clicking selects a skill", function()
    Hub.open("character")
    local skills = Hub.instance.skills
    skills:prerender()
    expectEq(#skills.groups[1].perks, 4, "craft skills")
    expectEq(#skills.groups[2].perks, 4, "first aid included in survival")
    expectEq(#skills.groups[3].perks, 3, "combat skills")
    expectEq(#skills.groups[4].perks, 4, "physical skills")
    local physical = {}
    for _, perk in ipairs(skills.groups[4].perks) do physical[perk:getId()] = true end
    expect(physical.Fitness and physical.Strength and physical.Sprinting and physical.Sneak,
        "Build 42.21 PhysicalCategory stays out of crafting")
    expectEq(skills.selected:getId(), "Mechanics", "best craft skill selected initially")
    local data = skills:xpData(skills.selected)
    expectEq(data.level, 4, "survivor level")
    expectEq(data.earned, 60, "XP above current level")
    expectEq(data.needed, 100, "XP for next level")
    local row = skills.rows[1]
    skills:onMouseDown(row.x + 10, row.y + 5)
    expect(skills.selected == row.perk, "detail follows clicked row")
    Hub.close()
end)

test("XP and reading bonuses display numbers without translation format tokens", function()
    Hub.open("character")
    local skills = Hub.instance.skills
    local originalXp = chr.getXp
    chr.getXp = function() return {
        getXP = function() return 460 end, getMultiplier = function() return 3 end,
        getPerkBoost = function() return 3 end,
    } end
    resetDrawLog()
    skills:drawDetail(0, 600)
    chr.getXp = originalXp
    expect(drawnText("Gain d’expérience : 125 %"), "French XP rate")
    expect(drawnText("Bonus de lecture : x3"), "reading multiplier")
    for _, d in ipairs(DRAWLOG) do
        for _, a in ipairs(d.args) do
            if type(a) == "string" then
                expect(not a:find("%1", 1, true) and not a:find("$s", 1, true), "no leaked placeholder")
            end
        end
    end
    Hub.close()
end)

local map = ISPanel:new(0, 0, 1920, 1080)
map:initialise(); map:setVisible(false)
local speed, renderedW, renderedH = 1, nil, nil
getGameSpeed = function() return speed end
map.render = function(self)
    -- Same fullscreen resize request made by the real ISWorldMap.render.
    self:setWidth(1920); self:setHeight(1080)
    renderedW, renderedH = self.width, self.height
end
map.close = function(self) self:setVisible(false); speed = 1 end
ISWorldMap = {
    ShowWorldMap = function()
        map:setVisible(true); speed = 0
        ISWorldMap_instance = map
    end,
}

test("map stays inside the menu and its native fullscreen resize is bounded", function()
    Hub.open("map")
    local m = Hub.instance:metrics()
    expect(Hub.isOpen() and Hub.instance.tab == "map", "menu stays open")
    expect(map:isVisible() and Hub.isDocked(map), "map docked")
    expectEq(map.y, m.y0, "map below menu tabs")
    map:render()
    expectEq(renderedW, m.cw, "native render preserves allocated width")
    expectEq(renderedH, m.ch, "native render preserves allocated height")
    Hub.setTab("character")
    expect(not map:isVisible(), "map closes when switching tabs")
    expectEq(speed, 1, "map pause released")
    expectEq(map.width, 1920, "original map geometry restored")
    Hub.close()
end)

test("Tab closes the integrated map even when map settings pause the game", function()
    Hub.open("map")
    expectEq(speed, 0, "map paused game")
    Hub.onKeyPressed(Keyboard.KEY_TAB); Hub.flushKeys()
    expect(not Hub.isOpen() and not map:isVisible(), "Tab closes menu and map")
    expectEq(speed, 1, "game resumed")
    Hub.open("map")
    map:close() -- native Escape / M / close button
    Hub.watch()
    expect(not Hub.isOpen(), "native map close also closes hub")
end)

local vanillaFR = {
    IGUI_CraftingWindow_SearchRecipes = "Rechercher une recette",
    IGUI_CraftingCategories_All = "Toutes les recettes", IGUI_CraftingCategories_Favourites = "Favoris",
    IGUI_CraftingCategories_Carpentry = "Menuiserie", IGUI_CraftingCategories_Survival = "Survie",
    IGUI_FilterType_RecipeName = "Nom de recette", IGUI_SortType_RecipeName = "Tri : nom",
    IGUI_CraftingUI_ShowAllRecipe = "Afficher tout", IGUI_CraftingWindow_Requires = "Ingrédients",
    IGUI_CraftingWindow_Creates = "Résultats", IGUI_CraftingWindow_Quantity = "Quantité :",
    IGUI_CraftingWindow_TimeRequired = "Temps :", IGUI_CraftingWindow_Craft = "Fabriquer",
}
for k, v in pairs(vanillaFR) do TRANSLATIONS_FR[k] = v end
ResourceType = { Item = "Item", Fluid = "Fluid" }
local item = { getDisplayName = function() return "Planche" end,
    getNormalTexture = function() return getTexture("media/textures/Item_Plank.png") end }
local input = {
    getResourceType = function() return "Item" end, getIntMaxAmount = function() return 3 end,
    getPossibleInputItems = function() return MockList({ item }) end,
}
local function recipe(name, texture)
    return {
        getTranslationName = function() return name end,
        getIconTexture = function() return getTexture("media/textures/Item_" .. texture .. ".png") end,
        getInputs = function() return MockList({ input }) end,
        getOutputs = function() return MockList({}) end,
        getRequiredSkillCount = function() return 0 end,
        getTime = function() return 45 end, isAllowBatchCraft = function() return true end,
    }
end
local r1, r2 = recipe("Barricade de fenêtre", "Plank"), recipe("Caisse en bois", "Crate")
local windows, lastQuantity, startCount, placementOrder = {}, nil, 0, {}
local function makeEngine(build)
    local logic = { selected = r1, can = true }
    logic.getRecipe = function(self) return self.selected end
    logic.setRecipe = function(self, r) self.selected = r end
    logic.getCategoryList = function() return MockList({ "carpentry", "survival" }) end
    logic.cachedCanPerformCurrentRecipe = function(self) return self.can end
    logic.getCachedRecipeInfo = function(self)
        return { isValid = function() return true end, isCanPerform = function() return self.can end }
    end
    logic.getSatisfiedInputItems = function() return MockList({ item }) end
    logic.getInputCount = function() return 3 end
    logic.isInputSatisfied = function(self) return self.can end
    logic.getPossibleCraftCount = function() return 5 end
    local cc = {
        setCraftQuantity = function(_, q) lastQuantity = q end,
        startHandcraft = function() startCount = startCount + 1 end,
    }
    local hp = { logic = logic, recipesPanel = { recipeListPanel = { recipeListPanel = {
        items = { { text = "Barricade de fenêtre", item = r1 }, { text = "Caisse en bois", item = r2 } },
    } } }, recipePanel = { craftControl = cc },
        setRecipeListMode = function(self, v) self.listMode = v end, update = function() end,
        onCategoryChanged = function(self, c) self.filterCategory = c end,
        setRecipeFilter = function(self, s) self.searchText = s end,
        updateContainers = function(self) self.refreshCount = (self.refreshCount or 0) + 1 end,
        createBuildIsoEntity = function() placementOrder[#placementOrder + 1] = "place" end,
        updateManualInputs = function() end,
    }
    local win = ISCollapsableWindow:new(0, 0, 1200, 800)
    win:initialise(); win:setVisible(true)
    win.update = function() end
    win.close = function(self)
        placementOrder[#placementOrder + 1] = "close"
        self.hasClosedWindowInstance = true; self:setVisible(false)
    end
    if build then win.BuildPanel = hp else win.handCraftPanel = hp end
    return win
end
ISEntityUI = {
    GetWindowInstance = function(_, key) return windows[key] end,
    OpenHandcraftWindow = function() windows.HandcraftWindow = makeEngine(false) end,
    OpenBuildWindow = function() windows.BuildWindow = makeEngine(true) end,
}

test("custom crafting hides the native window and retains its recipe engine", function()
    Hub.open("crafting")
    local ui = Hub.instance.craft
    ui:tick()
    expect(ui.win == windows.HandcraftWindow, "native engine attached")
    expect(not ui.win:isVisible() and ui.win.n26CraftEngine, "native presentation hidden")
    expect(ui:panel().listMode, "native list mode used for recipe data")
    expectEq(#ui.list.items, 2, "recipes from engine")
    expectEq(#ui.cats.items, 4, "all, favourites and real categories")
    Hub.watch()
    expect(Hub.isOpen(), "hidden engine is still considered open by watcher")
    ui:onRecipeClick(r2)
    expect(ui:recipe() == r2, "selection updates native logic")
    ui:onCategory("carpentry")
    expectEq(ui:panel().filterCategory, "carpentry", "category sent to engine")
    ui.search:setText("bois"); ui:onSearch()
    expectEq(ui:panel().searchText, "bois", "search sent to engine")
    ui:onRecipeClick(r1)
    ui.sheet:rebuild(ui:logic(), r1, chr)
    expectEq(ui.sheet.data.inputs[1].have, 3, "live inventory count")
    expectEq(ui.sheet.data.inputs[1].need, 3, "recipe requirement")
    resetDrawLog(); renderTree(Hub.instance)
    snapshot("13_hub_crafting", 1920, 1080)
    F.noHookErrors()
end)

test("craft button delegates quantity and blocks recipes the engine rejects", function()
    local ui = Hub.instance.craft
    ui:startCraft(3)
    expectEq(lastQuantity, 3, "quantity passed to native control")
    expectEq(startCount, 1, "native craft action triggered")
    ui:logic().can = false
    ui:startCraft(3)
    expectEq(startCount, 1, "unavailable recipe blocked")
    ui:logic().can = true
end)

test("craftable filter removes unavailable recipes and recipe sheet scrolls long inputs", function()
    local ui = Hub.instance.craft
    local source = ui:panel().recipesPanel.recipeListPanel.recipeListPanel.items
    ui.onlyCraftable = true
    ui:logic().can = false
    ui:fillList(source)
    expectEq(#ui.list.items, 0, "unavailable recipes hidden")
    ui:logic().can = true
    ui:fillList(source)
    expectEq(#ui.list.items, 2, "available recipes restored")
    ui.onlyCraftable = false
    local many = {}
    for i = 1, 24 do many[i] = input end
    local oldInputs = r1.getInputs
    r1.getInputs = function() return MockList(many) end
    ui.sheet.data = nil
    ui.sheet:prerender()
    expect(ui.sheet.scrollMax > 0, "long ingredient sheet can scroll")
    ui.sheet:onMouseWheel(4)
    expect(ui.sheet.contentScroll > 0, "mouse wheel scrolls ingredients")
    r1.getInputs = oldInputs
    ui.sheet.data, ui.sheet.contentScroll = nil, 0
    ui:setWidth(1256); ui:setHeight(600); ui:layout()
    expect(ui.list.width > 500 and ui.sheet.width > 400, "columns usable at 1280px")
    expectEq(ui.list.vscroll.x, ui.list.width - ui.list.vscroll.width, "scrollbar follows resized recipe list")
    expectEq(ui.list.vscroll.height, ui.list.height, "scrollbar uses list viewport")
end)

test("crafting shortcut closes the custom page without exposing its hidden window", function()
    expect(Hub.instance:isKeyConsumed(KeybindId.CRAFTING_UI), "craft shortcut consumed")
    Hub.instance:onKeyRelease(KeybindId.CRAFTING_UI)
    expect(not Hub.isOpen(), "shortcut closes menu")
    expect(windows.HandcraftWindow.hasClosedWindowInstance, "hidden engine closed")
    Hub.open("crafting", "craft")
end)

test("construction uses a custom page and closes before creating its placement cursor", function()
    Hub.setTab("crafting", "build")
    local ui = Hub.instance.craft
    expect(ui.isBuild and ui.win == windows.BuildWindow, "build engine attached")
    expect(not ui.win:isVisible(), "native build UI hidden")
    placementOrder = {}
    ui:startCraft(1)
    expect(not Hub.isOpen(), "menu closes for placement")
    expectEq(table.concat(placementOrder, ","), "close,place", "closing cannot clear new placement cursor")
    expect(ui.win == nil, "engine detached from view")
end)
