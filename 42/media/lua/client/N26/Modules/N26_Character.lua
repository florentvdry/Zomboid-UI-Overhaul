--[[
    N26 Character (boards 08 & 12) — ISCharacterScreen (info), ISCharacterInfo
    (skills), ISSkillProgressBar (level pips), ISCharacterProtection.

    All four keep their vanilla layout code (they size the info window); only
    their drawing is remapped:
      * labels → muted, values → primary text (vanilla does the opposite),
        names and section titles → condensed headings with accent rules;
      * skill groups → uppercase captions over a divider; perk names coloured
        by XP-boost tier (none / low / normal / high → dim / text2 / text /
        accent); multiplier arrows → accent chevrons;
      * level pips → rounded N26 cells (textures) in accent / muted / dim;
      * protection table → zebra rows, muted header, coloured values kept.
]]

require "XpSystem/ISUI/ISCharacterScreen"
require "XpSystem/ISUI/ISCharacterInfo"
require "XpSystem/ISUI/ISSkillProgressBar"
require "XpSystem/ISUI/ISCharacterProtection"
require "N26/Skin/N26_SkinControls"

local Theme = N26.Theme
local D = N26.Draw
local Skin = N26.Skin
local floor, abs, max = math.floor, math.abs, math.max

N26.registerModule({ id = "character", label = "UI_N26_Mod_Character", tooltip = "UI_N26_Mod_Character_Tip" })
local MODULE = "character"

local function near(a, b) return abs(a - b) < 0.02 end
local function isWhite(r, g, b) return near(r, 1) and near(g, 1) and near(b, 1) end

-- ---------------------------------------------------------------------------
-- Info sheet
-- ---------------------------------------------------------------------------

local function sheetDrawText(self, str, x, y, r, g, b, a, font)
    local C = Theme.C
    if type(str) ~= "string" then return ISUIElement.drawText(self, str, x, y, r, g, b, a, font) end
    if font == UIFont.Medium and isWhite(r, g, b) then
        -- character name
        return D.heading(self, str, x, y + 2, C.text, "md")
    end
    if isWhite(r, g, b) and near(a, 0.5) then
        return D.text(self, str, x, y, C.text, font)        -- value
    end
    if isWhite(r, g, b) then
        return D.text(self, str, x, y, C.muted, font)       -- label / profession
    end
    return ISUIElement.drawText(self, str, x, y, r, g, b, a, font)
end

local function sheetDrawTextRight(self, str, x, y, r, g, b, a, font)
    if isWhite(r, g, b) then
        return D.text(self, str, x, y, Theme.C.muted, font, "right")
    end
    return ISUIElement.drawTextRight(self, str, x, y, r, g, b, a, font)
end

local function sheetDrawRect(self, x, y, w, h, a, r, g, b)
    if h == 1 then
        -- underline below the name -> short accent rule
        return D.rect(self, x, y + 1, math.min(w, 48), 2, Theme.C.accent)
    end
    return ISUIElement.drawRect(self, x, y, w, h, a, r, g, b)
end

local sheetRenderSpec = { fill = false, stroke = false, extra = {
    drawText = sheetDrawText, drawTextRight = sheetDrawTextRight, drawRect = sheetDrawRect,
} }

N26.hook(ISCharacterScreen, "ISCharacterScreen", "render", MODULE, function(orig, self)
    return Skin.intercept(self, sheetRenderSpec, orig)
end)

-- Avatar well: field surface + viewport brackets instead of a grey box.
local function avatarBorder(self, x, y, w, h)
    local C = Theme.C
    D.fill(self, x, y, w, h, C.field, Theme.R.md)
    local L = 10
    local c = C.white
    D.rect(self, x, y, L, 1, c, 0.3); D.rect(self, x, y, 1, L, c, 0.3)
    D.rect(self, x + w - L, y, L, 1, c, 0.3); D.rect(self, x + w - 1, y, 1, L, c, 0.3)
    D.rect(self, x, y + h - 1, L, 1, c, 0.3); D.rect(self, x, y + h - L, 1, L, c, 0.3)
    D.rect(self, x + w - L, y + h - 1, L, 1, c, 0.3); D.rect(self, x + w - 1, y + h - L, 1, L, c, 0.3)
end

local function avatarTexture(self, tex, x, y, w, h, a, r, g, b)
    if tex == self.avatarBackgroundTexture then
        -- soft top light instead of the grey backdrop
        D.fill(self, x, y, w, h, Theme.C.white, 0, 0.03)
        return
    end
    return ISUIElement.drawTextureScaled(self, tex, x, y, w, h, a, r, g, b)
end

local sheetPrerenderSpec = { extra = {
    drawRectBorder = function(self, x, y, w, h) avatarBorder(self, x, y, w, h) end,
    drawTextureScaled = avatarTexture,
} }

