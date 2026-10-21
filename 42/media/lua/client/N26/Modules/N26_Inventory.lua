--[[
    N26 Inventory (boards 01 & 02) — ISInventoryPage + ISInventoryPane.

    Window
      Tactical header: accent bar + condensed title, live weight readout and a
      full-width capacity gauge (neutral → amber at 75 % → red when over), item
      search, controls moved to the right. Container rail on the right as tiles
      with a per-container fill gauge and an accent frame on the open container.

    Item list
      Vanilla renderdetails() still runs (it builds the row list, ages food,
      dries clothes…); its drawing is intercepted and remapped by meaning:
      selection → accent wash + 2px bar, invalid drop → danger wash, hover,
      stack children indented, quantity as a chip, categories muted, condition /
      remaining bars flat. Rows are 6px taller for 32px icons.

    Search
      Filters the rows by name or category after vanilla refreshContainer();
      selection is re-applied by item identity, so drag & drop, context menus and
      transfers behave exactly as without the filter.

    Not done here: a Tarkov-like spatial grid. The pane's mouse code derives the
    row from y in ~15 places (marquee, drag, buttons…); a grid would mean
    re-implementing all of it. See docs/LIMITATIONS.md.
]]

require "ISUI/ISInventoryPage"
require "ISUI/ISInventoryPane"
require "ISUI/ISTextEntryBox"
require "N26/Skin/N26_SkinControls"

local Theme = N26.Theme
local D = N26.Draw
local Skin = N26.Skin
local Config = N26.Config
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

N26.registerModule({ id = "inventory", label = "UI_N26_Mod_Inventory", tooltip = "UI_N26_Mod_Inventory_Tip" })
local MODULE = "inventory"

local ROW_EXTRA = 6     -- extra row height (px)
local CAP_ROW = 10      -- capacity gauge strip under the title row

-- ---------------------------------------------------------------------------
-- Page geometry
-- ---------------------------------------------------------------------------

local function titleRowHeight(self)
    return max(16, self.titleFontHgt + 1) + 6
end

N26.hook(ISInventoryPage, "ISInventoryPage", "titleBarHeight", MODULE, function(orig, self)
    return titleRowHeight(self) + CAP_ROW
end)

-- On loot pages self.lootAll is a button; on the player's inventory the name
-- resolves to the class method ISInventoryPage.lootAll (vanilla FIXME), so only
-- trust an instance field that is a table.
local function lootAllButton(self)
    local b = rawget(self, "lootAll")
    if type(b) == "table" and b.isVisible then return b end
    return nil
end

local function placeHeaderControls(self)
    local rowH = titleRowHeight(self)
    local bh = rowH - 6
    local x = self.width - 4 - bh
    local function put(btn)
        if not btn then return end
        btn:setHeight(bh)
        btn:setWidth(bh)
        btn:setY(3)
        btn:setX(x)
        btn.anchorLeft, btn.anchorRight = false, true
        btn.n26TitleButton = true
        x = x - bh - 2
    end
    put(self.closeButton)
    -- pin & collapse share a slot (only one is visible at a time)
    if self.pinButton then
        self.pinButton:setHeight(bh); self.pinButton:setWidth(bh); self.pinButton:setY(3); self.pinButton:setX(x)
        self.pinButton.anchorLeft, self.pinButton.anchorRight = false, true
        self.pinButton.n26TitleButton = true
    end
    put(self.collapseButton)
    put(self.n26SearchButton)
    put(self.infoButton)
    self.n26HeaderRight = x + bh
    local loot = lootAllButton(self)
    if loot then
        loot:setHeight(bh)
        loot:setY(3)
        loot.anchorLeft, loot.anchorRight = false, true
    end
end

local function onSearchChange(page, entry)
    if not page or not page.inventoryPane then return end
    page.n26Filter = entry:getInternalText() or ""
    page.inventoryPane:refreshContainer()
end

local function toggleSearch(page)
    local e = page.n26SearchEntry
    if not e then return end
    local show = not e:isVisible()
    e:setVisible(show)
    if show then
        e:focus()
    else
        e:setText("")
        e:unfocus()
        page.n26Filter = ""
        page.inventoryPane:refreshContainer()
    end
