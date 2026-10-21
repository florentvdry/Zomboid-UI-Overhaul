--[[
    Zomboid UI Overhaul — entry point.

    The mod adds the full-screen tactical screen opened with Tab
    (Modules/N26_Hub.lua), with custom character and craft/build pages and an
    integrated world map. Hosted inventory and health views get the redesign;
    every other interface keeps the game's own look (see N26.scopeOf).
]]

require "N26/Core/N26_Core"
require "N26/Core/N26_Config"
require "N26/Core/N26_Theme"
require "N26/Core/N26_Draw"

require "N26/Skin/N26_SkinCore"
require "N26/Skin/N26_SkinWindow"
require "N26/Skin/N26_SkinControls"
require "N26/Skin/N26_SkinMenus"

require "N26/Modules/N26_Inventory"
require "N26/Modules/N26_Health"
require "N26/Modules/N26_Character"
require "N26/Modules/N26_Crafting"
require "N26/Modules/N26_Hub"

N26.Config.buildOptions()
N26.log("Zomboid UI Overhaul %s loaded", N26.VERSION)
