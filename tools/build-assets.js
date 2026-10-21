/*
 * Zomboid UI Overhaul — asset generator.
 *
 * Generates every texture and bitmap font shipped by the mod from vector sources
 * (tools/src/icons*.json, tools/src/fonts/*.woff2). Re-run after editing tokens or icons:
 *
 *   npm install @napi-rs/canvas      (once, anywhere on NODE_PATH)
 *   node tools/build-assets.js
 *
 * Nothing here is loaded by the game; only the files written under 42/media are.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { createCanvas, GlobalFonts, Path2D } = require('@napi-rs/canvas');

const ROOT = path.resolve(__dirname, '..');
const SRC = path.join(__dirname, 'src');
const MEDIA = path.join(ROOT, '42', 'media');
const UI = path.join(MEDIA, 'ui');

// ---- Design tokens (must mirror N26_Theme.lua) -------------------------------
const T = {
  text: '#E8EAE6', text2: '#C9CEC6', muted: '#8E948B', dim: '#4F554C',
  panel: 'rgb(13,15,14)', accent: '#E8A33D', ok: '#7FB069', info: '#4CC9F0', danger: '#FF5A5F',
};

GlobalFonts.registerFromPath(path.join(SRC, 'fonts', 'BarlowCondensed-600-latin.woff2'), 'N26Barlow600');
GlobalFonts.registerFromPath(path.join(SRC, 'fonts', 'BarlowCondensed-500-latin.woff2'), 'N26Barlow500');
GlobalFonts.registerFromPath(path.join(SRC, 'fonts', 'Inter-600-latin.woff2'), 'N26Inter');

const ICONS = Object.assign(
  {},
  JSON.parse(fs.readFileSync(path.join(SRC, 'icons.json'), 'utf8')),
  JSON.parse(fs.readFileSync(path.join(SRC, 'icons_extra.json'), 'utf8')),
);
const FILLED = new Set(['starFill', 'play']);

// Only the mod's own namespace (media/ui/N26) is written: the mod no longer
// replaces any vanilla texture or font.
let written = 0;
function out(rel, canvas) {
  if (!rel.startsWith('ui/N26/')) return;
  const p = path.join(MEDIA, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, canvas.toBuffer('image/png'));
  written++;
}

/** Draw a 24-unit icon into ctx, fitted into a size×size box at (x,y). */
function drawIcon(g, name, x, y, size, color, strokeUnits) {
  const d = ICONS[name];
  if (!d) throw new Error('unknown icon ' + name);
  g.save();
  g.translate(x, y);
  g.scale(size / 24, size / 24);
  const p = new Path2D(d);
  if (FILLED.has(name)) {
    g.fillStyle = color;
    g.fill(p);
  } else {
    g.strokeStyle = color;
    g.lineWidth = strokeUnits || 1.6;
    g.lineCap = 'round';
    g.lineJoin = 'round';
    g.stroke(p);
  }
  g.restore();
}

function roundRectPath(g, x, y, w, h, r) {
  g.beginPath();
  g.moveTo(x + r, y);
  g.arcTo(x + w, y, x + w, y + h, r);
  g.arcTo(x + w, y + h, x, y + h, r);
  g.arcTo(x, y + h, x, y, r);
  g.arcTo(x, y, x + w, y, r);
  g.closePath();
}

// ---- 1. Icon set: white strokes, several native sizes for crisp downscaling ---
// Stroke width grows a little at small sizes so 1px lines stay solid after filtering.
const ICON_SIZES = [16, 24, 32, 48, 64];
for (const name of Object.keys(ICONS)) {
  for (const s of ICON_SIZES) {
    const c = createCanvas(s, s);
    const g = c.getContext('2d');
    const stroke = s <= 16 ? 2.0 : s <= 24 ? 1.8 : 1.6;
    drawIcon(g, name, 0, 0, s, '#FFFFFF', stroke);
    out(`ui/N26/icons/${s}/${name}.png`, c);
  }
}

