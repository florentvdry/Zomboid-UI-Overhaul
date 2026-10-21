/*
 * Snapshot support for the headless harness.
 *
 *  - fontMetricsLua():  real glyph advances / kerning / line heights from the
 *    game's AngelCode fonts (and the mod's), injected into the Lua stubs so text
 *    layout in tests matches the game.
 *  - texDimsLua():      real pixel sizes of every loose UI texture.
 *  - render(snapshot):  replays a recorded draw list into a PNG with the same
 *    textures and bitmap fonts the game would use. Packed textures (UI.pack)
 *    are not available on disk and are drawn as faint placeholders.
 */
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const MOD_MEDIA = path.join(ROOT, '42', 'media');

function gameMedia() {
  return (process.env.PZ_MEDIA || 'E:/SteamLibrary/steamapps/common/ProjectZomboid/media').replace(/\\/g, '/');
}

// ---------------------------------------------------------------- fonts
const FONT_FILES = {
  Small: () => path.join(gameMedia(), 'fonts/EN/1x/zomboidSmall.fnt'),
  Medium: () => path.join(gameMedia(), 'fonts/EN/1x/zomboidMedium.fnt'),
  Large: () => path.join(gameMedia(), 'fonts/EN/1x/zomboidLarge.fnt'),
  Title: () => path.join(gameMedia(), 'fonts/EN/1x/zomboidLarge.fnt'),
  Massive: () => path.join(gameMedia(), 'fonts/EN/1x/zomboidLarge.fnt'),
};
const FONT_ALIAS = { NewSmall: 'Small', NewMedium: 'Medium', NewLarge: 'Large', MediumNew: 'Medium', Code: 'Small', CodeSmall: 'Small', Dialogue: 'Small', Cred1: 'Medium', Cred2: 'Large' };

const fontCache = {};
function parseFnt(file) {
  if (fontCache[file]) return fontCache[file];
  const txt = fs.readFileSync(file, 'utf8');
  const font = { chars: {}, kern: {}, lineHeight: 19, base: 14, page: null };
  for (const line of txt.split(/\r?\n/)) {
    const kv = {};
    for (const m of line.matchAll(/(\w+)=("[^"]*"|\S+)/g)) kv[m[1]] = m[2].replace(/"/g, '');
    if (line.startsWith('common ')) { font.lineHeight = +kv.lineHeight; font.base = +kv.base; }
    else if (line.startsWith('page ')) font.page = path.join(path.dirname(file), kv.file);
    else if (line.startsWith('char ')) {
      font.chars[+kv.id] = { x: +kv.x, y: +kv.y, w: +kv.width, h: +kv.height, xo: +kv.xoffset, yo: +kv.yoffset, adv: +kv.xadvance };
    } else if (line.startsWith('kerning ')) {
      font.kern[(+kv.first) * 65536 + (+kv.second)] = +kv.amount;
    }
  }
  fontCache[file] = font;
  return font;
}

function fontFor(name) {
  name = FONT_ALIAS[name] || name;
  const f = FONT_FILES[name] || FONT_FILES.Small;
  return parseFnt(f());
}

function fontMetricsLua() {
  const parts = [];
  for (const name of Object.keys(FONT_FILES).concat(Object.keys(FONT_ALIAS))) {
    const f = fontFor(name);
    const adv = Object.entries(f.chars).map(([id, c]) => `[${id}]=${c.adv}`).join(',');
    const kern = Object.entries(f.kern).map(([k, v]) => `[${k}]=${v}`).join(',');
    parts.push(`${name}={lineHeight=${f.lineHeight},adv={${adv}},kern={${kern}}}`);
  }
  return 'FONT_METRICS={' + parts.join(',') + '}';
}

// ---------------------------------------------------------------- textures
function pngSize(file) {
  const b = fs.readFileSync(file);
  return [b.readUInt32BE(16), b.readUInt32BE(20)];
}

const texIndex = {};   // "media/ui/..." (lower case) -> absolute file
function indexTextures() {
  if (Object.keys(texIndex).length) return texIndex;
  // game first, then mod (mod overrides like the game's file system)
  for (const base of [gameMedia(), MOD_MEDIA.replace(/\\/g, '/')]) {
    const walk = (d) => {
      if (!fs.existsSync(d)) return;
      for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) walk(p);
        else if (p.toLowerCase().endsWith('.png')) {
          const rel = 'media/' + path.relative(base, p).split(path.sep).join('/');
          texIndex[rel.toLowerCase()] = p;
        }
      }
    };
    walk(path.join(base, 'ui'));
    walk(path.join(base, 'textures'));
  }
  return texIndex;
}

