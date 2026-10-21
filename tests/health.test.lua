-- Health module: vanilla ISHealthPanel with the N26 body view and wound cards.

dofile(HARNESS_DIR .. "/mocks_game.lua")
require "N26/N26_Boot"
-- these tests exercise the redesign as it appears inside the tactical screen
N26.scopeOf = function() return "window" end
require "ISUI/BodyParts/ISBodyPartPanel"
require "XpSystem/ISUI/ISHealthPanel"

local function noHookErrors()
    for key, h in pairs(N26.Hooks) do
        if h.errors > 0 then error("hook " .. key .. " errored: " .. tostring(h.lastError)) end
    end
end

-- Generic body part: unknown getters return 0, predicates return false.
local function MockBodyPart(typeName, health, overrides)
    local bp = { typeName = typeName, health = health or 100 }
    local fixed = {
        getType = function() return typeName end,
        getHealth = function() return bp.health end,
        HasInjury = function() return (overrides and overrides.injured) or false end,
        bleeding = function() return (overrides and overrides.bleeding) or false end,
        isCut = function() return (overrides and overrides.cut) or false end,
        bandaged = function() return (overrides and overrides.bandaged) or false end,
    }
    return setmetatable(bp, { __index = function(_, k)
        if fixed[k] then return fixed[k] end
        if k:sub(1, 3) == "get" then return function() return 0 end end
        return function() return false end
    end })
end

local NAMES = { "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R", "UpperArm_L", "UpperArm_R", "Torso_Upper",
    "Torso_Lower", "Head", "Neck", "Groin", "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R", "Foot_L", "Foot_R" }

local parts = {}
for _, n in ipairs(NAMES) do parts[#parts + 1] = MockBodyPart(n, 100) end
parts[14] = MockBodyPart("LowerLeg_L", 64, { injured = true, bleeding = true, cut = true })

local bodyDamage = {
    getBodyParts = function() return MockList(parts) end,
    getHealth = function() return 82 end,
    getOverallBodyHealth = function() return 82 end,
    getBodyPart = function(_, t) for _, p in ipairs(parts) do if p.typeName == t then return p end end end,
}
local patient = MockPlayer(MockContainer({}, 20))
patient.getBodyDamage = function() return bodyDamage end
patient.isLocalPlayer = function() return true end
patient.getMoodles = function() return { getMoodleLevel = function() return 1 end } end
patient.getJoypadBind = function() return -1 end
patient.getStats = function() return { get = function() return 0 end } end
patient.getReduceInfectionPower = function() return 0 end
patient.getPerkLevel = function() return 0 end
patient.isFemale = function() return false end
getSpecificPlayer = function() return patient end
BodyPartType = {
    getDisplayName = function(t) return tostring(t) end,
    FromIndex = function(i) return NAMES[i + 1] end,
}
MoodleType = { PAIN = "PAIN", ENDURANCE = "ENDURANCE" }
ISTimedActionQueue = ISTimedActionQueue or {}
ISTimedActionQueue.getTimedActionQueue = function() return nil end

test("health panel builds with the N26 body view", function()
    local panel = ISHealthPanel:new(patient, 0, 0, 520, 480)
    panel:initialise()
    panel:addToUIManager()
    expect(panel.n26Body ~= nil, "body view created")
    expect(panel.n26Body.model ~= nil, "real 3D character widget attached")
    expect(panel.listbox.x > panel.n26Body:getRight(), "list right of the body")
    panel.healthPanel.javaObject = { getDamageStatusString = function() return "Moderate" end }
    panel:updateBodyPartList()
    panel.listbox:clear()
    panel.listbox:addItem("dummy", { bodyPart = parts[14] })
    resetDrawLog()
    panel:prerender()
    panel:render()
    panel.n26Body:prerender()
    panel.listbox:prerender()
    expect(drawnText("Moderate"), "status string drawn")
    expect(drawnText("64 / 100"), "card health readout")
    noHookErrors()
end)

test("body view hit-test maps zones and routes right-click to vanilla treatment menu", function()
    local panel = ISHealthPanel:new(patient, 0, 0, 520, 480)
    panel:initialise()
    panel:addToUIManager()
    local body = panel.n26Body
    local s, ox, oy = body:layout()
    local hx, hy = ox + 80 * s, oy + 20 * s
    expectEq(body:zoneAt(hx, hy), "Head")
    local called
    panel.doBodyPartContextMenu = function(_, bp, x, y) called = bp end
    UIManager.getSpeedControls = function() return { getCurrentGameSpeed = function() return 1 end } end
    body:onRightMouseUp(hx, hy)
    expect(called and called:getType() == "Head", "treatment menu opened for the head")
    noHookErrors()
end)
