--[[
    N26 controls — buttons, tick boxes, combo boxes, text fields, scroll bars,
    tab panels, list boxes, modal dialogs, progress bars.

    Behaviour is always the vanilla one: either the vanilla function runs under
    Skin.intercept (only its rectangles are restyled) or, where the visuals are the
    whole function (scroll bar, tab strip), it is rewritten keeping every state
    field other code relies on (barx/bary…, tab drag & blink, overflow arrows).
]]

require "ISUI/ISButton"
require "ISUI/ISTickBox"
require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISScrollBar"
require "ISUI/ISTabPanel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISModalDialog"
require "ISUI/ISProgressBar"
require "N26/Skin/N26_SkinCore"

local Theme = N26.Theme
local D = N26.Draw
local Skin = N26.Skin
local floor, max, min = math.floor, math.max, math.min
local MODULE = "skin"

local tmpA, tmpB = {}, {}

-- ---------------------------------------------------------------------------
-- ISButton
-- ---------------------------------------------------------------------------

-- Semantic variants replace the vanilla accept/cancel colour helpers.
N26.after(ISButton, "ISButton", "enableAcceptColor", MODULE, function(self) self.n26Variant = "primary" end)
N26.after(ISButton, "ISButton", "enableCancelColor", MODULE, function(self) self.n26Variant = "danger" end)
N26.after(ISButton, "ISButton", "restoreDefaultColors", MODULE, function(self)
    self.n26Variant = nil
    Skin.apply(self)
end)

local function buttonFill(self, a, r, g, b)
    local C = Theme.C
    local over = (self.mouseOver and self:isMouseOver()) or self.joypadFocused
    if self.n26TitleButton then
        if over and self.enable then return C.hover2 end
        return nil
    end
    if not self.enable then
        return C.cell
    end
    local v = self.n26Variant
    if v == "primary" then
        local base = C.accent
        if self.pressed then return Theme.mix(base, C.black, 0.25, tmpA) end
        if over then return Theme.mix(base, C.white, 0.14, tmpA) end
        return base
    elseif v == "danger" then
        tmpA.r, tmpA.g, tmpA.b = C.danger.r, C.danger.g, C.danger.b
        tmpA.a = over and 0.28 or 0.14
        return tmpA
    end
    -- default: vanilla blend of (remapped) background and hover colours
    tmpA.r, tmpA.g, tmpA.b, tmpA.a = r, g, b, a
    return tmpA
end

local function buttonStroke(self, a, r, g, b)
    local C = Theme.C
    if self.n26TitleButton then return nil end
    local over = (self.mouseOver and self:isMouseOver()) or self.joypadFocused
    local v = self.n26Variant
    if not self.enable then return C.divider end
    if v == "primary" then return nil end
    if v == "danger" then
        tmpB.r, tmpB.g, tmpB.b, tmpB.a = C.danger.r, C.danger.g, C.danger.b, 0.6
        return tmpB
    end
    if over then return C.accentLine end
    if a <= 0 then return nil end
    tmpB.r, tmpB.g, tmpB.b, tmpB.a = r, g, b, a
    return tmpB
end

local buttonSpec = { radius = Theme.R.md, fill = buttonFill, stroke = buttonStroke }

N26.hook(ISButton, "ISButton", "prerender", MODULE, function(orig, self)
    return Skin.intercept(self, buttonSpec, orig)
end)

-- Text colour per variant; disabled text uses the dim token instead of 0.3 grey.
local function buttonDrawText(self, str, x, y, r, g, b, a, font)
    local C = Theme.C
    if str == self.title then
        local c
        if not self.enable then
            c = C.dim
        elseif self.n26Variant == "primary" then
            c = C.onAccent
        elseif self.n26Variant == "danger" then
            c = C.dangerTxt
        end
        if c then r, g, b = c.r, c.g, c.b end
    end
    return ISUIElement.drawText(self, str, x, y, r, g, b, a, font)
end

local buttonRenderSpec = { fill = false, stroke = false, extra = { drawText = buttonDrawText } }

N26.hook(ISButton, "ISButton", "render", MODULE, function(orig, self)
    if self.title == nil or self.title == "" then
        return orig(self)
    end
    return Skin.intercept(self, buttonRenderSpec, orig)
end)

