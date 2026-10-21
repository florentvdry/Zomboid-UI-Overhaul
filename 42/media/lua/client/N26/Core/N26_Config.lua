--[[
    N26 configuration.

    Player-facing settings live in the native Build 42 mod options page
    (Options > Mods > Zomboid UI Overhaul) through PZAPI.ModOptions, which
    persists them in Zomboid/Lua/ModOptions.ini.
]]

require "N26/Core/N26_Core"
require "PZAPI/ModOptions"

N26.Config = N26.Config or {}
local Config = N26.Config

local OPTIONS_ID = "N26_UIOverhaul"

-- Defaults double as the schema: type is inferred from the default value.
Config.DEFAULTS = {
    accent = 1,            -- index into N26.Theme.ACCENTS
    panelOpacity = 90,     -- %
    animations = true,     -- pulsing highlights (health zones…)
}

Config.values = Config.values or {}
for k, v in pairs(Config.DEFAULTS) do
    if Config.values[k] == nil then Config.values[k] = v end
end

local listeners = {}

function N26.on(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
end

function N26.fire(event, ...)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then N26.log("listener %s failed: %s", event, tostring(err)) end
    end
end

function Config.get(key)
    local v = Config.values[key]
    if v == nil then return Config.DEFAULTS[key] end
    return v
end

function Config.set(key, value)
    Config.values[key] = value
end

function Config.animations()
    return Config.get("animations") == true
end

function Config.moduleEnabled(id)
    local v = Config.values["mod_" .. id]
    if v == nil then
        local def = N26.Modules[id]
        return not def or def.default ~= false
    end
    return v == true
end

-- ---------------------------------------------------------------------------
-- Native mod options page
-- ---------------------------------------------------------------------------

local options

local function pullFromOptions()
    if not options then return end
    for key in pairs(Config.DEFAULTS) do
        local opt = options:getOption(key)
        if opt then Config.values[key] = opt:getValue() end
    end
    for _, id in ipairs(N26.ModuleOrder) do
        local opt = options:getOption("mod_" .. id)
        if opt then Config.values["mod_" .. id] = opt:getValue() end
    end
end

function Config.buildOptions()
    if options or not PZAPI or not PZAPI.ModOptions then return end
    options = PZAPI.ModOptions:create(OPTIONS_ID, "UI_N26_Options_Title")

    options:addDescription("UI_N26_Options_Desc")

    -- the tactical screen itself first, then each redesign shown inside it
    local order = { "hub" }
    for _, id in ipairs(N26.ModuleOrder) do
        if id ~= "hub" then order[#order + 1] = id end
    end
    for _, id in ipairs(order) do
        local def = N26.Modules[id]
        if def then options:addTickBox("mod_" .. id, def.label, def.default ~= false, def.tooltip) end
    end

    options:addTitle("UI_N26_Options_Section_Style")
    local accent = options:addComboBox("accent", "UI_N26_Opt_Accent", "UI_N26_Opt_Accent_Tip")
    for i, preset in ipairs(N26.Theme.ACCENTS) do
        accent:addItem(preset.label, i == Config.DEFAULTS.accent)
    end
    options:addSlider("panelOpacity", "UI_N26_Opt_Opacity", 60, 100, 5, Config.DEFAULTS.panelOpacity, "UI_N26_Opt_Opacity_Tip")
    options:addTickBox("animations", "UI_N26_Opt_Animations", Config.DEFAULTS.animations, "UI_N26_Opt_Animations_Tip")

    options.apply = function()
        pullFromOptions()
        if N26.Theme then N26.Theme.refresh() end
        N26.fire("configChanged")
    end

    -- Read the saved values now: the game only loads ModOptions.ini when the
    -- options screen opens, but the tactical screen needs them from the start.
    local ok, err = pcall(function() PZAPI.ModOptions:load() end)
    if not ok then N26.log("could not load ModOptions.ini: %s", tostring(err)) end
    pullFromOptions()
    if N26.Theme then N26.Theme.refresh() end
end
