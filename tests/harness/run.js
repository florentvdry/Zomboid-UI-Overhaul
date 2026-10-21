/*
 * Headless test runner: executes tests/*.test.lua inside fengari (a Lua VM in JS)
 * with the real vanilla ISUI files from the game install and the mod's Lua.
 *
 *   NODE_PATH=<dir with fengari + @napi-rs/canvas> node tests/harness/run.js [filter]
 *   PZ_LUA=<game>/media/lua     overrides the game Lua location
 *   PZ_MEDIA=<game>/media       overrides the game media location (fonts, textures)
 *
 * Tests may call snapshot(name, w, h): the recorded draw list is replayed into
 * tests/out/<name>.png with the game's fonts and textures (see snapshot.js).
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const snapshot = require('./snapshot');

const ROOT = path.resolve(__dirname, '..', '..');
const GAME = (process.env.PZ_LUA || 'E:/SteamLibrary/steamapps/common/ProjectZomboid/media/lua').replace(/\\/g, '/');
const MOD = path.join(ROOT, '42', 'media', 'lua').replace(/\\/g, '/');
const TESTS = path.join(ROOT, 'tests');
const filter = process.argv[2];

if (!fs.existsSync(GAME)) {
  console.error('Game Lua not found at ' + GAME + ' (set PZ_LUA)');
  process.exit(2);
}

function check(L, status) {
  if (status !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
}

function runFile(L, file) {
  const code = fs.readFileSync(file);
  check(L, lauxlib.luaL_loadbuffer(L, code, null, to_luastring('@' + path.basename(file))));
  check(L, lua.lua_pcall(L, 0, 0, 0));
}

// Index every Lua file by its path below media/lua/<shared|client>/ so the
// searcher can resolve PZ-style suffix requires ("ISUI/ISVehicleMenu" lives in
// client/Vehicles/ISUI/). Mod files come first, so they override vanilla.
function indexLua(base) {
  const out = [];
  for (const side of ['shared', 'client']) {
    const root = path.join(base, side);
    if (!fs.existsSync(root)) continue;
    const walk = (d) => {
      for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) walk(p);
        else if (p.endsWith('.lua')) {
          const rel = path.relative(root, p).split(path.sep).join('/').slice(0, -4);
          out.push([rel, p.split(path.sep).join('/')]);
        }
      }
    };
    walk(root);
  }
  return out;
}
const LUA_INDEX = indexLua(MOD).concat(indexLua(GAME));
const indexLuaSrc = 'LUA_INDEX = {' + LUA_INDEX.map(([r, f]) => '{' + JSON.stringify(r) + ',' + JSON.stringify(f) + '}').join(',') + '}';

const PRELUDE = fs.readFileSync(path.join(__dirname, 'prelude.lua'), 'utf8')
  .replace('__HARNESS_DIR__', __dirname.split(path.sep).join('/'));

const engineGlobals = fs.readFileSync(path.join(__dirname, 'engine_globals.txt'), 'utf8').split(/\s+/).filter(Boolean);
const engineGlobalsSrc = 'ANY_GLOBALS = {' + engineGlobals.map((g) => '[' + JSON.stringify(g) + ']=true').join(',') + '}';
const fontSrc = snapshot.fontMetricsLua();
const texSrc = snapshot.texDimsLua();
// French mod strings, for tests that want readable snapshots (TRANSLATIONS_FR[key]).
const frJson = JSON.parse(fs.readFileSync(path.join(ROOT, '42', 'media', 'lua', 'shared', 'Translate', 'FR', 'UI.json'), 'utf8'));
const trSrc = 'TRANSLATIONS_FR = {' + Object.entries(frJson).map(([k, v]) => '[' + JSON.stringify(k) + ']=' + JSON.stringify(v)).join(',') + '}';

let files = fs.readdirSync(TESTS).filter((f) => f.endsWith('.test.lua')).sort();
if (filter) files = files.filter((f) => f.includes(filter));
let pass = 0, fail = 0;
const snapshots = [];

function getString(L, field) {
  lua.lua_getfield(L, -1, to_luastring(field));
  const v = lua.lua_isstring(L, -1) ? to_jsstring(lua.lua_tostring(L, -1)) : '';
  lua.lua_pop(L, 1);
  return v;
}

for (const f of files) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  try {
    check(L, lauxlib.luaL_dostring(L, to_luastring(engineGlobalsSrc)));
    check(L, lauxlib.luaL_dostring(L, to_luastring(fontSrc)));
    check(L, lauxlib.luaL_dostring(L, to_luastring(texSrc)));
    check(L, lauxlib.luaL_dostring(L, to_luastring(trSrc)));
    runFile(L, path.join(__dirname, 'stubs.lua'));
    check(L, lauxlib.luaL_dostring(L, to_luastring(indexLuaSrc)));
    check(L, lauxlib.luaL_dostring(L, to_luastring(PRELUDE)));
    runFile(L, path.join(TESTS, f));
  } catch (e) {
    console.log(`✗ ${f}: load error\n    ${String(e.message).split('\n').slice(0, 6).join('\n    ')}`);
    fail++;
    continue;
  }
  lua.lua_getglobal(L, to_luastring('__RESULTS'));
  const n = lua.lua_rawlen(L, -1);
  for (let i = 1; i <= n; i++) {
    lua.lua_rawgeti(L, -1, i);
    const name = getString(L, 'name');
    lua.lua_getfield(L, -1, to_luastring('ok'));
    const ok = lua.lua_toboolean(L, -1);
    lua.lua_pop(L, 1);
    const err = getString(L, 'err');
    lua.lua_pop(L, 1);
    if (ok) { pass++; console.log(`✓ ${f} › ${name}`); }
    else { fail++; console.log(`✗ ${f} › ${name}\n    ${err.split('\n').slice(0, 8).join('\n    ')}`); }
  }
  lua.lua_pop(L, 1);
  lua.lua_getglobal(L, to_luastring('__SNAPSHOTS'));
  const ns = lua.lua_rawlen(L, -1);
  for (let i = 1; i <= ns; i++) {
    lua.lua_rawgeti(L, -1, i);
    snapshots.push(JSON.parse(to_jsstring(lua.lua_tostring(L, -1))));
    lua.lua_pop(L, 1);
  }
  lua.lua_pop(L, 1);
}

(async () => {
  for (const snap of snapshots) {
    const out = path.join(TESTS, 'out', snap.name + '.png');
    try {
      const unknown = await snapshot.render(snap, out);
      const extra = Object.keys(unknown).length ? ' unhandled: ' + JSON.stringify(unknown) : '';
      console.log(`  snapshot ${snap.name}.png (${snap.records.length} draws)${extra}`);
    } catch (e) {
      console.log(`  snapshot ${snap.name} failed: ${e.message}`);
    }
  }
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
