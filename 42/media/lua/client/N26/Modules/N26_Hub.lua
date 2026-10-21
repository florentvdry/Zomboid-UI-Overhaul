--[[
    Zomboid UI Overhaul ("hub") — one full-screen view with a tab bar at the
    top, in the spirit of Escape from Tarkov, instead of separate floating
    windows:

        PERSONNAGE   INVENTAIRE   SANTÉ   FABRICATION   CARTE

    The tabs host the game's own panels, so every vanilla interaction keeps
    working (drag & drop, context menus, transfers, treatment, crafting):

      Inventaire   N26 equipment column (3D character + worn slots + health
                   summary) | vanilla player inventory page | vanilla loot
                   page, plus the current timed action at the bottom.
      Santé        vanilla info window on its health view + care supplies column.
      Personnage   N26 identity, grouped skill board and selected skill details.
      Fabrication  N26 recipe browser/sheet; hidden native craft/build engines.
      Carte        native world map docked below the menu navigation.

    Entry points: Tab (replaces the vanilla inventory toggle) and every vanilla
    way of opening those windows (keys, sidebar buttons, context menus): a
    per-frame watcher notices the window and opens the hub on the matching
    tab. Closing the window that a tab shows (same key again) closes the hub;
    Escape closes it too.

    Docking: the vanilla windows stay top-level windows. While the hub is
    open they are positioned (and, for inventory pages, sized) into the hub's
    columns every frame, with their title-bar close/pin/resize controls
    hidden; their previous geometry is restored when the hub closes.

    Disabled for controller players (vanilla joypad navigation relies on the
    original windows) and in the tutorial.
]]

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISUI3DModel"
require "ISUI/ISInventoryPage"
require "ISUI/ISInventoryPane"
require "ISUI/ISToolTipInv"
require "XpSystem/ISUI/ISCharacterInfoWindow"
require "N26/Core/N26_Draw"
require "N26/Modules/N26_HubCharacter"
require "N26/Modules/N26_HubCraft"

local Theme = N26.Theme
local D = N26.Draw
local floor, max, min = math.floor, math.max, math.min

N26.registerModule({ id = "hub", label = "UI_N26_Mod_Hub", tooltip = "UI_N26_Mod_Hub_Tip" })
local MODULE = "hub"

N26.Hub = N26.Hub or {}
local Hub = N26.Hub

local PAD = 12
local PLAYER = 0

Hub.TABS = {
    { id = "character", label = "UI_N26_Hub_Character", bind = "TOGGLE_SKILL_PANEL" },
    { id = "inventory", label = "UI_N26_Hub_Inventory", bind = "TOGGLE_INVENTORY" },
    { id = "health",    label = "UI_N26_Hub_Health",    bind = "TOGGLE_HEALTH_PANEL" },
    { id = "crafting",  label = "UI_N26_Hub_Crafting",  bind = "CRAFTING_UI" },
    { id = "map",       label = "UI_N26_Hub_Map",       bind = "MAP" },
}

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

--- Safe method call on a Java object: returns nil when the method is missing or throws.
local function call(obj, name, ...)
    if not obj then return nil end
    local f = obj[name]
    if not f then return nil end
    local ok, r = pcall(f, obj, ...)
    if ok then return r end
    return nil
end

local function keyName(bind)
    local ok, s = pcall(function()
        local id = KeybindId and KeybindId[bind]
        if not id then return nil end
        local code = getCore():getKey(id)
        if not code or code <= 0 then return nil end
        return getKeyName(code)
    end)
    if ok then return s end
    return nil
end

local function isKey(bind, key)
    local ok, r = pcall(function()
        return KeybindId and KeybindId[bind] and getCore():isKey(KeybindId[bind], key)
    end)
    return ok and r == true
end

local function player() return getSpecificPlayer(PLAYER) end
local function invPage() return getPlayerInventory and getPlayerInventory(PLAYER) or nil end
local function lootPage() return getPlayerLoot and getPlayerLoot(PLAYER) or nil end
local function infoWin() return getPlayerInfoPanel and getPlayerInfoPanel(PLAYER) or nil end

local function visible(w)
    return w ~= nil and w:getIsVisible() == true
end

--- Open entity window (handcraft / build) for the player, or nil.
local function entityWin(key)
    if not ISEntityUI or not ISEntityUI.GetWindowInstance then return nil end
    local ok, w = pcall(ISEntityUI.GetWindowInstance, PLAYER, key)
    if ok and w and not w.hasClosedWindowInstance and (w:isVisible() or w.n26CraftEngine) then return w end
    return nil
end

--- The hub is used by mouse & keyboard player 1 only.
function Hub.active()
    if not N26.isEnabled(MODULE) then return false end
    if getCore():getGameMode() == "Tutorial" then return false end
    if JoypadState and JoypadState.players and JoypadState.players[PLAYER + 1] then return false end
    return player() ~= nil
end

function Hub.isOpen()
    return Hub.instance ~= nil and Hub.instance.isOpen == true
end

-- ---------------------------------------------------------------------------
-- Docking vanilla windows into the hub
-- ---------------------------------------------------------------------------

local docked = {}     -- window -> saved state
local dockOrder = {}  -- windows in raise order

local HIDE_WHILE_DOCKED = { "closeButton", "pinButton", "collapseButton", "resizeWidget", "resizeWidget2" }

