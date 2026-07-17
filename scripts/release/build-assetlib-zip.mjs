#!/usr/bin/env node
// Godot Asset Library release DRY-RUN (US-EP4).
//
// Stages the plugin into `dist/insimul-godot/` with `addons/insimul/**` at its
// root (the path the Godot editor's AssetLib installer preserves into a project),
// zips it to `dist/insimul-godot-<version>.zip`, and asserts the file set. The
// game-template tree (templates/) is excluded — the Asset Library ships only the
// reusable `addons/insimul` plugin.
//
// This DOES NOT publish. Standalone (Node + zip only, no repo-root deps) so it
// moves verbatim into the future insimul-godot split repo. Run:
//   node scripts/release/build-assetlib-zip.mjs

import { readFileSync, rmSync, mkdirSync, cpSync, existsSync, readdirSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative } from 'node:path';

const PKG_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const DIST = join(PKG_DIR, 'dist');
const FOLDER = 'insimul-godot';
const STAGE = join(DIST, FOLDER);

// Minimal INI read for plugin.cfg version (no deps).
function iniValue(txt, key) {
  const m = txt.match(new RegExp(`^${key}\\s*=\\s*"?([^"\\n]*)"?`, 'm'));
  return m ? m[1].trim() : undefined;
}
const version = iniValue(readFileSync(join(PKG_DIR, 'addons', 'insimul', 'plugin.cfg'), 'utf8'), 'version');

// Members copied into the staged package root.
const INCLUDE = ['addons', 'README.md', 'CHANGELOG.md'];
const FORBIDDEN_DIRS = ['templates', 'dist', '.git', 'node_modules'];

function fail(msg) {
  console.error(`  FAIL ${msg}`);
  return 1;
}
function walk(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const abs = join(dir, name);
    if (statSync(abs).isDirectory()) out.push(...walk(abs));
    else out.push(abs);
  }
  return out;
}

console.log(`godot AssetLib dry-run: staging ${FOLDER} v${version}\n`);

rmSync(DIST, { recursive: true, force: true });
mkdirSync(STAGE, { recursive: true });

for (const member of INCLUDE) {
  const src = join(PKG_DIR, member);
  if (!existsSync(src)) {
    console.error(`\ngodot release:dry-run FAILED: missing source member ${member}`);
    process.exit(1);
  }
  cpSync(src, join(STAGE, member), { recursive: true });
}

const staged = walk(STAGE).map((p) => relative(STAGE, p).split('\\').join('/')).sort();

let problems = 0;
// Required layout — the plugin config + at least one .gd script under addons/insimul.
if (!staged.includes('addons/insimul/plugin.cfg')) problems += fail('staged package missing addons/insimul/plugin.cfg');
// Every committed addons/ file must be present.
const addonFiles = walk(join(PKG_DIR, 'addons')).map((p) => relative(PKG_DIR, p).split('\\').join('/'));
for (const f of addonFiles) {
  if (!staged.includes(f)) problems += fail(`staged package missing addon file: ${f}`);
}
const gd = staged.filter((f) => f.startsWith('addons/insimul/') && f.endsWith('.gd'));
if (gd.length === 0) problems += fail('staged package ships no addons/insimul/*.gd scripts');
// Nothing forbidden leaked in.
for (const f of staged) {
  const top = f.split('/')[0];
  if (FORBIDDEN_DIRS.includes(top)) problems += fail(`staged package contains forbidden entry: ${f}`);
}
if (!version) problems += fail('could not read version from addons/insimul/plugin.cfg');

const zipName = `${FOLDER}-${version}.zip`;
execFileSync('zip', ['-r', '-q', zipName, FOLDER], { cwd: DIST, stdio: 'inherit' });

console.log(`  staged: dist/${FOLDER}/ (${staged.length} files — ${gd.length} .gd scripts)`);
console.log(`  zip:    dist/${zipName}`);

if (problems) {
  console.error(`\ngodot release:dry-run FAILED — ${problems} layout problem(s).`);
  process.exit(1);
}

console.log(`
godot release:dry-run OK — Asset Library zip layout valid.

Asset Library readiness checklist (manual — this script does NOT publish):
  [ ] version ${version} synced in VERSIONS.json / plugin.cfg / asset-lib.json (npm run engines:manifests)
  [ ] git tag / commit hash for the submission pushed to the public repo
  [ ] asset-lib.json fields (title/category/godot_version/icon_url) reviewed against the AssetLib form
  [ ] submission created/updated at godotengine.org/asset-library pointing at the tagged commit
`);