// ---- 2. Shape kit: one quarter (top-left) per radius, flipped at runtime -----
// fill = antialiased solid quarter disc; ring = 1px antialiased quarter outline.
const CORNERS = { tl: [1, 1], tr: [-1, 1], bl: [1, -1], br: [-1, -1] };
for (const r of [2, 3, 4, 6, 8]) {
  for (const [cn, [sx, sy]] of Object.entries(CORNERS)) {
    for (const kind of ['fill', 'ring']) {
      const c = createCanvas(r, r);
      const g = c.getContext('2d');
      // draw the top-left quarter, mirrored into the requested corner
      g.translate(sx < 0 ? r : 0, sy < 0 ? r : 0);
      g.scale(sx, sy);
      if (kind === 'fill') {
        g.fillStyle = '#FFFFFF';
        g.beginPath(); g.moveTo(r, r); g.arc(r, r, r, Math.PI, Math.PI * 1.5); g.closePath(); g.fill();
      } else {
        g.strokeStyle = '#FFFFFF'; g.lineWidth = 1;
        g.beginPath(); g.arc(r, r, r - 0.5, Math.PI, Math.PI * 1.5); g.stroke();
      }
      out(`ui/N26/shape/q${r}_${kind}_${cn}.png`, c);
    }
  }
}
// 1x1 white, soft vertical gradient (for subtle panel sheen), radial vignette.
{
  const c = createCanvas(4, 4); const g = c.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, 4, 4);
  out('ui/N26/shape/white.png', c);
  const gr = createCanvas(4, 64); const gg = gr.getContext('2d');
  const lg = gg.createLinearGradient(0, 0, 0, 64); lg.addColorStop(0, 'rgba(255,255,255,1)'); lg.addColorStop(1, 'rgba(255,255,255,0)');
  gg.fillStyle = lg; gg.fillRect(0, 0, 4, 64);
  out('ui/N26/shape/vgrad.png', gr);
  const hz = createCanvas(64, 4); const hg = hz.getContext('2d');
  const lh = hg.createLinearGradient(0, 0, 64, 0); lh.addColorStop(0, 'rgba(255,255,255,1)'); lh.addColorStop(1, 'rgba(255,255,255,0)');
  hg.fillStyle = lh; hg.fillRect(0, 0, 64, 4);
  out('ui/N26/shape/hgrad.png', hz);
  const rv = createCanvas(256, 256); const rg = rv.getContext('2d');
  const radial = rg.createRadialGradient(128, 128, 20, 128, 128, 128);
  radial.addColorStop(0, 'rgba(255,255,255,1)'); radial.addColorStop(1, 'rgba(255,255,255,0)');
  rg.fillStyle = radial; rg.fillRect(0, 0, 256, 256);
  out('ui/N26/shape/radial.png', rv);
  // Body silhouette parts for the health screen (white, tinted at runtime).
}

