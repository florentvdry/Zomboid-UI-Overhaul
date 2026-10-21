--[[
    N26 drawing primitives.

    All functions take the ISUIElement to draw into as first argument (`ui`) and use
    element-local coordinates, exactly like ui:drawRect(). Pass static = true for
    content that must not follow the element's scroll offset (list backgrounds…).

    Rounded shapes are built from pre-oriented quarter-circle textures plus
    rectangles that partition the area, so translucent fills never double-blend.
]]

require "ISUI/ISUIElement"
require "N26/Core/N26_Theme"

N26.Draw = N26.Draw or {}
local D = N26.Draw
local Theme = N26.Theme

local TM = getTextManager()
-- Always call the base ISUIElement draw methods: widgets running under
-- Skin.intercept carry instance-level draw overrides that route back here.
local UIE = ISUIElement
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

-- ---------------------------------------------------------------------------
-- Textures
-- ---------------------------------------------------------------------------

local texCache = {}
local function tex(path)
    local t = texCache[path]
    if t == nil then
        t = getTexture(path) or false
        texCache[path] = t
    end
    return t or nil
end
D.tex = tex

local RADII = { 2, 3, 4, 6, 8 }
local function snapRadius(r)
    local best = RADII[1]
    for i = 1, #RADII do
        if RADII[i] <= r then best = RADII[i] end
    end
    return best
end

local cornerCache = {}
local function corners(r, kind)
    local key = r .. kind
    local c = cornerCache[key]
    if not c then
        local base = "media/ui/N26/shape/q" .. r .. "_" .. kind .. "_"
        c = { tl = tex(base .. "tl.png"), tr = tex(base .. "tr.png"),
              bl = tex(base .. "bl.png"), br = tex(base .. "br.png") }
        cornerCache[key] = c
    end
    return c
end

local ICON_SIZES = { 16, 24, 32, 48, 64 }
local iconCache = {}
--- Texture for an icon of the N26 set, choosing the closest native size >= px.
function D.iconTex(name, px)
    local size = 64
    for i = 1, #ICON_SIZES do
        if ICON_SIZES[i] >= (px or 24) then size = ICON_SIZES[i]; break end
    end
    local key = name .. size
    local t = iconCache[key]
    if t == nil then
        t = getTexture("media/ui/N26/icons/" .. size .. "/" .. name .. ".png") or false
        iconCache[key] = t
    end
    return t or nil
end

-- ---------------------------------------------------------------------------
-- Rectangles
-- ---------------------------------------------------------------------------

local function rect(ui, x, y, w, h, c, aMul, static)
    if w <= 0 or h <= 0 then return end
    local a = c.a * (aMul or 1)
    if a <= 0 then return end
    if static then
        UIE.drawRectStatic(ui, x, y, w, h, a, c.r, c.g, c.b)
    else
        UIE.drawRect(ui, x, y, w, h, a, c.r, c.g, c.b)
    end
end
D.rect = rect

local function texRect(ui, t, x, y, w, h, c, a, static)
    if static then
        -- vanilla drawTextureScaledStatic does not compensate scrolling (drawRectStatic
        -- does): subtract it here so static shapes stay glued together
        UIE.drawTextureScaled(ui, t, x - ui:getXScroll(), y - ui:getYScroll(), w, h, a, c.r, c.g, c.b)
    else
        UIE.drawTextureScaled(ui, t, x, y, w, h, a, c.r, c.g, c.b)
    end
end

--- Filled rounded rectangle.
function D.fill(ui, x, y, w, h, c, radius, aMul, static)
    if w <= 0 or h <= 0 or not c then return end
    local a = c.a * (aMul or 1)
    if a <= 0 then return end
    local r = radius and radius > 0 and snapRadius(min(radius, floor(w / 2), floor(h / 2))) or 0
    if r < 2 then
        rect(ui, x, y, w, h, c, aMul, static)
        return
    end
    local q = corners(r, "fill")
    if not q.tl then
        rect(ui, x, y, w, h, c, aMul, static)
        return
    end
    texRect(ui, q.tl, x, y, r, r, c, a, static)
    texRect(ui, q.tr, x + w - r, y, r, r, c, a, static)
    texRect(ui, q.bl, x, y + h - r, r, r, c, a, static)
    texRect(ui, q.br, x + w - r, y + h - r, r, r, c, a, static)
    rect(ui, x + r, y, w - 2 * r, r, c, aMul, static)
    rect(ui, x, y + r, w, h - 2 * r, c, aMul, static)
    rect(ui, x + r, y + h - r, w - 2 * r, r, c, aMul, static)
end

