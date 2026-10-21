--[[
    N26 Health (board 04) — ISHealthPanel.

    Layout (responsive to the info window width):
        ┌ body ─────────┐  ┌ status ─────────────────────────────┐
        │  silhouette   │  │ OVERALL STATUS   82 / 100  ▬▬▬▬▬▬▬  │
        │  17 zones     │  │ pain · wet · endurance · temp (pips) │
        │  coloured by  │  ├ injuries ───────────────────────────┤
        │  part health  │  │ [card per injured part: name, bar,   │
        └───────────────┘  │  wounds as coloured bullets, action] │
                            └─────────────────────────────────────┘

    The Java silhouette (NewHealthPanel) draws from packed textures that cannot
    be overridden reliably, so it is hidden and replaced by an N26 body view.
    Everything clinical stays vanilla:
      * right-click a zone (or a card) → vanilla treatment menu
        (ISHealthPanel:doBodyPartContextMenu);
      * drop items on a zone → ISHealthPanel:dropItemsOnBodyPart;
      * wound text, severity gating by Doctor level, remote patients (MP),
        fitness button, blocking messages, joypad navigation.
    The wound cards run the vanilla doDrawItem under interception.
]]

require "ISUI/BodyParts/ISBodyPartPanel"
require "XpSystem/ISUI/ISHealthPanel"
require "ISUI/ISUI3DModel"
require "N26/Skin/N26_SkinControls"

local Theme = N26.Theme
local D = N26.Draw
local Skin = N26.Skin
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

N26.registerModule({ id = "health", label = "UI_N26_Mod_Health", tooltip = "UI_N26_Mod_Health_Tip" })
local MODULE = "health"

local PAD = 10