// ---- 3. Moodles (Java-rendered; we replace textures only) --------------------
// BGsolid is tinted by the engine with the good/bad level colour: a dark interior
// and a bright rim make the tint read as a coloured 1px border, as on board 05.
const MOODLE_DIRS = { 32: 32, 48: 48, 64: 64, 80: 80, 96: 96, 128: 126 };
const MOODLE_ICONS = {
  'Status_Hunger': 'fork', 'Status_Thirst': 'drop', 'Mood_Sleepy': 'moon', 'Mood_Exhausted': 'run',
  'Status_Bleeding': 'blood', 'Mood_Pained': 'pain', 'Status_Wet': 'umb', 'Mood_Stressed': 'bolt',
  'Mood_Bored': 'clock', 'Mood_Sad': 'sad', 'Mood_Happy': 'happy', 'Mood_Angry': 'angry',
  'Mood_Panicked': 'scared', 'Mood_Scared': 'scared', 'Mood_Ill': 'virus', 'Mood_Nauseous': 'swirl',
  'Mood_Drunk': 'bottle', 'Mood_Hungover': 'hangover', 'Mood_Dizzy': 'swirl', 'Mood_NoxiousSmell': 'cloud',
  'Mood_Discomfort': 'warn', 'Mood_Concentrating': 'target', 'Mood_Dead': 'skull', 'Mood_Zombified': 'skull',
  'Status_InjuredMinor': 'bandage', 'Status_InjuredMajor': 'plus', 'Status_HeavyLoad': 'weight',
  'Status_TemperatureHot': 'thermoUp', 'Status_TemperatureLow': 'thermoDown', 'Status_Windchill': 'wind',
  'Status_HearingImpaired': 'ear', 'Status_VisionImpaired': 'eyeoff', 'Status_DifficultyBreathing': 'lungs',
  'Status_MovementRestricted': 'chain', 'Status_Sedated': 'pill', 'Status_Wired': 'bolt',
};
for (const [dir, s] of Object.entries(MOODLE_DIRS)) {
  const rad = Math.max(3, Math.round(s * 0.14));
  const bw = Math.max(1, Math.round(s / 32));
  // solid: rim (white) + dark interior
  const solid = createCanvas(s, s);
  const g = solid.getContext('2d');
  roundRectPath(g, 0.5, 0.5, s - 1, s - 1, rad);
  g.fillStyle = '#FFFFFF';
  g.fill();
  roundRectPath(g, bw + 0.5, bw + 0.5, s - 2 * bw - 1, s - 2 * bw - 1, Math.max(1, rad - bw));
  g.globalCompositeOperation = 'destination-out';
  g.fillStyle = '#000';
  g.fill();
  g.globalCompositeOperation = 'source-over';
  g.fillStyle = 'rgba(30,30,30,0.86)';
  g.fill();
  out(`ui/Moodles/${dir}/_Moodles_BGsolid.png`, solid);
  // outline: a soft dark halo so tiles separate from bright terrain
  const ol = createCanvas(s, s);
  const go = ol.getContext('2d');
  roundRectPath(go, 0.5, 0.5, s - 1, s - 1, rad);
  go.strokeStyle = 'rgba(0,0,0,0.55)';
  go.lineWidth = 1;
  go.stroke();
  out(`ui/Moodles/${dir}/_Moodles_BGoutline.png`, ol);
  for (const [file, icon] of Object.entries(MOODLE_ICONS)) {
    const c = createCanvas(s, s);
    const gi = c.getContext('2d');
    const isz = Math.round(s * 0.56);
    const off = Math.round((s - isz) / 2);
    drawIcon(gi, icon, off, off, isz, T.text, s <= 32 ? 2.0 : 1.7);
    out(`ui/Moodles/${dir}/${file}.png`, c);
  }
}
// Loose top-level moodle icons (used by a few moodles at a single size).
for (const [file, icon] of [['Moodle_Icon_Windchill', 'wind'], ['Moodle_Icon_CantSprint', 'norun']]) {
  const c = createCanvas(48, 48); const g = c.getContext('2d');
  drawIcon(g, icon, 10, 10, 28, T.text, 1.7);
  out(`ui/${file}.png`, c);
}