end

N26.after(ISInventoryPage, "ISInventoryPage", "createChildren", MODULE, function(self)
    local rowH = titleRowHeight(self)
    local bh = rowH - 6

    local search = ISButton:new(0, 3, bh, bh, "", self, function(page) toggleSearch(page) end)
    search:initialise()
    search.borderColor.a = 0
    search.backgroundColor.a = 0
    search:setImage(D.iconTex("search", 24))
    search:forceImageSize(math.max(10, bh - 8), math.max(10, bh - 8))
    search.textureColor = Theme.copy(Theme.C.text2)
    search:setTooltip(getText("UI_N26_Inv_Search"))
    self:addChild(search)
    self.n26SearchButton = search

    local entry = ISTextEntryBox:new("", 10, 3, 120, bh)
    entry:initialise()
    entry:instantiate()
    entry.target = self
    entry.onTextChangeFunction = onSearchChange
    entry:setClearButton(true)
    entry:setPlaceholderText(getText("UI_N26_Inv_Search"))
    self:addChild(entry)
    entry:setVisible(false)
    self.n26SearchEntry = entry
    self.n26Filter = ""

    placeHeaderControls(self)
end)

-- ---------------------------------------------------------------------------
-- Page frame
-- ---------------------------------------------------------------------------

local function capacityColor(frac)
    local C = Theme.C
    if frac > 1 then return C.danger end
    if frac > 0.75 then return C.warn end
    return C.ok
end

local function blinkContainers(self)
    if not self.blinkContainer then return end
    if not self.blinkAlphaContainer then self.blinkAlphaContainer = 0.7; self.blinkAlphaIncreaseContainer = false end
    local ms = UIManager.getMillisSinceLastRender() / 33.3
    if not self.blinkAlphaIncreaseContainer then
        self.blinkAlphaContainer = self.blinkAlphaContainer - 0.04 * ms
        if self.blinkAlphaContainer < 0.3 then self.blinkAlphaContainer = 0.3; self.blinkAlphaIncreaseContainer = true end
    else
        self.blinkAlphaContainer = self.blinkAlphaContainer + 0.04 * ms
        if self.blinkAlphaContainer > 0.7 then self.blinkAlphaContainer = 0.7; self.blinkAlphaIncreaseContainer = false end
    end
    for _, v in ipairs(self.backpacks) do
        if (self.blinkContainerType and v.inventory:getType() == self.blinkContainerType) or not self.blinkContainerType then
            if v.inventory == self.inventoryPane.inventory then
                v:setBackgroundRGBA(1, 0, 0, self.blinkAlphaContainer)
            else
                v:setBackgroundRGBA(1, 0, 0, self.blinkAlphaContainer * 0.75)
            end
        end
    end
end

local function titleText(self)
    local text = self.title
    if not text then return nil end
    if self.onCharacter then return text end
    local inv = self.inventoryPane.inventory
    if inv and inv:getParent() then
        local fireTile = inv:getParent()
        local campfire = CCampfireSystem and CCampfireSystem.instance and CCampfireSystem.instance:getLuaObjectOnSquare(fireTile:getSquare())
        if campfire then
            text = text .. ": " .. (ISCampingMenu.timeString(luautils.round(campfire.fuelAmt)))
        elseif fireTile and fireTile:isFireInteractionObject() then
            if fireTile:isPropaneBBQ() and not fireTile:hasPropaneTank() then
                text = text .. ": " .. getText("IGUI_BBQ_NeedsPropaneTank")
            else
                text = text .. ": " .. tostring(ISCampingMenu.timeString(fireTile:getFuelAmount()))
            end
        end
    end
    if inv and inv:isOccupiedVehicleSeat() then
        text = text .. " " .. getText("IGUI_invpage_Occupied")
    end
    return text
end

