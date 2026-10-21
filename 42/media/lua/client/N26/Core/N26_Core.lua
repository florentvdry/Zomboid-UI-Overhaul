--[[
    Zomboid UI Overhaul — core namespace and safe patching.

    Every change the mod makes to a vanilla UI class goes through N26.hook(). A hook:
      * is attached to a module id, and becomes a pass-through when that module is
        disabled in the mod options (no reload needed);
      * runs inside pcall; after MAX_ERRORS failures it disables itself for the
        session and the vanilla function takes over again, so a broken skin can
        never take a window down with it;
      * keeps the function it replaced, so other mods that patched the same
        method before us still run (we call the captured original).
]]

N26 = N26 or {}
N26.VERSION = "1.0.0"
N26.MOD_ID = "N26_UIOverhaul"

local MAX_ERRORS = 3

N26.Modules = N26.Modules or {}      -- id -> definition
N26.ModuleOrder = N26.ModuleOrder or {}
N26.Hooks = N26.Hooks or {}          -- key -> { errors, disabled, lastError }

function N26.log(msg, ...)
    if select("#", ...) > 0 then
        msg = string.format(msg, ...)
    end
    print("[N26] " .. tostring(msg))
end

--- Declare a feature module that the player can toggle in the mod options.
-- def = { id = "inventory", label = "UI_N26_Mod_Inventory", default = true, tooltip = ... }
function N26.registerModule(def)
    if not N26.Modules[def.id] then
        table.insert(N26.ModuleOrder, def.id)
    end
    if def.default == nil then def.default = true end
    N26.Modules[def.id] = def
    return def
end

--- True when the module is switched on. Unknown modules are considered on.
function N26.isEnabled(id)
    if not id then return true end
    local cfg = N26.Config
    if cfg and cfg.moduleEnabled then
        return cfg.moduleEnabled(id)
    end
    local def = N26.Modules[id]
    return not def or def.default ~= false
end

local function reportError(key, err)
    local h = N26.Hooks[key]
    h.errors = h.errors + 1
    h.lastError = tostring(err)
    if h.errors == 1 or h.errors >= MAX_ERRORS then
        N26.log("hook %s failed (%d/%d): %s", key, h.errors, MAX_ERRORS, h.lastError)
    end
    if h.errors >= MAX_ERRORS and not h.disabled then
        h.disabled = true
        N26.log("hook %s disabled for this session; vanilla behaviour restored", key)
    end
end

-- ---------------------------------------------------------------------------
-- Scope: N26 only restyles what the tactical screen shows.
--   "window"  the element belongs to the hub or to a vanilla window docked in it
--   "popup"   a context menu / tooltip while the hub is open
--   nil       anything else: the game's own look, untouched
-- ---------------------------------------------------------------------------

local POPUPS = { ISContextMenu = true, ISToolTip = true, ISToolTipInv = true }

function N26.scopeOf(el)
    local hub = N26.Hub
    if not hub or not hub.isOpen or not hub.isOpen() then return nil end
    local e, n = el, 0
    while type(e) == "table" and n < 64 do
        if rawget(e, "n26Docked") or rawget(e, "n26HubOwned") then return "window" end
        local p = rawget(e, "parent")
        if p == nil then break end
        e = p
        n = n + 1
    end
    if type(e) == "table" and POPUPS[e.Type] then return "popup" end
    return nil
end

--- Build-time changes (createChildren…) only happen while the tactical screen
--- is enabled; the windows they touch are only ever shown inside it.
function N26.buildScope()
    return N26.isEnabled("hub")
end

--[[ Replace class[method] with impl(orig, self, ...).

  opts.fallback (default true): when impl errors, call the original so the frame
    still renders. Set to false for functions with side effects (child creation…)
    where running both would duplicate work.
  opts.scope: "hub" (default) runs impl only for elements N26.scopeOf() accepts;
    "build" only while the tactical screen is enabled; "always" without check.
]]
function N26.hook(class, className, method, moduleId, impl, opts)
    if type(class) ~= "table" then
        N26.log("cannot hook %s.%s: class missing", tostring(className), tostring(method))
        return false
    end
    local orig = class[method]
    if type(orig) ~= "function" then
        N26.log("cannot hook %s.%s: method missing", tostring(className), tostring(method))
        return false
    end
    local key = className .. "." .. method
    local fallback = not opts or opts.fallback ~= false
    local scope = opts and opts.scope or "hub"
    N26.Hooks[key] = N26.Hooks[key] or { errors = 0, disabled = false, module = moduleId }
    local state = N26.Hooks[key]
    class[method] = function(self, ...)
        if state.disabled or not N26.isEnabled(moduleId) then
            return orig(self, ...)
        end
        if scope == "hub" then
            local where = N26.scopeOf(self)
            if not where then return orig(self, ...) end
            if where == "window" and N26.Skin and N26.Skin.apply then N26.Skin.apply(self) end
        elseif scope == "build" and not N26.buildScope() then
            return orig(self, ...)
        end
        -- Track the vanilla call so that (a) an error raised by vanilla code is
        -- re-raised untouched instead of being blamed on N26, and (b) vanilla
        -- never runs twice when N26 code fails after it.
        local phase = 0          -- 0 = before orig, 1 = inside orig, 2 = orig done
        local o1, o2, o3
        local function callOrig(...)
            phase = 1
            o1, o2, o3 = orig(...)
            phase = 2
            return o1, o2, o3
        end
        local ok, r1, r2, r3 = pcall(impl, callOrig, self, ...)
        if ok then
            return r1, r2, r3
        end
        if phase == 1 then
            error(r1, 0)
        end
        reportError(key, r1)
        if phase == 2 then
            return o1, o2, o3
        end
        if fallback then
            return orig(self, ...)
        end
    end
    return true
end

--- Add a function after an existing one (orig runs first, then post(self, ...)).
--- Default scope "build" (state set up at creation); pass "hub" for per-frame code.
function N26.after(class, className, method, moduleId, post, scope)
    return N26.hook(class, className, method, moduleId, function(orig, self, ...)
        local r1, r2, r3 = orig(self, ...)
        post(self, ...)
        return r1, r2, r3
    end, { fallback = false, scope = scope or "build" })
end

--- Number of hooks that disabled themselves after repeated errors.
function N26.failedHookCount()
    local n = 0
    for _, h in pairs(N26.Hooks) do
        if h.disabled then n = n + 1 end
    end
    return n
end

--- Safe call for module code outside hooks (event handlers, constructors).
function N26.try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        N26.log("%s failed: %s", label, tostring(err))
    end
    return ok, err
end

--- Translation with fallback when the key is missing (getText returns the key).
function N26.text(key, ...)
    local s
    if select("#", ...) > 0 then
        s = getText(key, ...)
    else
        s = getText(key)
    end
    return s
end
