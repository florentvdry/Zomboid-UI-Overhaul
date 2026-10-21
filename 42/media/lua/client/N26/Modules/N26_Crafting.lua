--[[
    N26 Crafting & building (board 07) — B42 handcraft / build / workstation UIs.

    These windows are assembled by the XUI system from script styles; their
    palette is retuned by media/scripts/xui/defaultskin/x_colors.txt (shipped by
    this mod) and every panel/button/list inherits the global skin. This module
    adds the pieces the palette cannot reach:
      * recipe list rows: hard 50 % grid lines → soft dividers, craftable
        titles in primary text, non-craftable in dim, sub-lines muted;
      * recipe icon grid: rounded tiles, hover plate, accent frame on the
        selected recipe.
]]

require "Entity/ISUI/CraftRecipe/ISRecipeScrollingListBox"
require "Entity/ISUI/CraftRecipe/ISTiledIconListBox"
require "Entity/ISUI/CraftRecipe/ISWidgetRecipeFilterPanel"
require "Entity/ISUI/CraftRecipe/ISWidgetRecipeCategories"
require "Entity/ISUI/Controls/ISWidgetTitleHeader"
require "Entity/ISUI/CraftRecipe/ISWidgetInput"
require "Entity/ISUI/CraftRecipe/ISWidgetOutput"
require "Entity/ISUI/CraftRecipe/ISWidgetIngredients"
require "Entity/ISUI/CraftRecipe/ISWidgetHandCraftControl"
require "ISUI/Crafting/ISHandcraftWindowHeader"
require "ISUI/Building/ISBuildWindowHeader"
require "N26/Skin/N26_SkinControls"

local Theme = N26.Theme
local D = N26.Draw
local Skin = N26.Skin
local abs = math.abs

N26.registerModule({ id = "crafting", label = "UI_N26_Mod_Crafting", tooltip = "UI_N26_Mod_Crafting_Tip" })
local MODULE = "crafting"

local function near(a, b) return abs(a - b) < 0.02 end

-- Recipe list ----------------------------------------------------------------

local function listRowBorder(self, x, y, w, h, a, r, g, b)
    D.rect(self, x + 6, y + h - 1, w - 12, 1, Theme.C.divider)
end

local function listText(self, str, x, y, r, g, b, a, font)
    local C = Theme.C
    local col
    if near(r, 1) and near(g, 1) and near(b, 1) then col = C.text
    elseif near(r, 0.5) and near(g, 0.5) and near(b, 0.5) then col = C.dim
    end
    if col then
        return D.text(self, str, x, y, col, font, nil, nil, a)
    end
    return ISUIElement.drawText(self, str, x, y, r, g, b, a, font)
end

local listSpec = { fill = false, stroke = false, extra = { drawRectBorder = listRowBorder, drawText = listText } }

N26.hook(ISRecipeScrollingListBox, "ISRecipeScrollingListBox", "doDrawItem", MODULE, function(orig, self, y, item, alt)
    return Skin.intercept(self, listSpec, orig, y, item, alt)
end)

-- Recipe icon grid --------------------------------------------------------------

local function isPanelFrame(self, x, y, w, h)
    return x == 0 and y == 0 and w == self.width and h == self.height
end

local function tileFill(self, x, y, w, h, a, r, g, b)
    if isPanelFrame(self, x, y, w, h) then return ISUIElement.drawRectStatic(self, x, y, w, h, a, r, g, b) end
    local C = Theme.C
    if near(r, 0.2) then
        D.fill(self, x + 1, y + 1, w - 2, h - 2, C.hover2, Theme.R.md, 1, true)   -- hover
    else
        D.fill(self, x + 1, y + 1, w - 2, h - 2, C.accentSoft, Theme.R.md, 1, true) -- selected
    end
end

local function tileStroke(self, x, y, w, h, a, r, g, b)
    if isPanelFrame(self, x, y, w, h) then return ISUIElement.drawRectBorderStatic(self, x, y, w, h, a, r, g, b) end
    local C = Theme.C
    if near(r, 0.8) then
        D.stroke(self, x + 1, y + 1, w - 2, h - 2, C.accent, Theme.R.md, 1, true)
    else
        D.stroke(self, x, y, w, h, C.outline, Theme.R.md, 1, true)
    end
end

local tileSpec = { fill = false, stroke = false, extra = { drawRectStatic = tileFill, drawRectBorderStatic = tileStroke } }

N26.hook(ISTiledIconListBox, "ISTiledIconListBox", "prerender", MODULE, function(orig, self)
    return Skin.intercept(self, tileSpec, orig)
end)

-- Vanilla bug fix: the filter tick boxes are sized from the untranslated key
-- ("IGUI_CraftingUI_ShowAllVersion"), so longer translations (French…) overflow
-- onto the sort label. Size them from the real label; calculateLayout then
-- reserves enough width.
N26.after(ISWidgetRecipeFilterPanel, "ISWidgetRecipeFilterPanel", "createChildren", MODULE, function(self)
    local fh = getTextManager():getFontHeight(UIFont.Small) + 6
    for key, box in pairs({ IGUI_CraftingUI_ShowAllVersion = self.tickBoxShowAllVersion,
                            IGUI_CraftingUI_ShowAllRecipe = self.showAllRecipeTickBox }) do
        if box then
            box:setWidth(fh + 8 + getTextManager():MeasureStringX(UIFont.Small, getText(key)))
        end
    end
end)

-- ===========================================================================
-- Window layout pieces (board 07)
-- ===========================================================================

local floor, max = math.floor, math.max

-- Window header (handcraft "Fabrication" / build "Construction"): raised card
-- with an accent strip and the title as a large condensed heading.
local function headerPanel(self, x, y, w, h)
    local C = Theme.C
    D.fill(self, x, y, w, h, C.panel2, Theme.R.lg, 1, true)
    D.rect(self, x, y + 6, 3, h - 12, C.accent, 1, true)
