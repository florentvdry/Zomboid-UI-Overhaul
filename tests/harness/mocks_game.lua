--[[
    Minimal game-object mocks (player, items, containers) for module tests.
    Only what the exercised vanilla code paths call is implemented.
]]

local function list(t)
    return {
        size = function() return #t end,
        get = function(_, i) return t[i + 1] end,
        isEmpty = function() return #t == 0 end,
        contains = function(_, x) for _, v in ipairs(t) do if v == x then return true end end return false end,
        add = function(_, x) t[#t + 1] = x end,
    }
end
MockList = list

local itemMeta = { __index = {} }
local I = itemMeta.__index
function I:getName() return self.name end
function I:getDisplayName() return self.name end
function I:getType() return self.type end
function I:getFullType() return "Base." .. self.type end
function I:getTex() return getTexture("media/textures/Item_" .. self.type .. ".png") end
function I:getTexture() return self:getTex() end
function I:getDisplayCategory() return self.cat end
function I:getCategory() return self.cat end
function I:isHidden() return false end
function I:IsFood() return false end
function I:getUnequippedWeight() return self.weight end
function I:getActualWeight() return self.weight end
function I:getWeight() return self.weight end
function I:updateAge() end
function I:updateWetness() end
function I:isBroken() return false end
function I:isFavorite() return self.fav == true end
function I:isNoRecipes() return false end
function I:isFavouriteRecipeInput() return false end
function I:hasBeenSeen() return false end
function I:hasBeenHeard() return false end
function I:getFluidContainer() return nil end
function I:getWorldItem() return nil end
function I:getJobDelta() return 0 end
function I:getHeat() return 1 end
function I:getItemHeat() return 1 end
function I:isUnwanted() return false end
function I:IsLiterature() return false end
function I:isItemType() return false end
function I:hasTag() return false end
function I:isEquipped() return false end
function I:getA() return 1 end
function I:getR() return 1 end
function I:getG() return 1 end
function I:getB() return 1 end
function I:getCondition() return 5 end
function I:getConditionMax() return 10 end
function I:getMeltingTime() return 0 end
function I:getHungerChange() return 0 end
function I:getIcon() return nil end
function I:getContainer() return nil end
function I:getModData() return {} end
function I:hasModData() return false end

function MockItem(name, cat, weight)
    return setmetatable({ name = name, type = name:gsub("%s", ""), cat = cat or "Item", weight = weight or 0.5 }, itemMeta)
end

local containerMeta = { __index = {} }
local Ct = containerMeta.__index
function Ct:getItems() return list(self.items) end
function Ct:isDrawDirty() return self.dirty end
function Ct:setDrawDirty(v) self.dirty = v end
function Ct:isLockedToCharacter() return false end
function Ct:getType() return self.type end
function Ct:getCapacityWeight() local w = 0 for _, i in ipairs(self.items) do w = w + i.weight end return w end
function Ct:getContentsWeight() return self:getCapacityWeight() end
function Ct:getEffectiveCapacity() return self.capacity end
function Ct:getCapacity() return self.capacity end
function Ct:getMaxWeight() return self.capacity end
function Ct:getItemsFromCategory() return MockList({}) end
function Ct:getAllCategory() return MockList({}) end
function Ct:isInCharacterInventory() return true end
function Ct:getCharacter() return nil end
function Ct:getVehiclePart() return nil end
function Ct:getParent() return nil end
function Ct:isOccupiedVehicleSeat() return false end
function Ct:isExplored() return true end
function Ct:getContainingItem() return nil end
function Ct:contains(i) for _, v in ipairs(self.items) do if v == i then return true end end return false end

function MockContainer(items, capacity, type)
    return setmetatable({ items = items, capacity = capacity or 20, type = type or "none", dirty = true }, containerMeta)
end

local playerMeta = { __index = {} }
local Pl = playerMeta.__index
function Pl:getInventory() return self.inv end
function Pl:getMaxWeight() return 20 end
function Pl:getInventoryWeight() return self.inv:getCapacityWeight() end
function Pl:getWornItems() return list({}) end
function Pl:getPrimaryHandItem() return nil end
function Pl:getSecondaryHandItem() return nil end
function Pl:isEquipped() return false end
function Pl:isKnownPoison() return false end
function Pl:hasReadMap() return false end
function Pl:isAsleep() return false end
function Pl:isDead() return false end
function Pl:getPlayerNum() return 0 end
function Pl:getJoypadBind() return -1 end
function Pl:isInvPageDirty() return false end
function Pl:isLiteratureRead() return false end
function Pl:isRecipeActuallyKnown() return false end
function Pl:getBodyDamage() return { getOverallBodyHealth = function() return 82 end, getHealth = function() return 82 end } end
function Pl:getForwardDirection() return { getX = function() return 0 end, getY = function() return -1 end } end

function MockPlayer(inv)
    return setmetatable({ inv = inv }, playerMeta)
end

-- engine helpers used by the inventory code paths
instanceof = function(o, cls)
    if cls == "InventoryItem" then return getmetatable(o) == itemMeta end
    if cls == "Texture" then return type(o) == "table" and o.path ~= nil end
    return false
end
round = round or function(n, d) local m = 10 ^ (d or 0) return math.floor(n * m + 0.5) / m end
getPlayerHotbar = function() return nil end
getSandboxOptions = function() return { getOptionByName = function() return { getValue = function() return false end } end } end

-- Kahlua extension: string.sort(a, b) is a Java compareTo > 0 test.
string.sort = string.sort or function(a, b) return tostring(a) >= tostring(b) end
require "ISUI/ISButton"
require "ISUI/ISResizeableButton"
