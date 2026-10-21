-- Harness prelude: module searcher, test API, snapshot serialisation.

HARNESS_DIR = "__HARNESS_DIR__"

-- PZ-style require: exact relative path, then path suffix, then bare file name.
-- A module that cannot be found is not fatal (the game only logs it).
table.insert(package.searchers, 2, function(name)
    for _, e in ipairs(LUA_INDEX) do
        local rel = e[1]
        if rel == name or rel:sub(-#name - 1) == "/" .. name then
            local f, err = loadfile(e[2])
            if not f then error(err) end
            return f, e[2]
        end
    end
    local base = name:match("([^/]+)$")
    for _, e in ipairs(LUA_INDEX) do
        if e[1]:match("([^/]+)$") == base then
            local f, err = loadfile(e[2])
            if not f then error(err) end
            return f, e[2]
        end
    end
    MISSING_REQUIRES = MISSING_REQUIRES or {}
    MISSING_REQUIRES[name] = true
    return function() return nil end, name
end)

__RESULTS = {}
function test(name, fn)
    resetDrawLog()
    local ok, err = xpcall(fn, debug.traceback)
    table.insert(__RESULTS, { name = name, ok = ok, err = err })
end

function expect(cond, msg) if not cond then error(msg or "expectation failed", 2) end end
function expectEq(a, b, msg)
    if a ~= b then error((msg or "values differ") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end

function countDraws(kind)
    local n = 0
    for _, d in ipairs(DRAWLOG) do if not kind or d.kind == kind then n = n + 1 end end
    return n
end

function drawsUsing(pattern)
    local n = 0
    for _, d in ipairs(DRAWLOG) do
        local t = d.args[1]
        if type(t) == "table" and t.path and t.path:find(pattern) then n = n + 1 end
    end
    return n
end

function drawnText(s)
    for _, d in ipairs(DRAWLOG) do
        local n = d.args.n or #d.args
        for i = 1, n do if d.args[i] == s then return true end end
    end
    return false
end

-- ------------------------------------------------------------ snapshots

local function jstr(s)
    s = tostring(s):gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end)
    return '"' .. s .. '"'
end

local function jval(v)
    local t = type(v)
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "0" end
        return string.format("%.4f", v)
    end
    if t == "string" then return jstr(v) end
    if t == "boolean" then return tostring(v) end
    if t == "table" and v.path then return '{"path":' .. jstr(v.path) .. '}' end
    return "null"
end

__SNAPSHOTS = {}

--- Serialise the current draw log (records with an absolute position only).
function snapshot(name, w, h)
    local out = {}
    for _, d in ipairs(DRAWLOG) do
        if d.ax then
            local args = {}
            local n = d.args.n or #d.args
            for i = 1, n do args[i] = jval(d.args[i]) end
            out[#out + 1] = '{"k":' .. jstr(d.kind) .. ',"ax":' .. jval(d.ax) .. ',"ay":' .. jval(d.ay)
                .. ',"sx":' .. jval(d.sx or 0) .. ',"sy":' .. jval(d.sy or 0)
                .. ',"a":[' .. table.concat(args, ",") .. ']}'
        end
    end
    __SNAPSHOTS[#__SNAPSHOTS + 1] = '{"name":' .. jstr(name) .. ',"w":' .. w .. ',"h":' .. h
        .. ',"records":[' .. table.concat(out, ",") .. ']}'
end

--- Render an element tree like the game's UIElement.render():
--- Lua prerender, then the children, then Lua render (overlays, stencil clear).
function renderTree(el)
    if el.isVisible and not el:isVisible() then return end
    if el.prerender then el:prerender() end
    local kids = rawget(el, "childrenInOrder")
    if kids then
        for _, c in ipairs(kids) do renderTree(c) end
    end
    if el.render then el:render() end
end
