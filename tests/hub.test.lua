-- Tactical screen (N26_Hub): docking of the vanilla windows, equipment slots,
-- health summary, key handling, watcher. Snapshots use French strings.

local F = dofile(HARNESS_DIR .. "/hub_fixture.lua")
local playerInv, chr, worn, noHookErrors = F.playerInv, F.chr, F.worn, F.noHookErrors

-- ------------------------------------------------------------------ windows
-- Stand-ins for the vanilla inventory pages: a collapsable window holding a
-- real ISInventoryPane (the real ISInventoryPage needs the whole game).

local function makePage(title, inv, onChar)
    local win = ISCollapsableWindow:new(100, 100, 420, 600)
    win:initialise()
    win:setTitle(title)
    win:addToUIManager()
    win.onCharacter = onChar
    win.n26Filter = ""
    win.isCollapsed = false
    local pane = ISInventoryPane:new(0, win:titleBarHeight(), 420, 560, inv, 1)
    pane.player = 0
    pane.inventoryPage = win
    pane:initialise()
    win:addChild(pane)
    win.inventoryPane = pane
    pane:refreshContainer()
    win:setVisible(false)
    return win
end

local invWin = makePage("Sur moi · Sac à dos", playerInv, true)
local lootWin = makePage("À proximité · Sol", MockContainer({
    MockItem("Planche", "Material", 3), MockItem("Clous", "Material", 0.2), MockItem("Clous", "Material", 0.2),
    MockItem("Couteau de cuisine", "Weapon", 0.3), MockItem("Pull", "Clothing", 0.6), MockItem("Chips", "Food", 0.2),
}, 50, "floor"), false)
invWin.backpacks = { { inventory = playerInv } }
lootWin.backpacks = { { inventory = lootWin.inventoryPane.inventory } }
getPlayerInventory = function() return invWin end
getPlayerLoot = function() return lootWin end
-- Stand-in for the vanilla character info window (tab panel with views).
xpSystemText = { skills = "Compétences", health = "Santé", info = "Info" }
local skillsView = { name = "skills" }
local healthView = ISPanel:new(0, 30, 560, 600)
healthView:initialise()
local infoWin = ISCollapsableWindow:new(100, 100, 560, 640)
infoWin:initialise()
infoWin:setTitle("Compétences")
infoWin:addToUIManager()
infoWin:setVisible(false)
infoWin.healthView = healthView
infoWin.panel = {
    active = skillsView,
    getActiveView = function(self) return self.active end,
    activateView = function(self, name) self.active = (name == xpSystemText.health) and healthView or skillsView end,
    y = 20, tabHeight = 30,
    setWidth = function(self, w) self.width = w end,
    setHeight = function(self, h) self.height = h end,
}
infoWin.close = function(self) self:setVisible(false) end
getPlayerInfoPanel = function() return infoWin end

local Hub = N26.Hub

local function fitPanes()
    for _, w in ipairs({ invWin, lootWin }) do
        local p = w.inventoryPane
        p:setWidth(w.width)
        p:setHeight(w.height - p.y)
    end
end

-- ------------------------------------------------------------------ tests

test("body locations map to equipment slots", function()
    local cases = {
        Hat = "head", JacketHat = "head", FannyPackBack = "belt", Right_RingFinger = "accessories",
        RightWrist = "accessories", TorsoExtraVest = "rig", Shoes = "feet", Socks = "feet",
        Pants = "legs", Tshirt = "torso", Jacket = "torso", Back = "back", Hands = "hands", Neck = "neck",
    }
    for loc, slot in pairs(cases) do
        expectEq(Hub.slotForLocation(loc), slot, loc)
    end
end)