end

local headerSpec = { fill = false, stroke = false, extra = {
    drawRectStatic = function(self, x, y, w, h) headerPanel(self, x, y, w, h) end,
    drawRectBorderStatic = function(self, x, y, w, h)
        D.stroke(self, x, y, w, h, Theme.C.outline, Theme.R.lg, 1, true)
    end,
} }

for name, cls in pairs({ ISHandcraftWindowHeader = ISHandcraftWindowHeader, ISBuildWindowHeader = ISBuildWindowHeader }) do
    if cls then
        N26.hook(cls, name, "prerender", MODULE, function(orig, self)
            return Skin.intercept(self, headerSpec, orig)
        end)
        N26.after(cls, name, "createChildren", MODULE, function(self)
            if self.title then self.title.n26Heading = "lg" end
        end)
    end
end

-- Category column: pills, the active category filled with the accent.
local function categoryDrawItem(self, y, item, alt)
    local C = Theme.C
    local h = self.itemheight
    item.height = h
    if (y + self:getYScroll() + h < 0) or (y + self:getYScroll() >= self.height) then
        return y + h
    end
    local selected = self.selected == item.index
    local over = (self.mouseoverselected == item.index) and self:isMouseOver() and not self:isMouseOverScrollBar()
    local w = self:getWidth() - (self:isVScrollBarVisible() and 14 or 0)
    if selected then
        D.fill(self, 4, y + 2, w - 8, h - 4, C.accent, Theme.R.md)
    elseif over then
        D.fill(self, 4, y + 2, w - 8, h - 4, C.hover2, Theme.R.md)
    end
    local fh = D.fontHeight(self.font)
    local col = selected and C.onAccent or (over and C.text or C.text2)
    D.text(self, item.text, 14, y + floor((h - fh) / 2), col, self.font, nil, w - 24)
    return y + h
end

N26.after(ISWidgetRecipeCategories, "ISWidgetRecipeCategories", "createChildren", MODULE, function(self)
    local list = self.recipeCategoryPanel
    if not list then return end
    list.drawBorder = false
    list.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    list.itemheight = D.fontHeight(UIFont.Small) + 14
    list.doDrawItem = function(lb, y, item, alt)
        if not N26.isEnabled(MODULE) then return ISScrollingListBox.doDrawItem(lb, y, item, alt) end
        return categoryDrawItem(lb, y, item, alt)
    end
end)

-- Recipe title: condensed heading.
N26.after(ISWidgetTitleHeader, "ISWidgetTitleHeader", "createChildren", MODULE, function(self)
    if self.titleLabel then self.titleLabel.n26Heading = "md" end
end)

-- "Requires" / "Creates" section titles: muted captions.
N26.after(ISWidgetIngredients, "ISWidgetIngredients", "createChildren", MODULE, function(self)
    for _, l in ipairs({ self.inputsLabel, self.outputsLabel }) do
        if l then
            l.n26Heading = "sm"
            l.n26HeadingColor = Theme.C.muted
        end
    end
end)

-- Ingredient / result cells: rounded wells; vanilla state colours (missing =
-- bad colour, partial…) are kept, the neutral border becomes the N26 outline.
local function isNeutral(r, g, b) return math.abs(r - g) < 0.05 and math.abs(g - b) < 0.05 end

local cellSpec = { fill = false, stroke = false, extra = {
    drawRect = function(self, x, y, w, h, a, r, g, b)
        -- hover highlight around the cell
        D.fill(self, x, y, w, h, Theme.C.hover2, Theme.R.lg)
    end,
    drawRectStatic = function(self, x, y, w, h, a, r, g, b)
        D.fill(self, x, y, w, h, Theme.C.field, Theme.R.md, 1, true)
    end,
    drawRectBorderStatic = function(self, x, y, w, h, a, r, g, b)
        local C = Theme.C
        if isNeutral(r, g, b) then
            D.stroke(self, x, y, w, h, C.outline2, Theme.R.md, 1, true)
        else
            local c = { r = r, g = g, b = b, a = 1 }
            D.stroke(self, x, y, w, h, c, Theme.R.md, 1, true)
            D.stroke(self, x + 1, y + 1, w - 2, h - 2, c, Theme.R.md, 0.35, true)
        end
    end,
} }

for name, cls in pairs({ ISWidgetInput = ISWidgetInput, ISWidgetOutput = ISWidgetOutput }) do
    if cls then
        N26.hook(cls, name, "prerender", MODULE, function(orig, self)
            return Skin.intercept(self, cellSpec, orig)
        end)
    end
end

-- Craft controls: card surface, muted labels, primary "Craft" button.
local controlSpec = { fill = false, stroke = false, extra = {
    drawRectStatic = function(self, x, y, w, h)
        D.fill(self, x, y, w, h, Theme.C.panel2, Theme.R.lg, 1, true)
    end,
    drawRectBorderStatic = function(self, x, y, w, h)
        D.stroke(self, x, y, w, h, Theme.C.outline, Theme.R.lg, 1, true)
    end,
} }

N26.hook(ISWidgetHandCraftControl, "ISWidgetHandCraftControl", "prerender", MODULE, function(orig, self)
    return Skin.intercept(self, controlSpec, orig)
end)

N26.after(ISWidgetHandCraftControl, "ISWidgetHandCraftControl", "createChildren", MODULE, function(self)
    for _, l in ipairs({ self.quantityLabel, self.durationLabel }) do
        if l then l.textColor = Theme.copy(Theme.C.muted) end
    end
    if self.buttonCraft then self.buttonCraft.n26Variant = "primary" end
end)
