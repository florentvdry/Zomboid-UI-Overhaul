--[[
    N26 crafting screen — the "Fabrication" tab of the tactical screen.

    The game's own handcraft window stays the engine: it owns the HandcraftLogic
    (recipes, containers, inputs, crafting queue) and runs hidden. This panel is
    the view: categories, recipe list, recipe sheet (requirements, products) and
    the craft controls, all drawn by N26. Crafting itself goes through the
    window's own craft control, so queueing, item transfer and returns are the
    vanilla ones.

    Hub.lua attaches the window (N26HubCraft:attach) and removes the panel again
    when the tab is left; nothing here runs while the tactical screen is closed.
]]

require "N26/Core/N26_Core"
require "N26/Core/N26_Theme"
require "N26/Core/N26_Draw"
require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"

local Theme = N26.Theme
local D = N26.Draw
local floor, max, min = math.floor, math.max, math.min

local PAD = 10

local function call(obj, name, ...)
    if obj == nil then return nil end
    local f = obj[name]
    if type(f) ~= "function" then return nil end
    local ok, r = pcall(f, obj, ...)
    if ok then return r end
    return nil
end

local function tex(name)
    return getTexture and getTexture(name) or nil
end

--- Count of a Java list (ArrayList) or 0.
local function size(list)
    return list and (call(list, "size") or 0) or 0
end

local function listGet(list, i)
    return list and call(list, "get", i) or nil
end

-- ---------------------------------------------------------------------------
-- Generic list (categories, recipes): vanilla scrolling list, N26 rows
-- ---------------------------------------------------------------------------

N26CraftList = ISScrollingListBox:derive("N26CraftList")

function N26CraftList:new(x, y, w, h, rowH, drawRow)
    local o = ISScrollingListBox:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.itemheight = rowH
    o.n26DrawRow = drawRow
    o.drawBorder = false
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.n26NoSkin = true
    return o
end

function N26CraftList:doDrawItem(y, item, alt)
    local h = self.itemheight
    item.height = h
    if y + self:getYScroll() + h < 0 or y + self:getYScroll() >= self.height then return y + h end
    local w = self:getWidth() - (self:isVScrollBarVisible() and 14 or 0)
    local over = self.mouseoverselected == item.index and self:isMouseOver() and not self:isMouseOverScrollBar()
    self.n26DrawRow(self, y, h, w, item, self.selected == item.index, over)
    return y + h
end

