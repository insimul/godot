#!/usr/bin/env node
// check-ui.mjs — the structural gate for the default-UI panel registry
// (PLATFORM_SPLIT_AND_ENGINE_PLUGINS.md §4.5, tasklist 192).
//
// The headless gate (addons/insimul/tests/run_ui_registry_headless.sh) proves the
// BEHAVIOR — the shared registry / loading-phase cases, the module gate, the
// token mirror — but it needs a Godot binary and skips without one. This gate
// needs nothing but Node, so the claims below hold on every box:
//
//   1. THE MANIFEST IS TOTAL, BOTH WAYS. Every panel key the shared corpus
//      documents (conformance/ui/registry-cases.json → panel_keys) has an entry
//      in addons/insimul/ui/panels.json, and every entry is a documented key. A
//      key in the corpus and not the manifest is a panel the other ports have and
//      this one does not; a key here and not there is a divergence the shared
//      cases will never see.
//
//   2. EVERY PANEL REALLY HAS A SCENE. A default pointing at a scene that does
//      not exist resolves fine and instantiates to null — the registry answers a
//      path, and only `instantiate()` ever finds out. That is exactly the failure
//      a creator reads as "the panel is blank", so the paths are checked as
//      files, and so is the script each scene attaches.
//
//   3. THE MODULE GATE NAMES REAL MODULES. Every id under `requires` is a module
//      in the band-111 activation table (conformance/modules/genre-activation.json)
//      AND is activated by at least one genre bundle. A typo gates a panel off
//      forever; a module no bundle selects is a panel no game can ever show.
//
//   4. THE READER SPELLS NEITHER. insimul_ui_registry.gd may name no panel key
//      and no module id, for the same reason insimul_module_activation.gd may
//      name no module: the panel set and its gates are DATA, and "a creator swaps
//      a panel without an engine code change" is only true while the engine code
//      has nothing to change. Comments are stripped first — unlike
//      check-mechanics.mjs's seventh check, which greps them on purpose. The
//      difference is what the comment is doing: a comment LISTING the panels rots
//      like code, and there is none; a doc comment showing one call is the rule
//      being documented.
//
//   5. THE TOKENS MIRROR THE CORPUS, BOTH WAYS. insimul_ui_tokens.gd is the
//      Godot half of a shared token set; a value that drifts is a parity bug that
//      no test with a hand-written expectation would ever catch.
//
//   6. THE UI LAYER NEEDS NO GDEXTENSION. Nothing under addons/insimul/ui/ may
//      name InsimulCore. The default UI must load in a project with no native
//      build — that is what lets the headless gate stage the UI alone and treat
//      ANY parse error as a UI bug, and what keeps a menu from going dark because
//      the extension is missing.
//
// Every check has a NEGATIVE CONTROL under --self-test: the gate breaks its own
// input and demands the check goes red. A gate that cannot fail is worse than no
// gate.
//
// Usage:
//   node tools/verify-ui/check-ui.mjs
//   node tools/verify-ui/check-ui.mjs --self-test   (adds the controls)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '../..');
const UI_DIR = path.join(REPO, 'addons', 'insimul', 'ui');
const MANIFEST = path.join(UI_DIR, 'panels.json');
const REGISTRY_GD = path.join(UI_DIR, 'insimul_ui_registry.gd');
const TOKENS_GD = path.join(UI_DIR, 'insimul_ui_tokens.gd');
const REGISTRY_CASES = path.join(REPO, 'conformance', 'ui', 'registry-cases.json');
const THEME_TOKENS = path.join(REPO, 'conformance', 'ui', 'theme-tokens.json');
const ACTIVATION_TABLE = path.join(REPO, 'conformance', 'modules', 'genre-activation.json');

/** A res:// path, resolved against this repo. */
const RES_PREFIX = 'res://';
function resToRepo(ref) {
  return ref.startsWith(RES_PREFIX) ? path.join(REPO, ref.slice(RES_PREFIX.length)) : null;
}

let checks = 0;
let failures = 0;
function check(ok, what, detail) {
  checks += 1;
  if (ok) return true;
  failures += 1;
  console.error(`  FAIL  ${what}${detail ? ` — ${detail}` : ''}`);
  return false;
}

function read(file) {
  return fs.readFileSync(file, 'utf8');
}

function readJson(file) {
  return JSON.parse(read(file));
}

/** GDScript comments, gone. Strings are left alone — none of them hold a `#`. */
export function stripComments(source) {
  return source
    .split('\n')
    .map((line) => {
      let inString = null;
      for (let i = 0; i < line.length; i += 1) {
        const c = line[i];
        if (inString) {
          if (c === '\\') i += 1;
          else if (c === inString) inString = null;
        } else if (c === '"' || c === "'") inString = c;
        else if (c === '#') return line.slice(0, i);
      }
      return line;
    })
    .join('\n');
}

/**
 * The entries of a `const NAME := { "k": v, ... }` block, as a plain object.
 * Values keep their JSON-ish type: a quoted value is a string, a bare one a
 * number.
 */