N26.hook(ISCharacterScreen, "ISCharacterScreen", "prerender", MODULE, function(orig, self)
    return Skin.intercept(self, sheetPrerenderSpec, orig)
end)

-- ---------------------------------------------------------------------------
-- Skills
-- ---------------------------------------------------------------------------

local function skillsDrawText(self, str, x, y, r, g, b, a, font)
    local C = Theme.C
    if type(str) ~= "string" then return ISUIElement.drawText(self, str, x, y, r, g, b, a, font) end
    if isWhite(r, g, b) and x <= (self.__n26groupX or 0) + 0.5 then
        -- group header: caption + divider to the right
        local w = D.caption(self, str, x, y + 2)
        D.rect(self, x + w + 10, y + floor(D.fontHeight(font) / 2) + 1, max(0, self.width - (x + w + 10) - 20), 1, C.divider)
        return
    end
    local col
    if near(r, 0.54) then col = C.dim
    elseif near(r, 0.8) then col = C.text2
    elseif near(r, 1) and near(g, 0.83) then col = C.accent
    else col = C.text end
    return D.text(self, str, x, y, col, font)
end

local function skillsDrawTexture(self, tex, x, y, a, r, g, b)
    local C = Theme.C
    if tex == self.SkillBarSeparator then return end
    if tex == self.arrow then
        return D.icon(self, "chevR", x, y, 14, C.accent)
    end
    if tex == self.disabledArrow then
        return D.icon(self, "chevR", x, y, 14, C.dim)
    end
    return ISUIElement.drawTexture(self, tex, x, y, a, r, g, b)
end

local function skillsDrawRectBorder(self, x, y, w, h)
    D.stroke(self, x, y, w, h, Theme.C.accent, Theme.R.md)
end

local skillsSpec = { fill = false, stroke = false, extra = {
    drawText = skillsDrawText,
    drawTexture = skillsDrawTexture,
    drawRectBorder = skillsDrawRectBorder,
} }

N26.hook(ISCharacterInfo, "ISCharacterInfo", "render", MODULE, function(orig, self)
    -- group headers are drawn at `left` (vanilla), perks 20px further right
    local FONT_HGT_SMALL = D.fontHeight(UIFont.Small)
    self.__n26groupX = 10 * 2 + FONT_HGT_SMALL + 6 + 1
    return Skin.intercept(self, skillsSpec, orig)
end)

N26.after(ISCharacterInfo, "ISCharacterInfo", "createChildren", MODULE, function(self)
    for _, b in ipairs(self.buttonList or {}) do
        b.n26TitleButton = true
        b.textureColor = Theme.copy(Theme.C.text2)
    end
end)

-- Level pips: vanilla tints the cell textures; map tints to the palette.
local function pipTexture(self, tex, x, y, w, h, a, r, g, b)
    local C = Theme.C
    local col
    if near(r, 1) and near(g, 0.89) and near(b, 0.38) then col = C.accent       -- acquired
    elseif near(r, 0.4) and near(g, 0.4) then col = C.muted                      -- in progress
    elseif near(r, 0.2) and near(g, 0.2) then col = C.dim                         -- locked
    elseif isWhite(r, g, b) then col = C.text                                     -- ready to train
    end
    if col then r, g, b = col.r, col.g, col.b end
    return ISUIElement.drawTextureScaled(self, tex, x, y, w, h, a, r, g, b)
end

local pipSpec = { fill = false, stroke = false, extra = { drawTextureScaled = pipTexture } }

N26.hook(ISSkillProgressBar, "ISSkillProgressBar", "renderPerkRect", MODULE, function(orig, self)
    return Skin.intercept(self, pipSpec, orig)
end)

-- ---------------------------------------------------------------------------
-- Protection
-- ---------------------------------------------------------------------------

local function protDrawText(self, str, x, y, r, g, b, a, font)
    local C = Theme.C
    if type(str) ~= "string" then return ISUIElement.drawText(self, str, x, y, r, g, b, a, font) end
    local fh = D.fontHeight(UIFont.Small)
    if y <= 11 then
        -- header row
        return D.caption(self, str, x, y + 2)
    end
    if isWhite(r, g, b) then
        -- part name: zebra background across the table
        self.__n26row = (self.__n26row or 0) + 1
        if self.__n26row % 2 == 0 then
            D.rect(self, x - 6, y, self.width - x - 4, fh, C.white, 0.025)
        end
        return D.text(self, str, x, y, C.text2, font)
    end
    return ISUIElement.drawText(self, str, x, y, r, g, b, a, font)
end

local protSpec = { fill = false, stroke = false, extra = { drawText = protDrawText } }

N26.hook(ISCharacterProtection, "ISCharacterProtection", "render", MODULE, function(orig, self)
    self.__n26row = 0
    return Skin.intercept(self, protSpec, orig)
end)
