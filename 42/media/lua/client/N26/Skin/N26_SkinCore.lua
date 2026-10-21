--[[
    N26 skin for the windows shown in the tactical screen — palette remapping
    and draw interception. Nothing outside the tactical screen is affected
    (see N26.scopeOf in N26_Core).

    1. Palette remapping. Vanilla widgets hard-code a small set of greys (black
       panels, 0.4 grey borders, white text…). The first time an element is drawn
       inside the tactical screen, those *default* colours are replaced with
       design tokens. Colours a screen chose on purpose (red warnings, green
       accept…) are not greys and are left alone.

    2. Draw interception. Many widgets draw their frame with full-size
       drawRect/drawRectBorder calls inside otherwise valuable logic (fades,
       tooltips, joypad focus). Skin.intercept() runs the vanilla function while
       routing those full-size rectangles to rounded, themed shapes.
]]

require "ISUI/ISUIElement"
require "ISUI/ISPanel"
require "ISUI/ISPanelJoypad"
require "N26/Core/N26_Draw"
require "N26/Core/N26_Config"

N26.Skin = N26.Skin or {}
local Skin = N26.Skin
local Theme = N26.Theme
local D = N26.Draw
local abs = math.abs

N26.registerModule({ id = "skin", label = "UI_N26_Mod_Skin", tooltip = "UI_N26_Mod_Skin_Tip" })
local floor = math.floor

-- ---------------------------------------------------------------------------
-- Palette remapping
-- ---------------------------------------------------------------------------

local function isGrey(c)
    return abs(c.r - c.g) < 0.03 and abs(c.g - c.b) < 0.03
end

-- Each rule returns the token to use (a copy is stored on the element) or nil.
local C = Theme.C

local function bgFor(c, el)
    if not isGrey(c) or c.r > 0.2 or c.a <= 0 then return nil end
    if el.isButton or el.Type == "ISButton" then
        -- solid black buttons become quiet raised cells
        return Theme.copy(C.cell, 1 * C.cell.a + 0.02)
    end
    if c.a >= 0.95 then return Theme.copy(C.panel2) end
    if c.a >= 0.7 then return Theme.copy(C.panel) end
    -- half-transparent backdrops: keep them lighter than full panels
    return Theme.copy(C.panel, C.panel.a * 0.78)
end

local function hoverFor(c)
    if not isGrey(c) or c.a <= 0 then return nil end
    return Theme.copy(C.hover2, 0.10)
end

-- Remapped borders are opaque dark greys rather than translucent white: a lot of
-- vanilla code draws borderColor's RGB with its own hard-coded alpha (list row
-- separators use 0.5), which must stay subtle.
local function borderFor(c, el)
    if not isGrey(c) or c.a <= 0 then return nil end
    if c.r >= 0.6 then return Theme.copy(C.edge2, c.a) end   -- light borders (buttons, fields)
    return Theme.copy(C.edge, c.a)
end

local function textFor(c)
    if not isGrey(c) or c.r < 0.75 then return nil end
    return Theme.copy(C.text, c.a)
end

local RULES = {
    backgroundColor = bgFor,
    backgroundColorMouseOver = hoverFor,
    borderColor = borderFor,
    textColor = textFor,
    selectedTextColor = textFor,
    choicesColor = function(c) if isGrey(c) then return Theme.copy(C.text2) end end,
    selectionColor = function(c)
        -- vanilla list selection is a translucent orange
        if c.r > 0.6 and c.g < 0.5 and c.b < 0.3 then return Theme.copy(C.accentSoft) end
    end,
    -- altBgColor is deliberately untouched: ISScrollingListBox passes its channels
    -- in (r,g,b,a) order to drawRect(a,r,g,b), so any remap would be misread.
    listHeaderColor = function(c) if isGrey(c) then return Theme.copy(C.panel2) end end,
    mouseOverHighlightColor = function(c) if isGrey(c) and c.r > 0.8 then return Theme.copy(C.hover) end end,
    progressColor = function(c) if c.g > 0.8 and c.r < 0.4 then return Theme.copy(C.accent) end end,
}

local FIELDS = {}
for k in pairs(RULES) do table.insert(FIELDS, k) end

-- Per-class adjustments run after the palette pass: Skin.classHooks[Type](el)
Skin.classHooks = Skin.classHooks or {}