N26.hook(ISInventoryPage, "ISInventoryPage", "prerender", MODULE, function(orig, self)
    local C = Theme.C
    blinkContainers(self)

    local th = self:titleBarHeight()
    local rowH = titleRowHeight(self)
    local w = self:getWidth()
    local height = self.isCollapsed and th or self:getHeight()
    local R = Theme.R.lg

    D.fill(self, 0, 0, w, height, self.backgroundColor, R)
    -- header surface; blinks white like vanilla when the game asks for attention
    D.fill(self, 1, 1, w - 2, th - 1, C.panel2, R - 1)
    if self.blink then
        if not self.blinkAlpha then self.blinkAlpha = 1 end
        D.fill(self, 1, 1, w - 2, th - 1, C.accent, R - 1, self.blinkAlpha * 0.35)
        local ms = UIManager.getMillisSinceLastRender() / 33.3
        if not self.blinkAlphaIncrease then
            self.blinkAlpha = self.blinkAlpha - 0.1 * ms
            if self.blinkAlpha < 0 then self.blinkAlpha = 0; self.blinkAlphaIncrease = true end
        else
            self.blinkAlpha = self.blinkAlpha + 0.1 * ms
            if self.blinkAlpha > 1 then self.blinkAlpha = 1; self.blinkAlphaIncrease = false end
        end
    end
    if not self.isCollapsed then
        D.rect(self, 1, th - 1, w - 2, 1, C.divider)
        -- container rail
        local rx = w - self.buttonSize
        D.rect(self, rx, th, self.buttonSize, self.inventoryPane.height, C.black, 0.18)
        D.rect(self, rx, th, 1, self.inventoryPane.height, C.divider)
    end

    -- weight / capacity
    self.totalWeight = ISInventoryPage.loadWeight(self.inventoryPane.inventory)
    local roundedWeight = round(self.totalWeight, 2)
    local playerObj = getSpecificPlayer(self.player)
    local maxW
    local label
    if self.capacity then
        if playerObj and self.inventoryPane.inventory == playerObj:getInventory() then
            maxW = playerObj:getMaxWeight()
            label = roundedWeight .. " / " .. maxW
        else
            maxW = self.capacity
            label = roundedWeight .. " / " .. self.capacity
            if isClient() then
                local itemLimit = getServerOptions():getInteger("ItemNumbersLimitPerContainer")
                if itemLimit > 0 then
                    label = label .. " (" .. self.totalItems .. " / " .. itemLimit .. ")"
                end
            end
        end
    else
        label = tostring(roundedWeight)
    end

    local right = (self.n26HeaderRight or (w - 40)) - 8
    local loot = lootAllButton(self)
    if loot and loot:isVisible() then
        loot:setX(right - loot.width)
        right = right - loot.width - 8
    end
    local fh = D.fontHeight(UIFont.Small)
    local ty = floor((rowH - fh) / 2)
    local lw = D.text(self, label, right, ty, C.text2, UIFont.Small, "right")
    D.icon(self, "weight", right - lw - 18, floor((rowH - 14) / 2), 14, C.muted)
    local titleRight = right - lw - 26

    -- title (or the search field, which occupies the same slot)
    local searching = self.n26SearchEntry and self.n26SearchEntry:isVisible()
    D.rect(self, 8, floor((rowH - 14) / 2), 2, 14, C.accent)
    if searching then
        local e = self.n26SearchEntry
        e:setX(16)
        e:setY(3)
        e:setWidth(max(60, titleRight - 20))
    else
        local text = titleText(self)
        if text then
            local hh = D.headingHeight("sm")
            D.heading(self, text, 16, floor((rowH - hh) / 2) + 1, C.text, "sm", nil, max(10, titleRight - 20))
        end
    end

    -- capacity gauge
    if maxW and maxW > 0 then
        local frac = self.totalWeight / maxW
        D.bar(self, 10, rowH + 2, w - 20, 4, min(1, frac), capacityColor(frac), C.hover2, 2)
    else
        D.rect(self, 10, rowH + 3, w - 20, 1, C.divider)
    end

    self:setStencilRect(0, 0, self.width + 1, height)
    self.containerButtonPanel:keepSelectedButtonVisible()

    if playerObj and playerObj:isInvPageDirty() then
        playerObj:setInvPageDirty(false)
        ISInventoryPage.renderDirty = false
        ISInventoryPage.dirtyUI()
    end
    if ISInventoryPage.renderDirty then
        ISInventoryPage.renderDirty = false
        ISInventoryPage.dirtyUI()
    end
end)

