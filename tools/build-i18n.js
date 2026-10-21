/*
 * Builds media/lua/shared/Translate/<LANG>/UI.json from tools/src/i18n.json
 * (key -> [EN, FR]) and checks that every UI_N26_* key used in Lua exists.
 *
 *   node tools/build-i18n.js
 */
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const src = JSON.parse(fs.readFileSync(path.join(__dirname, 'src', 'i18n.json'), 'utf8'));
const LANGS = ['EN', 'FR'];

LANGS.forEach((lang, i) => {
  const out = {};
  for (const [k, v] of Object.entries(src)) out[k] = v[i] || v[0];
  const dir = path.join(ROOT, '42', 'media', 'lua', 'shared', 'Translate', lang);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'UI.json'), JSON.stringify(out, null, 4) + '\n');
});

// usage check
const used = new Set();
(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p);
    else if (p.endsWith('.lua')) {
      for (const m of fs.readFileSync(p, 'utf8').matchAll(/"(UI_N26_[A-Za-z0-9_]+)"/g)) used.add(m[1]);
    }
  }
})(path.join(ROOT, '42', 'media', 'lua'));
const missing = [...used].filter((k) => !src[k] && !k.endsWith('_'));
console.log(`i18n: ${Object.keys(src).length} keys x ${LANGS.length} languages`);
if (missing.length) {
  console.log('MISSING keys: ' + missing.join(', '));
  process.exit(1);
}