// ---- 4. Clock (Java-rendered) ---------------------------------------------------
function clockBg(w, h, rel) {
  const c = createCanvas(w, h); const g = c.getContext('2d');
  roundRectPath(g, 0.5, 0.5, w - 1, h - 1, Math.round(h * 0.12));
  g.fillStyle = 'rgba(13,15,14,0.86)'; g.fill();
  g.strokeStyle = 'rgba(255,255,255,0.12)'; g.lineWidth = 1; g.stroke();
  out(rel, c);
}
clockBg(156, 62, 'ui/ClockAssets/ClockLargeBackground.png');
clockBg(81, 32, 'ui/ClockAssets/ClockSmallBackground.png');
function glyphTile(ch, w, h, px, rel, family) {
  const c = createCanvas(w, h); const g = c.getContext('2d');
  g.fillStyle = '#FFFFFF';
  g.font = `${px}px ${family || 'N26Barlow600'}`;
  g.textAlign = 'center';
  g.textBaseline = 'alphabetic';
  const m = g.measureText(ch);
  const asc = m.actualBoundingBoxAscent, desc = m.actualBoundingBoxDescent;
  const y = Math.round((h + asc - desc) / 2);
  g.fillText(ch, w / 2, y);
  out(rel, c);
}
for (let d = 0; d <= 9; d++) {
  glyphTile(String(d), 18, 34, 38, `ui/ClockAssets/ClockDigitsLarge${d}.png`);
  glyphTile(String(d), 9, 17, 19, `ui/ClockAssets/ClockDigitsMedium${d}.png`);
}
for (const [ch, name] of [['C', 'C'], ['E', 'E'], ['F', 'F']]) glyphTile(ch, 9, 17, 19, `ui/ClockAssets/ClockDigitsMedium${name}.png`);
glyphTile('-', 4, 17, 19, 'ui/ClockAssets/ClockDigitsMediumMinus.png');
glyphTile(':', 6, 34, 34, 'ui/ClockAssets/ClockDivideLarge.png');
glyphTile(':', 4, 17, 17, 'ui/ClockAssets/ClockDivideMedium.png');
glyphTile('/', 5, 17, 17, 'ui/ClockAssets/DateDivideMedium.png');
glyphTile('AM', 22, 10, 12, 'ui/ClockAssets/ClockAmLarge.png', 'N26Barlow600');
glyphTile('PM', 22, 10, 12, 'ui/ClockAssets/ClockPmLarge.png', 'N26Barlow600');
glyphTile('AM', 12, 6, 7, 'ui/ClockAssets/ClockAmMedium.png', 'N26Barlow600');
glyphTile('PM', 12, 6, 7, 'ui/ClockAssets/ClockPmMedium.png', 'N26Barlow600');

// ---- 5. Window / pane buttons (loose files under media/ui/inventoryPanes) -----
function iconTile(w, h, icon, color, rel, frac, stroke) {
  const c = createCanvas(w, h); const g = c.getContext('2d');
  const s = Math.round(Math.min(w, h) * (frac || 0.6));
  drawIcon(g, icon, Math.round((w - s) / 2), Math.round((h - s) / 2), s, color, stroke || 1.8);
  out(rel, c);
}
iconTile(39, 39, 'close', T.text, 'ui/inventoryPanes/Button_Close.png', 0.5, 2.0);
iconTile(39, 39, 'chevU', T.text, 'ui/inventoryPanes/Button_Collapse.png', 0.55, 2.0);
iconTile(39, 39, 'pin', T.text, 'ui/inventoryPanes/Button_Pin.png', 0.6, 1.8);
iconTile(39, 39, 'info', T.text, 'ui/inventoryPanes/Button_Info.png', 0.6, 1.8);
iconTile(39, 39, 'lock', T.accent, 'ui/inventoryPanes/Button_Lock.png', 0.6, 1.8);
iconTile(39, 39, 'lock', T.muted, 'ui/inventoryPanes/Button_LockOpen.png', 0.6, 1.8);
iconTile(61, 61, 'settings', T.text, 'ui/inventoryPanes/Button_Gear.png', 0.55, 1.8);
iconTile(64, 64, 'settings', T.text, 'ui/inventoryPanes/Button_Settings.png', 0.55, 1.8);
iconTile(15, 15, 'chevR', T.text2, 'ui/inventoryPanes/Button_TreeCollapsed.png', 0.9, 2.4);
iconTile(15, 15, 'chevD', T.text2, 'ui/inventoryPanes/Button_TreeExpanded.png', 0.9, 2.4);
iconTile(48, 48, 'starFill', T.accent, 'ui/inventoryPanes/FavouriteYes.png', 0.62);
iconTile(48, 48, 'star', T.dim, 'ui/inventoryPanes/FavouriteNo.png', 0.62, 1.8);
iconTile(64, 64, 'tick', '#FFFFFF', 'ui/inventoryPanes/Tickbox_Tick.png', 0.8, 2.6);
iconTile(64, 64, 'close', T.danger, 'ui/inventoryPanes/Tickbox_Cross.png', 0.7, 2.6);
{ // resize grip: three diagonal dashes
  const c = createCanvas(22, 22); const g = c.getContext('2d');
  g.strokeStyle = 'rgba(232,234,230,0.55)'; g.lineWidth = 1.5; g.lineCap = 'round';
  for (const o of [6, 11, 16]) { g.beginPath(); g.moveTo(20, o); g.lineTo(o, 20); g.stroke(); }
  out('ui/ResizeIcon.png', c);
}
// Radio buttons
{
  const c = createCanvas(16, 16); const g = c.getContext('2d');
  g.strokeStyle = 'rgba(232,234,230,0.5)'; g.lineWidth = 1.2; g.beginPath(); g.arc(8, 8, 6.4, 0, Math.PI * 2); g.stroke();
  out('ui/RadioButtonCircle.png', c);
  const d = createCanvas(16, 16); const gd = d.getContext('2d');
  gd.fillStyle = T.accent; gd.beginPath(); gd.arc(8, 8, 3.6, 0, Math.PI * 2); gd.fill();
  out('ui/RadioButtonIndicator.png', d);
}

