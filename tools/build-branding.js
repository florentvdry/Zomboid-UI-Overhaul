// Code-drawn branding, using the same fonts, icon sources and palette as the mod.
// Reads the current public name and version; does not edit an existing image.
'use strict';
const fs = require('fs');
const path = require('path');
const { createCanvas, GlobalFonts, Path2D } = require('@napi-rs/canvas');
const root = path.resolve(__dirname, '..');
const info = fs.readFileSync(path.join(root, '42/mod.info'), 'utf8');
const name = /^name=(.+)$/m.exec(info)[1].trim();
const version = /^modversion=(.+)$/m.exec(info)[1].trim();
const build = /^versionMin=(.+)$/m.exec(info)[1].trim();
GlobalFonts.registerFromPath(path.join(__dirname, 'src/fonts/BarlowCondensed-600-latin.woff2'), 'N26Brand');
GlobalFonts.registerFromPath(path.join(__dirname, 'src/fonts/Inter-600-latin.woff2'), 'N26BrandSmall');
const icons = JSON.parse(fs.readFileSync(path.join(__dirname, 'src/icons.json'), 'utf8'));
function draw(size, file) {
  const canvas = createCanvas(size, size), g = canvas.getContext('2d');
  g.scale(size / 256, size / 256);
  const bg = g.createRadialGradient(130, 60, 5, 130, 60, 290);
  bg.addColorStop(0, '#2c3629'); bg.addColorStop(1, '#0b0e0a');
  g.fillStyle = bg; g.fillRect(0, 0, 256, 256);
  for (const [i, key] of ['heart', 'bag', 'map', 'hammer'].entries()) {
    g.save(); g.translate(24 + i * 30, 24); g.scale(0.75, 0.75);
    g.strokeStyle = '#C9CEC6'; g.lineWidth = 1.6; g.lineCap = 'round'; g.lineJoin = 'round';
    g.stroke(new Path2D(icons[key])); g.restore();
  }
  g.fillStyle = '#E8A33D'; g.fillRect(20, 72, 3, 117);
  const words = name.replace(/^N26\s*/i, '').toUpperCase().split(/\s+/);
  const lines = words.length > 1 ? [words[0], words.slice(1).join(' ')] : words;
  for (const [i, line] of lines.entries()) {
    let px = 45;
    do { g.font = `${px}px N26Brand`; if (g.measureText(line).width <= 202) break; px--; } while (px > 15);
    g.fillStyle = i ? '#E8A33D' : '#E8EAE6';
    g.fillText(line, 32, 116 + i * 47);
  }
  g.fillStyle = '#C9CEC6'; g.font = '10px N26BrandSmall';
  g.fillText(`V${version}  /  BUILD ${build}+`, 24, 218);
  g.fillStyle = '#8E948B'; g.font = '9px N26BrandSmall';
  g.fillText('PROJECT ZOMBOID', 24, 236);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, canvas.toBuffer('image/png'));
}
draw(512, path.join(root, '42/poster.png'));
draw(128, path.join(root, '42/icon.png'));
draw(256, path.join(root, 'publishing/preview.png'));
console.log(`Branding: ${name} ${version}; poster 512, icon 128, Workshop preview 256`);
