--[[
    N26 menus & tooltips — ISContextMenu (board 10), ISToolTip, ISToolTipInv.

    Context menu: a padded dark card (6px radius, 14% outline); rows are inset
    pills — the highlighted row is filled with the accent and its text turns dark,
    unavailable rows are dimmed with their label in the "bad" colour, sub-menus
    show a chevron. Geometry stays vanilla-compatible: itemHgt and padTopBottom are
    the only inputs of getIndexAt/getItemY, and we only change padTopBottom.
]]

require "ISUI/ISContextMenu"
require "ISUI/ISToolTip"
require "ISUI/ISToolTipInv"
require "ISUI/ISInventoryItem"
require "N26/Skin/N26_SkinCore"

local Theme = N26.Theme
local D = N26.Draw
local Skin = N26.Skin
local floor, max = math.floor, math.max
local TM = getTextManager()

N26.registerModule({ id = "menus", label = "UI_N26_Mod_Menus", tooltip = "UI_N26_Mod_Menus_Tip" })
local MODULE = "menus"

local PAD = 4            -- card padding (top/bottom == padTopBottom)
local ROW_INSET = 4      -- horizontal inset of row pills
local ARROW_W = 14

-- padTopBottom is read by getIndexAt/getItemY/calcHeight, so changing it keeps
-- hit-testing exact. Applied when a menu is (re)filled.
local function ensurePadding(menu)
    if menu.padTopBottom ~= PAD then
        menu.padTopBottom = PAD
    end
end

N26.hook(ISContextMenu, "ISContextMenu", "calcHeight", MODULE, function(orig, self)
    ensurePadding(self)
    return orig(self)
end)

local function iconColumn(self)
    local iconSize = self.itemHgt - 12
    return iconSize, ROW_INSET + 6, iconSize + ROW_INSET + 6 + 8
end

N26.hook(ISContextMenu, "ISContextMenu", "calcWidth", MODULE, function(orig, self)
    local maxWidth = 0
    for _, k in ipairs(self.options) do
        local w = TM:MeasureStringX(self.font, k.name)
        if w > maxWidth then maxWidth = w end
    end
    local _, _, textX = iconColumn(self)
    return max(textX + maxWidth + 16 + ARROW_W + ROW_INSET, 140)
end)

local white = { r = 1, g = 1, b = 1, a = 1 }

local function drawOptionIcon(self, k, x, y, size, onAccent)
    if k.color ~= nil and k.iconTexture then
        self:drawTextureScaledAspect(k.iconTexture, x, y, size, size, 1.0, k.color.r, k.color.g, k.color.b)
    elseif k.iconTexture ~= nil then
        self:drawTextureScaledAspect(k.iconTexture, x, y, size, size, 1.0, 1, 1, 1)
    elseif k.itemForTexture ~= nil then
        ISInventoryItem.renderItemIcon(self, k.itemForTexture, x, y, 1.0, size, size)
    end
end