// ---- 6. Speed controls (Java) --------------------------------------------------
const SPEED = [
  ['Play', 16, 22, 'play'], ['Pause', 20, 22, 'pause'], ['FFwd1', 26, 22, 'ffwd'], ['FFwd2', 36, 22, 'ffwd2'],
  ['Wait', 22, 22, 'wait'], ['StepForward', 22, 22, 'step'],
];
for (const [name, w, h, icon] of SPEED) {
  for (const [state, col] of [['Off', T.muted], ['On', T.accent]]) {
    if (name === 'StepForward' && state === 'On') continue;
    const c = createCanvas(w, h); const g = c.getContext('2d');
    const s = Math.min(w, h) - 4;
    drawIcon(g, icon, Math.round((w - s) / 2), Math.round((h - s) / 2), s, col, 2.0);
    out(`ui/speedControls/${name}_${state}.png`, c);
  }
}

// ---- 6a. Skill level cells (ISSkillProgressBar tints them) ----------------------
{
  const fill = createCanvas(48, 48); const gf = fill.getContext('2d');
  roundRectPath(gf, 4.5, 4.5, 39, 39, 9); gf.fillStyle = '#FFFFFF'; gf.fill();
  out('ui/SkillPanel/SkillUnit_fill.png', fill);
  const ring = createCanvas(48, 48); const gr = ring.getContext('2d');
  roundRectPath(gr, 5, 5, 38, 38, 9); gr.strokeStyle = '#FFFFFF'; gr.lineWidth = 3; gr.stroke();
  out('ui/SkillPanel/SkillUnit_border.png', ring);
}

