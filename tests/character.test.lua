-- Character module: info/skills/protection drawing remaps on vanilla code paths.

dofile(HARNESS_DIR .. "/mocks_game.lua")
require "N26/N26_Boot"
-- these tests exercise the redesign as it appears inside the tactical screen
N26.scopeOf = function() return "window" end

local function noHookErrors()
    for key, h in pairs(N26.Hooks) do
        if h.errors > 0 then error("hook " .. key .. " errored: " .. tostring(h.lastError)) end
    end
end

test("skill pips remap vanilla tints to the palette", function()
    local bar = setmetatable({}, { __index = ISSkillProgressBar })
    bar.javaObject = UIElement.new(bar)
    bar.SkillUnitFilled = getTexture("media/ui/SkillPanel/SkillUnit_Fill.png")
    bar.SkillUnitBorder = getTexture("media/ui/SkillPanel/SkillUnit_Border.png")
    bar.level = 3
    bar.perk = { getType = function() return "Carpentry" end, isPassiv = function() return false end,
                 getXpForLevel = function() return 100 end, getXp1 = function() return 50 end,
                 getXp2 = function() return 50 end, getXp3 = function() return 50 end }
    bar.char = { getPerkLevel = function() return 3 end,
                 getXp = function() return { getXP = function() return 175 end } end }
    bar.parent = {}
    bar.xpForLvl = 100
    resetDrawLog()
    bar:renderPerkRect()
    local accent = N26.Theme.C.accent
    local found = false
    for _, d in ipairs(DRAWLOG) do
        if d.kind == "DrawTextureScaledColor" then
            local r, g, b = d.args[6], d.args[7], d.args[8]
            if math.abs(r - accent.r) < 0.01 and math.abs(g - accent.g) < 0.01 then found = true end
        end
    end
    expect(found, "acquired level drawn in accent")
    noHookErrors()
end)