export function parseGdConst(source, name) {
  const start = source.indexOf(`const ${name} := {`);
  if (start < 0) return null;
  const open = source.indexOf('{', start);
  let depth = 0;
  let end = -1;
  for (let i = open; i < source.length; i += 1) {
    if (source[i] === '{') depth += 1;
    else if (source[i] === '}') {
      depth -= 1;
      if (depth === 0) {
        end = i;
        break;
      }
    }
  }
  if (end < 0) return null;
  const body = source.slice(open + 1, end);
  const out = {};
  for (const match of body.matchAll(/"([^"]+)"\s*:\s*("([^"]*)"|[-\d.]+)/g)) {
    out[match[1]] = match[2].startsWith('"') ? match[3] : Number(match[2]);
  }
  return out;
}

/** A whole-word occurrence of `name`, the way check-mechanics.mjs looks for one. */
function namesWord(source, name) {
  return new RegExp(`(^|[^A-Za-z0-9_-])${name}([^A-Za-z0-9_-]|$)`).test(source);
}

// ── the checks ───────────────────────────────────────────────────────────────

export function runChecks(input) {
  const { manifest, panelKeys, table, registryText, tokensText, tokens, files, uiSources } = input;
  const panels = manifest.panels ?? {};
  const keys = Object.keys(panels);

  // 1. The manifest and the shared corpus document the same panel set.
  console.log('\n1. the manifest is total, both ways');
  for (const key of panelKeys) {
    check(keys.includes(key), `corpus panel "${key}" is in the shipped manifest`,
      'add it to addons/insimul/ui/panels.json, or the other ports have a panel this one does not');
  }
  for (const key of keys) {
    check(panelKeys.includes(key), `manifest panel "${key}" is documented by the corpus`,
      'conformance/ui/registry-cases.json → panel_keys is the shared list; a key only here diverges');
  }

  // 2. Every default really resolves to a scene, and the scene to a script.
  console.log('\n2. every panel really has a scene');
  for (const [key, entry] of Object.entries(panels)) {
    const ref = entry.scene ?? '';
    if (!check(ref.startsWith(RES_PREFIX), `panel "${key}" declares a res:// scene`, `got "${ref}"`)) continue;
    const rel = ref.slice(RES_PREFIX.length);
    if (!check(files.includes(rel), `panel "${key}" scene exists`, `no such file: ${ref}`)) continue;
    const scene = input.sceneTexts[rel] ?? '';
    for (const match of scene.matchAll(/path="(res:\/\/[^"]+)"/g)) {
      const dep = match[1].slice(RES_PREFIX.length);
      check(files.includes(dep), `panel "${key}" scene resource exists`, `no such file: ${match[1]}`);
    }
  }

  // 3. The gate names modules the activation table really has, and really uses.
  console.log('\n3. the module gate names real modules');
  const activated = new Map();
  for (const [genre, set] of Object.entries(table.genres ?? {})) {
    for (const module of set.modules ?? []) {
      if (!activated.has(module.id)) activated.set(module.id, []);
      activated.get(module.id).push(genre);
    }
  }
  let gatedPanels = 0;
  for (const [key, entry] of Object.entries(panels)) {
    for (const id of entry.requires ?? []) {
      gatedPanels += 1;
      check(activated.has(id), `panel "${key}" gates on module "${id}", which the activation table has`,
        'a module id nobody activates gates the panel off in every game there is');
    }
  }
  check(gatedPanels > 0, 'at least one panel is module-gated',
    'a registry that gates nothing is not resolving through the module registry at all');

  // 4. The reader spells neither a panel nor a module.
  console.log('\n4. the reader spells neither a panel key nor a module id');
  const code = stripComments(registryText);
  for (const key of keys) {
    check(!namesWord(code, key), `insimul_ui_registry.gd does not name panel "${key}"`,
      'the panel set is data; a reader that spells a panel stops answering when a creator adds one');
  }
  for (const id of activated.keys()) {
    check(!namesWord(code, id), `insimul_ui_registry.gd does not name module "${id}"`,
      'the gate is data; a reader that spells a module stops answering when core adds one');
  }

  // 5. The Godot token set IS the shared token set.
  console.log('\n5. the tokens mirror the shared corpus, both ways');
  const GROUPS = { colors: 'COLORS', spacing: 'SPACING', radius: 'RADIUS', font_size: 'FONT_SIZE' };
  for (const [group, constName] of Object.entries(GROUPS)) {
    const shared = tokens[group] ?? {};
    const mine = parseGdConst(tokensText, constName);
    if (!check(mine !== null, `insimul_ui_tokens.gd declares const ${constName}`)) continue;
    for (const [name, value] of Object.entries(shared)) {
      check(String(mine[name]) === String(value), `token ${group}.${name} mirrors the corpus`,
        `corpus "${value}", godot "${mine[name]}"`);
    }
    for (const name of Object.keys(mine)) {
      check(name in shared, `token ${group}.${name} is in the shared set`,
        'a token only Godot has is a token the other ports cannot mirror');
    }
  }

  // 6. The default UI loads without the GDExtension.
  console.log('\n6. the UI layer needs no GDExtension');
  for (const [file, source] of Object.entries(uiSources)) {
    check(!namesWord(stripComments(source), 'InsimulCore'), `${file} does not call into InsimulCore`,
      'the default UI must load in a project with no native build');
  }

  return failures;
}

