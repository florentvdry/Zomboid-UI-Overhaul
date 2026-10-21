-- Custom character skill board. Perks and XP come from the live survivor;
-- no character-info window is displayed by this page.
require "ISUI/ISPanel"
require "N26/Core/N26_Draw"

local D, Theme = N26.Draw, N26.Theme
local floor, max, min = math.floor, math.max, math.min
local function call(o, k, ...)
    if not o or not o[k] then return nil end
    local ok, v = pcall(o[k], o, ...)
    if ok then return v end
end
local function plain(s) return tostring(s or ""):gsub("<[^>]*>", " "):gsub("\n", " ") end
local function lines(s, width)
    local out, line = {}, ""
    for word in plain(s):gmatch("%S+") do
        local nextLine = line == "" and word or line .. " " .. word
        if line ~= "" and D.measure(UIFont.Small, nextLine) > width then
            out[#out + 1], line = line, word
        else line = nextLine end
    end
    if line ~= "" then out[#out + 1] = line end
    return out
end

N26HubSkills = ISPanel:derive("N26HubSkills")
local Skills = N26HubSkills
function Skills:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self); self.__index = self
    o.background, o.scroll, o.detailScroll = false, 0, 0
    return o
end

function Skills:refresh()
    local groups = {
        { key = "UI_N26_Char_Craft", perks = {} },
        { key = "UI_N26_Char_Survival", perks = {} },
        { key = "UI_N26_Char_Combat", perks = {} },
        { key = "UI_N26_Char_Physical", perks = {} },
    }
    local all = PerkFactory and PerkFactory.PerkList
    for i = 0, (call(all, "size") or 0) - 1 do
        local perk = all:get(i)
        local parent = call(perk, "getParent")
        if parent and parent ~= Perks.None and parent ~= Perks.MAX then
            local id = tostring(call(perk, "getId") or call(perk, "getType"))
            local pid = tostring(parent)
            local group = 1
            if parent == Perks.Survivalist or id == "Doctor" then group = 2
            elseif parent == Perks.Combat or parent == Perks.Firearm then group = 3
            elseif parent == Perks.PhysicalCategory or parent == Perks.Passiv or parent == Perks.Agility
                or pid == "PhysicalCategory" or pid == "Passive" then group = 4 end
            groups[group].perks[#groups[group].perks + 1] = perk
        end
    end
    for _, g in ipairs(groups) do
        table.sort(g.perks, function(a, b) return a:getName() < b:getName() end)
    end
    self.groups = groups
    if not self.selected then
        local best = -1
        for _, p in ipairs(groups[1].perks) do
            local level = call(getSpecificPlayer(0), "getPerkLevel", p:getType()) or 0
            if level > best then self.selected, best = p, level end
        end
        if not self.selected then
            for _, g in ipairs(groups) do if #g.perks > 0 then self.selected = g.perks[1]; break end end
        end
    end
end

function Skills:xpData(perk)
    local chr = getSpecificPlayer(0)
    local level = call(chr, "getPerkLevel", perk:getType()) or 0
    local xp = call(chr, "getXp")
    local total = call(xp, "getXP", perk:getType()) or 0
    local previous, needed = 0, 0
    if ISSkillProgressBar then
        local ok, v = pcall(ISSkillProgressBar.getPreviousXpLvl, perk, level)
        if ok then previous = v or 0 end
        ok, v = pcall(ISSkillProgressBar.getXpForLvl, perk, level)
        if ok then needed = v or 0 end
    end
    return { level = level, earned = max(0, total - previous), needed = needed,
        multiplier = call(xp, "getMultiplier", perk:getType()) or 0,
        boost = call(xp, "getPerkBoost", perk:getType()) or 0 }
end

function Skills:drawDetail(x, w)
    local C, fh = Theme.C, D.fontHeight(UIFont.Small)
    D.panel(self, x, 0, w, self.height, C.panel, C.outline, Theme.R.lg)
    local p = self.selected
    if not p then return end
    local data = self:xpData(p)
    local pad = 16
    D.titleWithBar(self, p:getName(), x + pad, 12, 34, C.text, "md")
    D.heading(self, tostring(data.level), x + w - pad, 16, C.accent, "lg", "right")
    local y = 64
    D.caption(self, getText(data.level >= 10 and "UI_N26_Char_Max" or "UI_N26_Char_Next"), x + pad, y)
    y = y + fh + 8
    local fraction = data.level >= 10 and 1 or (data.needed > 0 and min(1, data.earned / data.needed) or 0)
    D.bar(self, x + pad, y, w - 2 * pad, 5, fraction, C.accent, C.hover2, 2)
    y = y + 14
    local s = data.level >= 10 and "10 / 10" or string.format("%.0f / %.0f XP", data.earned, data.needed)
    D.text(self, s, x + w - pad, y, C.text2, UIFont.Small, "right")
    y = y + fh + 14
    local boost = ({ [1] = 75, [2] = 100, [3] = 125 })[data.boost]
    if boost then
        D.text(self, getText("UI_N26_Char_Boost") .. " " .. tostring(boost) .. " %", x + pad, y, C.text2, UIFont.Small, nil, w - 2 * pad)
        y = y + fh + 6
    end
    if data.multiplier > 0 then
        D.text(self, getText("UI_N26_Char_Book") .. " x" .. tostring(data.multiplier), x + pad, y, C.info, UIFont.Small, nil, w - 2 * pad)
        y = y + fh + 6
    end
    y = y + 14
    D.rect(self, x + pad, y, w - 2 * pad, 1, C.divider)
    y = y + 14
    local key = "IGUI_perks_" .. p:getName() .. "_Description"
    local desc = getTextOrNull and getTextOrNull(key)
    if desc == key then desc = nil end
    local nextKey = key .. min(10, data.level + 1)
    local nextDesc = data.level < 10 and getTextOrNull and getTextOrNull(nextKey)
    if nextDesc == nextKey then nextDesc = nil end
    local text = (desc or getText("UI_N26_Char_Practice")) .. (nextDesc and ("\n\n" .. nextDesc) or "")
    local wrapped = lines(text, w - 2 * pad)
    local available = self.height - y - pad
    self.detailMax = max(0, #wrapped * (fh + 5) - available)
    self.detailScroll = min(self.detailScroll, self.detailMax)
    self:setStencilRect(x + pad, y, w - 2 * pad, max(0, available))
    for i, line in ipairs(wrapped) do D.text(self, line, x + pad, y + (i - 1) * (fh + 5) - self.detailScroll, C.text2, UIFont.Small) end
    self:clearStencilRect()
end

function Skills:prerender()
    if not self.groups then self:refresh() end
    local C, fh = Theme.C, D.fontHeight(UIFont.Small)
    local fs = D.fontScale()
    local dw = floor(self.width * 0.34)
    local boardW = self.width - dw - 12
    self.detailX = boardW + 12
    local cw = floor((boardW - 12) / 2)
    local rowH, headH = max(28, floor(32 * fs)), max(34, floor(38 * fs))
    local heights = {}
    for i, g in ipairs(self.groups) do heights[i] = headH + #g.perks * rowH + 10 end
    local firstH = max(heights[1], heights[2])
    self.scrollMax = max(0, firstH + 12 + max(heights[3], heights[4]) - self.height)
    self.scroll = min(self.scroll, self.scrollMax)
    self.rows = {}
    self:setStencilRect(0, 0, boardW, self.height)
    for i, g in ipairs(self.groups) do
        local x = ((i - 1) % 2) * (cw + 12)
        local y = (i <= 2 and 0 or firstH + 12) - self.scroll
        D.panel(self, x, y, cw, heights[i], C.panel2, C.outline, Theme.R.md)
        D.caption(self, getText(g.key), x + 12, y + 10)
        for j, p in ipairs(g.perks) do
            local ry = y + headH + (j - 1) * rowH
            local active = p == self.selected
            if active then D.fill(self, x + 6, ry, cw - 12, rowH - 2, C.accentSoft, Theme.R.sm) end
            local data = self:xpData(p)
            local pipW = max(4, min(13, floor(cw * 0.026)))
            local pw = 10 * (pipW + 3) - 3
            local px = x + cw - pw - 34
            D.text(self, p:getName(), x + 14, ry + floor((rowH - fh) / 2), active and C.accent or C.text2, UIFont.Small, nil, px - x - 24)
            for n = 1, 10 do
                D.fill(self, px + (n - 1) * (pipW + 3), ry + floor(rowH / 2) - 4, pipW, 8, n <= data.level and C.accent or C.hover2, 1)
            end
            D.text(self, tostring(data.level), x + cw - 14, ry + floor((rowH - fh) / 2), C.text, UIFont.Small, "right")
            self.rows[#self.rows + 1] = { x = x, y = ry, w = cw, h = rowH, perk = p }
        end
    end
    self:clearStencilRect()
    if self.scrollMax > 0 then
        local sh = max(24, self.height * self.height / (self.height + self.scrollMax))
        D.fill(self, boardW - 3, (self.height - sh) * self.scroll / self.scrollMax, 3, sh, C.muted, 1)
    end
    self:drawDetail(self.detailX, dw)
end

function Skills:onMouseDown(x, y)
    for _, r in ipairs(self.rows or {}) do
        if x >= r.x and x < r.x + r.w and y >= max(0, r.y) and y < min(self.height, r.y + r.h) then
            self.selected, self.detailScroll = r.perk, 0
            return true
        end
    end
    return true
end
function Skills:onMouseWheel(del)
    if self:getMouseX() >= (self.detailX or self.width) then
        self.detailScroll = max(0, min(self.detailMax or 0, self.detailScroll + del * 40))
    else self.scroll = max(0, min(self.scrollMax or 0, self.scroll + del * 40)) end
    return true
end