test("Tab opens the hub and docks both inventory pages into their columns", function()
    Hub.watch() -- first frame: primes the watcher (hub closed)
    Hub.onKeyPressed(Keyboard.KEY_TAB); Hub.flushKeys()
    expect(Hub.isOpen(), "hub open")
    local h = Hub.instance
    expectEq(h.tab, "inventory")
    expect(invWin:isVisible() and lootWin:isVisible(), "pages shown")
    expect(Hub.isDocked(invWin) and Hub.isDocked(lootWin), "pages docked")
    expect(invWin.x > h.equip.x + h.equip.width, "inventory right of the equipment column")
    expect(lootWin.x > invWin.x + invWin.width, "loot right of the inventory")
    expectEq(lootWin.x + lootWin.width, h.width - 12, "loot reaches the right margin")
    expect(not invWin.closeButton:isVisible(), "close button hidden while docked")
    expect(h:isKeyConsumed(Keyboard.KEY_ESCAPE), "Escape is consumed by the hub")
    noHookErrors()
end)

test("world dimmer never covers docked inventory windows, even when drawn last", function()
    local h, D = Hub.instance, N26.Draw
    h:layoutDocks()
    local regions = {}
    local fill, shade = D.fill, D.shade
    D.fill = function(_, x, y, w, h) regions[#regions + 1] = { x = x, y = y, w = w, h = h } end
    D.shade = D.fill
    local ok, err = pcall(h.drawBackdrop, h)
    D.fill, D.shade = fill, shade
    expect(ok, tostring(err))
    expect(#regions > 0, "world still dimmed")
    local area = 0
    for i, r in ipairs(regions) do
        for _, win in ipairs({ invWin, lootWin }) do
            expect(r.x + r.w <= win.x or r.x >= win.x + win.width
                or r.y + r.h <= win.y or r.y >= win.y + win.height, "no dimmer over a native window")
        end
        if i % 2 == 1 then area = area + r.w * r.h end
    end
    expectEq(area, h.width * h.height - invWin.width * invWin.height - lootWin.width * lootWin.height,
        "only the two docked rectangles are excluded")
end)

test("snapshot: tactical screen, inventory tab", function()
    local h = Hub.instance
    fitPanes()
    invWin.inventoryPane.selected[2] = invWin.inventoryPane.itemslist[2].items[1]
    resetDrawLog()
    renderTree(h)
    renderTree(invWin)
    renderTree(lootWin)
    -- the 3D character is drawn by the game (Java); mark its area in the preview
    local m = h.equip.model
    ISUIElement.drawTextCentre(m, "[ personnage 3D ]", m.width / 2, m.height / 2, 0.55, 0.58, 0.55, 1, UIFont.Small)
    snapshot("10_hub_inventory", 1920, 1080)
    expect(drawnText("ÉQUIPEMENT") or drawnText("Équipement"), "equipment header")
    expect(drawnText("Jambe gauche"), "injury listed in the health summary")
    expect(drawnText("Transfert · Bandage"), "current action in the bottom bar")
    noHookErrors()
end)

test("dropping clothing on a slot wears it, on a hand slot equips it", function()
    local h = Hub.instance
    local equip = h.equip
    local wore, equipped
    ISInventoryPaneContextMenu.onWearItems = function(items) wore = items end
    ISInventoryPaneContextMenu.equipWeapon = function(item, primary) equipped = { item = item, primary = primary } end
    local pull = MockItem("Pull", "Clothing", 0.6)
    pull.getBodyLocation = function() return "Sweater" end
    ISMouseDrag = { dragging = { pull } }
    local r = equip.slotRects.torso
    equip:onMouseUp(r.x + 4, r.y + 4)
    expect(wore and wore[1] == pull, "wear called with the dropped item")
    local knife = MockItem("Couteau", "Weapon", 0.3)
    ISMouseDrag = { dragging = { knife } }
    r = equip.slotRects.secondary
    equip:onMouseUp(r.x + 4, r.y + 4)
    expect(equipped and equipped.item == knife and equipped.primary == false, "off-hand equip")
    ISMouseDrag = { dragging = nil }
    noHookErrors()
end)

test("double click on a worn slot takes the item off", function()
    local equip = Hub.instance.equip
    local removed
    ISInventoryPaneContextMenu.onUnEquip = function(items) removed = items[1] end
    local t = 1000
    getTimestampMs = function() return t end
    local r = equip.slotRects.head
    equip:onMouseUp(r.x + 4, r.y + 4)
    t = 1200
    equip:onMouseUp(r.x + 4, r.y + 4)
    expect(removed and removed:getDisplayName() == "Casquette", "cap taken off")
end)

test("snapshot: custom character page has skills instead of the vanilla window", function()
    local h = Hub.instance
    Hub.setTab("character")
    expect(not infoWin:isVisible() and not Hub.isDocked(infoWin), "vanilla info window hidden")
    expect(h.skills:isVisible(), "custom skill board visible")
    expect(not invWin:isVisible(), "inventory hidden on other tabs")
    expect(h.skills.x >= h.ident.x + h.ident.width, "skills right of the identity column")
    resetDrawLog()
    renderTree(h)
    local m = h.ident.model
    ISUIElement.drawTextCentre(m, "[ personnage 3D ]", m.width / 2, m.height / 2, 0.55, 0.58, 0.55, 1, UIFont.Small)
    snapshot("11_hub_character", 1920, 1080)
    expect(drawnText("Mécanicien"), "profession")
    expect(drawnText("Costaud"), "trait")
    -- the vanilla info window switched to its health view (H key) -> health tab
    infoWin.panel:activateView(xpSystemText.health)
    infoWin:setVisible(true)
    Hub.watch()
    expectEq(h.tab, "health", "follows the info window to the health tab")
    Hub.setTab("inventory")
    expect(not infoWin:isVisible(), "info window closed on the inventory tab")
    expect(invWin:isVisible(), "inventory back")
    noHookErrors()
end)

test("health size stays stable through repeated vanilla auto-size attempts", function()
    Hub.setTab("health")
    local w, h = healthView.width, healthView.height
    expect(w > 600 and h > 600, "health fills its allotted area")
    for i = 1, 30 do
        healthView:setWidthAndParentWidth(400)
        healthView:setHeightAndParentHeight(450)
        Hub.watch()
        Hub.instance:layoutDocks()
        expectEq(Hub.instance.tab, "health", "health stays selected")
        expectEq(healthView.width, w, "width stable")
        expectEq(healthView.height, h, "height stable")
    end
    Hub.setTab("character")
    expectEq(rawget(healthView, "setWidthAndParentWidth"), nil, "vanilla width method restored")
    expectEq(rawget(healthView, "setHeightAndParentHeight"), nil, "vanilla height method restored")
    Hub.setTab("inventory")
end)

test("snapshot: health tab with the care supplies column", function()
    for _, it in ipairs(playerInv.items) do
        if it.name == "Bandage" then it.getBandagePower = function() return 2 end end
    end
    local splint = MockItem("Attelle", "FirstAid", 0.5)
    splint.type = "Splint"
    table.insert(lootWin.inventoryPane.inventory.items, splint)
    local h = Hub.instance
    Hub.setTab("health")
    expectEq(h.tab, "health")
    expect(h.care:isVisible(), "care column shown")
    expect(infoWin.x + infoWin.width <= h.care.x, "health window left of the care column")
    local sup = Hub.careSupplies()
    expectEq(sup.bandage.mine, 2, "two bandages on me")
    expectEq(sup.splint.near, 1, "a splint nearby")
    infoWin:setTitle("Santé")
    resetDrawLog()
    renderTree(h)
    renderTree(infoWin)
    snapshot("12_hub_health", 1920, 1080)
    expect(drawnText("Pansements"), "bandage row")
    local readableMissing, readableZero = false, false
    for _, d in ipairs(DRAWLOG) do
        local a = d.args
        if d.kind == "DrawText" and a[2] == "Désinfectant" then
            readableMissing = a[5] == N26.Theme.C.text2.r and a[8] == 1
        elseif d.kind == "DrawTextCentre" and a[2] == "0" then
            readableZero = a[5] == N26.Theme.C.muted.r and a[8] == 1
        end
    end
    expect(readableMissing and readableZero, "missing supplies and zero counts remain readable")
    Hub.setTab("inventory")
    noHookErrors()
end)

test("windows outside the tactical screen keep the vanilla look", function()
    expect(Hub.isOpen(), "hub open")
    local other = ISCollapsableWindow:new(50, 50, 300, 200)
    other:initialise()
    other:setTitle("Autre fenêtre")
    other:addToUIManager()
    local bg = other.backgroundColor
    local r, g, b, a = bg.r, bg.g, bg.b, bg.a
    expectEq(N26.scopeOf(other), nil, "not in scope")
    resetDrawLog()
    renderTree(other)
    expect(other.backgroundColor == bg and bg.r == r and bg.g == g and bg.b == b and bg.a == a, "colours untouched")
    expect(not rawget(other, "n26Skinned"), "not skinned")
    expect(drawnText("Autre fenêtre"), "vanilla title drawn as is (not upper-cased)")
    -- a docked window is in scope
    expectEq(N26.scopeOf(invWin.inventoryPane), "window", "docked page content in scope")
    other:removeFromUIManager()
    noHookErrors()
end)

test("with the hub closed nothing is in scope", function()
    Hub.close()
    expectEq(N26.scopeOf(invWin), nil)
    expectEq(N26.scopeOf(ISContextMenu:new(0, 0, 1, 1, 1)), nil, "context menus vanilla when the hub is closed")
    Hub.open("inventory")
end)

test("Tab again closes the hub and restores the windows", function()
    Hub.onKeyPressed(Keyboard.KEY_TAB); Hub.flushKeys()
    expect(not Hub.isOpen(), "hub closed")
    expect(not invWin:isVisible() and not lootWin:isVisible(), "pages hidden")
    expect(not Hub.isDocked(invWin), "undocked")
    expectEq(invWin.x, 100, "position restored")
    expectEq(invWin.width, 420, "size restored")
    expect(invWin.closeButton:isVisible(), "close button back")
end)

test("Tab works with inventory bound to I, and I still toggles the hub", function()
    local core = getCore()
    local originalIsKey = core.isKey
    core.isKey = function(_, id, key) return id == KeybindId.TOGGLE_INVENTORY and key == 23 end
    Hub.onKeyPressed(Keyboard.KEY_TAB); Hub.flushKeys()
    local tabOpened = Hub.isOpen()
    Hub.onKeyPressed(Keyboard.KEY_TAB); Hub.flushKeys()
    local tabClosed = not Hub.isOpen()
    Hub.onKeyPressed(23); Hub.flushKeys()
    local inventoryOpened = Hub.isOpen()
    Hub.onKeyPressed(23); Hub.flushKeys()
    local inventoryClosed = not Hub.isOpen()
    core.isKey = originalIsKey
    expect(tabOpened and tabClosed, "Tab opens and closes with inventory bound to I")
    expect(inventoryOpened and inventoryClosed, "configured inventory key opens and closes")
    noHookErrors()
end)

test("Tab still opens the hub when another key handler toggles the inventory in the same event", function()
    -- e.g. the vanilla inventory toggle left registered by a load-order problem
    Hub.onKeyPressed(Keyboard.KEY_TAB)
    invWin:setVisible(not invWin:getIsVisible())
    lootWin:setVisible(invWin:getIsVisible())
    Hub.flushKeys()
    expect(Hub.isOpen(), "hub open after the deferred toggle")
    Hub.instance:prerender()
    expect(Hub.isOpen() and invWin:isVisible(), "the watcher keeps it open with the inventory shown")
    Hub.onKeyPressed(Keyboard.KEY_TAB)
    invWin:setVisible(not invWin:getIsVisible())
    Hub.flushKeys()
    expect(not Hub.isOpen() and not invWin:isVisible(), "second Tab closes it")
    noHookErrors()
end)

test("watcher: a window opened the vanilla way opens the hub, closing it closes the hub", function()
    invWin:setVisible(true) -- e.g. the sidebar inventory button
    Hub.watch()
    expect(Hub.isOpen() and Hub.instance.tab == "inventory", "hub opened on the inventory tab")
    invWin:setVisible(false)
    Hub.watch()
    expect(not Hub.isOpen(), "hub closed with the inventory")
    noHookErrors()
end)

test("controller players keep the vanilla windows", function()
    JoypadState.players[1] = {}
    invWin:setVisible(true)
    Hub.watch()
    expect(not Hub.isOpen(), "no hub with a controller")
    invWin:setVisible(false)
    JoypadState.players[1] = nil
end)