N26.hook(ISContextMenu, "ISContextMenu", "render", MODULE, function(orig, self)
    self.visibleCheck = true
    if self:isEmpty() then return end
    ensurePadding(self)
    local C = Theme.C

    local y = self.padTopBottom
    local dy = 0
    if self:getScrollHeight() > self:getScrollAreaHeight() then
        dy = self.scrollIndicatorHgt
        y = y + dy
    end

    local iconSize, iconX, textX = iconColumn(self)
    local iconShiftY = floor((self.itemHgt - iconSize) / 2)
    local W = self.width

    -- card (static: does not follow the scroll offset)
    D.fill(self, 0, 0, W, self.height, C.panel, Theme.R.lg, 1, true)
    D.fill(self, 0, 0, W, self.height, C.black, Theme.R.lg, 0.35, true)
    D.stroke(self, 0, 0, W, self.height, C.outline2, Theme.R.lg, 1, true)

    local highestWid = 0
    local textDY = floor((self.itemHgt - self.fontHgt) / 2)
    self.currentOptionRect = { x = self.x, y = self.y + y + self:getYScroll(), width = 100, height = self.itemHgt }
    local c = 1
    local sizeMap = {}
    local offTop, offBottom = false, false
    local showTooltip = false
    local highlightedOption = nil
    local good, bad = Theme.good(), Theme.bad()
    local msMul = UIManager.getMillisSinceLastRender() / 33.3

    for i, k in ipairs(self.options) do
        if k.disable then return end
        local rowX, rowW = ROW_INSET, W - ROW_INSET * 2
        local rowY, rowH = y + 1, self.itemHgt - 2
        if y + self:getYScroll() < 0 then
            offTop = true
        elseif y + self:getYScroll() + self.itemHgt > self.scrollIndicatorHgt + self.padTopBottom + self:getScrollAreaHeight() then
            offBottom = true
        else
            local hovered = self.mouseOver == c
            local textCol, iconOnAccent = C.text, false
            local unavailable = k.isDisabled or k.notAvailable

            if hovered then
                if unavailable then
                    D.fill(self, rowX, rowY, rowW, rowH, C.hover, Theme.R.md)
                    D.stroke(self, rowX, rowY, rowW, rowH, C.outline, Theme.R.md)
                else
                    D.fill(self, rowX, rowY, rowW, rowH, C.accent, Theme.R.md)
                    textCol = C.onAccent
                    iconOnAccent = true
                end
            elseif self.blinkOption == k.name and not unavailable then
                if not self.blinkAlpha then
                    self.blinkAlpha = 1
                    self.blinkAlphaIncrease = false
                end
                if not self.blinkAlphaIncrease then
                    self.blinkAlpha = self.blinkAlpha - 0.1 * msMul
                    if self.blinkAlpha < 0 then self.blinkAlpha = 0; self.blinkAlphaIncrease = true end
                else
                    self.blinkAlpha = self.blinkAlpha + 0.1 * msMul
                    if self.blinkAlpha > 1 then self.blinkAlpha = 1; self.blinkAlphaIncrease = false end
                end
                D.fill(self, rowX, rowY, rowW, rowH, C.accentSoft, Theme.R.md, self.blinkAlpha * 2.5)
            end

            local alphaMul = 1
            if k.isDisabled then
                textCol, alphaMul = C.dim, 1
            elseif k.notAvailable then
                textCol, alphaMul = hovered and C.dangerTxt or bad, 0.85
                if not hovered then textCol = Theme.mix(bad, C.text, 0.15) end
            elseif k.badColor and not hovered then
                textCol = bad
            elseif k.goodColor and not hovered then
                textCol = good
            end

            drawOptionIcon(self, k, iconX, y + iconShiftY, iconSize, iconOnAccent)
            D.text(self, k.name, textX, y + textDY, textCol, self.font, nil, nil, alphaMul)

            if k.subOption ~= nil then
                D.icon(self, "chevR", W - ROW_INSET - ARROW_W - 2, y + floor((self.itemHgt - 12) / 2), 12, textCol, alphaMul)
            end
            if k.isDefaultOption then
                D.icon(self, "chevL", ROW_INSET, y + floor((self.itemHgt - 10) / 2), 10, hovered and C.onAccent or C.muted)
            end

            if hovered then
                local isMouseOut = self:isMouseOut()
                if JoypadState.players[self.player + 1] and not self.joyfocus then
                    isMouseOut = true
                end
                if not isMouseOut then
                    highlightedOption = k
                end
                if k.toolTip and not isMouseOut then
                    self:showTooltip(k)
                    showTooltip = true
                end
                if k.subOption ~= nil then
                    if self:isOptionSingleMenu() then
                        -- nothing
                    elseif self.forceVisible then
                        self.subMenu = self:getSubMenu(k.subOption)
                        self.subMenu:setVisible(true)
                        local sdy = (self.subMenu:getScrollHeight() > self.subMenu:getScrollAreaHeight()) and self.scrollIndicatorHgt or 0
                        self:getSubMenu(k.subOption):setY(y - self.subMenu.padTopBottom + self.y + self:getYScroll() - sdy)
                        table.insert(sizeMap, self:getSubMenu(k.subOption))
                    end
                end
                self.currentOptionRect = { x = self.x, y = self.y + y + self:getYScroll(), width = 100, height = self.itemHgt }
            end
        end
        if k.checkMark then
            local tick = self.tickTexture
            if tick then
                local col = (self.mouseOver == c) and C.onAccent or C.accent
                self:drawTextureScaledAspect(tick, iconX, y + iconShiftY, iconSize, iconSize, 1, col.r, col.g, col.b)
            end
        end
        if k.isDefaultOption and self.options[i + 1] and not self.options[i + 1].isDefaultOption then
            D.rect(self, ROW_INSET + 2, y + self.itemHgt - 1, W - (ROW_INSET + 2) * 2, 1, C.divider)
        end
        y = y + self.itemHgt
        local w = TM:MeasureStringX(self.font, k.name)
        if w > highestWid then highestWid = w end
        c = c + 1
    end

    if offTop then
        D.fill(self, 1, 1, W - 2, self.scrollIndicatorHgt, C.panel2, Theme.R.md, 1, true)
        D.icon(self, "chevU", floor(W / 2) - 6, floor((self.scrollIndicatorHgt - 12) / 2) + 1, 12, C.text2, 1, true)
    end
    if offBottom then
        local by = self.height - self.scrollIndicatorHgt - 1
        D.fill(self, 1, by, W - 2, self.scrollIndicatorHgt, C.panel2, Theme.R.md, 1, true)
        D.icon(self, "chevD", floor(W / 2) - 6, by + floor((self.scrollIndicatorHgt - 12) / 2), 12, C.text2, 1, true)
    end

    if self.toolTip then
        self.toolTip:setContextMenu(self)
        self.toolTip:setVisible(true)
    end

    local ww = max(textX + highestWid + 16 + ARROW_W + ROW_INSET, 140)
    self:setWidth(ww)
    self.currentOptionRect.width = ww

    for _, subMenu in ipairs(sizeMap) do
        local subMenuWidth = subMenu:calcWidth()
        if self.parent ~= nil and self.x < self.parent.x then
            subMenu:setX(self.x - subMenuWidth - 2)
        elseif self.x + ww + 2 + subMenuWidth > getCore():getScreenWidth() then
            subMenu:setX(self.x - subMenuWidth - 2)
        else
            subMenu:setX(self.x + ww + 2)
        end
    end

    self:checkHighlightedOption(highlightedOption)

    if not showTooltip and self.player == 0 then
        self:hideToolTip()
    end
end)