local function dock(win, x, y, w, h, opts)
    if not win then return end
    local st = docked[win]
    if not st then
        st = { x = win.x, y = win.y, w = win.width, h = win.height, hidden = {} }
        for _, k in ipairs(HIDE_WHILE_DOCKED) do
            local c = rawget(win, k)
            if type(c) == "table" and c.isVisible and c:isVisible() then
                c:setVisible(false)
                st.hidden[#st.hidden + 1] = c
            end
        end
        if opts.page then
            st.pin = win.pin
            win.pin = true
            win.isCollapsed = false
            if win.clearMaxDrawHeight then win:clearMaxDrawHeight() end
        end
        if opts.layout and win.calculateLayout then
            pcall(win.calculateLayout, win, w, h)
        end
        win.n26Docked = true
        docked[win] = st
        dockOrder[#dockOrder + 1] = win
        if Hub.instance then Hub.instance.needRaise = true end
    end
    if opts.resize then
        if win.width ~= w then win:setWidth(w) end
        if win.height ~= h then win:setHeight(h) end
        if win.x ~= x then win:setX(x) end
        if win.y ~= y then win:setY(y) end
    else
        -- natural size, centred horizontally, top-aligned, kept on screen
        local wx = x + max(0, floor((w - win.width) / 2))
        local wy = y
        if opts.center then wy = y + max(0, floor((h - win.height) / 2)) end
        if win.x ~= wx then win:setX(wx) end
        if win.y ~= wy then win:setY(wy) end
    end
end

local function undock(win)
    local st = win and docked[win]
    if not st then return end
    docked[win] = nil
    for i = #dockOrder, 1, -1 do
        if dockOrder[i] == win then table.remove(dockOrder, i) end
    end
    win.n26Docked = nil
    if st.health then
        st.health.setWidthAndParentWidth = st.healthWidth
        st.health.setHeightAndParentHeight = st.healthHeight
        st.health.n26MinW, st.health.n26MinH = nil, nil
    end
    for _, c in ipairs(st.hidden) do c:setVisible(true) end
    if st.pin ~= nil then win.pin = st.pin end
    if not win.calculateLayout then
        if win.width ~= st.w then win:setWidth(st.w) end
        if win.height ~= st.h then win:setHeight(st.h) end
    end
    win:setX(st.x)
    win:setY(st.y)
end

local function undockAll()
    for i = #dockOrder, 1, -1 do undock(dockOrder[i]) end
end

function Hub.isDocked(win) return docked[win] ~= nil end

-- A docked health page must have exactly one layout owner. Vanilla update()
-- resizes all ancestors to its text width, undoing N26's layout every frame.
local function sizeHealth(info, w, h)
    local view = info and info.healthView
    local st = info and docked[info]
    if not view or not st then return end
    if not st.health then
        st.health, st.healthWidth, st.healthHeight = view,
            rawget(view, "setWidthAndParentWidth"), rawget(view, "setHeightAndParentHeight")
        view.setWidthAndParentWidth = function() end
        view.setHeightAndParentHeight = function() end
    end
    if info.panel.setWidth then
        info.panel:setWidth(w)
        info.panel:setHeight(h - info.panel.y - info:resizeWidgetHeight())
        view:setWidth(w)
        view:setHeight(info.panel.height - (info.panel.tabHeight or 30))
    end
end

local function mapWin()
    return Hub.map or rawget(_G, "ISWorldMap_instance")
end

local function closeMap()
    local map = mapWin()
    if not map then return end
    undock(map)
    if visible(map) then map:close() end
end

-- The native map renders at the allocated size instead of forcing fullscreen.
-- Keep its zoom, exploration, symbols, map rules and mouse input intact.
local function integrateMap(map)
    if map.n26MapIntegrated then return end
    map.n26MapIntegrated = true
    local render, setWidth, setHeight = map.render, map.setWidth, map.setHeight
    map.setWidth = function(self, w) if not self.n26MapRendering then return setWidth(self, w) end end
    map.setHeight = function(self, h) if not self.n26MapRendering then return setHeight(self, h) end end
    map.render = function(self)
        if not self.n26Docked then return render(self) end
        self.n26MapRendering = true
        local ok, err = pcall(render, self)
        self.n26MapRendering = nil
        if not ok then error(err, 0) end
    end
end

-- ---------------------------------------------------------------------------
-- Equipment: worn-item slots around the 3D character
-- ---------------------------------------------------------------------------

-- First matching rule wins (body location names, lower-cased, substring match).
local SLOT_RULES = {
    { "accessories", { "ring", "finger", "wrist", "ear", "nose", "belly", "tongue", "lip", "eyebrow", "necklace" } },
    { "belt",  { "fanny", "belt", "waist" } },
    { "back",  { "back" } },
    { "head",  { "hat", "helmet", "mask", "eye", "hood", "head" } },
    { "neck",  { "neck", "scarf" } },
    { "hands", { "hand", "glove" } },
    { "rig",   { "vest", "webbing", "ammo", "bandolier", "holster", "sling" } },
    { "feet",  { "shoe", "sock", "feet", "foot", "boot" } },
    { "legs",  { "pant", "leg", "skirt", "short", "knee", "thigh", "shin", "calf", "bottom" } },
}

function Hub.slotForLocation(loc)
    local s = string.lower(tostring(loc or ""))
    for _, rule in ipairs(SLOT_RULES) do
        for _, k in ipairs(rule[2]) do
            if string.find(s, k, 1, true) then return rule[1] end
        end
    end
    return "torso"
end

Hub.SLOTS = {
    { id = "head",        label = "UI_N26_Slot_Head",        side = 1 },
    { id = "neck",        label = "UI_N26_Slot_Neck",        side = 1 },
    { id = "torso",       label = "UI_N26_Slot_Torso",       side = 1 },
    { id = "rig",         label = "UI_N26_Slot_Rig",         side = 1 },
    { id = "accessories", label = "UI_N26_Slot_Accessories", side = 1 },
    { id = "primary",     label = "UI_N26_Slot_Primary",     side = 1, hand = true },
    { id = "back",        label = "UI_N26_Slot_Back",        side = 2 },
    { id = "belt",        label = "UI_N26_Slot_Belt",        side = 2 },
    { id = "hands",       label = "UI_N26_Slot_Hands",       side = 2 },
    { id = "legs",        label = "UI_N26_Slot_Legs",        side = 2 },
    { id = "feet",        label = "UI_N26_Slot_Feet",        side = 2 },
    { id = "secondary",   label = "UI_N26_Slot_Secondary",   side = 2, hand = true },
}

--- { slotId = { item, item… } } for the player's worn and held items.
function Hub.collectEquipment(chr)
    local out = {}
    for _, s in ipairs(Hub.SLOTS) do out[s.id] = {} end
    if not chr then return out end
    local worn = call(chr, "getWornItems")
    local n = worn and call(worn, "size") or 0
    for i = 0, n - 1 do
        local wi = worn:get(i)
        local item = wi and call(wi, "getItem")
        if item then
            local slot = Hub.slotForLocation(call(wi, "getLocation"))
            table.insert(out[slot], item)
        end
    end
    local p1, p2 = call(chr, "getPrimaryHandItem"), call(chr, "getSecondaryHandItem")
    if p1 then table.insert(out.primary, p1) end
    if p2 and p2 ~= p1 then table.insert(out.secondary, p2) end
    out.twoHanded = p1 ~= nil and p1 == p2
    return out
end

-- ---------------------------------------------------------------------------
-- Health summary
-- ---------------------------------------------------------------------------

local CONDITIONS = {
    { "bleeding",     "UI_N26_Hub_Cond_Bleeding", "danger" },
    { "bitten",       "UI_N26_Hub_Cond_Bitten",   "danger" },
    { "fracture",     "UI_N26_Hub_Cond_Fracture", "danger" },
    { "deepWounded",  "UI_N26_Hub_Cond_Deep",     "danger" },
    { "haveBullet",   "UI_N26_Hub_Cond_Bullet",   "danger" },
    { "burn",         "UI_N26_Hub_Cond_Burn",     "warn" },
    { "isCut",        "UI_N26_Hub_Cond_Cut",      "warn" },
    { "scratched",    "UI_N26_Hub_Cond_Scratch",  "warn" },
}

--- List of { name, label, tone, health, bandaged } for every injured body part.
function Hub.injuries(chr)
    local out = {}
    local bd = call(chr, "getBodyDamage")
    local parts = bd and call(bd, "getBodyParts")
    local n = parts and call(parts, "size") or 0
    for i = 0, n - 1 do
        local bp = parts:get(i)
        local found
        for _, c in ipairs(CONDITIONS) do
            local on
            if c[1] == "fracture" then
                on = (call(bp, "getFractureTime") or 0) > 0
            elseif c[1] == "burn" then
                on = (call(bp, "getBurnTime") or 0) > 0
            else
                on = call(bp, c[1]) == true
            end
            if on then found = c break end
        end
        if found then
            local t = call(bp, "getType")
            local name = BodyPartType and BodyPartType.getDisplayName and t and BodyPartType.getDisplayName(t) or tostring(t)
            out[#out + 1] = {
                name = name, label = getText(found[2]), tone = found[3],
                health = call(bp, "getHealth") or 100, bandaged = call(bp, "bandaged") == true,
            }
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Timed actions (bottom bar)
-- ---------------------------------------------------------------------------

local ACTION_LABELS = {
    ISInventoryTransferAction = "UI_N26_Act_Transfer",
    ISWearClothing = "UI_N26_Act_Wear",
    ISUnequipAction = "UI_N26_Act_Unequip",
    ISEquipWeaponAction = "UI_N26_Act_Equip",
    ISEatFoodAction = "UI_N26_Act_Eat",
    ISDrinkFromBottle = "UI_N26_Act_Drink",
    ISReadABook = "UI_N26_Act_Read",
    ISApplyBandage = "UI_N26_Act_Bandage",
    ISWalkToTimedAction = "UI_N26_Act_Walk",
    ISGrabItemAction = "UI_N26_Act_Grab",
    ISDropItemAction = "UI_N26_Act_Drop",
    ISDropWorldItemAction = "UI_N26_Act_Drop",
    ISHandcraftAction = "UI_N26_Act_Craft",
}

function Hub.actionLabel(action)
    if not action then return "" end
    local t = action.Type or ""
    local key = ACTION_LABELS[t]
    local label = key and getText(key) or t:gsub("^IS", ""):gsub("Action$", ""):gsub("(%l)(%u)", "%1 %2")
    local item = action.item
    local name = item and call(item, "getDisplayName")
    if name then label = label .. " · " .. name end
    return label
end

local function actionQueue(chr)
    if not ISTimedActionQueue or not ISTimedActionQueue.getTimedActionQueue then return nil end
    local ok, q = pcall(ISTimedActionQueue.getTimedActionQueue, chr)
    if ok and q and q.queue then return q.queue end
    return nil
end

-- ---------------------------------------------------------------------------
-- Equipment column widget
-- ---------------------------------------------------------------------------

N26HubEquip = ISPanel:derive("N26HubEquip")
local Equip = N26HubEquip

function Equip:new(x, y, w, h, hub)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.hub = hub
    o.background = false
    o.slotRects = {}
    o.slotIndex = {}
    o.equipment = Hub.collectEquipment(nil)
    o.lastClick = { t = 0 }
    return o
end

function Equip:createChildren()
    if not ISUI3DModel then return end
    local ok = pcall(function()
        local m = ISUI3DModel:new(0, 0, 10, 10)
        m:initialise()
        m:instantiate()
        self:addChild(m)
        m:setIsometric(false)
        m:setDirection(IsoDirections.S)
        m:setState("idle")
        -- dropping an item on the character wears / equips it; dragging rotates
        local equip = self
        m.onMouseUp = function(model, x, y)
            if ISMouseDrag.dragging then
                equip:dropOn(nil)
            end
            return ISUI3DModel.onMouseUp(model, x, y)
        end
        self.model = m
    end)
    if not ok then self.model = nil end
end

function Equip:refresh()
    local chr = player()
    self.equipment = Hub.collectEquipment(chr)
    if self.model and chr and self.model:getCharacter() ~= chr then
        self.model:setCharacter(chr)
    end
end

function Equip:metrics()
    local fs = D.fontScale()
    local hdrH = floor(34 * fs)
    local healthH = max(floor(150 * fs), min(floor(230 * fs), floor(self.height * 0.27)))
    local dollY = hdrH + 4
    local dollH = self.height - hdrH - healthH - 12
    local slotW = max(64, min(floor(112 * fs), floor(self.width * 0.25)))
    local gap = 6
    local slotH = min(floor(slotW * 1.05), floor((dollH - gap * 5) / 6))
    return { fs = fs, hdrH = hdrH, healthH = healthH, dollY = dollY, dollH = dollH,
             slotW = slotW, slotH = slotH, gap = gap }
end

function Equip:layout()
    local m = self:metrics()
    self.m = m
    local colH = m.slotH * 6 + m.gap * 5
    local y0 = m.dollY + max(0, floor((m.dollH - colH) / 2))
    local counts = { 0, 0 }
    for _, s in ipairs(Hub.SLOTS) do
        local i = counts[s.side]
        counts[s.side] = i + 1
        local x = s.side == 1 and 8 or (self.width - 8 - m.slotW)
        self.slotRects[s.id] = { x = x, y = y0 + i * (m.slotH + m.gap), w = m.slotW, h = m.slotH, def = s }
    end
    if self.model then
        local mx = 8 + m.slotW + 6
        local mw = self.width - 2 * mx
        if self.model.x ~= mx or self.model.width ~= mw or self.model.y ~= m.dollY or self.model.height ~= m.dollH then
            self.model:setX(mx); self.model:setY(m.dollY)
            self.model:setWidth(mw); self.model:setHeight(m.dollH)
        end
    end
    self.healthRect = { x = 0, y = self.height - m.healthH, w = self.width, h = m.healthH }
end

function Equip:slotAt(x, y)
    for id, r in pairs(self.slotRects) do
        if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then return id, r end
    end
    return nil
end

--- Item shown in a slot (click cycles through several worn items).
function Equip:slotItem(id)
    local list = self.equipment[id] or {}
    if #list == 0 then return nil, 0 end
    local i = self.slotIndex[id] or 1
    if i > #list then i = 1 end
    return list[i], #list
end

local function drawSlot(self, r, id, hovered, dropTarget)
    local C = Theme.C
    local s = r.def
    local item, count = self:slotItem(id)
    local fill = hovered and C.hover2 or C.field
    D.fill(self, r.x, r.y, r.w, r.h, fill, Theme.R.md)
    local border = dropTarget and C.accent or (item and C.outline2 or C.outline)
    D.stroke(self, r.x, r.y, r.w, r.h, border, Theme.R.md)
    D.caption(self, getText(s.label), r.x + 6, r.y + 4, item and C.muted or C.dim, nil, r.w - 12)
    local capH = D.headingHeight("sm") + 4
    if item then
        local tex = call(item, "getTex")
        local isz = min(r.w - 16, r.h - capH - D.fontHeight(UIFont.Small) - 6)
        isz = max(16, isz)
        if tex then
            self:drawTextureScaledAspect(tex, r.x + floor((r.w - isz) / 2), r.y + capH, isz, isz, 1, 1, 1, 1)
        end
        local name = call(item, "getDisplayName") or ""
        D.text(self, name, r.x + r.w / 2, r.y + r.h - D.fontHeight(UIFont.Small) - 3, C.text2, UIFont.Small, "center", r.w - 8)
        if count > 1 then
            local label = (self.slotIndex[id] or 1) .. "/" .. count
            local bw = D.measure(UIFont.Small, label) + 8
            D.fill(self, r.x + r.w - bw - 4, r.y + 4, bw, D.fontHeight(UIFont.Small), C.accentSoft, Theme.R.sm)
            D.text(self, label, r.x + r.w - bw / 2 - 4, r.y + 4, C.accent, UIFont.Small, "center")
        end
        if s.hand and self.equipment.twoHanded then
            local fh = D.fontHeight(UIFont.Small)
            D.caption(self, getText("UI_N26_Slot_TwoHands"), r.x + r.w / 2, r.y + r.h - fh - D.headingHeight("sm") - 4, C.accent, "center")
        end
        local cond, condMax = call(item, "getCondition"), call(item, "getConditionMax")
        if s.hand and cond and condMax and condMax > 0 then
            D.bar(self, r.x + 6, r.y + r.h - 3, r.w - 12, 2, cond / condMax, Theme.ramp(cond / condMax))
        end
    else
        if s.id == "secondary" and self.equipment.twoHanded then
            D.text(self, getText("UI_N26_Slot_TwoHands"), r.x + r.w / 2, r.y + floor(r.h / 2), C.dim, UIFont.Small, "center")
        else
            D.text(self, "—", r.x + r.w / 2, r.y + floor(r.h / 2) - 4, C.dim, UIFont.Small, "center")
        end
    end
end

local VITALS = {
    { "HUNGER", "UI_N26_Hub_Hunger", true },
    { "THIRST", "UI_N26_Hub_Thirst", true },
    { "FATIGUE", "UI_N26_Hub_Fatigue", true },
    { "ENDURANCE", "UI_N26_Hub_Endurance", false },
}

--- CharacterStat value 0..1, or nil when unavailable.
local function stat(chr, name)
    if not CharacterStat or not CharacterStat[name] then return nil end
    local st = call(chr, "getStats")
    if not st or not st.get then return nil end
    local ok, v = pcall(st.get, st, CharacterStat[name])
    if ok and type(v) == "number" then return max(0, min(1, v)) end
    return nil
end

function Equip:drawHealth()
    local C = Theme.C
    local r = self.healthRect
    local chr = player()
    D.panel(self, r.x, r.y, r.w, r.h, C.panel, C.outline, Theme.R.lg)
    local fh = D.fontHeight(UIFont.Small)
    local x, y, w = r.x + 12, r.y + 10, r.w - 24
    D.titleWithBar(self, getText("UI_N26_Hub_Health"), r.x + 10, y - 2, D.headingHeight("md") + 4, C.text, "md")
    local bd = call(chr, "getBodyDamage")
    local hp = bd and (call(bd, "getOverallBodyHealth") or call(bd, "getHealth")) or 100
    local hpC = hp > 60 and C.ok or (hp > 30 and C.warn or C.danger)
    D.number(self, tostring(floor(hp + 0.5)), r.x + r.w - 12, y - 4, hpC, floor(30 * D.fontScale()), "right")
    y = y + D.headingHeight("md") + 10
    D.bar(self, x, y, w, 4, hp / 100, hpC, C.hover2, 2)
    y = y + 12

    -- needs: hunger, thirst, fatigue (higher = worse), endurance (higher = better)
    local colW = floor((w - 3 * 10) / 4)
    local any = false
    for i, v in ipairs(VITALS) do
        local val = stat(chr, v[1])
        if val then
            any = true
            local good = v[3] and (1 - val) or val
            local cx = x + (i - 1) * (colW + 10)
            D.caption(self, getText(v[2]), cx, y, C.muted, nil, colW)
            D.bar(self, cx, y + D.headingHeight("sm") + 3, colW, 3, good, Theme.ramp(good), C.hover2, 1)
        end
    end
    if any then y = y + D.headingHeight("sm") + 14 end

    local list = Hub.injuries(chr)
    local lineH = fh + 6
    local maxLines = max(1, floor((r.y + r.h - y - fh - 14) / lineH))
    if #list == 0 then
        D.text(self, getText("UI_N26_Hub_NoInjury"), x, y, C.ok, UIFont.Small)
    else
        for i = 1, min(#list, maxLines) do
            local it = list[i]
            local tone = it.tone == "danger" and C.danger or C.warn
            D.rect(self, x, y + floor(fh / 2) - 3, 6, 6, it.bandaged and C.ok or tone)
            D.text(self, it.name, x + 14, y, C.text, UIFont.Small, nil, floor(w * 0.5))
            local status = it.label
            if it.bandaged then status = status .. " · " .. getText("UI_N26_Hub_Cond_Bandaged") end
            D.text(self, status, x + w, y, it.bandaged and C.ok or tone, UIFont.Small, "right", floor(w * 0.5) - 8)
            y = y + lineH
        end
        if #list > maxLines then
            D.text(self, "+" .. (#list - maxLines), x, y, C.muted, UIFont.Small)
        end
    end
    -- link to the health tab
    local key = keyName("TOGGLE_HEALTH_PANEL")
    local ly = r.y + r.h - fh - 8
    local label = getText("UI_N26_Hub_OpenHealth")
    local hovered = self.hoverHealth
    D.text(self, label, x, ly, hovered and C.accent or C.text2, UIFont.Small)
    if key then D.keycap(self, key, x + D.measure(UIFont.Small, label) + 8, ly - 1, fh + 2, "ghost") end
    self.healthLink = { x = x, y = ly - 2, w = w, h = fh + 4 }
end

function Equip:prerender()
    local C = Theme.C
    -- hand items change without a clothing event
    local chr0 = player()
    if chr0 then
        local p1, p2 = call(chr0, "getPrimaryHandItem"), call(chr0, "getSecondaryHandItem")
        if p1 ~= self.lastP1 or p2 ~= self.lastP2 then
            self.lastP1, self.lastP2 = p1, p2
            self:refresh()
        end
    end
    self:layout()
    local m = self.m
    D.panel(self, 0, 0, self.width, self.height - m.healthH - 8, C.panel, C.outline, Theme.R.lg)
    D.fill(self, 1, 1, self.width - 2, m.hdrH - 1, C.panel2, Theme.R.lg - 1)
    D.rect(self, 1, m.hdrH, self.width - 2, 1, C.divider)
    D.titleWithBar(self, getText("UI_N26_Hub_Equipment"), 10, 0, m.hdrH, C.text, "md")
    local chr = player()
    if chr then
        local wgt = call(chr, "getInventoryWeight") or 0
        local maxW = call(chr, "getMaxWeight") or 1
        local s = string.format("%.1f / %d", wgt, maxW)
        local c = wgt > maxW and C.dangerTxt or C.text2
        D.text(self, s, self.width - 12, floor((m.hdrH - D.fontHeight(UIFont.Small)) / 2), c, UIFont.Small, "right")
    end
    -- soft floor under the character
    local mx = 8 + m.slotW + 6
    D.shade(self, mx, m.dollY + floor(m.dollH * 0.82), self.width - 2 * mx, floor(m.dollH * 0.16), 0.35)
end

function Equip:render()
    local mx, my = self:getMouseX(), self:getMouseY()
    local over = self:isMouseOver()
    local hoverId = over and self:slotAt(mx, my) or nil
    local dragging = ISMouseDrag and ISMouseDrag.dragging ~= nil
    for id, r in pairs(self.slotRects) do
        drawSlot(self, r, id, id == hoverId, dragging and id == hoverId)
    end
    self:drawHealth()
    self.hoverHealth = over and self.healthLink and mx >= self.healthLink.x and mx < self.healthLink.x + self.healthLink.w
        and my >= self.healthLink.y and my < self.healthLink.y + self.healthLink.h
    self:updateTooltip(not dragging and hoverId and self:slotItem(hoverId) or nil)
    if dragging and over and not hoverId then
        -- dropping on the character itself
        local m = self.m
        local x0 = 8 + m.slotW + 6
        if mx >= x0 and mx < self.width - x0 and my >= m.dollY and my < m.dollY + m.dollH then
            D.stroke(self, x0, m.dollY, self.width - 2 * x0, m.dollH, Theme.C.accent, Theme.R.lg)
        end
    end
end

function Equip:updateTooltip(item)
    if item then
        if not self.toolRender then
            self.toolRender = ISToolTipInv:new(item)
            self.toolRender:initialise()
            self.toolRender:setOwner(self)
            self.toolRender:setCharacter(player())
        end
        if self.toolRender.item ~= item then self.toolRender:setItem(item) end
        if not self.toolRender:isVisible() then
            self.toolRender:addToUIManager()
            self.toolRender:setVisible(true)
        end
        self.toolRender.followMouse = true
        self.toolRender:bringToTop()
    elseif self.toolRender and self.toolRender:isVisible() then
        self.toolRender:removeFromUIManager()
        self.toolRender:setVisible(false)
    end
end

function Equip:onMouseMoveOutside()
    self.hoverHealth = false
    self:updateTooltip(nil)
end

--- Wear / equip the dragged items. slotId nil = dropped on the character.
function Equip:dropOn(slotId)
    local dragging = ISMouseDrag and ISMouseDrag.dragging
    if not dragging then return false end
    local items = ISInventoryPane.getActualItems(dragging)
    local chr = player()
    if not chr or #items == 0 then return false end
    local slot = slotId and self.slotRects[slotId] and self.slotRects[slotId].def
    local wear = {}
    for _, item in ipairs(items) do
        local isClothing = call(item, "getBodyLocation") ~= nil or call(item, "canBeEquipped") ~= nil
        if slot and slot.hand then
            ISInventoryPaneContextMenu.equipWeapon(item, slot.id == "primary", call(item, "isTwoHandWeapon") == true, PLAYER)
            break
        elseif isClothing then
            wear[#wear + 1] = item
        elseif not slot and (call(item, "IsWeapon") or instanceof(item, "HandWeapon")) then
            ISInventoryPaneContextMenu.equipWeapon(item, true, call(item, "isTwoHandWeapon") == true, PLAYER)
            break
        end
    end
    if #wear > 0 then ISInventoryPaneContextMenu.onWearItems(wear, PLAYER) end
    return true
end

function Equip:onMouseDown(x, y)
    self.hub.needRaise = true
    return true
end

function Equip:onMouseUp(x, y)
    local id = self:slotAt(x, y)
    if ISMouseDrag and ISMouseDrag.dragging then
        self:dropOn(id)
        return true
    end
    if self.hoverHealth then
        Hub.setTab("health")
        return true
    end
    if not id then return true end
    local item, count = self:slotItem(id)
    local now = getTimestampMs()
    if item and self.lastClick.id == id and now - self.lastClick.t < 350 then
        -- double click: take it off / put it away
        ISInventoryPaneContextMenu.onUnEquip({ item }, PLAYER)
        self.lastClick = { t = 0 }
        return true
    end
    self.lastClick = { id = id, t = now }
    if count > 1 then
        self.slotIndex[id] = ((self.slotIndex[id] or 1) % count) + 1
    end
    return true
end

function Equip:onRightMouseUp(x, y)
    local id = self:slotAt(x, y)
    local item = id and self:slotItem(id)
    if not item then return true end
    self.hub:raiseDocked()
    local menu = ISInventoryPaneContextMenu.createMenu(PLAYER, true, { item }, self:getAbsoluteX() + x, self:getAbsoluteY() + y)
    if menu and menu.bringToTop then menu:bringToTop() end
    return true
end

-- ---------------------------------------------------------------------------
-- Identity column (character tab)
-- ---------------------------------------------------------------------------

N26HubIdentity = ISPanel:derive("N26HubIdentity")
local Ident = N26HubIdentity

function Ident:new(x, y, w, h, hub)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.hub = hub
    o.background = false
    return o
end

function Ident:createChildren()
    self.traitScroll = 0
    self.hairButton = ISButton:new(0, 0, 100, 28, getText("UI_N26_Char_Hair"), self, function()
        local screen = infoWin() and infoWin().charScreen
        if screen then screen:hairMenu(self.hairButton) end
    end)
    self.hairButton:initialise(); self:addChild(self.hairButton)
    self.readButton = ISButton:new(0, 0, 100, 28, getText("UI_N26_Char_Read"), self, function()
        local screen = infoWin() and infoWin().charScreen
        if screen then screen:onShowLiterature() end
    end)
    self.readButton:initialise(); self:addChild(self.readButton)
    if not ISUI3DModel then return end
    pcall(function()
        local m = ISUI3DModel:new(0, 0, 10, 10)
        m:initialise()
        m:instantiate()
        self:addChild(m)
        m:setIsometric(false)
        m:setDirection(IsoDirections.S)
        m:setState("idle")
        self.model = m
    end)
end

function Ident:refresh()
    local chr = player()
    if self.model and chr and self.model:getCharacter() ~= chr then self.model:setCharacter(chr) end
    self.traits = {}
    local known = chr and call(call(chr, "getCharacterTraits"), "getKnownTraits")
    local n = known and call(known, "size") or 0
    for i = 0, n - 1 do
        local def = CharacterTraitDefinition and CharacterTraitDefinition.getCharacterTraitDefinition
            and CharacterTraitDefinition.getCharacterTraitDefinition(known:get(i))
        if def then
            self.traits[#self.traits + 1] = {
                label = call(def, "getLabel") or "?", desc = call(def, "getDescription") or "",
                cost = call(def, "getCost") or 0, tex = call(def, "getTexture"),
            }
        end
    end
    self.profession, self.professionTex = nil, nil
    local desc = call(chr, "getDescriptor")
    local prof = desc and call(desc, "getCharacterProfession")
    if prof and CharacterProfessionDefinition and CharacterProfessionDefinition.getCharacterProfessionDefinition then
        local pd = CharacterProfessionDefinition.getCharacterProfessionDefinition(prof)
        if pd then
            self.profession = call(pd, "getUIName")
            self.professionTex = call(pd, "getTexture")
        end
    end
end

function Ident:prerender()
    local C = Theme.C
    local fs = D.fontScale()
    local chr = player()
    D.panel(self, 0, 0, self.width, self.height, C.panel, C.outline, Theme.R.lg)
    local pad = 14
    local modelH = min(floor(self.height * 0.23), floor(210 * fs))
    local portraitW = floor(self.width * 0.33)
    if self.model then
        local mw = portraitW
        if self.model.width ~= mw or self.model.height ~= modelH then
            self.model:setX(pad); self.model:setY(pad)
            self.model:setWidth(mw); self.model:setHeight(modelH)
        end
        D.fill(self, pad, pad, portraitW, modelH, C.field, Theme.R.md)
    end
    local tx = pad + portraitW + 12
    local tw = self.width - tx - pad
    local y = pad
    local desc = chr and call(chr, "getDescriptor")
    local name = desc and ((call(desc, "getForename") or "") .. " " .. (call(desc, "getSurname") or "")) or ""
    D.heading(self, name, tx, y, C.text, "md", nil, tw)
    y = y + D.headingHeight("md") + 4
    if self.profession then
        D.text(self, self.profession, tx, y, C.accent, UIFont.Small, nil, tw)
        y = y + D.fontHeight(UIFont.Small) + 10
    end
    local fh = D.fontHeight(UIFont.Small)
    local hours = call(chr, "getHoursSurvived") or 0
    local stats = {
        { "UI_N26_Hub_Survived", string.format("%d j %d h", floor(hours / 24), floor(hours % 24)) },
        { "UI_N26_Hub_Kills", tostring(call(chr, "getZombieKills") or 0) },
    }
    local nut = call(chr, "getNutrition")
    local kg = nut and call(nut, "getWeight")
    if kg then stats[#stats + 1] = { "UI_N26_Hub_BodyWeight", string.format("%d kg", floor(kg + 0.5)) } end
    for _, s in ipairs(stats) do
        D.text(self, getText(s[1]), tx, y, C.muted, UIFont.Small, nil, tw * 0.55)
        D.text(self, s[2], self.width - pad, y, C.text, UIFont.Small, "right")
        y = y + fh + 4
    end
    y = max(y + 16, pad + modelH + 16)
    D.caption(self, getText("UI_N26_Hub_Traits"), pad, y)
    y = y + D.headingHeight("sm") + 6
    local rowH = fh * 3 + 16
    local top, bottom = y, self.height - pad - 42
    self.traitMax = max(0, #(self.traits or {}) * rowH - (bottom - top))
    self.traitScroll = min(self.traitScroll or 0, self.traitMax)
    y = y - self.traitScroll
    self:setStencilRect(pad, top, self.width - 2 * pad, max(1, bottom - top))
    for _, t in ipairs(self.traits or {}) do
        local good = t.cost > 0
        local tone = good and C.ok or (t.cost < 0 and C.danger or C.muted)
        D.fill(self, pad, y, self.width - 2 * pad, rowH - 4, C.hover, Theme.R.md)
        D.rect(self, pad, y, 2, rowH - 4, tone)
        local tx = pad + 10
        if t.tex then
            self:drawTextureScaledAspect(t.tex, tx, y + floor((rowH - 4 - 18) / 2), 18, 18, 1, 1, 1, 1)
            tx = tx + 26
        end
        D.text(self, t.label, tx, y + 3, C.text, UIFont.Small, nil, self.width - tx - pad)
        local d = (t.desc or ""):gsub("<br>", " "):gsub("\n", " ")
        D.text(self, d, tx, y + fh + 3, C.muted, UIFont.Small, nil, self.width - tx - pad - 4)
        y = y + rowH
    end
    self:clearStencilRect()
    local bh = max(28, fh + 10)
    self.hairButton:setX(pad); self.hairButton:setY(self.height - pad - bh)
    self.hairButton:setWidth(floor((self.width - 2 * pad - 6) / 2)); self.hairButton:setHeight(bh)
    self.readButton:setX(self.hairButton:getRight() + 6); self.readButton:setY(self.hairButton.y)
    self.readButton:setWidth(self.hairButton.width); self.readButton:setHeight(bh)
end

function Ident:onMouseWheel(del)
    self.traitScroll = max(0, min(self.traitMax or 0, (self.traitScroll or 0) + del * 40))
    return true
end

-- ---------------------------------------------------------------------------
-- Care supplies (health tab): what the vanilla treatment menu could use, on
-- the player and nearby. Same item tests as ISHealthPanel's handlers.
-- ---------------------------------------------------------------------------

Hub.CARE = {
    { id = "bandage",   label = "UI_N26_Care_Bandage" },
    { id = "disinfect", label = "UI_N26_Care_Disinfect" },
    { id = "suture",    label = "UI_N26_Care_Suture" },
    { id = "splint",    label = "UI_N26_Care_Splint" },
    { id = "tweezers",  label = "UI_N26_Care_Tweezers" },
    { id = "pills",     label = "UI_N26_Care_Pills" },
}

function Hub.careKind(item)
    if (call(item, "getBandagePower") or 0) > 0 then return "bandage" end
    local t = call(item, "getType") or ""
    if t == "Splint" then return "splint" end
    if t == "Needle" or t == "SutureNeedle" or t == "Thread" then return "suture" end
    if t == "Tweezers" or t == "SutureNeedleHolder" then return "tweezers" end
    if string.find(t, "Pills", 1, true) then return "pills" end
    local fc = call(item, "getFluidContainer")
    if fc then
        local amount = call(fc, "getAmount") or 0
        local props = call(fc, "getProperties")
        local alcohol = props and call(props, "getAlcohol") or 0
        if amount > 0.15 and alcohol / amount + 0.001 >= 0.4 then return "disinfect" end
        return nil
    end
    if call(item, "IsDrainable") and call(item, "getAlcoholPower") == 4.0 then return "disinfect" end
    return nil
end

local function pageContainers(page)
    local out = {}
    for _, b in ipairs(page and page.backpacks or {}) do
        if b.inventory then out[#out + 1] = b.inventory end
    end
    return out
end

--- { kind = { mine = n, near = n, item = first } } over the player's and nearby containers.
function Hub.careSupplies()
    local out = {}
    for _, c in ipairs(Hub.CARE) do out[c.id] = { mine = 0, near = 0 } end
    local done = {}
    local function scan(container, field, depth)
        if not container or done[container] then return end
        done[container] = true
        local items = call(container, "getItems")
        local n = items and call(items, "size") or 0
        for i = 0, n - 1 do
            local item = items:get(i)
            if call(item, "IsInventoryContainer") then
                if depth < 2 then scan(call(item, "getInventory"), field, depth + 1) end
            else
                local kind = Hub.careKind(item)
                if kind then
                    local e = out[kind]
                    e[field] = e[field] + 1
                    e.item = e.item or item
                end
            end
        end
    end
    for _, c in ipairs(pageContainers(invPage())) do scan(c, "mine", 0) end
    for _, c in ipairs(pageContainers(lootPage())) do scan(c, "near", 0) end
    return out
end

N26HubCare = ISPanel:derive("N26HubCare")
local Care = N26HubCare

function Care:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.nextScan = 0
    return o
end

function Care:prerender()
    local C = Theme.C
    local now = getTimestampMs()
    if not self.supplies or now >= self.nextScan then
        local ok, res = pcall(Hub.careSupplies)
        self.supplies = ok and res or self.supplies or {}
        self.nextScan = now + 1000
    end
    D.panel(self, 0, 0, self.width, self.height, C.panel, C.outline, Theme.R.lg)
    local fs = D.fontScale()
    local hdrH = floor(34 * fs)
    D.fill(self, 1, 1, self.width - 2, hdrH - 1, C.panel2, Theme.R.lg - 1)
    D.rect(self, 1, hdrH, self.width - 2, 1, C.divider)
    D.titleWithBar(self, getText("UI_N26_Care_Title"), 10, 0, hdrH, C.text, "md")
    local fh = D.fontHeight(UIFont.Small)
    local pad = 12
    local y = hdrH + 10
    local nearW = max(D.headingWidth(getText("UI_N26_Care_Near"), "sm"), 30) + 12
    local mineW = max(D.headingWidth(getText("UI_N26_Care_Mine"), "sm"), 30) + 12
    local nearX = self.width - pad - floor(nearW / 2)
    local mineX = self.width - pad - nearW - floor(mineW / 2)
    D.caption(self, getText("UI_N26_Care_Mine"), mineX, y, C.muted, "center")
    D.caption(self, getText("UI_N26_Care_Near"), nearX, y, C.muted, "center")
    y = y + D.headingHeight("sm") + 8
    local rowH = max(floor(40 * fs), fh * 2 + 8)
    for _, c in ipairs(Hub.CARE) do
        if y + rowH > self.height - fh * 3 then break end
        local e = self.supplies[c.id] or { mine = 0, near = 0 }
        local has = e.mine + e.near > 0
        D.fill(self, pad, y, self.width - 2 * pad, rowH - 4, has and C.hover or C.field, Theme.R.md)
        local isz = rowH - 12
        local tex = e.item and call(e.item, "getTex")
        if tex then
            self:drawTextureScaledAspect(tex, pad + 6, y + 4, isz, isz, 1, 1, 1, 1)
        end
        local tx = pad + 12 + isz
        local ty = y + floor((rowH - 4 - fh) / 2)
        D.text(self, getText(c.label), tx, ty, has and C.text or C.text2, UIFont.Small, nil, self.width - tx - pad - nearW - mineW)
        D.text(self, tostring(e.mine), mineX, ty, e.mine > 0 and C.ok or C.muted, UIFont.Small, "center")
        D.text(self, tostring(e.near), nearX, ty, e.near > 0 and C.info or C.muted, UIFont.Small, "center")
        y = y + rowH
    end
    -- treatment itself stays the vanilla menu on the body
    local hint = getText("UI_N26_Care_Hint")
    local lines = { hint }
    if D.measure(UIFont.Small, hint) > self.width - 2 * pad then
        local mid = floor(#hint / 2)
        local cut = hint:find(" ", mid, true) or mid
        lines = { hint:sub(1, cut - 1), hint:sub(cut + 1) }
    end
    local hy = self.height - pad - #lines * (fh + 2)
    for i, l in ipairs(lines) do
        D.text(self, l, pad, hy + (i - 1) * (fh + 2), C.muted, UIFont.Small, nil, self.width - 2 * pad)
    end
end

-- ---------------------------------------------------------------------------
-- Hub panel
-- ---------------------------------------------------------------------------

N26HubPanel = ISPanel:derive("N26HubPanel")
local Panel = N26HubPanel

function Panel:new()
    local W, H = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, W, H)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.moveWithMouse = false
    o.tab = "inventory"
    o.craftMode = "craft"
    o.tabRects = {}
    o.isOpen = false
    o.n26HubOwned = true
    o:setWantKeyEvents(true)
    return o
end

function Panel:createChildren()
    self.equip = N26HubEquip:new(0, 0, 300, 600, self)
    self.equip:initialise()
    self:addChild(self.equip)
    self.ident = N26HubIdentity:new(0, 0, 300, 600, self)
    self.ident:initialise()
    self:addChild(self.ident)
    self.ident:setVisible(false)
    self.care = N26HubCare:new(0, 0, 300, 600)
    self.care:initialise()
    self:addChild(self.care)
    self.care:setVisible(false)
    self.skills = N26HubSkills:new(0, 0, 600, 600)
    self.skills:initialise(); self:addChild(self.skills); self.skills:setVisible(false)
    self.craft = N26HubCraft:new(0, 0, 900, 600, player())
    self.craft:initialise(); self:addChild(self.craft); self.craft:setVisible(false)
end

function Panel:metrics()
    local fs = D.fontScale()
    local m = { fs = fs }
    m.topH = floor(54 * fs)
    m.botH = self.tab == "inventory" and floor(42 * fs) or 0
    m.x0, m.y0 = PAD, m.topH + PAD
    m.x1 = self.width - PAD
    m.y1 = self.height - PAD - (m.botH > 0 and (m.botH) or 0)
    m.cw, m.ch = m.x1 - m.x0, m.y1 - m.y0
    m.switchH = self.tab == "crafting" and floor(34 * fs) or 0
    return m
end

--- Position every docked window and child widget for the current tab.
function Panel:layoutDocks()
    local m = self:metrics()
    self.m = m
    local tab = self.tab
    self.equip:setVisible(tab == "inventory")
    self.ident:setVisible(tab == "character")
    self.care:setVisible(tab == "health")
    self.skills:setVisible(tab == "character")
    self.craft:setVisible(tab == "crafting")
    if tab == "inventory" then
        local ew = max(floor(300 * m.fs), min(floor(440 * m.fs), floor(m.cw * 0.27)))
        local colW = floor((m.cw - ew - 2 * PAD) / 2)
        if self.equip.x ~= m.x0 or self.equip.width ~= ew or self.equip.height ~= m.ch then
            self.equip:setX(m.x0); self.equip:setY(m.y0)
            self.equip:setWidth(ew); self.equip:setHeight(m.ch)
        end
        local inv, loot = invPage(), lootPage()
        dock(inv, m.x0 + ew + PAD, m.y0, colW, m.ch, { page = true, resize = true })
        dock(loot, m.x0 + ew + PAD + colW + PAD, m.y0, m.x1 - (m.x0 + ew + 2 * PAD + colW), m.ch, { page = true, resize = true })
    elseif tab == "health" then
        local cw = max(floor(260 * m.fs), min(floor(360 * m.fs), floor(m.cw * 0.22)))
        local cx = m.x1 - cw
        if self.care.x ~= cx or self.care.width ~= cw or self.care.height ~= m.ch then
            self.care:setX(cx); self.care:setY(m.y0)
            self.care:setWidth(cw); self.care:setHeight(m.ch)
        end
        local aw = m.cw - cw - PAD
        local info = infoWin()
        if info and info.healthView then
            -- the N26 health view grows to fill the tab (see N26_Health)
            info.healthView.n26MinW = min(aw, floor(1180 * m.fs))
            info.healthView.n26MinH = m.ch - info:titleBarHeight() - floor(40 * m.fs)
        end
        dock(info, m.x0, m.y0, aw, m.ch, { resize = true })
        sizeHealth(info, aw, m.ch)
    elseif tab == "character" then
        local iw = max(floor(280 * m.fs), min(floor(400 * m.fs), floor(m.cw * 0.25)))
        if self.ident.width ~= iw or self.ident.height ~= m.ch then
            self.ident:setX(m.x0); self.ident:setY(m.y0)
            self.ident:setWidth(iw); self.ident:setHeight(m.ch)
        end
        self.skills:setX(m.x0 + iw + PAD); self.skills:setY(m.y0)
        self.skills:setWidth(m.cw - iw - PAD); self.skills:setHeight(m.ch)
    elseif tab == "crafting" then
        local y = m.y0 + m.switchH + 8
        local info = infoWin()
        if info and info.healthView then info.healthView.n26MinW, info.healthView.n26MinH = nil, nil end
        local win = entityWin(self.craftMode == "build" and "BuildWindow" or "HandcraftWindow")
        if win then
            win.n26CraftEngine = true
            win:setVisible(false)
            self.craft:attach(win)
        end
        self.craft:setX(m.x0); self.craft:setY(y)
        self.craft:setWidth(m.cw); self.craft:setHeight(m.y1 - y)
    elseif tab == "map" then
        local map = mapWin()
        if map then dock(map, m.x0, m.y0, m.cw, m.ch, { resize = true }) end
    end
end

function Panel:raiseDocked()
    for _, w in ipairs(dockOrder) do
        if w:getIsVisible() then w:bringToTop() end
    end
    self.needRaise = false
end

local function tabLabel(t) return getText(t.label) end

function Panel:drawTopBar(m)
    local C = Theme.C
    local W = self.width
    D.fill(self, 0, 0, W, m.topH, Theme.copy(C.bg, 0.94))
    D.rect(self, 0, m.topH - 1, W, 1, C.divider)
    local chr = player()
    local fh = D.fontHeight(UIFont.Small)

    -- left: brand + survivor
    local x = PAD + 4
    local hh = D.headingHeight("md")
    local ty = floor((m.topH - hh) / 2)
    x = x + D.heading(self, "N26", x, ty, C.accent, "md") + 12
    local desc = chr and call(chr, "getDescriptor")
    if desc then
        local name = (call(desc, "getForename") or "") .. " " .. (call(desc, "getSurname") or "")
        x = x + D.heading(self, name, x, ty, C.text, "md", nil, floor(W * 0.16)) + 10
        local hours = call(chr, "getHoursSurvived") or 0
        D.text(self, getText("UI_N26_Hub_Day", tostring(floor(hours / 24) + 1)), x, floor((m.topH - fh) / 2) + 1, C.muted, UIFont.Small)
    end

    -- centre: tabs
    local items, total = {}, 0
    local kh = fh + 2
    for _, t in ipairs(Hub.TABS) do
        local label = tabLabel(t)
        local key = t.id == "inventory" and "Tab" or keyName(t.bind)
        local lw = D.headingWidth(label, "md")
        local kw = key and max(kh, D.measure(UIFont.Small, key) + 10) or 0
        local w = 18 + lw + (key and (8 + kw) or 0) + 18
        items[#items + 1] = { t = t, label = label, key = key, w = w, lw = lw }
        total = total + w + 4
    end
    local tx = floor((W - total) / 2)
    local mx, my = self:getMouseX(), self:getMouseY()
    self.tabRects = {}
    for _, it in ipairs(items) do
        local active = it.t.id == self.tab
        local hovered = my >= 0 and my < m.topH and mx >= tx and mx < tx + it.w
        if hovered and not active then D.fill(self, tx, 6, it.w, m.topH - 12, C.hover, Theme.R.md) end
        local fg = active and C.white or (hovered and C.text or C.muted)
        D.heading(self, it.label, tx + 18, ty, fg, "md")
        if it.key then
            D.keycap(self, it.key, tx + 18 + it.lw + 8, floor((m.topH - kh) / 2), kh, "ghost")
        end
        if active then D.rect(self, tx + 8, m.topH - 3, it.w - 16, 3, C.accent) end
        self.tabRects[#self.tabRects + 1] = { x = tx, w = it.w, id = it.t.id }
        tx = tx + it.w + 4
    end

    -- right: time · temperature · close
    local rx = W - PAD - 4
    local esc = getText("UI_N26_Hub_Close")
    rx = rx - D.measure(UIFont.Small, esc)
    D.text(self, esc, rx, floor((m.topH - fh) / 2), C.text2, UIFont.Small)
    rx = rx - 8
    local escKey = getText("UI_N26_Key_Escape")
    local kw = max(kh, D.measure(UIFont.Small, escKey) + 10)
    rx = rx - kw
    D.keycap(self, escKey, rx, floor((m.topH - kh) / 2), kh, "ghost")
    self.closeRect = { x = rx, w = W - rx }
    local gt = getGameTime and getGameTime()
    if gt then
        local s = string.format("%02d:%02d", call(gt, "getHour") or 0, call(gt, "getMinutes") or 0)
        local cm = getClimateManager and getClimateManager()
        local temp = cm and call(cm, "getTemperature")
        if temp then
            if getCore():getOptionDisplayAsCelsius() then
                s = s .. "  ·  " .. string.format("%d °C", floor(temp + 0.5))
            else
                s = s .. "  ·  " .. string.format("%d °F", floor(temp * 9 / 5 + 32 + 0.5))
            end
        end
        D.text(self, s, rx - 20, floor((m.topH - fh) / 2), C.text2, UIFont.Small, "right")
    end
end

function Panel:drawBottomBar(m)
    local C = Theme.C
    local y = self.height - m.botH
    D.fill(self, 0, y, self.width, m.botH, Theme.copy(C.bg, 0.94))
    D.rect(self, 0, y, self.width, 1, C.divider)
    local fh = D.fontHeight(UIFont.Small)
    local ty = y + floor((m.botH - fh) / 2)
    local x = PAD + 4
    x = x + D.caption(self, getText("UI_N26_Hub_Actions"), x, y + floor((m.botH - D.headingHeight("sm")) / 2)) + 14
    local q = actionQueue(player())
    if q and #q > 0 then
        local cur = q[1]
        local label = Hub.actionLabel(cur)
        local lw = min(D.measure(UIFont.Small, label), floor(self.width * 0.25))
        D.text(self, label, x, ty, C.text, UIFont.Small, nil, lw)
        x = x + lw + 12
        local delta = 0
        if cur.action and cur.action.getJobDelta then
            local ok, d = pcall(cur.action.getJobDelta, cur.action)
            if ok and d then delta = d end
        end
        D.bar(self, x, y + floor(m.botH / 2) - 2, floor(180 * m.fs), 4, delta, C.accent, C.hover2, 2)
        x = x + floor(180 * m.fs) + 12
        for i = 2, min(#q, 4) do
            local s = Hub.actionLabel(q[i])
            local w = min(D.measure(UIFont.Small, s) + 16, floor(self.width * 0.14))
            D.fill(self, x, y + 8, w, m.botH - 16, C.hover, Theme.R.md)
            D.text(self, s, x + 8, ty, C.text2, UIFont.Small, nil, w - 16)
            x = x + w + 6
        end
        if #q > 4 then D.text(self, "+" .. (#q - 4), x, ty, C.muted, UIFont.Small) end
    else
        D.text(self, getText("UI_N26_Hub_NoAction"), x, ty, C.dim, UIFont.Small)
    end
    -- hints (right)
    local hints = {
        { "UI_N26_Hint_RightClick", "UI_N26_Hint_Actions" },
        { "UI_N26_Hint_Drag", "UI_N26_Hint_Transfer" },
        { "UI_N26_Hint_DoubleClick", "UI_N26_Hint_Unequip" },
    }
    local rx = self.width - PAD - 4
    local kh = fh + 2
    for i = #hints, 1, -1 do
        local label = getText(hints[i][2])
        rx = rx - D.measure(UIFont.Small, label)
        D.text(self, label, rx, ty, C.muted, UIFont.Small)
        local key = getText(hints[i][1])
        local kw = max(kh, D.measure(UIFont.Small, key) + 10)
        rx = rx - 6 - kw
        D.keycap(self, key, rx, y + floor((m.botH - kh) / 2), kh, "ghost")
        rx = rx - 18
    end
end

function Panel:drawCraftSwitch(m)
    local C = Theme.C
    local opts = { { "craft", "UI_N26_Hub_Craft" }, { "build", "UI_N26_Hub_Build" } }
    local fh = D.fontHeight(UIFont.Small)
    local x = m.x0
    local mx, my = self:getMouseX(), self:getMouseY()
    self.switchRects = {}
    for _, o in ipairs(opts) do
        local label = getText(o[2])
        local w = D.headingWidth(label, "sm") + 36
        local active = self.craftMode == o[1]
        local hovered = my >= m.y0 and my < m.y0 + m.switchH and mx >= x and mx < x + w
        D.fill(self, x, m.y0, w, m.switchH, active and C.accent or (hovered and C.hover2 or C.panel2), Theme.R.md)
        D.heading(self, label, x + w / 2, m.y0 + floor((m.switchH - D.headingHeight("sm")) / 2), active and C.onAccent or C.text2, "sm", "center")
        self.switchRects[#self.switchRects + 1] = { x = x, w = w, id = o[1] }
        x = x + w + 4
    end
    local key = keyName(self.craftMode == "build" and "BUILDING_UI" or "CRAFTING_UI")
    if key then
        D.keycap(self, key, x + 8, m.y0 + floor((m.switchH - fh - 2) / 2), fh + 2, "ghost")
    end
end

-- bringToTop is queued by UIManager. After clicking the hub, native windows
-- can still render before it. Never paint the world dimmer over their bounds,
-- regardless of the current top-level render order.
function Panel:drawBackdrop()
    local regions = { { x = 0, y = 0, w = self.width, h = self.height } }
    for _, win in ipairs(dockOrder) do
        if visible(win) then
            local nextRegions = {}
            for _, r in ipairs(regions) do
                local x1, y1 = max(r.x, win.x), max(r.y, win.y)
                local x2, y2 = min(r.x + r.w, win.x + win.width), min(r.y + r.h, win.y + win.height)
                if x1 >= x2 or y1 >= y2 then
                    nextRegions[#nextRegions + 1] = r
                else
                    local function add(x, y, w, h)
                        if w > 0 and h > 0 then
                            nextRegions[#nextRegions + 1] = { x = x, y = y, w = w, h = h }
                        end
                    end
                    add(r.x, r.y, r.w, y1 - r.y)
                    add(r.x, y2, r.w, r.y + r.h - y2)
                    add(r.x, y1, x1 - r.x, y2 - y1)
                    add(x2, y1, r.x + r.w - x2, y2 - y1)
                end
            end
            regions = nextRegions
        end
    end
    local color = Theme.copy(Theme.C.bg, 0.72)
    for _, r in ipairs(regions) do
        D.fill(self, r.x, r.y, r.w, r.h, color)
        D.shade(self, r.x, r.y, r.w, r.h, 0.35)
    end
end

function Panel:prerender()
    if not self.isOpen then return end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    if self.width ~= sw or self.height ~= sh then
        self:setWidth(sw); self:setHeight(sh)
    end
    Hub.watch()
    if not self.isOpen then return end
    self:layoutDocks()
    if self.needRaise then self:raiseDocked() end
    local m = self.m
    -- dimmed world behind (Tarkov-like backdrop, the game keeps running)
    self:drawBackdrop()
    self:drawTopBar(m)
    if m.botH > 0 then self:drawBottomBar(m) end
    if self.tab == "crafting" then self:drawCraftSwitch(m) end
    if self.tab == "map" and not visible(mapWin()) then
        D.text(self, getText("UI_N26_Map_Unavailable"), self.width / 2, self.height / 2, Theme.C.muted, UIFont.Small, "center")
    end
end

function Panel:onMouseDown(x, y)
    self.needRaise = true
    local m = self.m or self:metrics()
    if y < m.topH then
        if self.closeRect and x >= self.closeRect.x then
            Hub.close()
            return true
        end
        for _, r in ipairs(self.tabRects) do
            if x >= r.x and x < r.x + r.w then
                if r.id ~= self.tab then
                    getSoundManager():playUISound("UIActivateTab")
                    Hub.setTab(r.id)
                end
                return true
            end
        end
    elseif self.tab == "crafting" and self.switchRects and y >= m.y0 and y < m.y0 + m.switchH then
        for _, r in ipairs(self.switchRects) do
            if x >= r.x and x < r.x + r.w and r.id ~= self.craftMode then
                Hub.setTab("crafting", r.id)
            end
        end
    end
    return true
end

function Panel:onRightMouseDown()
    self.needRaise = true
    return true
end

function Panel:onMouseWheel(del)
    local m = self.m or self:metrics()
    if self:getMouseY() >= m.topH then return false end
    local order = {}
    for _, t in ipairs(Hub.TABS) do order[#order + 1] = t.id end
    local cur = 1
    for i, id in ipairs(order) do if id == self.tab then cur = i end end
    local nxt = order[((cur - 1 + (del > 0 and 1 or -1)) % #order) + 1]
    Hub.setTab(nxt)
    return true
end

function Panel:isKeyConsumed(key)
    return key == Keyboard.KEY_ESCAPE or (self.tab == "crafting" and
        (isKey("CRAFTING_UI", key) or isKey("BUILDING_UI", key)))
end

function Panel:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE and self.isOpen then
        Hub.close()
    elseif self.isOpen and self.tab == "crafting" then
        local mode = isKey("BUILDING_UI", key) and "build" or (isKey("CRAFTING_UI", key) and "craft" or nil)
        if mode then
            if self.craftMode == mode then Hub.close() else Hub.setTab("crafting", mode) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Opening, switching, closing
-- ---------------------------------------------------------------------------

local function infoTabOf(info)
    if info and info.panel and info.healthView and info.panel:getActiveView() == info.healthView then
        return "health"
    end
    return "character"
end

local function closeInfo()
    local info = infoWin()
    if info then
        undock(info)
        if info:getIsVisible() then info:close() end
    end
end

local function closeCraft(except)
    for _, key in ipairs({ "HandcraftWindow", "BuildWindow" }) do
        local w = entityWin(key)
        if w and key ~= except then
            undock(w)
            w.n26CraftEngine = nil
            w:close()
        end
    end
end

--- Show the vanilla panels the current tab needs, then hide the others (in
--- that order, so mouse-unlock mods never see a frame with nothing open).
local function applyTab(h, sub)
    local chr = player()
    local inv, loot = invPage(), lootPage()
    local info = infoWin()
    local tab = h.tab

    -- 1. show
    if tab == "inventory" then
        if inv and not inv:getIsVisible() then inv:setVisible(true) end
        if loot and not loot:getIsVisible() then loot:setVisible(true) end
        h.equip:refresh()
    elseif tab == "character" then
        h.ident:refresh()
        h.skills:refresh()
    elseif tab == "health" and info and info.panel then
        if info.panel:getActiveView() ~= info.healthView then info.panel:activateView(xpSystemText.health) end
        if not info:getIsVisible() then
            info:setVisible(true)
            info:addToUIManager()
        end
    elseif tab == "crafting" then
        h.craftMode = sub or h.craftMode or "craft"
        local key = h.craftMode == "build" and "BuildWindow" or "HandcraftWindow"
        if not entityWin(key) and chr then
            if h.craftMode == "build" then
                ISEntityUI.OpenBuildWindow(chr, nil, "*")
            else
                ISEntityUI.OpenHandcraftWindow(chr, nil)
            end
        end
    elseif tab == "map" then
        if not ISWorldMap or not ISWorldMap.ShowWorldMap then require "ISUI/Maps/ISWorldMap" end
        ISWorldMap.ShowWorldMap(PLAYER)
        Hub.map = rawget(_G, "ISWorldMap_instance") or ISWorldMap.instance
        if Hub.map then integrateMap(Hub.map) end
        Hub.mapUnavailable = not visible(Hub.map)
    end

    -- 2. hide
    if tab ~= "inventory" then
        undock(inv); undock(loot)
        if visible(inv) then inv:setVisible(false) end
        if visible(loot) then loot:setVisible(false) end
    end
    if tab ~= "health" then closeInfo() end
    if tab ~= "map" then closeMap() end
    if tab == "crafting" then
        closeCraft(h.craftMode == "build" and "BuildWindow" or "HandcraftWindow")
    else
        h.craft:detach()
        closeCraft(nil)
    end
    h.needRaise = true
    h:layoutDocks()
end

function Hub.open(tab, sub)
    if not Hub.active() then return end
    local h = Hub.instance
    if not h then
        h = N26HubPanel:new()
        h:initialise()
        h:instantiate()
        Hub.instance = h
    end
    if not h.isOpen then
        h.isOpen = true
        h:setWidth(getCore():getScreenWidth())
        h:setHeight(getCore():getScreenHeight())
        h:setVisible(true)
        h:addToUIManager()
        getSoundManager():playUISound("UIActivateTab")
    end
    h.tab = tab or "inventory"
    applyTab(h, sub)
    h:raiseDocked()
end

function Hub.setTab(tab, sub)
    if not Hub.isOpen() then return Hub.open(tab, sub) end
    Hub.instance.tab = tab
    applyTab(Hub.instance, sub)
end

function Hub.close()
    local h = Hub.instance
    if not h or not h.isOpen then return end
    h.isOpen = false
    undockAll()
    local inv, loot = invPage(), lootPage()
    if visible(inv) then inv:setVisible(false) end
    if visible(loot) then loot:setVisible(false) end
    closeInfo()
    closeMap()
    h.craft:detach()
    closeCraft(nil)
    if h.equip then h.equip:updateTooltip(nil) end
    h:setVisible(false)
    h:removeFromUIManager()
end

function Hub.toggle(tab)
    if Hub.isOpen() then Hub.close() else Hub.open(tab or "inventory") end
end

-- ---------------------------------------------------------------------------
-- Watcher: vanilla ways of opening / closing the hosted windows
-- ---------------------------------------------------------------------------

local primed = false

function Hub.watch()
    if not Hub.active() then
        if Hub.isOpen() then N26.log("watch: screen inactive, closing"); Hub.close() end
        return
    end
    local inv, info = invPage(), infoWin()
    if not inv then return end
    local invV, infoV = visible(inv), visible(info)
    local craftW, buildW = entityWin("HandcraftWindow"), entityWin("BuildWindow")

    if not primed then
        primed = true
        if not Hub.isOpen() then
            -- windows restored visible from the saved layout: start with the hub closed
            if invV then inv:setVisible(false) end
            if visible(lootPage()) then lootPage():setVisible(false) end
            return
        end
    end

    if not Hub.isOpen() then
        if invV then Hub.open("inventory")
        elseif infoV then Hub.open(infoTabOf(info))
        elseif craftW then Hub.open("crafting", "craft")
        elseif buildW then Hub.open("crafting", "build")
        elseif visible(mapWin()) then Hub.open("map") end
        return
    end

    local h = Hub.instance
    local tab = h.tab
    if tab ~= "map" and visible(mapWin()) then return Hub.setTab("map") end
    if tab == "inventory" then
        if infoV then return Hub.setTab(infoTabOf(info)) end
        if craftW or buildW then return Hub.setTab("crafting", buildW and "build" or "craft") end
        if not invV then N26.log("watch: inventory hidden, closing"); return Hub.close() end
    elseif tab == "health" then
        if invV then return Hub.setTab("inventory") end
        if craftW or buildW then return Hub.setTab("crafting", buildW and "build" or "craft") end
        if not infoV then N26.log("watch: info window hidden, closing"); return Hub.close() end
        local t = infoTabOf(info)
        if t ~= tab then
            return Hub.setTab(t)
        end
    elseif tab == "character" then
        if invV then return Hub.setTab("inventory") end
        if craftW or buildW then return Hub.setTab("crafting", buildW and "build" or "craft") end
        if infoV then
            local t = infoTabOf(info)
            if t == "health" then return Hub.setTab(t) end
            closeInfo()
        end
    elseif tab == "crafting" then
        if invV then return Hub.setTab("inventory") end
        if infoV then return Hub.setTab(infoTabOf(info)) end
        if not craftW and not buildW then N26.log("watch: crafting window closed, closing"); return Hub.close() end
        local mode = buildW and "build" or "craft"
        if mode ~= h.craftMode then return Hub.setTab("crafting", mode) end
    elseif tab == "map" then
        if not Hub.mapUnavailable and not visible(mapWin()) then N26.log("watch: map closed, closing"); return Hub.close() end
        if invV then return Hub.setTab("inventory") end
        if infoV then return Hub.setTab(infoTabOf(info)) end
        if craftW or buildW then return Hub.setTab("crafting", buildW and "build" or "craft") end
    end
end

local pendingToggle = false

--- Run the Tab toggle requested during the last key event. Deferred to the next
--- frame so every other key handler (vanilla, other mods) has run first and
--- cannot hide the inventory again right after the hub opened.
local function runPendingToggle()
    if not pendingToggle then return false end
    pendingToggle = false
    local ok, err = pcall(function()
        if Hub.isOpen() then
            N26.log("Tab: closing the tactical screen")
            Hub.close()
        else
            N26.log("Tab: opening the tactical screen")
            Hub.open("inventory")
            if not Hub.isOpen() then N26.log("Tab: the tactical screen did not open (active=%s)", tostring(Hub.active())) end
        end
    end)
    if not ok then N26.log("Tab toggle failed: %s", tostring(err)) end
    return true
end

local function onFrame()
    if not getSpecificPlayer(PLAYER) then return end
    if runPendingToggle() then return end
    if Hub.isOpen() then return end -- the open hub runs the watcher from its prerender
    local ok, err = pcall(Hub.watch)
    if not ok then N26.log("hub watcher failed: %s", tostring(err)) end
end

-- Tab always toggles the hub, independently of the player's inventory binding.
-- Keep the configured inventory key too; vanilla handles it for controllers,
-- the tutorial and when the module is switched off.
local vanillaToggle = ISInventoryPage.onKeyPressed

function Hub.onKeyPressed(key)
    if not Hub.active() then
        return vanillaToggle(key)
    end
    if (key == Keyboard.KEY_TAB or isKey("TOGGLE_INVENTORY", key))
            and (getGameSpeed() > 0 or Hub.isOpen()) and getPlayerInventory(PLAYER) then
        pendingToggle = true
    end
end

--- Direct toggle (tests, other callers): runs the pending request now.
function Hub.flushKeys() return runPendingToggle() end

local function installKeyHandler()
    if Events.OnKeyPressed.Remove then
        Events.OnKeyPressed.Remove(vanillaToggle)
        Events.OnKeyPressed.Remove(Hub.onKeyPressed)
    end
    Events.OnKeyPressed.Add(Hub.onKeyPressed)
end
installKeyHandler()
-- again once the game runs, in case the vanilla handler was registered after us
Events.OnGameStart.Add(installKeyHandler)

-- Native health / skill shortcuts and sidebar buttons now select our pages.
-- Intercept before vanilla can flash its character sheet on screen.
if type(ISCharacterInfoWindow) == "table" and type(ISCharacterInfoWindow.toggleView) == "function" then
    N26.hook(ISCharacterInfoWindow, "ISCharacterInfoWindow", "toggleView", MODULE, function(orig, self, viewName)
        if not Hub.active() or self.playerNum ~= PLAYER then return orig(self, viewName) end
        local tab = viewName == xpSystemText.health and "health" or "character"
        if Hub.isOpen() and Hub.instance.tab == tab then return Hub.close() end
        return Hub.open(tab)
    end, { scope = "global" })
end

if Events.OnPreUIDraw then
    Events.OnPreUIDraw.Add(onFrame)
else
    Events.OnTick.Add(onFrame)
end

Events.OnClothingUpdated.Add(function(chr)
    local h = Hub.instance
    if h and h.isOpen and chr == player() then
        if h.equip then h.equip:refresh() end
        if h.ident and h.tab == "character" then h.ident:refresh() end
    end
end)

if Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(function(chr)
        if chr == player() then Hub.close() end
    end)
end

N26.on("configChanged", function()
    if Hub.isOpen() and not Hub.active() then Hub.close() end
end)