// ---- 6b. Sidebar dock (ISEquippedItem) -----------------------------------------
// Dimensions are read from the installed game so every replacement matches.
const GAME_UI = process.env.PZ_MEDIA ? path.join(process.env.PZ_MEDIA, 'ui') : 'E:/SteamLibrary/steamapps/common/ProjectZomboid/media/ui';
function pngSize(file) {
  const b = fs.readFileSync(file);
  return [b.readUInt32BE(16), b.readUInt32BE(20)];
}
const SIDEBAR_ICONS = {
  Inventory: 'bag', Heart: 'heart', Carpentry: 'hammer', Build: 'home', Furniture: 'box', Search: 'leaf',
  AnimalZone: 'fence', Map: 'map', Debug: 'settings', ARF_Icon: 'radio', Client_Icon: 'user2', Admin_Icon: 'shield', War: 'target',
};
const SIDEBAR_SINGLE = {
  Furniture_Pickup: 'hand', Furniture_Place: 'pin', Furniture_Rotate: 'rotate', Furniture_Disassemble: 'saw',
  Furniture_Repair: 'wrench', BuildingRoomsEditor: 'home', HandMain_Off: 'hand', HandSecondary_Off: 'hand',
};
function sidebarTile(w, h, icon, state, rel) {
  const c = createCanvas(w, h); const g = c.getContext('2d');
  const m = Math.max(1, Math.round(Math.min(w, h) * 0.06));
  roundRectPath(g, m + 0.5, m + 0.5, w - 2 * m - 1, h - 2 * m - 1, Math.round(Math.min(w, h) * 0.16));
  if (state === 'On') {
    g.fillStyle = 'rgba(232,163,61,0.16)'; g.fill();
    g.strokeStyle = 'rgba(232,163,61,0.75)'; g.lineWidth = Math.max(1, Math.round(w / 48)); g.stroke();
  } else if (state === 'Off') {
    g.fillStyle = 'rgba(10,12,11,0.62)'; g.fill();
    g.strokeStyle = 'rgba(255,255,255,0.10)'; g.lineWidth = 1; g.stroke();
  } else if (state === 'Hand') {
    g.fillStyle = 'rgba(10,12,11,0.55)'; g.fill();
    g.strokeStyle = 'rgba(255,255,255,0.10)'; g.lineWidth = 1; g.stroke();
  } else {
    g.fillStyle = 'rgba(10,12,11,0.62)'; g.fill();
  }
  const s = Math.round(Math.min(w, h) * 0.56);
  const col = state === 'On' ? T.accent : state === 'Hand' ? 'rgba(232,234,230,0.28)' : T.text2;
  drawIcon(g, icon, Math.round((w - s) / 2), Math.round((h - s) / 2), s, col, w <= 48 ? 1.9 : 1.6);
  out(rel, c);
}
if (fs.existsSync(path.join(GAME_UI, 'Sidebar'))) {
  for (const size of fs.readdirSync(path.join(GAME_UI, 'Sidebar'))) {
    const dir = path.join(GAME_UI, 'Sidebar', size);
    if (!fs.statSync(dir).isDirectory()) continue;
    for (const file of fs.readdirSync(dir)) {
      const [w, h] = pngSize(path.join(dir, file));
      const base = file.replace('_' + size + '.png', '');
      const rel = `ui/Sidebar/${size}/${file}`;
      const m = base.match(/^(.*)_(On|Off)$/);
      if (SIDEBAR_SINGLE[base]) {
        sidebarTile(w, h, SIDEBAR_SINGLE[base], base.startsWith('Hand') ? 'Hand' : 'Off', rel);
      } else if (m && SIDEBAR_ICONS[m[1]]) {
        sidebarTile(w, h, SIDEBAR_ICONS[m[1]], m[2], rel);
      } else if (base === 'Safety_Background') {
        const c = createCanvas(w, h); const g = c.getContext('2d');
        const mm = Math.max(1, Math.round(Math.min(w, h) * 0.06));
        roundRectPath(g, mm + 0.5, mm + 0.5, w - 2 * mm - 1, h - 2 * mm - 1, Math.round(Math.min(w, h) * 0.16));
        g.fillStyle = 'rgba(10,12,11,0.62)'; g.fill();
        g.strokeStyle = 'rgba(255,255,255,0.10)'; g.lineWidth = 1; g.stroke();
        out(rel, c);
      } else if (base === 'Safety_Tintable') {
        const c = createCanvas(w, h); const g = c.getContext('2d');
        const s = Math.round(Math.min(w, h) * 0.56);
        drawIcon(g, 'shield', Math.round((w - s) / 2), Math.round((h - s) / 2), s, '#FFFFFF', 1.8);
        out(rel, c);
      }
    }
  }
} else {
  console.warn('Sidebar textures skipped: game media not found (set PZ_MEDIA)');
}

