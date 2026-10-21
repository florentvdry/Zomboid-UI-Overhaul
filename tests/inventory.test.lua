-- Inventory module: real vanilla ISInventoryPane logic under the N26 interception.

dofile(HARNESS_DIR .. "/mocks_game.lua")
require "N26/N26_Boot"
-- these tests exercise the redesign as it appears inside the tactical screen
N26.scopeOf = function() return "window" end

local function noHookErrors()
    for key, h in pairs(N26.Hooks) do
        if h.errors > 0 then error("hook " .. key .. " errored: " .. tostring(h.lastError)) end
    end
end

local items = {
    MockItem("Bandage", "FirstAid", 0.1), MockItem("Bandage", "FirstAid", 0.1), MockItem("Bandage", "FirstAid", 0.1),
    MockItem("Canned Beans", "Food", 0.5), MockItem("Hammer", "Tool", 1.0),
}
local inv = MockContainer(items, 20, "none")
local player = MockPlayer(inv)
getSpecificPlayer = function() return player end

local function makePane()
    local parent = ISPanel:new(0, 0, 500, 400)
    parent.onCharacter = true
    parent:initialise()
    parent:addToUIManager()
    local pane = ISInventoryPane:new(0, 30, 450, 300, inv, 1)
    pane.player = 0
    pane.inventoryPage = parent
    pane:initialise()
    parent:addChild(pane)
    parent.n26Filter = ""
    parent.isCollapsed = false
    return pane, parent
end

test("rows are taller and stacks are grouped", function()
    local pane = makePane()
    expectEq(pane.itemHgt, 29 + 6, "row height bumped by 6px")
    pane:refreshContainer()
    expectEq(#pane.itemslist, 3, "3 groups (bandage x3, beans, hammer)")
end)

test("renderdetails runs vanilla logic under interception", function()
    local pane = makePane()
    pane:refreshContainer()
    pane.selected[1] = pane.itemslist[1].items[1]
    resetDrawLog()
    pane:prerender()
    pane:render()
    expect(#pane.items >= 3, "vanilla built the row list (" .. #pane.items .. ")")
    expect(drawnText("x3") or drawnText("Bandage"), "names drawn")
    noHookErrors()
end)

test("search filters by name and category, keeps selection by identity", function()
    local pane, parent = makePane()
    pane:refreshContainer()
    local hammerGroup
    for _, v in ipairs(pane.itemslist) do if v.items[1].name == "Hammer" then hammerGroup = v end end
    pane.selected = { [1] = hammerGroup }
    parent.n26Filter = "ham"
    pane:refreshContainer()
    expectEq(#pane.itemslist, 1)
    expectEq(pane.itemslist[1].items[1].name, "Hammer")
    expect(pane.selected[1] == hammerGroup.items[1], "selection re-applied to the filtered row")
    parent.n26Filter = "FirstAid"
    pane:refreshContainer()
    expectEq(#pane.itemslist, 1, "category match (getText returns the key in tests)")
    parent.n26Filter = ""
    pane:refreshContainer()
    expectEq(#pane.itemslist, 3)
    noHookErrors()
end)