N26.hook(ISInventoryPage, "ISInventoryPage", "render", MODULE, function(orig, self)
    local C = Theme.C
    local th = self:titleBarHeight()
    local height = self.isCollapsed and th or self:getHeight()
    local w = self:getWidth()
    local FONT_HGT_SMALL = D.fontHeight(UIFont.Small)
    local rh = (FONT_HGT_SMALL + 6) / 2 + 2
    if not self.isCollapsed then
        D.rect(self, 1, height - rh, w - 2, 1, C.divider)
        if self.resizeimage then
            self:drawTextureScaled(self.resizeimage, w - rh + 1, height - rh + 1, rh - 2, rh - 2, 1, 1, 1, 1)
        end
        if self.controlsUI and self.controlsUI:isVisible() then
            D.rect(self, 1, self.controlsUI.y, w - 2, 1, C.divider)
        end
    end
    self:clearStencilRect()
    D.stroke(self, 0, 0, w, height, self.borderColor, Theme.R.lg)
    if self.joyfocus then
        D.stroke(self, 0, 0, w, self:getHeight(), C.accent, Theme.R.lg)
    end
    if self.render3DItems and #self.render3DItems > 0 then
        self:render3DItemPreview()
    end
end)

-- ---------------------------------------------------------------------------
-- Container rail tiles
-- ---------------------------------------------------------------------------

