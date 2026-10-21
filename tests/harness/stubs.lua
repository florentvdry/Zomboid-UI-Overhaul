--[[
    Headless stand-ins for the Java side of Project Zomboid's UI, so the real
    vanilla ISUI Lua files and the N26 mod can run under a plain Lua VM.

    * UIElement.new() returns a recorder: every Draw* call is appended to DRAWLOG.
    * Text metrics are deterministic (7px per char) so layout code is testable.
    * Unknown globals resolve to a permissive "Any" object so vanilla files that
      touch unrelated engine APIs at load time still load. Tests must not rely on
      Any for behaviour they check.
]]

unpack = unpack or table.unpack
loadstring = loadstring or load

DRAWLOG = {}
function resetDrawLog() DRAWLOG = {} end

local function absOf(peer)
    local x, y = 0, 0
    local e = peer and peer.lua
    local guard = 0
    while type(e) == "table" and guard < 64 do
        x = x + (tonumber(rawget(e, "x")) or 0)
        y = y + (tonumber(rawget(e, "y")) or 0)
        e = rawget(e, "parent")
        guard = guard + 1
    end
    return x, y
end

local function record(kind, ...)
    DRAWLOG[#DRAWLOG + 1] = { kind = kind, args = { ... } }
end

local function recordPeer(kind, peer, ...)
    local ax, ay = absOf(peer)
    DRAWLOG[#DRAWLOG + 1] = { kind = kind, args = table.pack(...), ax = ax, ay = ay,
        sx = peer and peer.xscroll or 0, sy = peer and peer.yscroll or 0 }
end

-- ---------------------------------------------------------------- Any
local Any
local anyMeta = {}
anyMeta.__index = function() return Any end
anyMeta.__call = function() return Any end
anyMeta.__tostring = function() return "Any" end
anyMeta.__concat = function(a, b) return tostring(a) .. tostring(b) end
anyMeta.__len = function() return 0 end
anyMeta.__eq = function() return false end
anyMeta.__lt = function() return false end
anyMeta.__le = function() return false end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__unm", "__pow" }) do
    anyMeta[op] = function() return 0 end
end
Any = setmetatable({}, anyMeta)

-- ---------------------------------------------------------------- fonts / text
UIFont = {}
local FONT_H = {
    Small = 19, Medium = 29, Large = 33, Massive = 58, Title = 27, Code = 20, CodeSmall = 19,
    CodeMedium = 29, CodeLarge = 33, NewSmall = 19, NewMedium = 29, NewLarge = 33, Cred1 = 20, Cred2 = 32,
    Intro = 33, Handwritten = 19, Dialogue = 19, MainMenu1 = 40, MainMenu2 = 40, DebugConsole = 16,
    MediumNew = 29, AutoNormSmall = 19, AutoNormMedium = 29, AutoNormLarge = 33,
}
for k in pairs(FONT_H) do UIFont[k] = k end
UIFont.FromString = function(s) return UIFont[s] end

local TM = {}
local function metrics(f)
    return FONT_METRICS and (FONT_METRICS[f] or FONT_METRICS.Small)
end
function TM:getFontHeight(f)
    local m = metrics(f)
    if m then return m.lineHeight end
    return FONT_H[f] or 19
end
function TM:MeasureStringX(f, s)
    s = tostring(s or "")
    local m = metrics(f)
    if not m then return #s * 7 end
    local w, prev = 0, nil
    for _, cp in utf8.codes(s) do
        w = w + (m.adv[cp] or m.adv[63] or 7)
        if prev and m.kern[prev * 65536 + cp] then w = w + m.kern[prev * 65536 + cp] end
        prev = cp
    end
    return w
end
function TM:MeasureStringY(f, s) return TM:getFontHeight(f) end
function TM:MeasureFont(f) return TM:getFontHeight(f) end
function TM:getFontFromEnum(f)
    return { getLineHeight = function() return TM:getFontHeight(f) end }
end
function TM:DrawString(...) record("TM.DrawString", ...) end
function TM:DrawStringCentre(...) record("TM.DrawStringCentre", ...) end
function TM:DrawStringRight(...) record("TM.DrawStringRight", ...) end
function TM:WrapText(f, s) return s end
function getTextManager() return TM end

-- ---------------------------------------------------------------- textures
local texMeta = { __index = {} }
local T = texMeta.__index
function T:getWidth() return self.w end
function T:getHeight() return self.h end
function T:getWidthOrig() return self.w end
function T:getHeightOrig() return self.h end
function T:getName() return self.path end
function T:isReady() return true end
function T:getOffsetX() return 0 end
function T:getOffsetY() return 0 end
TEXTURES_REQUESTED = {}
function getTexture(path)
    if path == nil then return nil end
    TEXTURES_REQUESTED[path] = true
    local d = TEX_DIMS and (TEX_DIMS[path] or TEX_DIMS[string.lower(path)])
    return setmetatable({ path = path, w = d and d[1] or 16, h = d and d[2] or 16 }, texMeta)
end
Texture = { getSharedTexture = getTexture, trygetTexture = getTexture }

-- ---------------------------------------------------------------- core
local Core = {}
function Core:getScreenWidth() return 1920 end
function Core:getScreenHeight() return 1080 end
function Core:getOptionFontSizeReal() return 1 end
function Core:getOptionFontSize() return 1 end
function Core:getGoodHighlitedColor() return { getR = function() return 0.2 end, getG = function() return 0.8 end, getB = function() return 0.2 end } end
function Core:getBadHighlitedColor() return { getR = function() return 0.8 end, getG = function() return 0.2 end, getB = function() return 0.2 end } end
function Core:getOptionSingleContextMenu() return false end
function Core:getOptionContextMenuFont() return "Medium" end
function Core:isDisplayCursor() return true end
function Core:setDisplayCursor() end
function Core:getOptionUIRenderFPS() return 30 end
function Core:getOptionTooltipFont() return "Small" end
function Core:getOptionInventoryFont() return "Medium" end
function Core:getOptionInventoryContainerSize() return 2 end
function Core:getGameMode() return "Sandbox" end
function Core:getOptionDoContainerOutline() return false end
setmetatable(Core, { __index = function() return function() return Any end end })
function getCore() return Core end

function getDebug() return false end
function isDebugEnabled() return false end
function isClient() return false end
function isServer() return false end
function getText(key, ...) return key end
function getTextOrNull(key) return nil end
function getMouseX() return MOUSE_X or 0 end
function getMouseY() return MOUSE_Y or 0 end
function isMouseButtonDown() return false end
function getTimestampMs() return 0 end
function getPlayerScreenLeft() return 0 end
function getPlayerScreenTop() return 0 end
function getPlayerScreenWidth() return 1920 end
function getPlayerScreenHeight() return 1080 end
function instanceof() return false end
function getSpecificPlayer() return nil end
function getNumActivePlayers() return 1 end

string.sort = string.sort or function(a, b) return tostring(a) >= tostring(b) end
string.contains = string.contains or function(s, sub) return string.find(s, sub, 1, true) ~= nil end
string.trim = string.trim or function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
table.wipe = table.wipe or function(t) for k in pairs(t) do t[k] = nil end end

UIManager = {
    getMillisSinceLastRender = function() return 33.3 end,
    getSpeedControls = function() return nil end,
    AddUI = function(o) record("UIManager.AddUI", o) end,
    RemoveElement = function() end,
    getUI = function() return { size = function() return 0 end } end,
}

JoypadState = { players = {} }
Joypad = setmetatable({ Texture = setmetatable({}, { __index = function(_, k) return getTexture("joypad/" .. k) end }) }, { __index = function() return -1 end })

-- Event bus stub: Events.X.Add(fn)
EVENT_HANDLERS = {}
Events = setmetatable({}, { __index = function(t, name)
    local ev = { Add = function(fn) EVENT_HANDLERS[name] = EVENT_HANDLERS[name] or {}; table.insert(EVENT_HANDLERS[name], fn) end,
                 Remove = function() end }
    rawset(t, name, ev)
    return ev
end })
function triggerEvent(name, ...)
    for _, fn in ipairs(EVENT_HANDLERS[name] or {}) do fn(...) end
end

-- File IO used by N26.Config (in-memory)
FILES = {}
function getFileWriter(name)
    local buf = {}
    return { write = function(_, s) buf[#buf + 1] = s end, close = function() FILES[name] = table.concat(buf) end }
end
function getFileReader(name)
    local data = FILES[name]
    if not data then return nil end
    local lines = {}
    for line in data:gmatch("([^\r\n]*)\r?\n") do lines[#lines + 1] = line end
    local i = 0
    return { readLine = function() i = i + 1; return lines[i] end, close = function() end }
end

-- ---------------------------------------------------------------- UIElement (Java peer)
local peerMeta = {}
local function newPeer(lua)
    local p = { lua = lua, x = 0, y = 0, w = 0, h = 0, visible = true, yscroll = 0, xscroll = 0,
                scrollHeight = 0, children = {}, mouseOver = false, focused = false }
    return setmetatable(p, peerMeta)
end
local P = {}
peerMeta.__index = function(t, k)
    if P[k] then return P[k] end
    if type(k) == "string" and k:sub(1, 4) == "Draw" then
        return function(self, ...) recordPeer(k, self, ...) end
    end
    return function() return nil end
end
function P:setX(v) self.x = v end
function P:setY(v) self.y = v end
function P:setWidth(v) self.w = v end
function P:setHeight(v) self.h = v end
function P:setWidthOnly(v) self.w = v end
function P:setHeightOnly(v) self.h = v end
function P:getX() return self.x end
function P:getY() return self.y end
function P:getWidth() return self.w end
function P:getHeight() return self.h end
function P:getAbsoluteX() return self.x end
function P:getAbsoluteY() return self.y end
function P:setVisible(v) self.visible = v end
function P:isVisible() return self.visible end
function P:isReallyVisible() return self.visible end
function P:getYScroll() return self.yscroll end
function P:setYScroll(v) self.yscroll = v end
function P:getXScroll() return self.xscroll end
function P:setXScroll(v) self.xscroll = v end
function P:getScrollHeight() return self.scrollHeight end
function P:setScrollHeight(v) self.scrollHeight = v end
function P:isMouseOver() return self.mouseOver end
function P:isFocused() return self.focused end
function P:SetText(v) self.text = v end
function P:getText() return self.text or "" end
function P:getInternalText() return self.text or "" end
function P:AddChild(c) table.insert(self.children, c) end
function P:RemoveChild() end
function P:isEnabled() return true end
function P:isCapture() return false end
function P:clampToParentX(v) return v end
function P:clampToParentY(v) return v end
function P:getMaxDrawHeight() return -1 end
function P:isConsumeMouseEvents() return true end
function P:getScrollChildren() return false end
function P:getScrollWithParent() return true end
function P:isFollowGameWorld() return false end
function P:getRenderThisPlayerOnly() return -1 end
function P:isPointOver() return false end
function P:setStencilRect(x, y, w, h) recordPeer("stencil", self, x, y, w, h) end
function P:clearStencilRect() recordPeer("clearStencil", self) end
function P:repaintStencilRect() end
function P:suspendStencil() end
function P:resumeStencil() end

UIElement = { new = newPeer }
UITextBox2 = { new = function() return newPeer(nil) end }
function P:setTable(t) self.lua = t end

-- Engine globals that vanilla files touch at load time but tests never exercise.
ANY_GLOBALS = ANY_GLOBALS or {}
for _, k in ipairs({ "ColorInfo", "Color", "Colors", "Keyboard", "Mouse", "GameTime", "getGameTime",
    "SandboxVars", "ZombRand", "getSoundManager", "getPlayer", "getCell", "getWorld", "isKeyDown",
    "getActivatedMods", "isDemo", "getSteamModeActive", "getPlayerInventory", "getPlayerLoot",
    "ISMouseDrag", "PerformanceSettings", "GameWindow", "SpriteRenderer", "Translator",
    "getPlayerData", "getAllOutfits", "XuiManager", "XuiAutoApply", "ISXuiBuilder", "ResourceChannel",
    "colorToTable", "ISUITextureGetter", "getPlayerContextMenu", "getCameraOffX", "getCameraOffY",
    "Perks", "CharacterStat", "MoodleType", "BodyPartType", "getSquare", "isGamePaused", "getGameSpeed",
    "Clipboard", "getAccessLevel", "getServerOptions", "getLuaFileUrl", "SystemDisabler", "FadeInOut" }) do
    ANY_GLOBALS[k] = true
end
setmetatable(_G, { __index = function(t, k)
    if ANY_GLOBALS[k] then return Any end
    return nil
end })

-- UITransition (Java): fade helper used by buttons, tabs, combos, text fields.
UITransition = { new = function()
    local t = { fadeIn = false, frac = 0 }
    function t:setFadeIn(v) self.fadeIn = v and true or false end
    function t:update() self.frac = self.fadeIn and 1 or 0 end
    function t:fraction() return self.frac end
    function t:reset() self.frac = 0 end
    function t:setIgnoreUpdateTime() end
    function t:init() end
    return t
end }

-- getFileReader(name, createIfNull): the game creates the file when asked to.
local _getFileReader = getFileReader
function getFileReader(name, create)
    if FILES[name] == nil and create then FILES[name] = "" end
    return _getFileReader(name)
end

-- RadialMenu (Java): slices live in Lua; the peer only needs to exist.
RadialMenu = { new = function() return newPeer(nil) end }

-- 3D avatar widget (Java) and directions
UI3DModel = { new = function(lua) local p = newPeer(lua); return p end }
IsoDirections = { S = "S", N = "N", E = "E", W = "W" }
