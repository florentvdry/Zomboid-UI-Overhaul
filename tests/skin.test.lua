-- Global skin: loads on top of real vanilla ISUI files and renders without errors.

require "N26/N26_Boot"
-- these tests exercise the redesign as it appears inside the tactical screen
N26.scopeOf = function() return "window" end

local function noHookErrors()
    for key, h in pairs(N26.Hooks) do
        if h.errors > 0 then error("hook " .. key .. " errored: " .. tostring(h.lastError)) end
    end
end

test("boot registers modules and options", function()
    expect(#N26.ModuleOrder >= 2, "modules registered")
    expect(PZAPI.ModOptions:getOptions("N26_UIOverhaul") ~= nil, "options page created")
    expectEq(N26.Config.get("accent"), 1)
end)

test("theme exposes accent and panel tokens", function()
    local C = N26.Theme.C
    expect(C.accent and C.accent.r > 0.8 and C.accent.g > 0.5, "amber accent")
    expect(math.abs(C.panel.a - 0.9) < 0.001, "panel opacity 90%")
end)

test("palette remap replaces vanilla greys only", function()
    local p = ISPanel:new(0, 0, 100, 100)
    p:initialise()
    p.borderColor = { r = 1, g = 0, b = 0, a = 1 }      -- intentional red border
    p:addToUIManager()
    p:prerender() -- remapped the first time it is drawn in scope
    expect(math.abs(p.backgroundColor.r - N26.Theme.C.panel.r) < 0.01, "black bg -> panel")
    expectEq(p.borderColor.r, 1, "coloured border untouched")
    expectEq(p.borderColor.g, 0)
end)

test("panel prerender draws rounded static frame", function()
    local p = ISPanel:new(0, 0, 200, 100)
    p:initialise()
    p:addToUIManager()
    resetDrawLog()
    p:prerender()
    expect(drawsUsing("q6_fill") == 4, "4 filled corners (top-level radius 6)")
    expect(drawsUsing("q6_ring") == 4, "4 ring corners")
    noHookErrors()
end)

test("button prerender/render uses rounded shapes and variants", function()
    local b = ISButton:new(10, 10, 100, 24, "OK", nil, nil)
    b:initialise()
    b:addToUIManager()
    resetDrawLog()
    b:prerender()
    b:render()
    expect(drawsUsing("q4_fill") == 4, "rounded fill")
    b:enableAcceptColor()
    expectEq(b.n26Variant, "primary")
    resetDrawLog()
    b:prerender()
    b:render()
    noHookErrors()
end)

test("collapsable window chrome moves close button right", function()
    local w = ISCollapsableWindow:new(100, 100, 300, 200)
    w:initialise()
    w:addToUIManager()
    w:setTitle("Inventory")
    w:prerender()
    expect(w.closeButton:getX() > 250, "close button on the right, got " .. tostring(w.closeButton:getX()))
    -- a window that grows after creation (XUI windows) keeps its buttons on the right edge
    w:setWidth(500)
    w:prerender()
    expect(w.closeButton:getX() > 450, "close button follows the width, got " .. tostring(w.closeButton:getX()))
    resetDrawLog()
    w:prerender()
    w:render()
    local found = false
    for _, d in ipairs(DRAWLOG) do
        if d.kind == "DrawTextZoomed" or d.kind == "DrawText" then
            for _, a in ipairs(d.args) do
                if a == "INVENTORY" then found = true end
            end
        end
    end
    expect(found, "uppercase heading drawn")
    noHookErrors()
end)

test("tick box, combo, text entry, scroll bar, tab panel render", function()
    local t = ISTickBox:new(0, 0, 200, 20, "", nil, nil)
    t:initialise(); t:addOption("A"); t:addOption("B"); t:setSelected(1, true)
    t:addToUIManager()
    t:render()

    local c = ISComboBox:new(0, 0, 150, 24, nil, nil)
    c:initialise(); c:addOption("One"); c:addOption("Two")
    c:addToUIManager()
    c:prerender(); c:render()

    local e = ISTextEntryBox:new("text", 0, 0, 150, 24)
    e:initialise()
    e:addToUIManager()
    e:prerender()

    local l = ISScrollingListBox:new(0, 0, 200, 100)
    l:initialise()
    l:addToUIManager()
    for i = 1, 20 do l:addItem("item " .. i, nil) end
    l.selected = 2
    l:prerender(); l:render()
    l.vscroll:render()

    local tp = ISTabPanel:new(0, 0, 300, 200)
    tp:initialise()
    tp:addToUIManager()
    tp:addView("General", ISPanel:new(0, 0, 300, 180))
    tp:addView("Skills", ISPanel:new(0, 0, 300, 180))
    tp:prerender(); tp:render()
    noHookErrors()
end)

test("context menu renders and keeps hit-testing consistent", function()
    local m = ISContextMenu:new(50, 50, 1, 1, 1.5)
    m:initialise()
    m:addToUIManager()
    m:setFont(UIFont.Medium)
    local o1 = m:addOption("Eat", nil, nil)
    local o2 = m:addOption("Drop", nil, nil)
    o2.notAvailable = true
    m:calcHeight()
    expectEq(m.padTopBottom, 4)
    m.mouseOver = 1
    resetDrawLog()
    m:render()
    expect(m.width >= 140, "width computed")
    -- first row starts after the top padding
    expectEq(m:getIndexAt(10, 4 + 1), 1)
    expectEq(m:getIndexAt(10, 4 + m.itemHgt + 1), 2)
    noHookErrors()
end)

test("hook falls back to vanilla and disables itself after repeated errors", function()
    local calls = 0
    local Fake = { Type = "Fake" }
    function Fake.render(self) calls = calls + 1 end
    N26.hook(Fake, "Fake", "render", nil, function() error("boom") end)
    for i = 1, 5 do Fake.render({}) end
    expectEq(calls, 5, "vanilla ran every time")
    expect(N26.Hooks["Fake.render"].disabled, "hook disabled after 3 errors")
end)

test("disabling the module makes hooks pass-through", function()
    N26.Config.set("mod_menus", false)
    local m = ISContextMenu:new(0, 0, 1, 1, 1.5)
    m:initialise()
    m:addToUIManager()
    m:addOption("A", nil, nil)
    resetDrawLog()
    m:render()
    expectEq(drawsUsing("q6_fill"), 0, "no N26 card when module is off")
    N26.Config.set("mod_menus", true)
end)

test("vanilla errors propagate unchanged and are not blamed on N26", function()
    local calls = 0
    local Fake = { Type = "Fake2" }
    function Fake.render(self) calls = calls + 1; error("vanilla bug") end
    N26.hook(Fake, "Fake2", "render", nil, function(orig, self) return orig(self) end)
    for i = 1, 4 do
        local ok, err = pcall(Fake.render, {})
        expect(not ok and tostring(err):find("vanilla bug"), "vanilla error re-raised")
    end
    expectEq(calls, 4, "vanilla ran exactly once per call")
    expectEq(N26.Hooks["Fake2.render"].errors, 0, "not counted as an N26 error")
    expect(not N26.Hooks["Fake2.render"].disabled, "hook still active")
end)

test("N26 error after vanilla ran does not run vanilla twice", function()
    local calls = 0
    local Fake = { Type = "Fake3" }
    function Fake.render(self) calls = calls + 1; return "v" end
    N26.hook(Fake, "Fake3", "render", nil, function(orig, self) local r = orig(self); error("n26 bug") end)
    local r = Fake.render({})
    expectEq(calls, 1, "vanilla ran once")
    expectEq(r, "v", "vanilla result returned")
    expectEq(N26.Hooks["Fake3.render"].errors, 1)
end)

test("heading upper-casing handles accents", function()
    expectEq(N26.Draw.upper("démarrer le véhicule"), "DÉMARRER LE VÉHICULE")
    expectEq(N26.Draw.upper("œuvre à ça"), "ŒUVRE À ÇA")
    expectEq(N26.Draw.upper("5 ÷ 2"), "5 ÷ 2")
end)