--- 1px rounded outline.
function D.stroke(ui, x, y, w, h, c, radius, aMul, static)
    if w <= 0 or h <= 0 or not c then return end
    local a = c.a * (aMul or 1)
    if a <= 0 then return end
    local r = radius and radius > 0 and snapRadius(min(radius, floor(w / 2), floor(h / 2))) or 0
    if r < 2 then
        if static then
            UIE.drawRectBorderStatic(ui, x, y, w, h, a, c.r, c.g, c.b)
        else
            UIE.drawRectBorder(ui, x, y, w, h, a, c.r, c.g, c.b)
        end
        return
    end
    local q = corners(r, "ring")
    texRect(ui, q.tl, x, y, r, r, c, a, static)
    texRect(ui, q.tr, x + w - r, y, r, r, c, a, static)
    texRect(ui, q.bl, x, y + h - r, r, r, c, a, static)
    texRect(ui, q.br, x + w - r, y + h - r, r, r, c, a, static)
    rect(ui, x + r, y, w - 2 * r, 1, c, aMul, static)
    rect(ui, x + r, y + h - 1, w - 2 * r, 1, c, aMul, static)
    rect(ui, x, y + r, 1, h - 2 * r, c, aMul, static)
    rect(ui, x + w - 1, y + r, 1, h - 2 * r, c, aMul, static)
end

--- Standard surface: fill + outline. opts: fill, border, radius, static
function D.panel(ui, x, y, w, h, fill, border, radius, static)
    local C = Theme.C
    radius = radius or Theme.R.lg
    D.fill(ui, x, y, w, h, fill or C.panel, radius, 1, static)
    if border ~= false then
        D.stroke(ui, x, y, w, h, border or C.outline, radius, 1, static)
    end
end

function D.hline(ui, x, y, w, c, static)
    rect(ui, x, y, w, 1, c or Theme.C.divider, 1, static)
end

function D.vline(ui, x, y, h, c, static)
    rect(ui, x, y, 1, h, c or Theme.C.divider, 1, static)
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------

D.FONT_SMALL = UIFont.Small
D.FONT_MEDIUM = UIFont.Medium
D.FONT_LARGE = UIFont.Large

function D.fontHeight(font)
    return TM:getFontHeight(font or UIFont.Small)
end

function D.measure(font, s)
    if not s or s == "" then return 0 end
    return TM:MeasureStringX(font or UIFont.Small, s)
end

local ELLIPSIS = "..."
local fitCache, fitCount = {}, 0
--- Truncate s with an ellipsis so it fits maxW pixels (cached per font/width).
function D.fit(font, s, maxW)
    if not s then return "" end
    font = font or UIFont.Small
    if maxW <= 0 then return "" end
    if TM:MeasureStringX(font, s) <= maxW then return s end
    local key = tostring(font) .. "|" .. maxW .. "|" .. s
    local cached = fitCache[key]
    if cached then return cached end
    local ellW = TM:MeasureStringX(font, ELLIPSIS)
    local lo, hi = 0, #s
    while lo < hi do
        local mid = ceil((lo + hi) / 2)
        if TM:MeasureStringX(font, s:sub(1, mid)) + ellW <= maxW then lo = mid else hi = mid - 1 end
    end
    -- never cut inside a UTF-8 sequence
    while lo > 0 do
        local b = s:byte(lo + 1)
        if not b or b < 128 or b >= 192 then break end
        lo = lo - 1
    end
    local out = s:sub(1, lo):gsub("%s+$", "") .. ELLIPSIS
    if fitCount > 2000 then fitCache, fitCount = {}, 0 end
    fitCache[key] = out
    fitCount = fitCount + 1
    return out
end

--- Draw text. align: nil/"left", "center", "right". Returns drawn width.
function D.text(ui, s, x, y, c, font, align, maxW, aMul)
    if not s or s == "" then return 0 end
    c = c or Theme.C.text
    font = font or UIFont.Small
    if maxW then s = D.fit(font, s, maxW) end
    local a = c.a * (aMul or 1)
    if align == "center" then
        UIE.drawTextCentre(ui, s, x, y, c.r, c.g, c.b, a, font)
    elseif align == "right" then
        UIE.drawTextRight(ui, s, x, y, c.r, c.g, c.b, a, font)
    else
        UIE.drawText(ui, s, x, y, c.r, c.g, c.b, a, font)
    end
    return TM:MeasureStringX(font, s)
end

-- ---------------------------------------------------------------------------
-- Headings: Barlow Condensed (UIFont.Title / UIFont.Massive slots, see
-- media/fonts/EN/fonts.txt). Falls back to the game font when our bitmap fonts
-- are not active (non-Latin languages ship their own fonts.txt).
-- ---------------------------------------------------------------------------

local HEADING_LINE = 27   -- n26Heading.fnt lineHeight
local DISPLAY_LINE = 58   -- n26Display.fnt lineHeight
local fontsChecked, headingOK, displayOK = false, false, false

