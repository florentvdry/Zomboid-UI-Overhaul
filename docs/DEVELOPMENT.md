# Development

Requires Node.js 20+ and a local Project Zomboid installation for behavior tests.
Players do not need Node.js.

```powershell
npm ci
npm run i18n
npm run branding
npm run lint
npm run check:release
```

Set the game paths before running tests (adapt to your installation):

```powershell
$env:PZ_LUA = 'E:\SteamLibrary\steamapps\common\ProjectZomboid\media\lua'
$env:PZ_MEDIA = 'E:\SteamLibrary\steamapps\common\ProjectZomboid\media'
npm test
```

`npm run test:hub` runs the tactical screen, character, crafting and map tests.
The harness uses real game Lua plus engine doubles. PNG previews go to
`tests/out/`; packed textures and Java-rendered 3D models use placeholders.
These previews are development aids, not in-game screenshots.

## Source layout

- `42/media/lua/client/N26/Core`: hooks, configuration, palette and drawing.
- `42/media/lua/client/N26/Skin`: scoped window/control styling.
- `42/media/lua/client/N26/Modules`: hub and individual tabs.
- `42/media/lua/shared/Translate`: generated EN/FR labels.
- `42/media/ui/N26`: own icons and shapes; no vanilla asset overrides.
- `common`: Build 42 common directory.
- `tools/src/i18n.json`: translation source; regenerate with `npm run i18n`.
- `tools/build-branding.js`: code-drawn poster, icon and Workshop preview,
  using the current display name/version in `42/mod.info`.
- `publishing`: Workshop metadata, preview and release description.

The legacy `tools/build-assets.js` regenerates the icon/shape library from vector
sources. It reads local game UI sizes when present. Run `npm run branding` after
it so the final images match the release metadata.

## Scope and integration

`N26.scopeOf` gates styling to the tactical screen, its docked windows and popups
while open. Hosted windows remain top-level native windows. Geometry and controls
are restored when undocked. The world dimmer excludes their rectangles so it
cannot cover their content during temporary UIManager draw-order changes.

Native craft/build windows supply the recipe engines behind the custom page.
Build placement starts after the menu closes. The map retains its native close
path to release movement blocking and map pause. The hub owns health sizing
while docked to prevent vanilla auto-sizing from fighting the allocated size.

## Release artifacts

```powershell
npm run release
```

The tool checks version consistency, EN/FR translations, PNG dimensions and the
runtime entry point. It writes manual-install, source and Workshop ZIPs plus
SHA-256 sums to `dist/`. Runtime archives include `42`, `common` and user
documentation/license only; developer tools and test outputs stay out.

For a fresh local Workshop staging folder:

```powershell
npm run release -- --stage-workshop
```

This prepares `~/Zomboid/Workshop/N26_UIOverhaul` locally with private visibility.
It does not upload. If the folder exists, the tool refuses to overwrite it;
keep its Steam item ID and update `Contents/mods/N26_UIOverhaul` from the ZIP.
