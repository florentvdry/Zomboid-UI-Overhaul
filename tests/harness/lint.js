/*
 * Syntax check of every Lua file shipped by the mod, parsed as Lua 5.1
 * (Kahlua, the game's VM, implements 5.1). Also flags constructs Kahlua rejects
 * or that behave differently: goto, integer division //, bitwise operators.
 *
 *   NODE_PATH=<dir with luaparse> node tests/harness/lint.js
 */
'use strict';
const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');

const ROOT = path.resolve(__dirname, '..', '..');
const dirs = [path.join(ROOT, '42', 'media', 'lua')];
let files = [];
function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p);
    else if (p.endsWith('.lua')) files.push(p);
  }
}
dirs.forEach(walk);
let bad = 0;
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  try {
    luaparse.parse(src, { luaVersion: '5.1', comments: false });
  } catch (e) {
    bad++;
    console.log(`✗ ${path.relative(ROOT, f)}: ${e.message}`);
    continue;
  }
  const code = src.replace(/--\[\[[\s\S]*?\]\]/g, '').replace(/--[^\n]*/g, '').replace(/"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'/g, '""');
  const issues = [];
  if (/\bgoto\b/.test(code)) issues.push('goto');
  if (/[^-]\/\/[^\n]/.test(code)) issues.push('integer division //');
  if (/[^~=<>]~[^=]/.test(code)) issues.push('bitwise ~');
  if (/<<|>>/.test(code)) issues.push('bit shift');
  if (issues.length) { bad++; console.log(`✗ ${path.relative(ROOT, f)}: ${issues.join(', ')}`); }
}
console.log(`${files.length} Lua files checked, ${bad} with problems`);
process.exit(bad ? 1 : 0);