-- ---------------------------------------------------------------------------
-- ISTickBox
-- ---------------------------------------------------------------------------

local function tickDrawRect(self, x, y, w, h, a, r, g, b)
    if w == self.boxSize and h == self.boxSize then
        D.fill(self, x, y, w, h, Theme.C.hover2, Theme.R.sm)
        D.stroke(self, x, y, w, h, Theme.C.accentLine, Theme.R.sm)
        return
    end
    return ISUIElement.drawRect(self, x, y, w, h, a, r, g, b)
end

local function tickDrawRectBorder(self, x, y, w, h, a, r, g, b)
    if w == self.boxSize and h == self.boxSize then
        D.fill(self, x, y, w, h, Theme.C.field, Theme.R.sm)
        D.stroke(self, x, y, w, h, Theme.C.outline2, Theme.R.sm)
        return
    end
    -- joypad focus row
    D.stroke(self, x, y, w, h, Theme.C.accentLine, Theme.R.md)
end

local function tickDrawTextureScaled(self, tex, x, y, w, h, a, r, g, b)
    if tex == self.tickTexture then
        local C = Theme.C
        D.fill(self, x - 2, y - 2, w + 4, h + 4, C.accent, Theme.R.sm)
        return ISUIElement.drawTextureScaled(self, tex, x, y, w, h, a, C.onAccent.r, C.onAccent.g, C.onAccent.b)
    end
    return ISUIElement.drawTextureScaled(self, tex, x, y, w, h, a, r, g, b)
end

local tickSpec = { fill = false, stroke = false, extra = {
    drawRect = tickDrawRect, drawRectBorder = tickDrawRectBorder, drawTextureScaled = tickDrawTextureScaled,
} }

N26.hook(ISTickBox, "ISTickBox", "render", MODULE, function(orig, self)
    return Skin.intercept(self, tickSpec, orig)
end)

-- ---------------------------------------------------------------------------
-- ISComboBox
-- ---------------------------------------------------------------------------

local function comboStroke(self, a)
    local C = Theme.C
    if self.disabled then return C.divider end
    local f = self.fade and self.fade:fraction() or 0
    if self.expanded or self.joypadFocused then return C.accentLine end
    return Theme.mix(C.outline2, C.accentLine, f, tmpB)
end

local comboSpec = { radius = Theme.R.md, stroke = comboStroke }

N26.hook(ISComboBox, "ISComboBox", "prerender", MODULE, function(orig, self)
    return Skin.intercept(self, comboSpec, orig)
end)

Skin.classHooks.ISComboBox = function(el)
    local t = D.iconTex("chevD", 16)
    if t then el.image = t end
    el.backgroundColor = Theme.copy(Theme.C.field)
end

-- ---------------------------------------------------------------------------
-- ISTextEntryBox
-- ---------------------------------------------------------------------------

local function entryStroke(self, a, r, g, b)
    local C = Theme.C
    if self.javaObject and self.javaObject:isFocused() then return C.accent end
    if self.joyfocus or self.joypadFocused then return C.accentLine end
    if self.borderColor and not (self.borderColor.r == self.borderColor.g and self.borderColor.g == self.borderColor.b) then
        -- a screen-specific coloured border (validation…) wins
        tmpB.r, tmpB.g, tmpB.b, tmpB.a = r, g, b, a
        return tmpB
    end
    local f = self.fade and self.fade:fraction() or 0
    return Theme.mix(C.outline2, C.accentLine, f * 0.6, tmpB)
end

local entrySpec = { radius = Theme.R.md, stroke = entryStroke }

N26.hook(ISTextEntryBox, "ISTextEntryBox", "prerender", MODULE, function(orig, self)
    return Skin.intercept(self, entrySpec, orig)
end)

Skin.classHooks.ISTextEntryBox = function(el)
    local c = el.backgroundColor
    if c and c.a > 0 and c.r < 0.2 and c.g < 0.2 then
        el.backgroundColor = Theme.copy(Theme.C.field)
    end
end

-- ---------------------------------------------------------------------------
-- ISScrollBar — slim rounded thumb; same hit geometry as vanilla.
-- ---------------------------------------------------------------------------