// ---- 7. Bitmap fonts (AngelCode text format) ----------------------------------
// Title  -> heading font (Barlow Condensed 600) used for window/panel titles.
// Massive -> display font, drawn zoomed for large headings & HUD numerals.
const CHARSET = [];
for (let i = 32; i <= 126; i++) CHARSET.push(i);
for (let i = 160; i <= 255; i++) CHARSET.push(i);
for (const ch of 'ŒœŸ€’‘“”…–—•') CHARSET.push(ch.codePointAt(0));

function buildFont(opts) {
  const { family, px, tracking, file, face, atlas } = opts;
  const probe = createCanvas(8, 8).getContext('2d');
  probe.font = `${px}px ${family}`;
  const mAsc = probe.measureText('ÉÀÇgjpqy|');
  const ascent = Math.ceil(Math.max(mAsc.fontBoundingBoxAscent || 0, mAsc.actualBoundingBoxAscent));
  const descent = Math.ceil(Math.max(mAsc.fontBoundingBoxDescent || 0, mAsc.actualBoundingBoxDescent));
  const lineHeight = ascent + descent;
  const base = ascent;
  const pad = 2;
  const glyphs = [];
  for (const code of CHARSET) {
    const ch = String.fromCodePoint(code);
    const adv = probe.measureText(ch).width;
    const cw = Math.ceil(adv + px), chh = lineHeight + pad * 2;
    const c = createCanvas(cw + pad * 2, chh);
    const g = c.getContext('2d');
    g.font = `${px}px ${family}`;
    g.fillStyle = '#FFFFFF';
    g.textBaseline = 'alphabetic';
    g.fillText(ch, pad, pad + base);
    const img = g.getImageData(0, 0, c.width, c.height).data;
    let minX = c.width, minY = c.height, maxX = -1, maxY = -1;
    for (let y = 0; y < c.height; y++) for (let x = 0; x < c.width; x++) {
      if (img[(y * c.width + x) * 4 + 3] > 2) { if (x < minX) minX = x; if (x > maxX) maxX = x; if (y < minY) minY = y; if (y > maxY) maxY = y; }
    }
    const xadvance = Math.round(adv + tracking);
    if (maxX < 0) { glyphs.push({ code, w: 0, h: 0, xoff: 0, yoff: 0, xadvance, src: null }); continue; }
    glyphs.push({ code, w: maxX - minX + 1, h: maxY - minY + 1, xoff: minX - pad, yoff: minY - pad, xadvance, src: c, sx: minX, sy: minY });
  }
  // shelf pack
  const W = atlas, H = atlas;
  const sheet = createCanvas(W, H); const sg = sheet.getContext('2d');
  let x = 1, y = 1, rowH = 0;
  const sorted = glyphs.filter((gl) => gl.src).sort((a, b) => b.h - a.h);
  for (const gl of sorted) {
    if (x + gl.w + 1 > W) { x = 1; y += rowH + 1; rowH = 0; }
    if (y + gl.h + 1 > H) throw new Error('atlas too small for ' + file);
    sg.drawImage(gl.src, gl.sx, gl.sy, gl.w, gl.h, x, y, gl.w, gl.h);
    gl.x = x; gl.y = y; x += gl.w + 1; rowH = Math.max(rowH, gl.h);
  }
  // empty glyphs (space…) point at a transparent 1px cell in the corner
  for (const gl of glyphs) if (!gl.src) { gl.x = W - 2; gl.y = H - 2; gl.w = 1; gl.h = 1; gl.yoff = lineHeight - 1; }
  // kerning from the shaper: k(a,b) = w(ab) - w(a) - w(b)
  const kern = [];
  const kc = [];
  for (let i = 33; i <= 126; i++) kc.push(i);
  for (const a of kc) for (const b of kc) {
    const sa = String.fromCharCode(a), sb = String.fromCharCode(b);
    const k = Math.round(probe.measureText(sa + sb).width - probe.measureText(sa).width - probe.measureText(sb).width);
    if (k !== 0) kern.push(`kerning first=${a}  second=${b}  amount=${k}`);
  }
  const lines = [];
  lines.push(`info face="${face}" size=${px} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=2 padding=0,0,0,0 spacing=1,1 outline=0`);
  lines.push(`common lineHeight=${lineHeight} base=${base} scaleW=${W} scaleH=${H} pages=1 packed=0 alphaChnl=0 redChnl=4 greenChnl=4 blueChnl=4`);
  lines.push(`page id=0 file="${file}_0.png"`);
  lines.push(`chars count=${glyphs.length}`);
  for (const gl of glyphs.sort((a, b) => a.code - b.code)) {
    lines.push(`char id=${gl.code}   x=${gl.x}   y=${gl.y}   width=${gl.w}   height=${gl.h}   xoffset=${gl.xoff}   yoffset=${gl.yoff}   xadvance=${gl.xadvance}   page=0  chnl=15`);
  }
  lines.push(`kernings count=${kern.length}`);
  for (const k of kern) lines.push(k);
  out(`fonts/EN/${file}_0.png`, sheet);
  return { lineHeight, base, glyphs: glyphs.length, kernings: kern.length };
}
const fontInfo = {
  heading: buildFont({ family: 'N26Barlow600', px: 22, tracking: 1, file: 'n26Heading', face: 'Barlow Condensed SemiBold', atlas: 256 }),
  display: buildFont({ family: 'N26Barlow600', px: 48, tracking: 1, file: 'n26Display', face: 'Barlow Condensed SemiBold', atlas: 512 }),
};