N26.after(ISInventoryPage, "ISInventoryPage", "addContainerButton", MODULE, function(self, container)
    local b = self.backpacks[#self.backpacks]
    if b then b.n26ContainerPage = self end
end)

local fillCache = setmetatable({}, { __mode = "k" })
local function containerFill(btn)
    local inv, cap = btn.inventory, btn.capacity
    if not inv or not cap or cap <= 0 then return nil end
    local now = getTimestampMs()
    local c = fillCache[btn]
    if c and c.inv == inv and now - c.t < 500 then return c.v end
    local v = ISInventoryPage.loadWeight(inv) / cap
    fillCache[btn] = { inv = inv, t = now, v = v }
    return v
end

N26.hook(ISButton, "ISButton(container)", "prerender", MODULE, function(orig, self)
    local page = self.n26ContainerPage
    if not page then return orig(self) end
    local C = Theme.C
    local w, h = self.width, self.height
    local inset = 3
    local selected = page.inventoryPane and page.inventoryPane.inventory == self.inventory
    local over = self.mouseOver and self:isMouseOver()
    local bx, by, bw, bh = inset, inset, w - inset * 2, h - inset * 2
    local bg = self.backgroundColor
    D.fill(self, bx, by, bw, bh, selected and C.accentSoft or C.panel2, Theme.R.md, selected and 1 or 0.6)
    if over then D.fill(self, bx, by, bw, bh, C.hover2, Theme.R.md) end
    -- vanilla blink (red) for containers that need attention
    if bg and bg.r > 0.9 and bg.g < 0.1 and bg.a > 0 then
        D.fill(self, bx, by, bw, bh, C.danger, Theme.R.md, bg.a * 0.6)
    end
    D.stroke(self, bx, by, bw, bh, selected and C.accent or (over and C.outline2 or C.outline), Theme.R.md)
    local f = containerFill(self)
    if f then
        D.rect(self, bx + 3, by + bh - 4, bw - 6, 2, C.white, 0.10)
        D.rect(self, bx + 3, by + bh - 4, floor((bw - 6) * min(1, f)), 2, capacityColor(f))
    end
    self:updateTooltip()
end)

-- ---------------------------------------------------------------------------
-- Item list
-- ---------------------------------------------------------------------------

local function bumpRows(pane)
    if pane.n26RowsBumped == pane.fontHgt then return end
    pane.itemHgt = math.ceil(max(18, pane.fontHgt) * (pane.zoom or 1)) + ROW_EXTRA
    pane.texScale = min(32, (pane.itemHgt - 2)) / 32
    pane.n26RowsBumped = pane.fontHgt
    for _, b in ipairs({ pane.contextButton1, pane.contextButton2, pane.contextButton3 }) do
        if b then b:setHeight(pane.itemHgt) end
    end
end

N26.after(ISInventoryPane, "ISInventoryPane", "createChildren", MODULE, function(self)
    bumpRows(self)
    local C = Theme.C
    for _, hdr in ipairs({ self.nameHeader, self.typeHeader }) do
        if hdr then hdr.textColor = Theme.copy(C.muted) end
    end
    self.expandAll:setImage(D.iconTex("chevD", 16))
    self.collapseAll:setImage(D.iconTex("chevU", 16))
    self.filterMenu:setImage(D.iconTex("sort", 16))
    for _, b in ipairs({ self.expandAll, self.collapseAll, self.filterMenu }) do
        b.textureColor = Theme.copy(C.text2)
        b.n26TitleButton = true
    end
end)

N26.after(ISInventoryPane, "ISInventoryPane", "onInventoryFontChanged", MODULE, function(self)
    self.n26RowsBumped = nil
    bumpRows(self)
end)

-- Search filter -------------------------------------------------------------

local function matches(entry, needle)
    local name = entry.items and entry.items[1] and entry.items[1]:getName() or entry.name or ""
    if string.find(string.lower(name), needle, 1, true) then return true end
    local cat = entry.cat and getText("IGUI_ItemCat_" .. entry.cat) or ""
    return string.find(string.lower(cat), needle, 1, true) ~= nil
end

N26.hook(ISInventoryPane, "ISInventoryPane", "refreshContainer", MODULE, function(orig, self)
    local page = self.inventoryPage
    local needle = page and page.n26Filter
    if not needle or needle == "" then
        return orig(self)
    end
    local saved = self:saveSelection({})
    orig(self)
    needle = string.lower(needle)
    local kept = {}
    for _, v in ipairs(self.itemslist) do
        if matches(v, needle) then kept[#kept + 1] = v end
    end
    self.itemslist = kept
    table.wipe(self.selected)
    self:restoreSelection(saved)
    self:updateScrollbars()
end)

-- Row painting (interception of renderdetails) ------------------------------

local function near(a, b) return abs(a - b) < 0.011 end

local function paneDrawRect(self, x, y, w, h, a, r, g, b)
    local C = Theme.C
    if h == self.itemHgt then
        if near(r, 1) and near(g, 1) and near(b, 1) then
            if near(a, 0.20) then           -- selected / highlighted item
                D.rect(self, x, y, w, h, C.accentSoft)
                D.rect(self, x, y, 2, h, C.accent)
                return
            elseif near(a, 0.05) then       -- mouse over
                D.rect(self, x, y, w, h, C.hover)
                return
            elseif near(a, 0.02) then       -- alternate row
                D.rect(self, x, y, w, h, C.white, 0.018)
                return
            end
            -- blink highlight (search-for-item): accent pulse
            D.rect(self, x, y, w, h, C.accent, a * 0.6)
            return
        end
        if near(r, 1) and near(g, 0) and near(b, 0) then   -- cannot drop here
            D.rect(self, x, y, w, h, C.danger, 0.22)
            D.rect(self, x, y, 2, h, C.danger)
            return
        end
        if near(r, 0) and near(g, 0) and near(b, 0) then
            if near(a, 0.4) then             -- expanded stack child
                D.rect(self, x, y, w, h, C.black, 0.22)
                D.rect(self, self.column2 - 8, y, 1, h, C.divider)
                return
            end
            return                           -- plain row: transparent
        end
        if near(r, 0.4) and near(g, 1.0) and near(b, 0.3) then   -- job in progress
            D.rect(self, x, y, w, h, C.accent, 0.20)
            return
        end
        if near(r, 0.2) and near(g, 1.0) and near(b, 1.0) then   -- joypad cursor
            D.stroke(self, x, y, w, h, C.accent, Theme.R.sm)
            return
        end
    end
    if h == 1 and near(r, 1) and near(g, 1) then              -- equipped / unequipped divider
        D.rect(self, x + 6, y, w - 12, 1, C.accentLine)
        return
    end
    return ISUIElement.drawRect(self, x, y, w, h, a, r, g, b)
end

local function paneDrawRectStatic(self, x, y, w, h, a, r, g, b)
    local C = Theme.C
    if x == 0 and y == 0 and w == self.column2 then          -- icon column backdrop
        D.rect(self, 0, 0, w, h, C.black, 0.16, true)
        return
    end
    if y == 0 and h == self.headerHgt then                     -- column header bar
        D.rect(self, 1, 0, self.width - 2, h, C.panel2, 1, true)
        D.rect(self, 1, h - 1, self.width - 2, 1, C.divider, 1, true)
        return
    end
    return ISUIElement.drawRectStatic(self, x, y, w, h, a, r, g, b)
end

local function paneDrawRectBorder(self, x, y, w, h, a, r, g, b)
    -- marquee selection
    if w < 0 then x = x + w; w = -w end
    if h < 0 then y = y + h; h = -h end
    D.fill(self, x, y, w, h, Theme.C.accent, 0, 0.08)
    D.stroke(self, x, y, w, h, Theme.C.accentLine, 0)
end

local function paneDrawText(self, str, x, y, r, g, b, a, font)
    local C = Theme.C
    if type(str) ~= "string" then return ISUIElement.drawText(self, str, x, y, r, g, b, a, font) end
    local col
    if x >= (self.column3 or 1e9) then
        -- category column / job type
        if near(r, 0.6) and near(g, 0.6) and near(b, 0.8) then col = C.muted else col = C.accent end
        return D.text(self, str, x, y, col, font)
    end
    if near(r, 0.7) and near(g, 0.7) and near(b, 0.7) then col = C.text
    elseif near(r, 0.5) and near(g, 0.5) and near(b, 0.5) then col = C.dim
    elseif near(r, 0.7) and near(g, 0) then col = C.danger
    elseif near(r, 0.6) and near(g, 0.6) and near(b, 0.8) then col = C.muted   -- stack detail label
    end
    if not col then return ISUIElement.drawText(self, str, x, y, r, g, b, a, font) end
    -- "Name (12)" -> name + quantity chip
    local name, count = str:match("^(.*) %((%d+)%)$")
    if name and (col == C.text or col == C.dim) then
        local w = D.text(self, name, x, y, col, font)
        local label = "x" .. count
        local tw = D.measure(UIFont.Small, label)
        local fh = D.fontHeight(UIFont.Small)
        local cy = y + floor((D.fontHeight(font) - fh) / 2)
        D.fill(self, x + w + 8, cy - 1, tw + 10, fh + 2, C.hover2, Theme.R.sm)
        D.text(self, label, x + w + 13, cy, C.text2, UIFont.Small)
        return
    end
    return D.text(self, str, x, y, col, font)
end

local paneSpec = { fill = false, stroke = false, extra = {
    drawRect = paneDrawRect,
    drawRectStatic = paneDrawRectStatic,
    drawRectBorder = paneDrawRectBorder,
    drawText = paneDrawText,
} }

N26.hook(ISInventoryPane, "ISInventoryPane", "renderdetails", MODULE, function(orig, self, doDragged)
    bumpRows(self)
    return Skin.intercept(self, paneSpec, orig, doDragged)
end)

N26.hook(ISInventoryPane, "ISInventoryPane", "drawProgressBar", MODULE, function(orig, self, x, y, w, h, f, fg)
    D.bar(self, x, y, w, max(3, h - 2), f, fg, Theme.C.hover2, 2)
end)

-- Pane background: the page already paints the window surface.
Skin.classHooks.ISInventoryPane = function(el)
    el.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    el.borderColor = { r = 0, g = 0, b = 0, a = 0 }
end
