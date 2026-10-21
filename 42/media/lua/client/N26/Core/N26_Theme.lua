--[[
    N26 design tokens.

    Colours are {r, g, b, a} tables with 0..1 channels, the shape every ISUI widget
    expects. Never mutate a token in place from widget code: copy it (N26.Theme.copy)
    when a widget needs its own table.

    Palette (board 13 · "Spec mod"):
      panel  #0D0F0E · 90 %      outline #FFFFFF · 10 %
      text   #E8EAE6             text2   #C9CEC6     muted #8E948B    dim #4F554C
      accent #E8A33D (option)    ok #7FB069  info #4CC9F0  danger #FF5A5F  mind #C77DFF
    Shape: radius 4 (cells, buttons) / 6 (panels); spacing 4 · 8 · 12 · 16; 1px outlines,
    no blur, no drop shadows.
]]

require "N26/Core/N26_Core"

N26.Theme = N26.Theme or {}
local Theme = N26.Theme

local function hex(h, a)
    h = h:gsub("#", "")
    return {
        r = tonumber(h:sub(1, 2), 16) / 255,
        g = tonumber(h:sub(3, 4), 16) / 255,
        b = tonumber(h:sub(5, 6), 16) / 255,
        a = a or 1,
    }
end
Theme.hex = hex

-- Accent presets offered in the options (index order matters: stored as number).
Theme.ACCENTS = {
    { id = "amber",  label = "UI_N26_Accent_Amber",  color = "#E8A33D", onAccent = "#14110A" },
    { id = "green",  label = "UI_N26_Accent_Green",  color = "#7FB069", onAccent = "#0E140B" },
    { id = "cyan",   label = "UI_N26_Accent_Cyan",   color = "#4CC9F0", onAccent = "#071419" },
    { id = "red",    label = "UI_N26_Accent_Red",    color = "#FF5A5F", onAccent = "#1A0A0B" },
    { id = "violet", label = "UI_N26_Accent_Violet", color = "#C77DFF", onAccent = "#140A1A" },
    { id = "bone",   label = "UI_N26_Accent_Bone",   color = "#D9D2C1", onAccent = "#14130F" },
}

-- Static semantic colours. Panel alpha is driven by the opacity option.
local BASE = {
    bg        = hex("#0A0C0B"),
    panel     = hex("#0D0F0E", 0.90),
    panel2    = hex("#111412", 0.96),   -- raised surface (cards, headers)
    panel3    = hex("#181C19", 1.0),    -- hovered surface
    field     = hex("#080A09", 0.90),   -- inputs, wells
    line      = hex("#232823", 1.0),    -- opaque separators
    outline   = hex("#FFFFFF", 0.10),
    outline2  = hex("#FFFFFF", 0.16),   -- interactive outline
    edge      = hex("#2A302B"),         -- opaque equivalent of outline (remapped vanilla borders)
    edge2     = hex("#3A413B"),         -- opaque equivalent of outline2
    divider   = hex("#FFFFFF", 0.08),
    hover     = hex("#FFFFFF", 0.06),
    hover2    = hex("#FFFFFF", 0.10),
    cell      = hex("#FFFFFF", 0.04),
    text      = hex("#E8EAE6"),
    text2     = hex("#C9CEC6"),
    muted     = hex("#8E948B"),
    dim       = hex("#4F554C"),
    ok        = hex("#7FB069"),
    info      = hex("#4CC9F0"),
    danger    = hex("#FF5A5F"),
    dangerTxt = hex("#FF8A8E"),
    heart     = hex("#E5484D"),
    mind      = hex("#C77DFF"),
    warn      = hex("#E8A33D"),
    black     = hex("#000000"),
    white     = hex("#FFFFFF"),
}

Theme.C = {}           -- live palette (BASE + accent + opacity)
Theme.R = { sm = 3, md = 4, lg = 6 }   -- radii (px)
Theme.S = { xs = 4, sm = 8, md = 12, lg = 16 } -- spacing (px)

local function copyInto(dst, src, alphaMul)
    dst.r, dst.g, dst.b = src.r, src.g, src.b
    dst.a = src.a * (alphaMul or 1)
    return dst
end

function Theme.copy(c, alpha)
    return { r = c.r, g = c.g, b = c.b, a = alpha or c.a }
end

--- Rebuild Theme.C from the current options. Tables in Theme.C keep their identity
-- across refreshes so widgets holding a reference pick up the new values.
function Theme.refresh()
    local cfg = N26.Config
    local accentIdx = cfg and cfg.get("accent") or 1
    local opacity = (cfg and cfg.get("panelOpacity") or 90) / 100
    local preset = Theme.ACCENTS[accentIdx] or Theme.ACCENTS[1]
    local C = Theme.C
    for k, v in pairs(BASE) do
        C[k] = copyInto(C[k] or {}, v)
    end
    -- panels follow the opacity option; raised surfaces stay a bit more opaque
    C.panel.a = opacity
    C.panel2.a = math.min(1, opacity + 0.06)
    C.field.a = math.min(1, opacity + 0.02)
    C.accent = copyInto(C.accent or {}, hex(preset.color))
    C.onAccent = copyInto(C.onAccent or {}, hex(preset.onAccent))
    C.accentSoft = copyInto(C.accentSoft or {}, hex(preset.color, 0.18))
    C.accentLine = copyInto(C.accentLine or {}, hex(preset.color, 0.55))
    Theme.accentId = preset.id
    Theme.version = (Theme.version or 0) + 1
end

--- Health-style ramp: 1 -> ok, 0.5 -> warn, 0 -> danger.
function Theme.ramp(frac)
    local C = Theme.C
    if frac >= 0.66 then return C.ok end
    if frac >= 0.33 then return C.warn end
    return C.danger
end

--- Mix two colours (t = 0 -> a, 1 -> b) into out (allocates when out is nil).
function Theme.mix(a, b, t, out)
    out = out or {}
    out.r = a.r + (b.r - a.r) * t
    out.g = a.g + (b.g - a.g) * t
    out.b = a.b + (b.b - a.b) * t
    out.a = a.a + (b.a - a.a) * t
    return out
end

--- Colour helpers honouring the player's accessibility colours (Options > Display).
function Theme.good()
    local c = getCore():getGoodHighlitedColor()
    return { r = c:getR(), g = c:getG(), b = c:getB(), a = 1 }
end

function Theme.bad()
    local c = getCore():getBadHighlitedColor()
    return { r = c:getR(), g = c:getG(), b = c:getB(), a = 1 }
end

Theme.refresh()
