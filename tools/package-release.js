// Prepare local artifacts only. Never contacts GitHub or Steam.
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { zipSync } = require('fflate');
const root = path.resolve(__dirname, '..');
const id = 'N26_UIOverhaul';
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');
const info = Object.fromEntries(read('42/mod.info').split(/\r?\n/).filter(s => s.includes('=')).map(s => {
  const i = s.indexOf('='); return [s.slice(0, i), s.slice(i + 1)];
}));
const pkg = JSON.parse(read('package.json'));
function assert(ok, message) { if (!ok) throw new Error(message); }
assert(info.id === id, 'Unexpected mod ID');
assert(/^\d+\.\d+\.\d+$/.test(info.modversion), 'Invalid mod version');
assert(pkg.version === info.modversion, 'package.json and mod.info versions differ');
assert(read('42/media/lua/client/N26/Core/N26_Core.lua').includes(`N26.VERSION = "${pkg.version}"`), 'Lua version differs');
assert(read('publishing/workshop.txt').includes(`V${pkg.version}`), 'Workshop description version differs');
assert(read('publishing/RELEASE_NOTES.md').includes(`v${pkg.version}`), 'Release notes version differs');
const translations = JSON.parse(read('tools/src/i18n.json'));
for (const [i, lang] of ['EN', 'FR'].entries()) {
  const built = JSON.parse(read(`42/media/lua/shared/Translate/${lang}/UI.json`));
  assert(Object.keys(built).length === Object.keys(translations).length, `Unexpected ${lang} translation keys`);
  for (const [key, values] of Object.entries(translations)) assert(built[key] === (values[i] || values[0]), `Outdated ${lang} key: ${key}`);
}
for (const [file, size] of [['42/poster.png', 512], ['42/icon.png', 128], ['publishing/preview.png', 256]]) {
  const png = fs.readFileSync(path.join(root, file));
  assert(png.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10])), `Invalid PNG: ${file}`);
  assert(png.readUInt32BE(16) === size && png.readUInt32BE(20) === size, `Wrong image size: ${file}`);
  if (file.includes('preview')) assert(png.length <= 1000000, 'Workshop preview exceeds 1000 KB');
}
const source = {}, runtime = {};
const dirs = ['42', 'common', 'tools', 'tests', 'docs', 'publishing', '.github'];
const rootFiles = ['README.md', 'CHANGELOG.md', 'THIRD_PARTY_NOTICES.md', '.gitignore', '.gitattributes', 'package.json', 'package-lock.json'];
if (fs.existsSync(path.join(root, 'LICENSE'))) rootFiles.push('LICENSE');
function walk(rel) {
  for (const e of fs.readdirSync(path.join(root, rel), { withFileTypes: true })) {
    const p = `${rel}/${e.name}`;
    assert(!e.isSymbolicLink(), `Symlinks cannot be packaged: ${p}`);
    if (p === 'tests/out' || e.name === 'node_modules' || e.name === '.git') continue;
    if (e.isDirectory()) walk(p);
    else if (e.isFile()) source[p] = fs.readFileSync(path.join(root, p));
  }
}
for (const dir of dirs) walk(dir);
for (const file of rootFiles) source[file] = fs.readFileSync(path.join(root, file));
for (const [file, data] of Object.entries(source)) {
  if (file.startsWith('42/') || file.startsWith('common/')) runtime[`${id}/${file}`] = data;
}
runtime[`${id}/README.md`] = source['publishing/INSTALL.md'];
for (const file of ['CHANGELOG.md', 'THIRD_PARTY_NOTICES.md', 'LICENSE']) {
  if (source[file]) runtime[`${id}/${file}`] = source[file];
}
assert(Object.keys(runtime).some(p => p.endsWith('/42/media/lua/client/N26/N26_Boot.lua')), 'Runtime entry point missing');
assert(!Object.keys(runtime).some(p => /\/(tests|tools|node_modules|Saves|Logs)\//.test(p)), 'Development/private files in runtime');
const workshop = {
  'workshop.txt': source['publishing/workshop.txt'],
  'preview.png': source['publishing/preview.png'],
};
for (const [file, data] of Object.entries(runtime)) workshop[`Contents/mods/${file}`] = data;
console.log(`Release ${pkg.version}: ${Object.keys(runtime).length} runtime files, ${Object.keys(source).length} source files; validation passed`);
if (process.argv.includes('--check')) process.exit(0);
const dist = path.join(root, 'dist');
fs.mkdirSync(dist, { recursive: true });
function zip(filename, files) { fs.writeFileSync(path.join(dist, filename), zipSync(files, { level: 6 })); }
zip(`${id}-${pkg.version}.zip`, runtime);
zip(`${id}-source-${pkg.version}.zip`, Object.fromEntries(Object.entries(source).map(([p, b]) => [`${id}/${p}`, b])));
zip(`${id}-workshop-${pkg.version}.zip`, Object.fromEntries(Object.entries(workshop).map(([p, b]) => [`${id}/${p}`, b])));
const sums = fs.readdirSync(dist).filter(p => p.endsWith(`-${pkg.version}.zip`)).sort().map(p =>
  `${crypto.createHash('sha256').update(fs.readFileSync(path.join(dist, p))).digest('hex')}  ${p}`);
fs.writeFileSync(path.join(dist, `SHA256SUMS-${pkg.version}.txt`), sums.join('\n') + '\n');
if (process.argv.includes('--stage-workshop')) {
  const target = path.resolve(os.homedir(), 'Zomboid', 'Workshop', id);
  // Refuse to overwrite an existing item or its persistent Steam ID. A fresh
  // folder is prepared once; subsequent updates can use the Workshop ZIP.
  assert(!fs.existsSync(target), `Workshop folder already exists; preserve its workshop.txt/ID and update from the ZIP: ${target}`);
  for (const [rel, data] of Object.entries(workshop)) {
    const out = path.resolve(target, rel);
    assert(out.startsWith(target + path.sep), 'Invalid Workshop output path');
    fs.mkdirSync(path.dirname(out), { recursive: true }); fs.writeFileSync(out, data);
  }
  console.log(`Workshop item prepared (private): ${target}`);
}
console.log(`Artifacts: ${dist}`);