function Skin.apply(el)
    if type(el) ~= "table" or rawget(el, "n26Skinned") or el.n26NoSkin then return end
    if not N26.isEnabled("skin") or N26.scopeOf(el) ~= "window" then return end
    el.n26Skinned = true
    for i = 1, #FIELDS do
        local f = FIELDS[i]
        local c = rawget(el, f)
        if type(c) == "table" and c.r and c.a then
            local rule = RULES[f]
            local n = rule and rule(c, el)
            if n then el[f] = n end
        end
    end
    local hook = Skin.classHooks[el.Type]
    if hook then
        local ok, err = pcall(hook, el)
        if not ok then N26.log("class skin %s failed: %s", tostring(el.Type), tostring(err)) end
    end
end

-- (Skin.apply runs lazily from every scoped hook, see N26.hook.)

-- ---------------------------------------------------------------------------
-- Draw interception
-- ---------------------------------------------------------------------------

local function resolve(v, self, a, r, g, b)
    if type(v) == "function" then return v(self, a, r, g, b) end
    return v
end

local scratch = { r = 0, g = 0, b = 0, a = 0 }
local function passColor(a, r, g, b)
    scratch.r, scratch.g, scratch.b, scratch.a = r, g, b, a
    return scratch
end

local function isFullSize(self, x, w, h)
    return x == 0 and abs(w - self.width) < 1 and abs(h - self.height) < 1
end

local function makeFill(static)
    return function(self, x, y, w, h, a, r, g, b)
        local spec = self.__n26spec
        if spec and spec.fill ~= false and isFullSize(self, x, w, h) then
            -- a style function returning nil means "draw nothing"
            local c
            if spec.fill ~= nil then c = resolve(spec.fill, self, a, r, g, b) else c = passColor(a, r, g, b) end
            if c then D.fill(self, x, y, w, h, c, spec.radius, spec.fillMul, static) end
            return
        end
        if static then
            return ISUIElement.drawRectStatic(self, x, y, w, h, a, r, g, b)
        end
        return ISUIElement.drawRect(self, x, y, w, h, a, r, g, b)
    end
end

local function makeStroke(static)
    return function(self, x, y, w, h, a, r, g, b)
        local spec = self.__n26spec
        if spec and spec.stroke ~= false and isFullSize(self, x, w, h) then
            local c
            if spec.stroke ~= nil then c = resolve(spec.stroke, self, a, r, g, b) else c = passColor(a, r, g, b) end
            if c then D.stroke(self, x, y, w, h, c, spec.radius, 1, static) end
            return
        end
        if static then
            return ISUIElement.drawRectBorderStatic(self, x, y, w, h, a, r, g, b)
        end
        return ISUIElement.drawRectBorder(self, x, y, w, h, a, r, g, b)
    end
end

local PROXY = {
    drawRect = makeFill(false),
    drawRectStatic = makeFill(true),
    drawRectBorder = makeStroke(false),
    drawRectBorderStatic = makeStroke(true),
}

--[[ Run fn(self, ...) with full-size rectangles routed through spec:
   spec.radius  corner radius
   spec.fill    colour / function(self,a,r,g,b) -> colour / false (leave vanilla) / nil (keep passed colour)
   spec.stroke  same for borders
   spec.extra   table of extra method overrides for the duration of the call
]]
function Skin.intercept(self, spec, fn, ...)
    local saved = {}
    for name, proxy in pairs(PROXY) do
        saved[name] = rawget(self, name)
        self[name] = proxy
    end
    if spec.extra then
        for name, f in pairs(spec.extra) do
            saved[name] = rawget(self, name)
            self[name] = f
        end
    end
    local prevSpec = rawget(self, "__n26spec")
    self.__n26spec = spec
    local ok, r1, r2 = pcall(fn, self, ...)
    self.__n26spec = prevSpec
    for name in pairs(PROXY) do self[name] = saved[name] end
    if spec.extra then
        for name in pairs(spec.extra) do self[name] = saved[name] end
    end
    if not ok then error(r1, 0) end
    return r1, r2
end

--- Radius for a generic panel: top-level windows get the large radius.
function Skin.panelRadius(self)
    if self.n26Radius then return self.n26Radius end
    if self.parent == nil then return Theme.R.lg end
    return Theme.R.md
end

-- ---------------------------------------------------------------------------
-- Generic panels
-- ---------------------------------------------------------------------------

local function panelPrerender(orig, self)
    if not self.background then return end
    local r = Skin.panelRadius(self)
    local bg, bd = self.backgroundColor, self.borderColor
    D.fill(self, 0, 0, self.width, self.height, bg, r, 1, true)
    D.stroke(self, 0, 0, self.width, self.height, bd, r, 1, true)
end

N26.hook(ISPanel, "ISPanel", "prerender", "skin", panelPrerender)
N26.hook(ISPanelJoypad, "ISPanelJoypad", "prerender", "skin", panelPrerender)
