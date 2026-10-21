--[[
    N26 window chrome — ISCollapsableWindow and everything derived from it
    (≈90 vanilla windows plus most mod windows).

    Layout of the title bar:
        ▌ TITLE (condensed, uppercase)                 [i] [pin|collapse] [×]
    The close button moves from the left to the right edge, the window gets a
    raised header surface separated by a 1px divider, a rounded 6px frame and a
    flat status strip when resizable. Title bar height is unchanged so every
    window keeps its vanilla content layout.
]]

require "ISUI/ISCollapsableWindow"
require "ISUI/ISResizeWidget"
require "N26/Skin/N26_SkinCore"

local Theme = N26.Theme
local D = N26.Draw
local floor = math.floor

local MODULE = "skin"

local function headerColor()
    return Theme.C.panel2
end

local function setXIf(b, x)
    if b.x ~= x then b:setX(x) end
end

--- Extra buttons a window put in its title bar (lock, gear…), right to left.
local function extraTitleButtons(self, th)
    local kids = rawget(self, "childrenInOrder")
    local n = kids and #kids or 0
    local list = rawget(self, "__n26tb")
    if list and self.__n26tbN == n then return list end
    list = {}
    for i = 1, n do
        local c = kids[i]
        if c.isButton and c ~= self.closeButton and c ~= self.pinButton and c ~= self.collapseButton
            and c ~= self.infoButton and c.y <= 2 and c.height <= th then
            c.n26OrigX = c.n26OrigX or c.x
            c.n26TitleButton = true
            list[#list + 1] = c
        end
    end
    table.sort(list, function(a, b) return a.n26OrigX > b.n26OrigX end)
    self.__n26tb, self.__n26tbN = list, n
    return list
end

--- Lay the title-bar buttons out from the right edge: [i] [extras] [pin|collapse] [×].
--- Runs every frame because many windows (XUI build/craft windows…) size
--- themselves after creating their buttons.
local function layoutTitleButtons(self)
    local close = self.closeButton
    if not close or not self.drawFrame then return end
    local th = self:titleBarHeight()
    local bh = close.height
    local x = self.width - 1 - bh
    if close:isVisible() then
        setXIf(close, x)
        x = x - bh - 2
    end
    local pin, col = self.pinButton, self.collapseButton
    if (pin and pin:isVisible()) or (col and col:isVisible()) then
        if pin then setXIf(pin, x) end
        if col then setXIf(col, x) end
        x = x - bh - 2
    end
    for _, b in ipairs(extraTitleButtons(self, th)) do
        if b:isVisible() then
            setXIf(b, x - (b.width - bh))
            x = x - b.width - 2
        end
    end
    if self.infoButton and self.infoButton:isVisible() then
        setXIf(self.infoButton, x)
        x = x - bh - 2
    end
    self.__n26titleRight = x + bh
end

local function tintTitleButtons(self)
    if rawget(self, "__n26tinted") then return end
    self.__n26tinted = true
    for _, b in ipairs({ self.closeButton, self.pinButton, self.collapseButton, self.infoButton }) do
        if b then
            b.n26TitleButton = true
            b.textureColor = Theme.copy(Theme.C.text2)
        end
    end
end

--- Left edge reserved for the title (after accent bar), right edge before buttons.
local function titleArea(self)
    return 10, (self.__n26titleRight or (self.width - 4)) - 6
end

N26.hook(ISCollapsableWindow, "ISCollapsableWindow", "prerender", MODULE, function(orig, self)
    local C = Theme.C
    local th = self:titleBarHeight()
    local height = self.isCollapsed and th or self:getHeight()
    local w = self:getWidth()
    local R = Theme.R.lg
    tintTitleButtons(self)
    layoutTitleButtons(self)

    if self.drawFrame then
        -- body + header share one rounded frame
        D.fill(self, 0, 0, w, height, self.backgroundColor, R)
        D.fill(self, 1, 1, w - 2, th - 1, headerColor(), R - 1)
        if not self.isCollapsed then
            D.rect(self, 1, th - 1, w - 2, 1, C.divider)
        end
    elseif self.background and not self.isCollapsed then
        D.fill(self, 0, th, w, self.height - th, self.backgroundColor, R)
    end

    if self.clearStentil then
        self:setStencilRect(0, 0, w, height)
    end

    if self.title ~= nil and self.drawFrame then
        local left, right = titleArea(self)
        local barH = math.max(8, th - 8)
        D.rect(self, left - 6, floor((th - barH) / 2), 2, barH, C.accent)
        local hh = D.headingHeight("sm")
        D.heading(self, self.title, left, floor((th - hh) / 2) + 1, C.text, "sm", nil, right - left)
    end
end)

N26.hook(ISCollapsableWindow, "ISCollapsableWindow", "render", MODULE, function(orig, self)
    local C = Theme.C
    local th = self:titleBarHeight()
    local height = self.isCollapsed and th or self:getHeight()
    local w = self:getWidth()

    if not self.isCollapsed and self.resizable and self.drawFrame and self.resizeWidget and self.resizeWidget:getIsVisible() then
        local rh = self:resizeWidgetHeight()
        D.rect(self, 1, height - rh, w - 2, 1, C.divider)
        local grip = self.resizeimage
        if grip then
            self:drawTextureScaled(grip, w - rh + 1, height - rh + 1, rh - 2, rh - 2, 1, 1, 1, 1)
        end
    end

    if self.clearStentil then
        self:clearStencilRect()
    end
    if self.drawFrame then
        D.stroke(self, 0, 0, w, height, self.borderColor, Theme.R.lg)
    end

    if self.drawJoypadFocus then
        D.stroke(self, 0, 0, w, self:getHeight(), C.accent, Theme.R.lg)
        D.stroke(self, 1, 1, w - 2, self:getHeight() - 2, C.accentLine, Theme.R.lg - 1)
    end
end)