-- The menu panel itself must not draw the ISPanel background under our card.
N26.hook(ISContextMenu, "ISContextMenu", "prerender", MODULE, function(orig, self)
    ensurePadding(self)
    return orig(self)
end)

-- ---------------------------------------------------------------------------
-- Tooltips
-- ---------------------------------------------------------------------------

local tipSpec = {
    radius = Theme.R.lg,
    fill = function() return Theme.C.panel2 end,
    stroke = function() return Theme.C.outline2 end,
}

-- ISToolTip draws its frame in render() with hard-coded colours, and its body
-- background in prerender(); route both through the theme.
N26.hook(ISToolTip, "ISToolTip", "prerender", MODULE, function(orig, self)
    return Skin.intercept(self, tipSpec, orig)
end)

local function tipText(self, str, x, y, r, g, b, a, font)
    if self.name and str == self.name then
        local C = Theme.C
        return D.heading(self, str, x, y + 2, C.text, "md")
    end
    return ISUIElement.drawText(self, str, x, y, r, g, b, a, font)
end

local tipRenderSpec = {
    radius = Theme.R.lg,
    fill = false,  -- already painted in prerender
    stroke = function() return Theme.C.outline2 end,
    extra = { drawText = tipText },
}

N26.hook(ISToolTip, "ISToolTip", "render", MODULE, function(orig, self)
    return Skin.intercept(self, tipRenderSpec, orig)
end)

-- Item tooltips: the content is laid out by Java (InventoryItem:DoTooltip), so
-- only the frame can be restyled here; see docs/LIMITATIONS.md.
local invTipSpec = {
    radius = Theme.R.lg,
    fill = function() return Theme.C.panel2 end,
    stroke = function() return Theme.C.outline2 end,
}
N26.hook(ISToolTipInv, "ISToolTipInv", "render", MODULE, function(orig, self)
    Skin.intercept(self, invTipSpec, orig)
    if self.item and self.width > 8 then
        D.rect(self, 1, 1, self.width - 2, 2, Theme.C.accent)
    end
end)