local function checkFonts()
    if fontsChecked then return end
    fontsChecked = true
    headingOK = TM:getFontHeight(UIFont.Title) == HEADING_LINE
    displayOK = TM:getFontHeight(UIFont.Massive) == DISPLAY_LINE
    N26.log("heading font %s, display font %s", headingOK and "active" or "fallback", displayOK and "active" or "fallback")
end

function D.headingFontsActive()
    checkFonts()
    return headingOK and displayOK
end

local function useHeadingFont()
    checkFonts()
    return headingOK
end

-- Upper-casing for Latin scripts, accents included. Kahlua strings are Java
-- strings (one char per code point) while standard Lua strings are UTF-8 bytes;
-- string.upper may leave accented letters alone in either model, so Latin-1
-- lower-case letters (à..þ, except ÷) are mapped explicitly for both.
local CHAR_STRINGS = #"\233" == 1 and #"é" == 1
local function upperLatin1(s)
    if CHAR_STRINGS then
        return (s:gsub("[\224-\254]", function(c)
            local b = c:byte()
            if b == 247 then return c end
            return string.char(b - 32)
        end))
    end
    s = s:gsub("\195([\160-\190])", function(c)
        if c == "\183" then return "\195" .. c end
        return "\195" .. string.char(c:byte() - 32)
    end)
    return (s:gsub("\197\147", "\197\146"))   -- œ -> Œ
end

local upperCache, upperCount = {}, 0
local function upper(s)
    local u = upperCache[s]
    if not u then
        u = upperLatin1(string.upper(s))
        if upperCount > 1000 then upperCache, upperCount = {}, 0 end
        upperCache[s] = u
        upperCount = upperCount + 1
    end
    return u
end
D.upper = upper

--- Pixel height for a heading of a given size class ("sm", "md", "lg", "xl").
local HEADING_PX = { sm = 15, md = 19, lg = 26, xl = 40 }

function D.headingHeight(size)
    if not useHeadingFont() then
        if size == "lg" or size == "xl" then return TM:getFontHeight(UIFont.Large) end
        if size == "md" then return TM:getFontHeight(UIFont.Medium) end
        return TM:getFontHeight(UIFont.Small)
    end
    local px = HEADING_PX[size or "md"] * D.fontScale()
    return ceil(px * HEADING_LINE / 22)
end

--- Font scale relative to the default "1x" game font size (Options > Display > Font size).
local fontScaleCache
function D.fontScale()
    if not fontScaleCache then
        fontScaleCache = max(1, TM:getFontHeight(UIFont.Small) / 19)
    end
    return fontScaleCache
end

--- Uppercase condensed heading. Returns the drawn width.
function D.heading(ui, s, x, y, c, size, align, maxW)
    if not s or s == "" then return 0 end
    c = c or Theme.C.text
    size = size or "md"
    if not useHeadingFont() then
        local font = (size == "lg" or size == "xl") and UIFont.Large or (size == "md" and UIFont.Medium or UIFont.Small)
        return D.text(ui, upper(s), x, y, c, font, align, maxW)
    end
    s = upper(s)
    local px = HEADING_PX[size] * D.fontScale()
    local font, zoom
    if px <= 24 then
        font, zoom = UIFont.Title, px / 22
    else
        font, zoom = UIFont.Massive, px / 48
    end
    local w = TM:MeasureStringX(font, s) * zoom
    if maxW and w > maxW then
        -- scale down to fit rather than truncating headings
        zoom = zoom * (maxW / w)
        w = maxW
    end
    if align == "center" then
        x = x - w / 2
    elseif align == "right" then
        x = x - w
    end
    if zoom == 1 then
        UIE.drawText(ui, s, x, y, c.r, c.g, c.b, c.a, font)
    else
        UIE.drawTextZoomed(ui, s, x, y, zoom, c.r, c.g, c.b, c.a, font)
    end
    return w
end

function D.headingWidth(s, size)
    if not s or s == "" then return 0 end
    size = size or "md"
    if not useHeadingFont() then
        local font = (size == "lg" or size == "xl") and UIFont.Large or (size == "md" and UIFont.Medium or UIFont.Small)
        return TM:MeasureStringX(font, upper(s))
    end
    local px = HEADING_PX[size] * D.fontScale()
    if px <= 24 then
        return TM:MeasureStringX(UIFont.Title, upper(s)) * px / 22
    end
    return TM:MeasureStringX(UIFont.Massive, upper(s)) * px / 48
end