// ---- 8. Mod poster / icon -------------------------------------------------------
function poster(w, h, rel) {
  const c = createCanvas(w, h); const g = c.getContext('2d');
  const bg = g.createRadialGradient(w * 0.5, h * 0.3, 10, w * 0.5, h * 0.3, Math.max(w, h) * 0.8);
  bg.addColorStop(0, '#2c3629'); bg.addColorStop(0.6, '#161c14'); bg.addColorStop(1, '#0b0e0a');
  g.fillStyle = bg; g.fillRect(0, 0, w, h);
  const u = w / 256;
  g.fillStyle = T.accent; g.fillRect(Math.round(22 * u), Math.round(h * 0.36), Math.round(5 * u), Math.round(h * 0.3));
  g.fillStyle = T.text; g.font = `${Math.round(54 * u)}px N26Barlow600`; g.textBaseline = 'alphabetic';
  g.fillText('ZOMBOID', Math.round(36 * u), Math.round(h * 0.5));
  g.fillStyle = T.accent; g.fillText('UI · N26', Math.round(36 * u), Math.round(h * 0.66));
  g.fillStyle = T.muted; g.font = `${Math.round(13 * u)}px N26Inter`;
  g.fillText('TACTICAL UI OVERHAUL · BUILD 42', Math.round(36 * u), Math.round(h * 0.8));
  for (const [i, ic] of ['heart', 'bag', 'map', 'hammer'].entries()) drawIcon(g, ic, Math.round((36 + i * 30) * u), Math.round(h * 0.16), Math.round(20 * u), T.text2, 1.6);
  const p = path.join(ROOT, '42', rel);
  fs.writeFileSync(p, c.toBuffer('image/png'));
  written++;
}
poster(512, 512, 'poster.png');
poster(128, 128, 'icon.png');

console.log(`N26 assets: ${written} files written.`);
console.log('fonts', JSON.stringify(fontInfo));