N26.hook(ISScrollBar, "ISScrollBar", "render", MODULE, function(orig, self)
    local C = Theme.C
    local mx, my = self:getMouseX(), self:getMouseY()
    local over = self:isMouseOver()
    local onThumb = self.scrolling or (over and self:isPointOverThumb(mx, my))
    local thumb = self.scrolling and C.accent or (onThumb and C.text2 or C.muted)
    local thumbA = self.scrolling and 1 or (onThumb and 0.8 or (over and 0.55 or 0.35))
    local arrowA = over and 0.7 or 0.35
    local upH = self.uptex and self.uptex:getHeight() or 16

    if self.vertical then
        local sh = self.parent:getScrollHeight()
        if sh > self:getHeight() then
            if self.doSetStencil then self:setStencilRect(0, 0, self.width, self.height) end
            local del = self:getHeight() / sh
            local boxheight = max(8, math.ceil(del * (self:getHeight() - (16 * 2))))
            local dif = math.ceil((self:getHeight() - (16 * 2) - boxheight) * self.pos)
            self.barx = 2 + 3
            self.bary = 16 + dif
            self.barwidth = 8
            self.barheight = boxheight

            local cx = floor(self.width / 2) + 1
            D.fill(self, cx - 2, 16, 4, self.height - 32, C.hover, 2)
            D.fill(self, cx - 2, self.bary + 1, 4, self.barheight - 2, thumb, 2, thumbA)
            D.icon(self, "chevU", cx - 6, 2, 12, C.text2, arrowA)
            D.icon(self, "chevD", cx - 6, self.height - 14, 12, C.text2, arrowA)
            if self.doSetStencil then self:clearStencilRect() end
        else
            self.barx, self.bary, self.barwidth, self.barheight = 0, 0, 0, 0
        end
    else
        local sw = self.parent:getScrollWidth()
        if sw > self:getWidth() then
            if self.doSetStencil then self:setStencilRect(0, 0, self.width, self.height) end
            local del = self:getWidth() / sw
            local boxwidth = max(8, math.ceil(del * (self:getWidth() - (16 * 2))))
            local dif = math.ceil((self:getWidth() - (16 * 2) - boxwidth) * self.pos)
            self.barx = 16 + dif
            self.bary = 2 + 3
            self.barwidth = boxwidth
            self.barheight = 8

            local cy = floor(self.height / 2) + 1
            D.fill(self, 16, cy - 2, self.width - 32, 4, C.hover, 2)
            D.fill(self, self.barx + 1, cy - 2, self.barwidth - 2, 4, thumb, 2, thumbA)
            D.icon(self, "chevL", 2, cy - 6, 12, C.text2, arrowA)
            D.icon(self, "chevR", self.width - 14, cy - 6, 12, C.text2, arrowA)
            if self.doSetStencil then self:clearStencilRect() end
        else
            self.barx, self.bary, self.barwidth, self.barheight = 0, 0, 0, 0
        end
    end
end)

-- ---------------------------------------------------------------------------
-- ISTabPanel — flat tabs, active tab raised with an accent underline.
-- ---------------------------------------------------------------------------