-- ---------------------------------------------------------------------------
-- Silhouette geometry (design space 160 x 400, character facing the viewer:
-- the character's left side is drawn on the right)
-- ---------------------------------------------------------------------------

local ZONES = {
    { "Head",        60,   0, 40, 44, 18 },
    { "Neck",        70,  46, 20, 12, 4 },
    { "Torso_Upper", 44,  60, 72, 74, 14 },
    { "Torso_Lower", 48, 136, 64, 52, 12 },
    { "Groin",       52, 190, 56, 30, 10 },
    { "UpperArm_R",  16,  64, 24, 62, 10 },
    { "UpperArm_L", 120,  64, 24, 62, 10 },
    { "ForeArm_R",   10, 128, 24, 58, 10 },
    { "ForeArm_L",  126, 128, 24, 58, 10 },
    { "Hand_R",       6, 188, 24, 26, 8 },
    { "Hand_L",     130, 188, 24, 26, 8 },
    { "UpperLeg_R",  50, 222, 28, 84, 12 },
    { "UpperLeg_L",  82, 222, 28, 84, 12 },
    { "LowerLeg_R",  52, 308, 24, 70, 10 },
    { "LowerLeg_L",  84, 308, 24, 70, 10 },
    { "Foot_R",      46, 380, 30, 18, 6 },
    { "Foot_L",      84, 380, 30, 18, 6 },
}
local DESIGN_W, DESIGN_H = 160, 400

local function patientBodyDamage(panel)
    local patient = panel:getPatient()
    if isClient() and not patient:isLocalPlayer() then
        return patient:getBodyDamageRemote()
    end
    return patient:getBodyDamage()
end

local function bodyPartsByName(panel)
    local map = {}
    local parts = patientBodyDamage(panel):getBodyParts()
    for i = 1, parts:size() do
        local bp = parts:get(i - 1)
        map[tostring(bp:getType())] = bp
    end
    return map
end

-- ---------------------------------------------------------------------------
-- Body view widget
-- ---------------------------------------------------------------------------

local Body = ISPanel:derive("N26HealthBody")

function Body:new(panel, x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.panel = panel
    o.background = false
    o.n26NoSkin = true
    o.hover = nil
    return o
end

-- Where the figure sits inside the 3D viewport (fractions of the view height).
-- The game camera frames the character from head to feet with a small margin;
-- the zone overlay is fitted into the same band.
local FIG_TOP, FIG_BOTTOM = 0.05, 0.965

function Body:layout()
    local availH = self.height * (FIG_BOTTOM - FIG_TOP)
    local s = min((self.width - 8) / DESIGN_W, availH / DESIGN_H)
    local ox = floor((self.width - DESIGN_W * s) / 2)
    local oy = floor(self.height * FIG_TOP + (availH - DESIGN_H * s) / 2)
    return s, ox, oy
end

--- The real character: the game's 3D avatar widget (same as the character
--- sheet), facing the viewer, not rotatable here so zones stay aligned.
function Body:createChildren()
    if not ISUI3DModel then return end
    local ok, err = pcall(function()
        local m = ISUI3DModel:new(0, 0, self.width, self.height)
        m:initialise()
        m:instantiate()
        self:addChild(m)
        m:setVisible(true)
        m:setIsometric(false)
        m:setDirection(IsoDirections.S)
        m:setState("idle")
        if m.javaObject.setConsumeMouseEvents then m.javaObject:setConsumeMouseEvents(false) end
        -- clicks go to the body view (zones), not to the model's drag-rotate
        m.onMouseDown = function() return false end
        m.onMouseUp = function() return false end
        m.onMouseMove = function() return false end
        self.model = m
        self:refreshModel(true)
    end)
    if not ok then N26.log("health 3D model unavailable: %s", tostring(err)) end
end

function Body:refreshModel(force)
    local m = self.model
    if not m then return end
    local patient = self.panel:getPatient()
    if force or patient ~= self.modelChar or self.modelDirty then
        self.modelChar = patient
        self.modelDirty = false
        m:setCharacter(patient)
    end
    if m.width ~= self.width or m.height ~= self.height then
        m:setWidth(self.width)
        m:setHeight(self.height)
    end
end

function Body:zoneAt(mx, my)
    local s, ox, oy = self:layout()
    for i = #ZONES, 1, -1 do
        local z = ZONES[i]
        local x, y, w, h = ox + z[2] * s, oy + z[3] * s, z[4] * s, z[5] * s
        if mx >= x - 2 and mx <= x + w + 2 and my >= y - 2 and my <= y + h + 2 then
            return z[1]
        end
    end
    return nil
end

local function partState(bp)
    if not bp then return 1, false, false, false end
    local health = bp:getHealth() / 100
    local injured = bp:HasInjury()
    local bleeding = bp:bleeding()
    local treated = bp:bandaged() or bp:stitched() or bp:getSplintFactor() > 0
    return health, injured, bleeding, treated
end

function Body:selectedPartName()
    local lb = self.panel.listbox
    local item = lb and lb.items and lb.items[lb.selected]
    if item and item.item and item.item.bodyPart then
        return tostring(item.item.bodyPart:getType())
    end
    return nil
end

function Body:prerender()
    local C = Theme.C
    self:refreshModel(false)
    -- viewport well under the character
    D.fill(self, 0, 0, self.width, self.height, C.field, Theme.R.md, 0.9)
    D.shade(self, 0, floor(self.height * 0.15), self.width, floor(self.height * 0.85), 0.0)
    local fc = C.white
    local L = 12
    D.rect(self, 0, 0, L, 1, fc, 0.28); D.rect(self, 0, 0, 1, L, fc, 0.28)
    D.rect(self, self.width - L, 0, L, 1, fc, 0.28); D.rect(self, self.width - 1, 0, 1, L, fc, 0.28)
    D.rect(self, 0, self.height - 1, L, 1, fc, 0.28); D.rect(self, 0, self.height - L, 1, L, fc, 0.28)
    D.rect(self, self.width - L, self.height - 1, L, 1, fc, 0.28); D.rect(self, self.width - 1, self.height - L, 1, L, fc, 0.28)
    if not self.model then self:drawZones(true) end
end

--- Zone overlay. withBase = true draws every zone (no 3D model available);
--- over the real character only damaged / treated / hovered / selected zones.
function Body:drawZones(withBase)
    local C = Theme.C
    local parts = bodyPartsByName(self.panel)
    local s, ox, oy = self:layout()
    local selected = self:selectedPartName()
    local dragging = ISMouseDrag.dragging and #ISMouseDrag.dragging > 0
    local t = getTimestampMs()
    local pulse = N26.Config.animations() and (0.55 + 0.45 * math.sin(t / 180)) or 1

    for _, z in ipairs(ZONES) do
        local name = z[1]
        local x, y, w, h = floor(ox + z[2] * s), floor(oy + z[3] * s), floor(z[4] * s), floor(z[5] * s)
        local r = max(2, floor(z[6] * s))
        local health, injured, bleeding, treated = partState(parts[name])
        local col = Theme.ramp(health)
        local damaged = health < 0.9
        local fillA = (withBase and health < 0.999 or damaged) and (0.14 + (1 - health) * 0.3) or 0
        local notable = injured or treated or damaged or self.hover == name or selected == name
        if withBase or notable then
        if withBase then D.fill(self, x, y, w, h, C.white, r, 0.045) end
        if fillA > 0 then D.fill(self, x, y, w, h, col, r, fillA / col.a) end
        local stroke, strokeA = C.white, withBase and 0.18 or 0
        if injured then
            stroke, strokeA = C.danger, bleeding and pulse or 0.9
        elseif treated then
            stroke, strokeA = C.ok, 0.8
        elseif damaged or (withBase and health < 0.999) then
            stroke, strokeA = col, 0.8
        end
        if self.hover == name then
            stroke, strokeA = dragging and C.accent or C.text, 1
            D.fill(self, x, y, w, h, C.white, r, 0.06)
        end
        D.stroke(self, x, y, w, h, stroke, r, strokeA)
        if selected == name then
            D.stroke(self, x - 2, y - 2, w + 4, h + 4, C.accent, r + 2)
        end
        if treated then
            D.rect(self, x + w - 5, y + 3, 3, 3, C.ok)
        end
        end
    end
end

function Body:render()
    if self.model then self:drawZones(false) end
    if not self.hover then return end
    local C = Theme.C
    local bp = bodyPartsByName(self.panel)[self.hover]
    if not bp then return end
    local name = BodyPartType.getDisplayName(bp:getType())
    local health = bp:getHealth()
    local label = string.format("%s  %d / 100", name, floor(health + 0.5))
    local fh = D.fontHeight(UIFont.Small)
    local tw = D.measure(UIFont.Small, label) + 16
    local mx, my = self:getMouseX(), self:getMouseY()
    local x = min(max(0, mx - tw / 2), self.width - tw)
    local y = max(0, my - fh - 18)
    D.panel(self, x, y, tw, fh + 8, C.panel2, C.outline2, Theme.R.md)
    D.text(self, label, x + 8, y + 4, C.text, UIFont.Small)
end

function Body:onMouseMove(dx, dy)
    self.hover = self:zoneAt(self:getMouseX(), self:getMouseY())
end

function Body:onMouseMoveOutside(dx, dy)
    self.hover = nil
end

function Body:selectInList(bp)
    local lb = self.panel.listbox
    if not lb then return end
    for i, item in ipairs(lb.items) do
        if item.item.bodyPart == bp then
            lb.selected = i
            return
        end
    end
end

function Body:onMouseUp(x, y)
    local name = self:zoneAt(x, y)
    if not name then return true end
    local bp = bodyPartsByName(self.panel)[name]
    if not bp then return true end
    if ISMouseDrag.dragging and #ISMouseDrag.dragging > 0 then
        local items = ISInventoryPane.getActualItems(ISMouseDrag.dragging)
        self.panel:dropItemsOnBodyPart(bp, items)
        return true
    end
    self:selectInList(bp)
    return true
end

function Body:onMouseDown(x, y)
    return true
end

function Body:onRightMouseUp(x, y)
    if UIManager.getSpeedControls() and UIManager.getSpeedControls():getCurrentGameSpeed() == 0 and not getDebug() then
        return true
    end
    local name = self:zoneAt(x, y)
    local bp = name and bodyPartsByName(self.panel)[name]
    if bp then
        self:selectInList(bp)
        self.panel:doBodyPartContextMenu(bp, self.x + x, self.y + y)
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Panel layout
-- ---------------------------------------------------------------------------

local function bodyWidth(panel)
    return max(130, min(210, floor(panel.width * 0.36)))
end

N26.after(ISHealthPanel, "ISHealthPanel", "createChildren", MODULE, function(self)
    -- only the player's own health view lives in the tactical screen; the
    -- medical-check window for other players stays vanilla
    if self.otherPlayer or (self.character and self.character ~= getSpecificPlayer(0)) then return end
    local bw = bodyWidth(self)
    -- the Java silhouette stays in the tree (vanilla code reads its status
    -- string) but is not displayed
    self.healthPanel:setVisible(false)
    self.n26Body = Body:new(self, PAD, PAD, bw, max(260, min(420, self.height - 80)))
    self.n26Body:initialise()
    self:addChild(self.n26Body)
    self.listbox:setX(PAD + bw + 14)
    self.listbox:setWidth(self.width - (PAD + bw + 14) - PAD)
    self.listbox.n26Cards = true
end)

-- Hide the vanilla drag-over overlay (the N26 body view handles drops itself).
N26.hook(ISHealthPanel, "ISHealthPanel", "prerender", MODULE, function(orig, self)
    if self.bodyPartPanel then
        self.bodyPartPanel:setVisible(false)
        self.bodyPartPanel:deselect()
    end
    ISPanelJoypad.prerender(self)
end)

local VITALS = {
    { key = "PAIN", icon = "pain", label = "UI_N26_Health_Pain", color = "warn" },
    { key = "WET", icon = "umb", label = "UI_N26_Health_Wet", color = "info" },
    { key = "ENDURANCE", icon = "run", label = "UI_N26_Health_Endurance", color = "ok" },
    { key = "HYPOTHERMIA", icon = "thermoDown", label = "UI_N26_Health_Cold", color = "info" },
    { key = "HYPERTHERMIA", icon = "thermoUp", label = "UI_N26_Health_Hot", color = "danger" },
}

local function moodleLevel(patient, key)
    local okType, mt = pcall(function() return MoodleType[key] end)
    if not okType or not mt then return 0 end
    local ok, lvl = pcall(function() return patient:getMoodles():getMoodleLevel(mt) end)
    return ok and lvl or 0
end

N26.hook(ISHealthPanel, "ISHealthPanel", "render", MODULE, function(orig, self)
    local C = Theme.C
    if self.otherPlayer then self.fitness:setVisible(false) end

    -- The vanilla tab is sized for a text list (~340px). The body view + status
    -- column need more room: grow the info window while this tab is shown
    -- (other tabs size it back, as vanilla does when switching).
    local fsc = D.fontScale()
    local minW, minH = floor(600 * fsc), floor(500 * fsc)
    -- docked in the tactical screen: fill the tab (see N26_Hub)
    if self.n26MinW then minW = max(minW, self.n26MinW) end
    if self.n26MinH then minH = max(minH, self.n26MinH) end
    if self.width < minW then self:setWidthAndParentWidth(minW) end
    if self.height < minH then self:setHeightAndParentHeight(minH) end

    local fh = D.fontHeight(UIFont.Small)
    -- the body view follows the panel height (the tactical screen makes it tall)
    local bh = max(220, min(820, self.height - fh * 2 - 60))
    local bw = max(bodyWidth(self), min(floor(self.width * 0.36), floor(bh * 0.5)))
    local body = self.n26Body
    local colX = PAD + bw + 14
    local colW = self.width - colX - PAD
    if body then
        body:setWidth(bw)
        body:setHeight(bh)
    end
    self.listbox:setX(colX)
    self.listbox:setWidth(colW)

    -- fitness button under the body view
    local by = body and (body:getBottom() + 10) or PAD
    self.fitness:setX(PAD)
    self.fitness:setY(by)
    self.fitness:setWidth(bw)

    -- status block
    local y = PAD
    local patient = self:getPatient()
    local bd = patientBodyDamage(self)
    local health = bd:getHealth() / 100
    D.caption(self, getText("IGUI_health_Overall_Body_Status"), colX, y)
    y = y + D.headingHeight("sm") + 4
    local status = self.healthPanel.javaObject:getDamageStatusString()
    local sc = Theme.ramp(health)
    D.text(self, status, colX, y, sc, UIFont.Medium, nil, colW - 90)
    D.number(self, string.format("%d", floor(health * 100 + 0.5)), colX + colW - 34, y - 4, C.text, 26, "right")
    D.text(self, "/100", colX + colW, y + 2, C.muted, UIFont.Small, "right")
    y = y + D.fontHeight(UIFont.Medium) + 4
    D.bar(self, colX, y, colW, 4, health, sc, C.hover2, 2)
    y = y + 12

    -- moodle-driven vitals (only information the moodles already show)
    local cols = colW >= 320 and 2 or 1
    local cellW = floor((colW - 8 * (cols - 1)) / cols)
    local i = 0
    for _, v in ipairs(VITALS) do
        local lvl = moodleLevel(patient, v.key)
        if lvl > 0 or v.key == "PAIN" or v.key == "ENDURANCE" then
            local cx = colX + (i % cols) * (cellW + 8)
            local cy = y + floor(i / cols) * (fh + 10)
            local col = C[v.color]
            D.icon(self, v.icon, cx, cy + floor((fh - 14) / 2), 14, lvl > 0 and col or C.dim)
            D.text(self, getText(v.label), cx + 20, cy, lvl > 0 and C.text2 or C.muted, UIFont.Small, nil, cellW - 70)
            D.pips(self, cx + cellW - 44, cy + floor(fh / 2) - 1, lvl, 4, col, false, 9, 3, 2)
            i = i + 1
        end
    end
    y = y + math.ceil(i / cols) * (fh + 10) + 4

    -- debug/cheat lines kept from vanilla
    local doctor = self.otherPlayer or self.character
    local painLevel = patient:getMoodles():getMoodleLevel(MoodleType.PAIN)
    if isClient() and not patient:isLocalPlayer() then
        painLevel = patient:getBodyDamageRemote():getRemotePainLevel()
    end
    if (ISHealthPanel.cheat or (doctor == self.otherPlayer and self.doctorLevel > 4)) and painLevel > 0 then
        D.text(self, getText("Moodles_Pain_lvl" .. painLevel), colX, y, C.warn, UIFont.Small)
        y = y + fh
    end
    if self.cheat and self.character:getStats():get(CharacterStat.ZOMBIE_FEVER) > 0 then
        D.text(self, "Zombie Fever " .. self.character:getStats():get(CharacterStat.ZOMBIE_FEVER), colX, y, C.danger, UIFont.Small)
        y = y + fh
    end
    if self.cheat and self.character:getReduceInfectionPower() > 0 then
        D.text(self, "Antibiotic level " .. self.character:getReduceInfectionPower(), colX, y, C.info, UIFont.Small)
        y = y + fh
    end

    D.caption(self, getText("UI_N26_Health_Injuries"), colX, y)
    if #self.listbox.items == 0 then
        D.text(self, getText("UI_N26_Health_NoInjury"), colX, y + D.headingHeight("sm") + 6, C.ok, UIFont.Small)
    end
    y = y + D.headingHeight("sm") + 4

    -- footer hint (vanilla text)
    local footer
    if doctor:getJoypadBind() ~= -1 then
        footer = getText("IGUI_health_JoypadTreatment")
        self:drawTextureScaled(self.abutton, PAD, self.height - PAD - fh, fh, fh, 1, 1, 1, 1)
        D.text(self, footer, PAD + fh + 4, self.height - PAD - fh, C.muted, UIFont.Small)
    else
        footer = getText("IGUI_health_RightClickTreatement")
        D.icon(self, "info", PAD, self.height - PAD - fh + floor((fh - 14) / 2), 14, C.muted)
        D.text(self, footer, PAD + 20, self.height - PAD - fh, C.muted, UIFont.Small)
    end

    -- list height: same screen-limited computation as vanilla
    local listItemsHeight = self.listbox:getScrollHeight()
    local myHeight = y + listItemsHeight + fh + PAD * 2
    local myY = self:getY()
    local parent = self.parent
    while parent and parent.parent do
        myY = myY + parent:getY()
        parent = parent.parent
    end
    local minBody = body and (body:getBottom() + 20 + self.fitness.height + fh + PAD * 2) or 0
    myHeight = max(myHeight, minBody)
    if myY + myHeight > getCore():getScreenHeight() then
        myHeight = getCore():getScreenHeight() - myY
    end
    self.listbox:setY(y)
    self.listbox:setHeight(max(20, myHeight - (fh + PAD * 2) - y))
    self.listbox.vscroll:setHeight(self.listbox:getHeight())
    self.allTextHeight = myHeight - (fh + PAD * 2)

    if self.blockingMessage then
        D.fill(self, 0, 0, self.width, self.height, C.black, Theme.R.md, 0.9 * self.blockingAlpha)
        D.heading(self, self.blockingMessage, self.width / 2, (self.height / 2) - 10, C.text, "md", "center", self.width - 20)
    end
end)

-- ---------------------------------------------------------------------------
-- Wound cards (vanilla doDrawItem under interception)
-- ---------------------------------------------------------------------------

local function near(a, b) return abs(a - b) < 0.02 end
local LINE_SHIFT = 10   -- wound lines sit below the per-card health bar

local function woundColor(r, g, b)
    local C = Theme.C
    if near(r, 0.89) and near(g, 0.28) then return C.danger end         -- wounds
    if near(r, 0.28) and near(g, 0.89) then return C.ok end             -- treatments
    if near(r, 1) and near(g, 0.58) then return C.warn end              -- minor stiffness
    if near(r, 1) and near(g, 0.28) and near(b, 0) then return C.warn end -- infected / dirty
    if near(r, 0.89) and near(g, 0.89) then return C.warn end
    return nil
end

local function cardDrawText(self, str, x, y, r, g, b, a, font)
    local C = Theme.C
    if type(str) ~= "string" then return ISUIElement.drawText(self, str, x, y, r, g, b, a, font) end
    local item = self.__n26item
    if x <= 0 and item then
        -- part name line: heading + health readout
        local bp = item.item.bodyPart
        local health = bp:getHealth() / 100
        local col = Theme.ramp(health)
        local w = self:getWidth()
        D.heading(self, str, 10, y + 4, C.text, "sm", nil, w - 90)
        D.text(self, string.format("%d / 100", floor(bp:getHealth() + 0.5)), w - 12, y + 3, col, UIFont.Small, "right")
        D.bar(self, 10, y + D.fontHeight(UIFont.Small) + 4, w - 22, 3, health, col, C.hover2, 1)
        return
    end
    local col = woundColor(r, g, b)
    local text = str
    if col and text:sub(1, 2) == "- " then
        text = text:sub(3)
        D.rect(self, x + 2, y + LINE_SHIFT + floor(D.fontHeight(font) / 2) - 1, 4, 4, col)
        return D.text(self, text, x + 12, y + LINE_SHIFT, col, font)
    end
    if near(r, 0.8) and near(g, 0.8) then
        return D.text(self, str, x, y + LINE_SHIFT, C.text, font)   -- action label over its bar
    end
    return D.text(self, str, x, y + LINE_SHIFT, col or C.text2, font)
end

local function cardDrawRect(self, x, y, w, h, a, r, g, b)
    local C = Theme.C
    if near(r, 1) and near(g, 1) and near(b, 1) then
        if near(a, 0.2) then   -- selected
            D.fill(self, x + 2, y + 2, w - 4, h - 4, C.accentSoft, Theme.R.md)
            return
        end
        if near(a, 0.05) then  -- hover
            D.fill(self, x + 2, y + 2, w - 4, h - 4, C.hover, Theme.R.md)
            return
        end
    end
    return ISUIElement.drawRect(self, x, y, w, h, a, r, g, b)
end

local function cardDrawRectBorder(self, x, y, w, h, a, r, g, b)
    D.stroke(self, x + 2, y + 2, w - 4, h - 4, Theme.C.accent, Theme.R.md)
end

local function cardProgress(self, x, y, w, h, f, fg)
    D.bar(self, x, y + LINE_SHIFT + floor(h / 2) - 1, w, 3, f, Theme.C.accent, Theme.C.hover2, 2)
end

local cardSpec = { fill = false, stroke = false, extra = {
    drawText = cardDrawText, drawRect = cardDrawRect, drawRectBorder = cardDrawRectBorder,
    drawProgressBar = cardProgress,
} }

N26.hook(ISHealthBodyPartListBox, "ISHealthBodyPartListBox", "doDrawItem", MODULE, function(orig, self, y, item, alt)
    local C = Theme.C
    if item.height and item.height > 8 then
        -- card surface sized from last frame's measured height
        D.fill(self, 2, y + 2, self:getWidth() - 4, item.height - 4, C.panel2, Theme.R.md)
        D.stroke(self, 2, y + 2, self:getWidth() - 4, item.height - 4, item.item.bodyPart:HasInjury() and C.accentLine or C.outline, Theme.R.md)
    end
    self.__n26item = item
    local y2 = Skin.intercept(self, cardSpec, orig, y, item, alt)
    self.__n26item = nil
    -- extra breathing room under each card (header line + bar are taller)
    return (y2 or y) + 14
end)

-- Keep the 3D character in sync with clothing changes (like the info tab avatar).
local bodies = setmetatable({}, { __mode = "k" })
N26.after(Body, "N26HealthBody", "createChildren", MODULE, function(self) bodies[self] = true end)
Events.OnClothingUpdated.Add(function()
    for b in pairs(bodies) do b.modelDirty = true end
end)