-- ---------------------------------------------------------------------------
-- Recipe state helpers (read from the game's logic)
-- ---------------------------------------------------------------------------

local function craftable(logic, player, recipe)
    if not recipe then return false end
    if player and call(player, "isBuildCheat") then return true end
    local info = call(logic, "getCachedRecipeInfo", recipe)
    if info then
        if call(info, "isValid") == false then return false end
        if call(info, "isCanPerform") == false then return false end
        return true
    end
    return call(logic, "cachedCanPerformCurrentRecipe") == true and call(logic, "getRecipe") == recipe
end

local function favKey(recipe)
    if BaseCraftingLogic and BaseCraftingLogic.getFavouriteModDataString then
        return BaseCraftingLogic.getFavouriteModDataString(recipe)
    end
    return nil
end

local function isFavourite(player, recipe)
    local k = recipe and favKey(recipe)
    if not k then return false end
    local md = call(player, "getModData")
    return md and md[k] == true or false
end

local function toggleFavourite(player, recipe)
    local k = recipe and favKey(recipe)
    if not k then return end
    local md = call(player, "getModData")
    if not md then return end
    md[k] = not (md[k] == true)
    call(player, "transmitModData")
end

local function skillText(skill)
    local perk = call(skill, "getPerk")
    return tostring(call(perk, "getName") or "?") .. " " .. tostring(call(skill, "getLevel") or 0)
end

local function hasSkill(skill, player)
    if CraftRecipeManager and CraftRecipeManager.hasPlayerRequiredSkill then
        local ok, r = pcall(CraftRecipeManager.hasPlayerRequiredSkill, skill, player)
        return ok and r == true
    end
    return true
end

--- Wrap text into lines that fit maxW (own wrapper: no dependency on the text manager).
local function wrap(font, s, maxW, maxLines)
    s = tostring(s or ""):gsub("<[Bb][Rr]>", "\n"):gsub("<[^>]*>", "")
    local lines = {}
    for para in (s .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in para:gmatch("%S+") do
            local try = line == "" and word or (line .. " " .. word)
            if line ~= "" and D.measure(font, try) > maxW then
                lines[#lines + 1] = line
                line = word
            else
                line = try
            end
        end
        lines[#lines + 1] = line
    end
    if maxLines and #lines > maxLines then
        while #lines > maxLines do lines[#lines] = nil end
        lines[maxLines] = D.fit(font, lines[maxLines] .. " ...", maxW)
    end
    return lines
end

local function formatTime(seconds)
    seconds = floor((seconds or 0) + 0.5)
    local m, s = floor(seconds / 60), seconds % 60
    if m > 0 then return string.format("%dm %02ds", m, s) end
    return string.format("%ds", s)
end

local function round2(v)
    return floor((v or 0) * 100 + 0.5) / 100
end

-- ---------------------------------------------------------------------------
-- Recipe sheet (right column)
-- ---------------------------------------------------------------------------

N26HubCraftSheet = ISPanel:derive("N26HubCraftSheet")
local Sheet = N26HubCraftSheet

function Sheet:new(x, y, w, h, craft)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.craft = craft
    o.hits = {}
    o.qty = 1
    o.n26NoSkin = true
    return o
end

--- One ingredient / tool card description for an input script.
local function describeInput(logic, script)
    local d = { name = "?", need = 1, have = 0, ok = true }
    d.keep = call(script, "isKeep") == true
    d.tool = call(script, "isTool") == true
    local rt = call(script, "getResourceType")
    d.ok = call(logic, "isInputSatisfied", script) ~= false
    if rt == ResourceType.Item then
        local list = call(logic, "getSatisfiedInputItems", script)
        local n = size(list)
        if n == 0 then list = call(script, "getPossibleInputItems"); n = size(list) end
        local item = listGet(list, 0)
        if item then
            d.name = call(item, "getDisplayName") or d.name
            d.icon = call(item, "getNormalTexture")
            d.more = n > 1 and (n - 1) or nil
        end
        d.need = call(script, "getIntMaxAmount") or 1
        d.have = call(logic, "getInputCount", script) or 0
    elseif rt == ResourceType.Fluid then
        local list = call(logic, "getSatisfiedInputFluids", script)
        if size(list) == 0 then list = call(script, "getPossibleInputFluids") end
        local fluid = listGet(list, 0)
        d.name = call(script, "getInputFluidFilterDisplayName") or (fluid and call(fluid, "getDisplayName")) or d.name
        d.icon = tex("media/textures/Item_Waterdrop_Grey.png")
        d.need = call(script, "getAmount") or 0
        d.have = call(logic, "getInputUses", script) or 0
        d.fluid = true
    else
        local list = call(logic, "getSatisfiedInputItems", script)
        local e = listGet(call(script, "getPossibleInputItems") or list, 0)
        d.name = e and (call(e, "getDisplayName") or call(e, "getEnergyTypeString")) or d.name
        d.energy = true
    end
    return d
end

local function describeOutput(logic, script)
    local d = { name = "?", amount = "" }
    local rt = call(script, "getResourceType")
    if rt == ResourceType.Item then
        local list = call(script, "getPossibleResultItems")
        local item = listGet(list, 0)
        if item then
            d.name = call(item, "getDisplayName") or d.name
            d.icon = call(item, "getNormalTexture")
            d.more = size(list) > 1 and (size(list) - 1) or nil
        end
        local amount = call(script, "getIntAmount") or 1
        local maxAmount = call(script, "getIntMaxAmount") or amount
        if call(script, "isVariableAmount") then
            local ratio = call(logic, "getVariableInputRatio") or 1
            amount = min(amount * ratio, maxAmount)
        end
        d.amount = "x" .. tostring(round2(amount))
    elseif rt == ResourceType.Fluid then
        d.name = getText and getText("IGUI_CraftingWindow_Creates") or "?"
        d.icon = tex("media/textures/Item_Waterdrop_Grey.png")
        d.amount = tostring(round2(call(script, "getAmount") or 0)) .. "L"
    else
        local list = call(script, "getPossibleResultItems")
        local e = listGet(list, 0)
        d.name = e and call(e, "getDisplayName") or d.name
        d.amount = ""
    end
    return d
end

--- Rebuild everything that only changes with the recipe or the inventory.
function Sheet:rebuild(logic, recipe, player)
    local data = { recipe = recipe, inputs = {}, outputs = {}, skills = {} }
    if recipe then
        local keeps, rest = {}, {}
        local inputs = call(recipe, "getInputs")
        for i = 0, size(inputs) - 1 do
            local s = listGet(inputs, i)
            if s and not call(s, "isAutomationOnly") then
                local d = describeInput(logic, s)
                if d.keep or d.tool then keeps[#keeps + 1] = d else rest[#rest + 1] = d end
            end
        end
        for _, d in ipairs(keeps) do data.inputs[#data.inputs + 1] = d end
        for _, d in ipairs(rest) do data.inputs[#data.inputs + 1] = d end
        local outputs = call(recipe, "getOutputs")
        for i = 0, size(outputs) - 1 do
            local s = listGet(outputs, i)
            if s and not call(s, "isAutomationOnly") then data.outputs[#data.outputs + 1] = describeOutput(logic, s) end
        end
        for i = 0, (call(recipe, "getRequiredSkillCount") or 0) - 1 do
            local s = call(recipe, "getRequiredSkill", i)
            if s then data.skills[#data.skills + 1] = { text = skillText(s), ok = hasSkill(s, player) } end
        end
        data.time = call(recipe, "getTime", player)
        data.canBatch = call(recipe, "isAllowBatchCraft") == true and not self.craft.isBuild
    end
    self.data = data
end

--- Why the recipe cannot be started right now (nil when it can).
local function problems(logic, recipe, player)
    local errs = {}
    if not recipe then return nil end
    if call(logic, "areAllInputItemsSatisfied") == false then
        errs[#errs + 1] = getText("IGUI_CraftingWindow_Error_Inputs")
    end
    if call(recipe, "isCanWalk") == false and call(player, "isPlayerMoving") then
        errs[#errs + 1] = getText("IGUI_CraftingWindow_Error_Moving")
    end
    if call(recipe, "needToBeLearn") and not call(player, "isRecipeKnown", recipe, true) then
        errs[#errs + 1] = getText("IGUI_CraftingWindow_Error_NotLearn")
    end
    if call(recipe, "canBeDoneInDark") == false and call(player, "tooDarkToRead") then
        errs[#errs + 1] = getText("IGUI_CraftingWindow_Error_TooDark")
    end
    if call(recipe, "isInHandCraftCraft") == false and call(logic, "isCharacterInRangeOfWorkbench") == false then
        errs[#errs + 1] = getText("IGUI_CraftingWindow_Error_Workbench")
    end
    if #errs == 0 then return nil end
    return table.concat(errs, ", ")
end

local function drawCard(ui, x, y, w, h, d, kind)
    local C = Theme.C
    local fs = D.fontScale()
    local border = C.outline2
    local ok = d.ok ~= false
    if kind == "in" then
        if not ok then
            border = C.danger
        elseif d.have and d.need and d.have > 0 and d.have < d.need then
            border = C.warn
        end
    end
    D.fill(ui, x, y, w, h, C.field, Theme.R.md)
    D.stroke(ui, x, y, w, h, border, Theme.R.md)
    local isz = floor(h - 14)
    D.fill(ui, x + 7, y + 7, isz, isz, C.cell, Theme.R.sm)
    if d.icon then
        local a = (kind == "in" and not ok) and 0.45 or 1
        ui:drawTextureScaledAspect(d.icon, x + 9, y + 9, isz - 4, isz - 4, a, 1, 1, 1)
    end
    local tx = x + 7 + isz + 8
    local fh = D.fontHeight(UIFont.Small)
    local name = d.name .. (d.more and (" +" .. d.more) or "")
    local col = (kind == "in" and not ok) and C.dangerTxt or C.text
    D.text(ui, name, tx, y + 7, col, UIFont.Small, nil, w - (tx - x) - 8)
    local sub, subCol
    if kind == "in" then
        if d.energy then
            sub = ""
        elseif d.fluid then
            sub = tostring(round2(d.have)) .. "/" .. tostring(round2(d.need)) .. "L"
        else
            sub = tostring(d.have) .. "/" .. tostring(d.need)
        end
        subCol = ok and C.ok or ((d.have or 0) > 0 and C.warn or C.dangerTxt)
        if d.tool then
            local tag = getText("UI_N26_Craft_Tool")
            D.text(ui, tag, x + w - 8, y + h - 7 - fh, C.info, UIFont.Small, "right")
        elseif d.keep then
            local tag = getText("UI_N26_Craft_Kept")
            D.text(ui, tag, x + w - 8, y + h - 7 - fh, C.muted, UIFont.Small, "right")
        end
    else
        sub = d.amount
        subCol = C.accent
    end
    if sub ~= "" then D.text(ui, sub, tx, y + h - 7 - fh, subCol, UIFont.Small) end
end

function Sheet:addHit(x, y, w, h, fn)
    self.hits[#self.hits + 1] = { x = x, y = y, w = w, h = h, fn = fn }
end

function Sheet:prerender()
    local craft = self.craft
    local logic, recipe, player = craft:logic(), craft:recipe(), craft.player
    -- cached description: refresh on recipe change and every few frames
    self.frame = (self.frame or 0) + 1
    if not self.data or self.data.recipe ~= recipe or self.frame % 12 == 0 then
        self:rebuild(logic, recipe, player)
    end
    self.hits = {}
    local C = Theme.C
    local fs = D.fontScale()
    local W, H = self.width, self.height
    D.fill(self, 0, 0, W, H, C.panel2, Theme.R.lg)
    D.stroke(self, 0, 0, W, H, C.outline, Theme.R.lg)

    local fh = D.fontHeight(UIFont.Small)
    local data = self.data
    if not recipe then
        D.text(self, getText("IGUI_CraftingWindow_NoRecipes"), W / 2, H / 2 - fh / 2, C.muted, UIFont.Small, "center")
        return
    end

    local pad = floor(16 * fs)
    local x, y = pad, pad
    local inner = W - 2 * pad

    -- header: icon, title, favourite
    local isz = floor(64 * fs)
    D.fill(self, x, y, isz, isz, C.field, Theme.R.md)
    D.stroke(self, x, y, isz, isz, C.outline2, Theme.R.md)
    local icon = call(recipe, "getIconTexture")
    if icon then self:drawTextureScaledAspect(icon, x + 4, y + 4, isz - 8, isz - 8, 1, 1, 1, 1) end
    local tx = x + isz + 14
    local star = floor(24 * fs)
    local title = call(recipe, "getTranslationName") or "?"
    D.heading(self, title, tx, y, C.text, "lg", nil, W - tx - pad - star - 8)
    local fav = isFavourite(player, recipe)
    local starTex = tex(fav and "media/ui/inventoryPanes/FavouriteYes.png" or "media/ui/inventoryPanes/FavouriteNo.png")
    local sx = W - pad - star
    if starTex then
        local c = fav and C.warn or C.muted
        self:drawTextureScaledAspect(starTex, sx, y, star, star, 1, c.r, c.g, c.b)
    end
    self:addHit(sx - 4, y - 4, star + 8, star + 8, function()
        toggleFavourite(player, recipe)
        if craft.category == "*" then craft:onCategory("*") end
        craft.dirty = true
    end)

    local err = problems(logic, recipe, player)
    local statusY = y + D.headingHeight("lg") + 6
    if err then
        D.text(self, getText("IGUI_CraftingWindow_Error_NotAvailable") .. err, tx, statusY, C.dangerTxt, UIFont.Small, nil, W - tx - pad)
    else
        D.text(self, getText("UI_N26_Craft_Ready"), tx, statusY, C.ok, UIFont.Small)
    end
    -- skills chips
    local cx = tx
    local chipY = statusY + fh + 8
    for _, s in ipairs(data.skills) do
        local w = D.measure(UIFont.Small, s.text) + 16
        D.fill(self, cx, chipY, w, fh + 6, s.ok and C.accentSoft or Theme.copy(C.danger, 0.18), Theme.R.md)
        D.text(self, s.text, cx + 8, chipY + 3, s.ok and C.text or C.dangerTxt, UIFont.Small)
        cx = cx + w + 6
    end
    y = y + max(isz, (chipY + fh + 6) - y) + 14

    -- description
    local tip = call(recipe, "getTooltip")
    if tip then
        local lines = wrap(UIFont.Small, getText(tip), inner, 3)
        for _, l in ipairs(lines) do
            D.text(self, l, x, y, C.muted, UIFont.Small)
            y = y + fh + 2
        end
        y = y + 8
    end
    D.hline(self, x, y, inner, C.divider)
    y = y + 12

    -- reserve the control bar at the bottom
    local barH = floor(96 * fs)
    local bodyBottom = H - pad - barH - 12
    local bodyTop = y
    self.bodyTop, self.bodyBottom = bodyTop, bodyBottom
    y = y - (self.contentScroll or 0)
    self:setStencilRect(pad, bodyTop, inner, max(1, bodyBottom - bodyTop))

    -- grids of cards
    local cardH = floor(52 * fs)
    local cols = 1
    local cardW = floor((inner - (cols - 1) * 8) / cols)

    local function section(label, items, kind)
        if #items == 0 then return end
        D.caption(self, label, x, y, C.muted)
        y = y + fh + 8
        for i, d in ipairs(items) do
            local col, row = (i - 1) % cols, floor((i - 1) / cols)
            local cy = y + row * (cardH + 8)
            if cy + cardH <= bodyBottom then
                drawCard(self, x + col * (cardW + 8), cy, cardW, cardH, d, kind)
            end
        end
        y = y + math.ceil(#items / cols) * (cardH + 8) + 6
    end
    section(getText("IGUI_CraftingWindow_Requires"), data.inputs, "in")
    section(getText("IGUI_CraftingWindow_Creates"), data.outputs, "out")
    self.scrollMax = max(0, y + (self.contentScroll or 0) - bodyBottom)
    self.contentScroll = min(self.contentScroll or 0, self.scrollMax)
    self:clearStencilRect()

    -- control bar
    local by = H - pad - barH
    D.fill(self, pad, by, inner, barH, C.field, Theme.R.lg)
    D.stroke(self, pad, by, inner, barH, C.outline, Theme.R.lg)
    local bx, bpad = pad + 14, 12
    local rowH = floor(30 * fs)
    local row1 = by + bpad
    local inProgress = call(logic, "isCraftActionInProgress") == true
    local maxQty = max(1, call(logic, "getPossibleCraftCount", false) or 1)
    if data.canBatch then
        self.qty = max(1, min(self.qty, maxQty))
        D.text(self, getText("IGUI_CraftingWindow_Quantity"), bx, row1 + floor((rowH - fh) / 2), C.muted, UIFont.Small)
        local qx = bx + D.measure(UIFont.Small, getText("IGUI_CraftingWindow_Quantity")) + 12
        local function btn(label, x0, w, fn)
            local over = self:getMouseX() >= x0 and self:getMouseX() < x0 + w and self:getMouseY() >= row1 and self:getMouseY() < row1 + rowH
            D.fill(self, x0, row1, w, rowH, over and C.hover2 or C.panel3, Theme.R.md)
            D.stroke(self, x0, row1, w, rowH, C.outline2, Theme.R.md)
            D.text(self, label, x0 + w / 2, row1 + floor((rowH - fh) / 2), C.text, UIFont.Small, "center")
            self:addHit(x0, row1, w, rowH, fn)
        end
        btn("-", qx, rowH, function() self.qty = max(1, self.qty - 1) end)
        local nw = max(rowH + 8, D.measure(UIFont.Small, "000") + 16)
        D.text(self, tostring(self.qty), qx + rowH + 4 + nw / 2, row1 + floor((rowH - fh) / 2), C.text, UIFont.Small, "center")
        local px = qx + rowH + 8 + nw
        btn("+", px, rowH, function() self.qty = min(maxQty, self.qty + 1) end)
        local mw = D.measure(UIFont.Small, getText("UI_N26_Craft_Max")) + 20
        btn(getText("UI_N26_Craft_Max"), px + rowH + 6, mw, function() self.qty = maxQty end)
    end
    local timeStr = getText("IGUI_CraftingWindow_TimeRequired") .. " " .. formatTime(data.time)
    D.text(self, timeStr, pad + inner - 14, row1 + floor((rowH - fh) / 2), C.text2, UIFont.Small, "right")

    -- craft button / progress
    local row2 = row1 + rowH + 10
    local bw = inner - 28
    local can = (not inProgress) and call(logic, "cachedCanPerformCurrentRecipe") == true
    local over = can and self:getMouseX() >= bx and self:getMouseX() < bx + bw and self:getMouseY() >= row2 and self:getMouseY() < row2 + rowH
    if inProgress then
        local action = call(logic, "getCraftActionTable")
        local frac = action and call(action, "getJobDelta") or 0
        D.fill(self, bx, row2, bw, rowH, C.panel3, Theme.R.md)
        D.fill(self, bx, row2, max(2, floor(bw * frac)), rowH, C.accentLine, Theme.R.md)
        D.text(self, floor(frac * 100) .. "%", bx + bw / 2, row2 + floor((rowH - fh) / 2), C.text, UIFont.Small, "center")
    else
        local bg = can and (over and C.accentLine or C.accent) or C.panel3
        D.fill(self, bx, row2, bw, rowH, bg, Theme.R.md)
        local label = getText(craft.isBuild and "UI_N26_Craft_Place" or "IGUI_CraftingWindow_Craft")
        if data.canBatch and self.qty > 1 then label = label .. "  x" .. self.qty end
        D.heading(self, label, bx + bw / 2, row2 + floor((rowH - D.headingHeight("sm")) / 2), can and C.onAccent or C.dim, "sm", "center")
        if can then self:addHit(bx, row2, bw, rowH, function() craft:startCraft(self.qty) end) end
    end
end

function Sheet:onMouseWheel(del)
    self.contentScroll = max(0, min(self.scrollMax or 0, (self.contentScroll or 0) + del * 40))
    return true
end

function Sheet:onMouseDown(x, y)
    for i = #self.hits, 1, -1 do
        local h = self.hits[i]
        if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then
            getSoundManager():playUISound("UISelectListItem")
            h.fn()
            return true
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Craft panel
-- ---------------------------------------------------------------------------

N26HubCraft = ISPanel:derive("N26HubCraft")
local Craft = N26HubCraft

local FILTER_MODES = {
    { nil, "IGUI_FilterType_RecipeName" },
    { "InputName", "IGUI_FilterType_InputName" },
    { "OutputName", "IGUI_FilterType_OutputName" },
}
local SORT_MODES = {
    { "RecipeName", "IGUI_SortType_RecipeName" },
    { "LastUsed", "IGUI_SortType_LastUsed" },
    { "MostUsed", "IGUI_SortType_MostUsed" },
}

function Craft:new(x, y, w, h, player)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.player = player
    o.filterIdx = 1
    o.sortIdx = 1
    o.category = ""
    o.collapsed = {}
    o.n26NoSkin = true
    return o
end

function Craft:createChildren()
    local fs = D.fontScale()
    local fh = D.fontHeight(UIFont.Small)

    self.cats = N26CraftList:new(0, 0, 100, 100, fh + 16, function(list, y, h, w, item, selected, over)
        local C = Theme.C
        if selected then
            D.fill(list, 6, y + 2, w - 12, h - 4, C.accent, Theme.R.md)
        elseif over then
            D.fill(list, 6, y + 2, w - 12, h - 4, C.hover2, Theme.R.md)
        end
        local col = selected and C.onAccent or (over and C.text or C.text2)
        D.text(list, item.text, 16, y + floor((h - fh) / 2), col, UIFont.Small, nil, w - 28)
    end)
    self.cats:initialise()
    self.cats:instantiate()
    self.cats:setOnMouseDownFunction(self, self.onCategory)
    self:addChild(self.cats)

    local rowH = max(floor(56 * fs), fh * 2 + 18)
    self.list = N26CraftList:new(0, 0, 100, 100, rowH, function(list, y, h, w, item, selected, over)
        self:drawRecipeRow(list, y, h, w, item, selected, over)
    end)
    self.list:initialise()
    self.list:instantiate()
    self.list:setOnMouseDownFunction(self, self.onRecipeClick)
    self:addChild(self.list)

    self.search = ISTextEntryBox:new("", 0, 0, 100, fh + 10)
    self.search:initialise()
    self.search:instantiate()
    self.search.target = self
    self.search.onTextChangeFunction = function(target) target:onSearch() end
    self.search:setClearButton(true)
    self.search:setPlaceholderText(getText("IGUI_CraftingWindow_SearchRecipes"))
    self:addChild(self.search)

    self.sheet = N26HubCraftSheet:new(0, 0, 100, 100, self)
    self.sheet:initialise()
    self:addChild(self.sheet)
end

-- ---- engine access -------------------------------------------------------

function Craft:panel() return self.win and (self.win.handCraftPanel or self.win.BuildPanel) or nil end
function Craft:logic() local p = self:panel(); return p and p.logic or nil end
function Craft:recipe() local l = self:logic(); return l and call(l, "getRecipe") or nil end

--- Hand the panel the (hidden) vanilla handcraft window that runs the logic.
function Craft:attach(win)
    if self.win == win then return end
    self.win = win
    local hp = self:panel()
    if not hp then return end
    -- automatic ingredient choice; the list panel (not the tile grid) feeds the rows
    call(hp.logic, "setManualSelectInputs", false)
    call(hp.logic, "setLastManualInputMode", false)
    if hp.setRecipeListMode then hp:setRecipeListMode(true) end
    call(hp.logic, "autoPopulateInputs")
    self.srcItems = nil
    self.catSig = nil
    self.isBuild = win.BuildPanel ~= nil
    self.filterIdx, self.sortIdx, self.category = 1, 1, ""
    self.showAll = hp.seeAllRecipe == true
    self.search:setText("")
    self.sheet.data = nil
    self.sheet.contentScroll = 0
    self.sheet.qty = 1
end

function Craft:detach()
    self.win = nil
end

--- Called every frame by the hub while this tab is shown: the window is hidden,
--- so the updates the game would run on a visible window run from here.
function Craft:tick()
    local win = self.win
    if not win or win.hasClosedWindowInstance then return end
    local hp = self:panel()
    if not hp then return end
    if not N26.try("craft window update", win.update, win) then return end
    if win.hasClosedWindowInstance then return end
    N26.try("craft engine update", hp.update, hp)
    local now = getTimestampMs()
    if not self.nextRefresh or now >= self.nextRefresh then
        if not call(hp.logic, "isCraftActionInProgress") then call(hp, "updateContainers") end
        if self.onlyCraftable then self.dirty = true end
        self.nextRefresh = now + 500
    end
    self:syncCategories()
    self:syncRecipes()
end

-- ---- data sync -----------------------------------------------------------

function Craft:syncCategories()
    local hp = self:panel()
    local cats = call(hp.logic, "getCategoryList")
    local sig = tostring(size(cats))
    for i = 0, size(cats) - 1 do sig = sig .. "|" .. tostring(listGet(cats, i)) end
    if sig == self.catSig then return end
    self.catSig = sig
    local list = self.cats
    list:clear()
    list:addItem(getText("IGUI_CraftingCategories_All"), "")
    list:addItem(getText("IGUI_CraftingCategories_Favourites"), "*")
    local selected = (self.category == "" and 1) or (self.category == "*" and 2) or nil
    for i = 0, size(cats) - 1 do
        local c = tostring(listGet(cats, i))
        local label = getText("IGUI_CraftingCategories_" .. c:sub(1, 1):upper() .. c:sub(2))
        local it = list:addItem(label, c)
        if c == self.category then selected = it.itemindex end
    end
    if not selected then
        self.category = ""
        selected = 1
        hp.recipeCategories = hp.recipeCategories
    end
    list.selected = selected
end

function Craft:syncRecipes()
    local hp = self:panel()
    local src = hp.recipesPanel and hp.recipesPanel.recipeListPanel and hp.recipesPanel.recipeListPanel.recipeListPanel
    if not src or not src.items then return end
    local items = src.items
    local n = #items
    if self:recipe() ~= self.listDirtyRecipe then self.dirty = true end
    local sig = n > 0 and (tostring(items[1].text) .. "|" .. tostring(items[n].text)) or ""
    if items == self.srcItems and n == self.srcCount and sig == self.srcSig and not self.dirty then return end
    self.srcItems, self.srcCount, self.srcSig, self.dirty = items, n, sig, false
    self:fillList(items)
end

function Craft:fillList(items)
    local list = self.list
    local keepRecipe = self:recipe()
    list:clear()
    local group
    for _, it in ipairs(items) do
        if it.groupNode then
            group = it
            local row = list:addItem(it.text or "", nil)
            row.groupNode = it.groupNode
            row.title = it.text or ""
        elseif it.item and (not self.onlyCraftable or craftable(self:logic(), self.player, it.item)) then
            local inGroup = it.node and call(it.node, "getParent") ~= nil
            if not (inGroup and group and self.collapsed[group.text or ""]) then
                local row = list:addItem(it.text or "", it.item)
                row.inGroup = inGroup
            end
        end
    end
    -- selection follows the logic's recipe
    list.selected = 0
    for i, row in ipairs(list.items) do
        if row.item and row.item == keepRecipe then list.selected = i break end
    end
    self.listDirtyRecipe = keepRecipe
end

function Craft:onCategory(cat)
    local hp = self:panel()
    if not hp then return end
    self.category = cat or ""
    if hp.recipeCategories and hp.recipeCategories.onCategoryChanged then
        hp.recipeCategories:onCategoryChanged(self.category)
    else
        hp:onCategoryChanged(self.category)
    end
    self.dirty = true
end

function Craft:onRecipeClick(recipe)
    local hp = self:panel()
    if not hp then return end
    if recipe then
        call(hp.logic, "setRecipe", recipe)
        self.sheet.qty = 1
        self.sheet.contentScroll = 0
        return
    end
    -- group header: collapse / expand
    local row = self.list.items[self.list.selected]
    if row and row.title then
        self.collapsed[row.title] = not self.collapsed[row.title]
        self.dirty = true
    end
end

function Craft:onSearch()
    local hp = self:panel()
    if not hp then return end
    local mode = FILTER_MODES[self.filterIdx][1]
    hp:setRecipeFilter(self.search:getInternalText(), mode)
    self.dirty = true
end

function Craft:cycleFilter()
    self.filterIdx = self.filterIdx % #FILTER_MODES + 1
    self:onSearch()
end

function Craft:cycleSort()
    local hp = self:panel()
    if not hp then return end
    self.sortIdx = self.sortIdx % #SORT_MODES + 1
    hp:setSortMode(SORT_MODES[self.sortIdx][1])
    self.dirty = true
end

function Craft:toggleAll()
    local hp = self:panel()
    if not hp then return end
    self.showAll = not self.showAll
    if hp.recipesPanel and hp.recipesPanel.OnFilterAll then hp.recipesPanel:OnFilterAll(self.showAll) end
    if hp.setSeeAllRecipe then hp:setSeeAllRecipe(self.showAll) end
    self.dirty = true
end

function Craft:startCraft(qty)
    local hp = self:panel()
    if not hp or call(hp.logic, "cachedCanPerformCurrentRecipe") ~= true then return end
    if self.isBuild then
        -- Placement must outlive closing the menu: closing ISBuildWindow clears
        -- the drag cursor, so close first and then let the same logic create it.
        local panel = hp
        if N26.Hub then N26.Hub.close() end
        panel:createBuildIsoEntity()
        panel:updateManualInputs()
        call(panel.logic, "updateManualInputAllowedItemTypes")
        return
    end
    local rp = hp.recipePanel or hp.craftRecipePanel
    local cc = rp and rp.craftControl
    if not cc then return end
    if cc.setCraftQuantity then cc:setCraftQuantity(qty or 1) end
    cc.allowBatchCraft = call(self:recipe(), "isAllowBatchCraft") == true
    cc.craftTimes = nil
    cc:startHandcraft(false)
end

-- ---- drawing ---------------------------------------------------------------

function Craft:drawRecipeRow(list, y, h, w, item, selected, over)
    local C = Theme.C
    local fs = D.fontScale()
    local fh = D.fontHeight(UIFont.Small)
    local hp = self:panel()
    if item.groupNode then
        local open = not self.collapsed[item.title or ""]
        D.text(list, (open and "- " or "+ ") .. string.upper(item.title or ""), 12, y + floor((h - fh) / 2), C.muted, UIFont.Small, nil, w - 24)
        D.hline(list, 10, y + h - 1, w - 20, C.divider)
        return
    end
    local recipe = item.item
    if not recipe then return end
    local can = craftable(hp.logic, self.player, recipe)
    local x0 = item.inGroup and floor(18 * fs) or 0
    if selected then
        D.fill(list, 6 + x0, y + 2, w - 12 - x0, h - 4, C.accentSoft, Theme.R.md)
        D.rect(list, 6 + x0, y + 8, 3, h - 16, C.accent)
    elseif over then
        D.fill(list, 6 + x0, y + 2, w - 12 - x0, h - 4, C.hover2, Theme.R.md)
    end
    local isz = floor(h - 18)
    local icon = call(recipe, "getIconTexture")
    local a = can and 1 or 0.45
    if icon then list:drawTextureScaledAspect(icon, 16 + x0, y + 9, isz, isz, a, 1, 1, 1) end
    local tx = 16 + x0 + isz + 10
    local maxW = w - tx - 34
    D.text(list, call(recipe, "getTranslationName") or "?", tx, y + 8, can and C.text or C.dim, UIFont.Small, nil, maxW)
    -- second line: first missing skill, else the first ingredient
    local line, col = nil, C.muted
    for i = 0, (call(recipe, "getRequiredSkillCount") or 0) - 1 do
        local s = call(recipe, "getRequiredSkill", i)
        if s then
            line = skillText(s)
            col = hasSkill(s, self.player) and C.muted or C.dangerTxt
            if col == C.dangerTxt then break end
        end
    end
    if not line then
        local tip = call(recipe, "getTooltip")
        if tip then line = (getText(tip):gsub("<[^>]*>", " "):gsub("%s+", " ")) end
    end
    if line then D.text(list, line, tx, y + 8 + fh + 2, col, UIFont.Small, nil, maxW) end
    -- favourite / state marks
    if isFavourite(self.player, recipe) then
        local st = tex("media/ui/inventoryPanes/FavouriteYes.png")
        if st then list:drawTextureScaledAspect(st, w - 30, y + 8, 14, 14, 1, C.warn.r, C.warn.g, C.warn.b) end
    end
    if can then D.fill(list, w - 26, y + h - 18, 8, 8, C.ok, 4) end
end

function Craft:layout()
    local fs = D.fontScale()
    local W, H = self.width, self.height
    local catW = max(floor(160 * fs), min(floor(210 * fs), floor(W * 0.14)))
    local listW = floor(W * 0.50)
    local sheetW = W - catW - listW - 2 * PAD
    local fh = D.fontHeight(UIFont.Small)
    local topH = fh + 10 + 8

    self.catRect = { x = 0, y = 0, w = catW, h = H }
    self.listRect = { x = catW + PAD, y = 0, w = listW, h = H }
    self.cats:setX(2); self.cats:setY(10)
    self.cats:setWidth(catW - 4); self.cats:setHeight(H - 20)
    if self.cats.vscroll then
        self.cats.vscroll:setX(self.cats.width - self.cats.vscroll.width)
        self.cats.vscroll:setHeight(self.cats.height)
    end

    local lx = self.listRect.x
    local rowsTop = topH + 2 * (fh + 12) + 6
    self.rowsTop = rowsTop
    self.search:setX(lx + 10); self.search:setY(10)
    self.search:setWidth(listW - 20); self.search:setHeight(fh + 10)
    self.list:setX(lx + 2); self.list:setY(rowsTop)
    self.list:setWidth(listW - 4); self.list:setHeight(H - rowsTop - 8)
    if self.list.vscroll then
        self.list.vscroll:setX(self.list.width - self.list.vscroll.width)
        self.list.vscroll:setHeight(self.list.height)
    end
    self.sheet:setX(catW + listW + 2 * PAD); self.sheet:setY(0)
    self.sheet:setWidth(sheetW); self.sheet:setHeight(H)
    if self.sheet.vscroll then self.sheet.vscroll:setVisible(false) end
end

function Craft:prerender()
    if not self.win then return end
    self:tick()
    self:layout()
    local C = Theme.C
    local fh = D.fontHeight(UIFont.Small)
    local c, l = self.catRect, self.listRect
    D.fill(self, c.x, c.y, c.w, c.h, C.panel2, Theme.R.lg)
    D.stroke(self, c.x, c.y, c.w, c.h, C.outline, Theme.R.lg)
    D.fill(self, l.x, l.y, l.w, l.h, C.panel2, Theme.R.lg)
    D.stroke(self, l.x, l.y, l.w, l.h, C.outline, Theme.R.lg)

    -- filter / sort / all toggles under the search field
    local y = 10 + fh + 10 + 8
    local x = l.x + 10
    self.chipHits = {}
    local function chip(label, active, fn)
        local w = D.measure(UIFont.Small, label) + 18
        local over = self:getMouseX() >= x and self:getMouseX() < x + w and self:getMouseY() >= y and self:getMouseY() < y + fh + 8
        D.fill(self, x, y, w, fh + 8, active and C.accentSoft or (over and C.hover2 or C.cell), Theme.R.md)
        D.stroke(self, x, y, w, fh + 8, active and C.accentLine or C.outline, Theme.R.md)
        D.text(self, label, x + 9, y + 4, active and C.text or C.text2, UIFont.Small)
        self.chipHits[#self.chipHits + 1] = { x = x, y = y, w = w, h = fh + 8, fn = fn }
        x = x + w + 6
    end
    chip(getText(FILTER_MODES[self.filterIdx][2]), self.filterIdx > 1, function() self:cycleFilter() end)
    chip(getText(SORT_MODES[self.sortIdx][2]), self.sortIdx > 1, function() self:cycleSort() end)
    chip(getText("IGUI_CraftingUI_ShowAllRecipe"), self.showAll == true, function() self:toggleAll() end)
    chip(getText("UI_N26_Craft_OnlyReady"), self.onlyCraftable == true, function()
        self.onlyCraftable = not self.onlyCraftable
        self.dirty = true
    end)
    D.hline(self, l.x + 10, self.rowsTop - 8, l.w - 20, C.divider)
end

function Craft:render()
    if not self.win then return end
    local C = Theme.C
    if #self.list.items == 0 then
        D.text(self, getText("IGUI_CraftingWindow_NoRecipes"), self.listRect.x + self.listRect.w / 2,
            self.rowsTop + 24, C.muted, UIFont.Small, "center")
    end
end

function Craft:onMouseDown(x, y)
    for _, h in ipairs(self.chipHits or {}) do
        if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then
            getSoundManager():playUISound("UISelectListItem")
            h.fn()
            return true
        end
    end
    return true
end