N26.hook(ISTabPanel, "ISTabPanel", "render", MODULE, function(orig, self)
    local C = Theme.C
    local newViewList = {}
    local tabDragSelected = -1
    if self.draggingTab and not self.isDragging and ISTabPanel.xMouse > -1 and ISTabPanel.xMouse ~= self:getMouseX() then
        self.isDragging = self.allowDraggingTabs
    end
    local tabWidth = self.maxLength
    local inset = 1
    local gap = 1
    local th = self.tabHeight
    if self.isDragging and not ISTabPanel.mouseOut then
        for i, viewObject in ipairs(self.viewList) do
            if i ~= (self.draggingTab + 1) then
                table.insert(newViewList, viewObject)
            else
                ISTabPanel.viewDragging = viewObject
            end
        end
        tabDragSelected = self:getTabIndexAtX(self:getMouseX()) - 1
        tabDragSelected = min(#self.viewList - 1, max(tabDragSelected, 0))
        D.stroke(self, inset + (tabDragSelected * (tabWidth + gap)), 0, tabWidth, th - 1, C.accent, Theme.R.md)
    else
        newViewList = self.viewList
    end

    -- content area
    local bg = self.backgroundColor
    if bg and bg.a > 0 then
        D.fill(self, 0, th, self.width, self.height - th, bg, Theme.R.md)
    end
    D.rect(self, 0, th - 1, self.width, 1, C.divider)

    local x = inset
    if self.centerTabs and (self:getWidth() >= self:getWidthOfAllTabs()) then
        x = (self:getWidth() - self:getWidthOfAllTabs()) / 2
    else
        x = x + self.scrollX
    end
    local widthOfAllTabs = self:getWidthOfAllTabs()
    local overflowLeft = self.scrollX < 0
    local overflowRight = x + widthOfAllTabs > self.width
    local blinkTabsAlphaNotUpdated = true
    if widthOfAllTabs > self.width then
        self:setStencilRect(0, 0, self.width, th)
    end
    local fontHgt = D.fontHeight(UIFont.Small)
    local textY = max(1, floor((th - 1 - fontHgt) / 2))
    local msMul = UIManager.getMillisSinceLastRender() / 33.3
    for i, viewObject in ipairs(newViewList) do
        tabWidth = self.equalTabWidth and self.maxLength or viewObject.tabWidth
        if tabDragSelected ~= -1 and i == (tabDragSelected + 1) then
            x = x + tabWidth + gap
        end
        local active = viewObject.id == self.activeView.id and not self.isDragging and not ISTabPanel.mouseOut
        local textCol = C.muted
        local tabA = self.tabTransparency or 1
        if active then
            D.fill(self, x, 0, tabWidth, th - 1, C.panel3, Theme.R.md, tabA)
            D.rect(self, x + 4, th - 3, tabWidth - 8, 2, C.accent, tabA)
            textCol = C.text
        else
            local shouldBlink = false
            if self.blinkTabs then
                for _, tab in ipairs(self.blinkTabs) do
                    if tab and tab == viewObject.name then shouldBlink = true end
                end
            end
            if (self.blinkTab and self.blinkTab == viewObject.name) or (shouldBlink and blinkTabsAlphaNotUpdated) then
                blinkTabsAlphaNotUpdated = false
                if not self.blinkTabAlpha then
                    self.blinkTabAlpha = self.tabTransparency
                    self.blinkTabAlphaIncrease = false
                end
                if not self.blinkTabAlphaIncrease then
                    self.blinkTabAlpha = self.blinkTabAlpha - 0.1 * self.tabTransparency * msMul
                    if self.blinkTabAlpha < 0 then
                        self.blinkTabAlpha = 0
                        self.blinkTabAlphaIncrease = true
                    end
                else
                    self.blinkTabAlpha = self.blinkTabAlpha + 0.1 * self.tabTransparency * msMul
                    if self.blinkTabAlpha > self.tabTransparency then
                        self.blinkTabAlpha = self.tabTransparency
                        self.blinkTabAlphaIncrease = false
                    end
                end
                D.fill(self, x, 0, tabWidth, th - 1, C.accentSoft, Theme.R.md, self.blinkTabAlpha * 2)
                textCol = C.text
            elseif shouldBlink then
                D.fill(self, x, 0, tabWidth, th - 1, C.accentSoft, Theme.R.md, (self.blinkTabAlpha or 0.5) * 2)
                textCol = C.text
            else
                if self:getMouseY() >= 0 and self:getMouseY() < th and self:isMouseOver() and self:getTabIndexAtX(self:getMouseX()) == i then
                    viewObject.fade:setFadeIn(true)
                else
                    viewObject.fade:setFadeIn(false)
                end
                viewObject.fade:update()
                local f = viewObject.fade:fraction()
                if f > 0 then
                    D.fill(self, x, 0, tabWidth, th - 1, C.hover, Theme.R.md, f * tabA)
                    textCol = Theme.mix(C.muted, C.text2, f, tmpA)
                end
            end
        end
        local label = D.fit(UIFont.Small, viewObject.name, tabWidth - 8)
        D.text(self, label, x + (tabWidth / 2), textY, textCol, UIFont.Small, "center", nil, self.textTransparency)
        x = x + tabWidth + gap
    end

    local butPadX = 3
    if overflowLeft then
        local tex = getTexture("media/ui/ArrowLeft.png")
        local butWid = (tex and tex:getWidthOrig() or 10) + butPadX * 2
        D.fill(self, inset, 0, butWid, th, C.panel2, Theme.R.md)
        D.icon(self, "chevL", inset + floor((butWid - 12) / 2), floor((th - 12) / 2), 12, C.text)
    end
    if overflowRight then
        local tex = getTexture("media/ui/ArrowRight.png")
        local butWid = (tex and tex:getWidthOrig() or 10) + butPadX * 2
        D.fill(self, self.width - inset - butWid, 0, butWid, th, C.panel2, Theme.R.md)
        D.icon(self, "chevR", self.width - inset - butWid + floor((butWid - 12) / 2), floor((th - 12) / 2), 12, C.text)
    end
    if widthOfAllTabs > self.width then
        self:clearStencilRect()
    end
    if self.draggingTab and self.isDragging and not ISTabPanel.mouseOut then
        local gx
        if self.draggingTab > 0 then
            gx = inset + (self.draggingTab * (tabWidth + gap)) + (self:getMouseX() - ISTabPanel.xMouse)
        else
            gx = inset + (self:getMouseX() - ISTabPanel.xMouse)
        end
        D.fill(self, gx, 0, tabWidth, th - 1, C.panel3, Theme.R.md, 0.9)
        D.rect(self, gx + 4, th - 3, tabWidth - 8, 2, C.accent)
        D.text(self, ISTabPanel.viewDragging.name, gx + (tabWidth / 2), textY, C.text, UIFont.Small, "center")
    end
end)

-- ---------------------------------------------------------------------------
-- ISScrollingListBox
-- ---------------------------------------------------------------------------

N26.hook(ISScrollingListBox, "ISScrollingListBox", "drawSelection", MODULE, function(orig, self, x, y, w, h)
    local C = Theme.C
    D.rect(self, x, y, w, h, C.accentSoft)
    D.rect(self, x, y, 2, h, C.accent)
end)

N26.hook(ISScrollingListBox, "ISScrollingListBox", "drawMouseOverHighlight", MODULE, function(orig, self, x, y, w, h)
    D.rect(self, x, y, w, h, Theme.C.hover)
end)

local listSpec = { radius = Theme.R.md }
N26.hook(ISScrollingListBox, "ISScrollingListBox", "prerender", MODULE, function(orig, self)
    return Skin.intercept(self, listSpec, orig)
end)

-- ---------------------------------------------------------------------------
-- ISModalDialog — raised card, title text in the primary colour
-- ---------------------------------------------------------------------------

local modalSpec = { radius = Theme.R.lg, stroke = function() return Theme.C.outline2 end }
N26.hook(ISModalDialog, "ISModalDialog", "prerender", MODULE, function(orig, self)
    Skin.intercept(self, modalSpec, orig)
    D.rect(self, 1, 1, self.width - 2, 2, Theme.C.accent)
end)

-- ---------------------------------------------------------------------------
-- ISProgressBar — flat bar, accent fill
-- ---------------------------------------------------------------------------

local progressSpec = { radius = Theme.R.sm }
N26.hook(ISProgressBar, "ISProgressBar", "prerender", MODULE, function(orig, self)
    return Skin.intercept(self, progressSpec, orig)
end)

-- ---------------------------------------------------------------------------
-- ISLabel — optional condensed heading rendering.
-- Modules flag a label with label.n26Heading = "sm" | "md" | "lg" (and
-- optionally label.n26HeadingColor) to draw it as an N26 heading.
-- ---------------------------------------------------------------------------

require "ISUI/ISLabel"

local function labelHeadingText(self, str, x, y, r, g, b, a, font)
    local size = self.n26Heading
    local hh = D.headingHeight(size)
    local ty = floor((self.height - hh) / 2) + 1
    local col = self.n26HeadingColor or Theme.C.text
    return D.heading(self, str, x, ty, col, size, nil, self.n26HeadingMaxW)
end

local labelHeadingSpec = { fill = false, stroke = false, extra = {
    drawText = labelHeadingText,
    drawTextCentre = function(self, str, x, y, r, g, b, a, font)
        local w = D.headingWidth(str, self.n26Heading)
        return labelHeadingText(self, str, x - w / 2, y, r, g, b, a, font)
    end,
} }

N26.hook(ISLabel, "ISLabel", "prerender", MODULE, function(orig, self)
    if not self.n26Heading then return orig(self) end
    return Skin.intercept(self, labelHeadingSpec, orig)
end)