function texDimsLua() {
  const idx = indexTextures();
  const parts = [];
  for (const [rel, file] of Object.entries(idx)) {
    try {
      const [w, h] = pngSize(file);
      parts.push(`[${JSON.stringify(rel)}]={${w},${h}}`);
    } catch (e) { /* unreadable */ }
  }
  return 'TEX_DIMS={' + parts.join(',') + '}';
}

// ---------------------------------------------------------------- renderer
async function render(snap, outFile) {
  const { createCanvas, loadImage } = require('@napi-rs/canvas');
  const idx = indexTextures();
  const images = {};
  async function img(p) {
    if (!p) return null;
    const key = p.toLowerCase();
    if (images[key] !== undefined) return images[key];
    const file = idx[key];
    images[key] = file ? await loadImage(fs.readFileSync(file)) : null;
    return images[key];
  }
  const fontImages = {};
  async function fontImg(font) {
    if (!fontImages[font.page]) fontImages[font.page] = await loadImage(fs.readFileSync(font.page));
    return fontImages[font.page];
  }

  const W = snap.w, H = snap.h;
  const canvas = createCanvas(W, H);
  const g = canvas.getContext('2d');
  // backdrop: same radial "world" as the design boards
  const bg = g.createRadialGradient(W / 2, H * 0.3, 10, W / 2, H * 0.3, Math.max(W, H) * 0.8);
  bg.addColorStop(0, '#2c3629'); bg.addColorStop(0.6, '#161c14'); bg.addColorStop(1, '#0b0e0a');
  g.fillStyle = bg; g.fillRect(0, 0, W, H);

  const scratch = createCanvas(4, 4);
  function tinted(image, w, h, r, gg, b) {
    w = Math.max(1, Math.round(w)); h = Math.max(1, Math.round(h));
    scratch.width = w; scratch.height = h;
    const s = scratch.getContext('2d');
    s.clearRect(0, 0, w, h);
    s.drawImage(image, 0, 0, w, h);
    if (!(r === 1 && gg === 1 && b === 1)) {
      s.globalCompositeOperation = 'multiply';
      s.fillStyle = `rgb(${r * 255},${gg * 255},${b * 255})`;
      s.fillRect(0, 0, w, h);
      s.globalCompositeOperation = 'destination-in';
      s.drawImage(image, 0, 0, w, h);
      s.globalCompositeOperation = 'source-over';
    }
    return scratch;
  }
  const rgba = (r, gg, b, a) => `rgba(${Math.round(r * 255)},${Math.round(gg * 255)},${Math.round(b * 255)},${a})`;

  async function drawString(fontName, str, x, y, r, gg, b, a, zoom, align) {
    const font = fontFor(fontName);
    const atlas = await fontImg(font);
    const cps = Array.from(String(str)).map((c) => c.codePointAt(0));
    let width = 0, prev = null;
    for (const cp of cps) { const c = font.chars[cp] || font.chars[63]; if (c) width += c.adv; if (prev && font.kern[prev * 65536 + cp]) width += font.kern[prev * 65536 + cp]; prev = cp; }
    if (align === 'center') x -= (width * zoom) / 2;
    if (align === 'right') x -= width * zoom;
    const tw = Math.ceil(width * zoom) + 4, th = Math.ceil(font.lineHeight * zoom) + 4;
    const tc = createCanvas(tw, th); const t = tc.getContext('2d');
    let pen = 0; prev = null;
    for (const cp of cps) {
      const c = font.chars[cp] || font.chars[63];
      if (!c) continue;
      if (prev && font.kern[prev * 65536 + cp]) pen += font.kern[prev * 65536 + cp];
      if (c.w > 0 && c.h > 0) t.drawImage(atlas, c.x, c.y, c.w, c.h, (pen + c.xo) * zoom, c.yo * zoom, c.w * zoom, c.h * zoom);
      pen += c.adv; prev = cp;
    }
    t.globalCompositeOperation = 'source-in';
    t.fillStyle = rgba(r, gg, b, 1);
    t.fillRect(0, 0, tw, th);
    g.globalAlpha = a;
    g.drawImage(tc, Math.round(x), Math.round(y));
    g.globalAlpha = 1;
  }

  let stencil = 0;
  const unknown = {};
  for (const rec of snap.records) {
    const k = rec.k, A = rec.a;
    const ox = rec.ax + (rec.sx || 0), oy = rec.ay + (rec.sy || 0);
    switch (k) {
      case 'stencil': {
        g.save(); stencil++;
        g.beginPath(); g.rect(rec.ax + A[0], rec.ay + A[1], A[2], A[3]); g.clip();
        break;
      }
      case 'clearStencil':
        if (stencil > 0) { g.restore(); stencil--; }
        break;
      case 'DrawTextureScaledColor': {
        const [tex, x, y, w, h, r, gg, b, a] = A;
        if (!tex) { g.fillStyle = rgba(r, gg, b, a); g.fillRect(ox + x, oy + y, w, h); break; }
        const im = await img(tex.path || tex);
        if (!im) { g.strokeStyle = 'rgba(255,0,255,0.25)'; g.strokeRect(ox + x + 0.5, oy + y + 0.5, w - 1, h - 1); break; }
        g.globalAlpha = a; g.drawImage(tinted(im, w, h, r, gg, b), ox + x, oy + y); g.globalAlpha = 1;
        break;
      }
      case 'DrawTextureScaled': {
        const [tex, x, y, w, h, a] = A;
        const im = tex && await img(tex.path || tex);
        if (!im) break;
        g.globalAlpha = a; g.drawImage(im, ox + x, oy + y, w, h); g.globalAlpha = 1;
        break;
      }
      case 'DrawTextureScaledAspect': case 'DrawTextureScaledAspect2': case 'DrawTextureScaledAspect3': {
        const [tex, x, y, w, h, r, gg, b, a] = A;
        const im = tex && await img(tex.path || tex);
        if (!im) break;
        const s = Math.min(w / im.width, h / im.height);
        const dw = im.width * s, dh = im.height * s;
        g.globalAlpha = a; g.drawImage(tinted(im, dw, dh, r, gg, b), ox + x + (w - dw) / 2, oy + y + (h - dh) / 2); g.globalAlpha = 1;
        break;
      }
      case 'DrawTexture': case 'DrawTextureColor': {
        const tex = A[0];
        const im = tex && await img(tex.path || tex);
        if (!im) break;
        const [x, y] = [A[1], A[2]];
        const col = k === 'DrawTextureColor' ? A.slice(3, 7) : [1, 1, 1, A[3]];
        g.globalAlpha = col[3]; g.drawImage(tinted(im, im.width, im.height, col[0], col[1], col[2]), ox + x, oy + y); g.globalAlpha = 1;
        break;
      }
      case 'DrawText': {
        if (A.length >= 9) { const [font, str, x, y, zoom, r, gg, b, a] = A; await drawString(font, str, ox + x, oy + y, r, gg, b, a, zoom); }
        else { const [font, str, x, y, r, gg, b, a] = A; await drawString(font, str, ox + x, oy + y, r, gg, b, a, 1); }
        break;
      }
      case 'DrawTextCentre': { const [font, str, x, y, r, gg, b, a] = A; await drawString(font, str, ox + x, oy + y, r, gg, b, a, 1, 'center'); break; }
      case 'DrawTextRight': { const [font, str, x, y, r, gg, b, a] = A; await drawString(font, str, ox + x, oy + y, r, gg, b, a, 1, 'right'); break; }
      case 'DrawPolygon': {
        const [tex, x1, y1, x2, y2, x3, y3, x4, y4, r, gg, bb, a] = A;
        g.fillStyle = rgba(r, gg, bb, a);
        g.beginPath();
        g.moveTo(ox + x1, oy + y1); g.lineTo(ox + x2, oy + y2); g.lineTo(ox + x3, oy + y3); g.lineTo(ox + x4, oy + y4);
        g.closePath(); g.fill();
        break;
      }
      default: unknown[k] = (unknown[k] || 0) + 1;
    }
  }
  while (stencil-- > 0) g.restore();
  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  fs.writeFileSync(outFile, canvas.toBuffer('image/png'));
  return unknown;
}

module.exports = { fontMetricsLua, texDimsLua, render };