// ── driver ───────────────────────────────────────────────────────────────────

/** Every file under addons/insimul/ui/, repo-relative with forward slashes. */
function listUiFiles() {
  const out = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else out.push(path.relative(REPO, full).split(path.sep).join('/'));
    }
  };
  walk(UI_DIR);
  return out;
}

function readInput() {
  const files = listUiFiles();
  const sceneTexts = {};
  const uiSources = {};
  for (const rel of files) {
    if (rel.endsWith('.tscn')) sceneTexts[rel] = read(path.join(REPO, rel));
    if (rel.endsWith('.gd')) uiSources[rel] = read(path.join(REPO, rel));
  }
  return {
    manifest: readJson(MANIFEST),
    panelKeys: readJson(REGISTRY_CASES).panel_keys ?? [],
    table: readJson(ACTIVATION_TABLE),
    tokens: readJson(THEME_TOKENS),
    registryText: read(REGISTRY_GD),
    tokensText: read(TOKENS_GD),
    files,
    sceneTexts,
    uiSources,
  };
}

const input = readInput();
console.log('check-ui: the default-UI panel registry');
runChecks(input);

if (process.argv.includes('--self-test')) {
  console.log('\n7. negative controls');
  const controls = [
    ['the manifest check fails when a documented panel is dropped', (i) => {
      const panels = { ...i.manifest.panels };
      delete panels[i.panelKeys[0]];
      return { ...i, manifest: { ...i.manifest, panels } };
    }],
    ['the manifest check fails when a panel nobody documents is added', (i) => ({
      ...i,
      manifest: { ...i.manifest, panels: { ...i.manifest.panels, invented: { scene: 'res://x.tscn' } } },
    })],
    ['the scene check fails when a default points nowhere', (i) => {
      const key = Object.keys(i.manifest.panels)[0];
      const panels = { ...i.manifest.panels, [key]: { ...i.manifest.panels[key], scene: 'res://gone.tscn' } };
      return { ...i, manifest: { ...i.manifest, panels } };
    }],
    ['the scene check fails when a scene attaches a script that is not there', (i) => {
      const rel = Object.keys(i.sceneTexts).find((r) => i.sceneTexts[r].includes('path="res://'));
      return {
        ...i,
        sceneTexts: { ...i.sceneTexts, [rel]: i.sceneTexts[rel].replace(/path="res:\/\/[^"]+"/, 'path="res://gone.gd"') },
      };
    }],
    ['the gate check fails on a module the activation table does not have', (i) => {
      const key = Object.keys(i.manifest.panels).find((k) => (i.manifest.panels[k].requires ?? []).length > 0);
      const panels = { ...i.manifest.panels, [key]: { ...i.manifest.panels[key], requires: ['not-a-module'] } };
      return { ...i, manifest: { ...i.manifest, panels } };
    }],
    ['the gate check fails when nothing is module-gated at all', (i) => {
      const panels = {};
      for (const [key, entry] of Object.entries(i.manifest.panels)) {
        const { requires, ...rest } = entry;
        panels[key] = rest;
      }
      return { ...i, manifest: { ...i.manifest, panels } };
    }],
    ['the reader check fails when the registry spells a panel key', (i) => ({
      ...i,
      registryText: `${i.registryText}\nfunc _shortcut() -> String:\n\treturn _defaults["${i.panelKeys[0]}"]\n`,
    })],
    ['the reader check fails when the registry spells a module id', (i) => ({
      ...i,
      registryText: `${i.registryText}\nfunc _trades() -> bool:\n\treturn _active_modules.has("equipment")\n`,
    })],
    ['the token check fails on a drifted colour', (i) => ({
      ...i,
      tokensText: i.tokensText.replace(
        `"accent": "${i.tokens.colors.accent}"`,
        '"accent": "#ff00ff"',
      ),
    })],
    ['the token check fails on a token only Godot has', (i) => ({
      ...i,
      tokensText: i.tokensText.replace('const RADIUS := {', 'const RADIUS := {"xxl": 99, '),
    })],
    ['the no-GDExtension check fails when the UI calls into the native core', (i) => {
      const file = Object.keys(i.uiSources)[0];
      return { ...i, uiSources: { ...i.uiSources, [file]: `${i.uiSources[file]}\nvar core := InsimulCore.new()\n` } };
    }],
  ];
  const quiet = { log: console.log, error: console.error };
  for (const [what, mutate] of controls) {
    console.log = () => {};
    console.error = () => {};
    const beforeFailures = failures;
    const beforeChecks = checks;
    const broke = runChecks(mutate(input)) - beforeFailures;
    failures = beforeFailures;
    checks = beforeChecks;
    console.log = quiet.log;
    console.error = quiet.error;
    check(broke > 0, `negative control: ${what}`, 'the gate stayed green on broken input');
  }
}

console.log(`\ncheck-ui: ${checks} check(s), ${failures} failure(s)`);
process.exit(failures > 0 ? 1 : 0);