--- Large numerals (HUD values). Uses the display font when available.
function D.number(ui, s, x, y, c, px, align)
    c = c or Theme.C.text
    checkFonts()
    if not displayOK then
        local font = px >= 24 and UIFont.Large or UIFont.Medium
        return D.text(ui, s, x, y, c, font, align)
    end
    local zoom = px / 48
    local w = TM:MeasureStringX(UIFont.Massive, s) * zoom
    if align == "center" then x = x - w / 2 elseif align == "right" then x = x - w end
    UIE.drawTextZoomed(ui, s, x, y, zoom, c.r, c.g, c.b, c.a, UIFont.Massive)
    return w
end

-- ---------------------------------------------------------------------------
-- Components
-- ---------------------------------------------------------------------------

--- Icon from the N26 set, tinted.
function D.icon(ui, name, x, y, size, c, aMul, static)
    local t = D.iconTex(name, size)
    if not t then return end
    c = c or Theme.C.text
    local a = c.a * (aMul or 1)
    if static then
        UIE.drawTextureScaled(ui, t, x - ui:getXScroll(), y - ui:getYScroll(), size, size, a, c.r, c.g, c.b)
    else
        UIE.drawTextureScaled(ui, t, x, y, size, size, a, c.r, c.g, c.b)
    end
end

--- Progress bar (thin, flat). frac 0..1
function D.bar(ui, x, y, w, h, frac, c, track, radius, static)
    local C = Theme.C
    frac = max(0, min(1, frac or 0))
    radius = radius or 0
    D.fill(ui, x, y, w, h, track or C.hover2, radius, 1, static)
    local fw = floor(w * frac + 0.5)
    if fw > 0 then
        D.fill(ui, x, y, fw, h, c or C.accent, radius, 1, static)
    end
end

--- Section caption: 10px uppercase muted label (board style).
function D.caption(ui, s, x, y, c, align, maxW)
    return D.heading(ui, s, x, y, c or Theme.C.muted, "sm", align, maxW)
end

--- Accent bar + heading, as used in panel headers. Returns x after the title.
function D.titleWithBar(ui, s, x, y, h, c, size, maxW)
    local C = Theme.C
    local hh = D.headingHeight(size or "md")
    local barH = min(h - 4, max(12, floor(hh * 0.7)))
    rect(ui, x, y + floor((h - barH) / 2), 3, barH, C.accent)
    local tx = x + 3 + Theme.S.sm + 2
    local w = D.heading(ui, s, tx, y + floor((h - hh) / 2) + 1, c or C.text, size or "md", nil, maxW)
    return tx + w
end

--- Keyboard key / shortcut chip. style "accent" (filled) or "ghost".
function D.keycap(ui, label, x, y, h, style, font)
    local C = Theme.C
    font = font or UIFont.Small
    local tw = D.measure(font, label)
    local w = max(h, tw + 10)
    if style == "ghost" then
        D.fill(ui, x, y, w, h, C.hover, Theme.R.md)
        D.stroke(ui, x, y, w, h, C.outline2, Theme.R.md)
        D.text(ui, label, x + w / 2, y + floor((h - D.fontHeight(font)) / 2), C.text2, font, "center")
    else
        D.fill(ui, x, y, w, h, C.accent, Theme.R.md)
        D.text(ui, label, x + w / 2, y + floor((h - D.fontHeight(font)) / 2), C.onAccent, font, "center")
    end
    return w
end

--- Level pips (moodle severity): n filled out of total, vertical or horizontal.
function D.pips(ui, x, y, n, total, c, vertical, pw, ph, gap)
    local C = Theme.C
    pw, ph, gap = pw or 10, ph or 3, gap or 2
    for i = 1, total do
        local col = i <= n and c or C.hover2
        if vertical then
            rect(ui, x, y + (total - i) * (ph + gap), pw, ph, col)
        else
            rect(ui, x + (i - 1) * (pw + gap), y, pw, ph, col)
        end
    end
end

--- Chip / pill (filters, tags). Returns width.
function D.chip(ui, label, x, y, h, active, icon, font)
    local C = Theme.C
    font = font or UIFont.Small
    local pad = 10
    local iw = icon and (h - 10) or 0
    local tw = D.measure(font, label)
    local w = pad * 2 + tw + (icon and (iw + 6) or 0)
    local bg = active and C.accent or C.hover
    local fg = active and C.onAccent or C.text2
    D.fill(ui, x, y, w, h, bg, Theme.R.md)
    local tx = x + pad
    if icon then
        D.icon(ui, icon, tx, y + floor((h - iw) / 2), iw, fg)
        tx = tx + iw + 6
    end
    D.text(ui, label, tx, y + floor((h - D.fontHeight(font)) / 2), fg, font)
    return w
end

--- Soft vignette behind HUD text for legibility over bright terrain.
function D.shade(ui, x, y, w, h, a)
    local t = tex("media/ui/N26/shape/radial.png")
    if t then
        UIE.drawTextureScaled(ui, t, x, y, w, h, a or 0.5, 0, 0, 0)
    end
end
