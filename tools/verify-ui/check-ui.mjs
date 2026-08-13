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
//      in addons/insimul/ui/panels.json, and every PINNED entry is a documented
//      key. A key in the corpus and not the manifest is a panel the other ports
//      have and this one does not; a pinned key here and not there is a
//      divergence the shared cases will never see.
//
//   1b. THE AHEAD-OF-CORPUS TIER IS A WAITING ROOM, NOT A PARKING LOT. US-2 ships
//      panels the shared corpus has no key for yet (skill tree, minimap, fullmap,
//      quickbar, radial menu, notice board, documents). Each carries a
//      `pending_corpus` string saying what has to happen — core adds the key,
//      then `npm run vendor:conformance` — and the gate refuses one whose key the
//      corpus ALREADY documents, so the entry cannot outlive its reason. An
//      ahead-of-corpus panel that gates on nothing must carry a `gate_note`
//      saying which module WOULD back it and why none does: an ungated panel is
//      an answer, not an omission. Same accounting idiom as NOT_ADOPTED in
//      check-mechanics.mjs and NOT_MIRRORED in vendor-conformance.mjs.
//
//   1c. A COMPOSITE'S CHILDREN ARE PANELS. A `children` list (the HUD) names
//      panel keys the manifest itself declares, and never itself — a composite
//      that mounts a key nothing resolves is a HUD with a hole in it, and one
//      that mounts itself does not terminate.
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
//   7. THE PAUSE-MENU TAB MAP IS TOTAL, AND EVERY TAB IS ACCOUNTED FOR. The ESC
//      menu's tab BODIES are manifest data (`pauseMenuTabs`: tab key -> panel
//      key), so the menu resolves them through the registry and each meets the
//      band-111 gate on the way in. Every shipped tab is in exactly one of
//      `pauseMenuTabs` and `pauseMenuTabNotes`, never both and never neither: a
//      tab with no body and no note is a pane that comes up blank, which is the
//      exact failure the registry's diagnostics exist to prevent. Same accounting
//      idiom as the ahead-of-corpus tier.
//
//   8. THE SHIPPED TAB SET IS THE SHARED TAB SET. InsimulPauseMenuModel's
//      DEFAULT_TABS is a mirror of the tab vocabulary the shared cases gate
//      (conformance/ui/pause-menu-cases.json). Every key a case expects to see is
//      shipped, every shipped key is one some case expects, and every case's
//      expectation is in DECLARATION ORDER — the cases pin visibility, and only
//      this holds the order the ports render in.
//
//   9. A RESOLVER SPELLS NO PANEL KEY. Check 4's rule is about the registry, but
//      the registry is not the only file that resolves panels through it: a
//      composite mounts `children`, and the menu shell mounts `tab_panel`s. Any
//      file under ui/ that calls one of those resolvers is held to the same rule,
//      which is how the rule reaches a file this gate was never told about.
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
const MENU_MODEL_GD = path.join(UI_DIR, 'pause_menu_model.gd');
const MENU_CASES = path.join(REPO, 'conformance', 'ui', 'pause-menu-cases.json');
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

/**
 * The repo-relative script a scene attaches, or null. Used to find the file behind
 * a panel key without the manifest having to name it twice.
 */
function scriptOfScene(input, sceneRef) {
  const rel = sceneRef.startsWith(RES_PREFIX) ? sceneRef.slice(RES_PREFIX.length) : null;
  const text = rel ? input.sceneTexts[rel] : null;
  if (!text) return null;
  const match = text.match(/\[ext_resource type="Script" path="res:\/\/([^"]+)"/);
  return match ? match[1] : null;
}

/**
 * The `key` of every entry in a `const NAME: Array = [ {"key": ...}, ... ]` block,
 * in declaration order. The shipped tab set is a code-level table because it
 * mirrors core's; check 8 is what holds it to the shared cases.
 */
export function parseGdTabKeys(source, name) {
  const start = source.indexOf(`const ${name}`);
  if (start < 0) return null;
  const open = source.indexOf('[', start);
  if (open < 0) return null;
  let depth = 0;
  let end = -1;
  for (let i = open; i < source.length; i += 1) {
    if (source[i] === '[') depth += 1;
    else if (source[i] === ']') {
      depth -= 1;
      if (depth === 0) {
        end = i;
        break;
      }
    }
  }
  if (end < 0) return null;
  return [...source.slice(open, end).matchAll(/"key"\s*:\s*"([^"]+)"/g)].map((m) => m[1]);
}

/**
 * The registry methods that hand a file OTHER panels to mount. A ui/ file that
 * calls one is a resolver, and lives under check 4's rule.
 */
const RESOLVER_CALLS = ['.children(', '.tab_panel(', '.tab_panels('];

/** A whole-word occurrence of `name`, the way check-mechanics.mjs looks for one. */
function namesWord(source, name) {
  return new RegExp(`(^|[^A-Za-z0-9_-])${name}([^A-Za-z0-9_-]|$)`).test(source);
}

// ── the checks ───────────────────────────────────────────────────────────────

export function runChecks(input) {
  const { manifest, panelKeys, table, registryText, tokensText, tokens, files, uiSources } = input;
  const { menuModelText, menuCases } = input;
  const panels = manifest.panels ?? {};
  const keys = Object.keys(panels);

  // 1. The manifest and the shared corpus document the same PINNED panel set.
  const pending = keys.filter((key) => String(panels[key].pending_corpus ?? '').trim() !== '');
  const pinned = keys.filter((key) => !pending.includes(key));
  console.log('\n1. the manifest is total, both ways');
  for (const key of panelKeys) {
    check(keys.includes(key), `corpus panel "${key}" is in the shipped manifest`,
      'add it to addons/insimul/ui/panels.json, or the other ports have a panel this one does not');
  }
  for (const key of pinned) {
    check(panelKeys.includes(key), `pinned panel "${key}" is documented by the corpus`,
      'conformance/ui/registry-cases.json → panel_keys is the shared list; a pinned key only here diverges');
  }
  check(pinned.length === panelKeys.length, 'the pinned tier is exactly the shared panel set',
    `${pinned.length} pinned vs ${panelKeys.length} documented`);

  // 1b. The ahead-of-corpus tier accounts for itself.
  console.log('\n1b. the ahead-of-corpus tier is a waiting room');
  for (const key of pending) {
    check(!panelKeys.includes(key), `ahead-of-corpus panel "${key}" is not in the corpus yet`,
      'the corpus documents this key now — drop pending_corpus and let check 1 pin it');
    check(String(panels[key].pending_corpus).trim().length >= 20,
      `ahead-of-corpus panel "${key}" says what it is waiting for`,
      'pending_corpus is the reason, not a flag');
    if ((panels[key].requires ?? []).length === 0) {
      check(String(panels[key].gate_note ?? '').trim().length >= 20,
        `ungated panel "${key}" records why nothing gates it`,
        'name the module that WOULD back it and why it is the wrong answer');
    }
  }

  // 1c. A composite mounts panels the manifest has, and never itself.
  console.log('\n1c. a composite mounts real panels');
  let composites = 0;
  for (const [key, entry] of Object.entries(panels)) {
    const children = entry.children ?? [];
    if (children.length === 0) continue;
    composites += 1;
    for (const child of children) {
      check(keys.includes(child), `composite "${key}" mounts panel "${child}", which the manifest has`,
        'a composite child nothing resolves is a hole in the HUD');
      check(child !== key, `composite "${key}" does not mount itself`, 'that does not terminate');
    }
  }
  check(composites > 0, 'at least one panel is a composite',
    'the HUD mounts its children through the registry — that is how they meet the module gate');
  // A composite is a SECOND resolver, so it lives under check 4's rule too: its
  // layout is manifest data, and a script that spells a child key stops answering
  // the moment a creator re-lays-out the HUD.
  for (const [key, entry] of Object.entries(panels)) {
    if ((entry.children ?? []).length === 0) continue;
    const script = scriptOfScene(input, entry.scene ?? '');
    if (!check(script !== null, `composite "${key}" has a script to mount with`, 'no script on the scene')) continue;
    const source = stripComments(uiSources[script] ?? '');
    for (const panelKey of keys) {
      check(!namesWord(source, panelKey), `${script} does not name panel "${panelKey}"`,
        'a composite reads its children from the manifest like everything else');
    }
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

  // 7. Every shipped tab has a body or a reason it has none — never both, never
  //    neither.
  console.log('\n7. the pause-menu tab map is total');
  const tabPanels = manifest.pauseMenuTabs ?? {};
  const tabNotes = manifest.pauseMenuTabNotes ?? {};
  const shippedTabs = parseGdTabKeys(menuModelText, 'DEFAULT_TABS');
  if (check(shippedTabs !== null && shippedTabs.length > 0,
    'pause_menu_model.gd declares a DEFAULT_TABS table', 'nothing to hold the map against')) {
    for (const tab of shippedTabs) {
      const mapped = tab in tabPanels;
      const noted = tab in tabNotes;
      check(mapped || noted, `tab "${tab}" has a body or a note saying why not`,
        'a tab in neither pauseMenuTabs nor pauseMenuTabNotes comes up blank with nothing to read');
      check(!(mapped && noted), `tab "${tab}" is not in both the map and the notes`,
        'a tab that ships a body does not also get to explain that it has none');
    }
    for (const tab of [...Object.keys(tabPanels), ...Object.keys(tabNotes)]) {
      check(shippedTabs.includes(tab), `the map accounts for tab "${tab}", which the menu ships`,
        'an entry for a tab nobody renders is dead data');
    }
    const closeTab = String(manifest.pauseMenuCloseTab ?? '');
    check(shippedTabs.includes(closeTab), `the close tab "${closeTab}" is a shipped tab`,
      'the menu shell reads this rather than spelling it — a stale value dismisses nothing');
    check(!(closeTab in tabPanels), `the close tab "${closeTab}" mounts no body`,
      'it dismisses the menu; a body behind it would never be seen');
  }
  for (const [tab, key] of Object.entries(tabPanels)) {
    check(keys.includes(key), `tab "${tab}" mounts panel "${key}", which the manifest has`,
      'a tab body nothing resolves is a blank pane');
  }
  for (const [tab, note] of Object.entries(tabNotes)) {
    check(String(note).trim().length >= 20, `tab "${tab}" says why no panel serves it`,
      'the note is the reason, not a flag');
  }
  check(Object.keys(tabPanels).length > 0, 'the ESC menu mounts at least one panel through the registry',
    'a menu that resolves nothing is not resolving through the module registry at all');

  // 8. The shipped tab vocabulary IS the one the shared cases gate.
  console.log('\n8. the shipped tab set mirrors the shared cases');
  if (shippedTabs !== null) {
    const defaultCases = (menuCases.cases ?? []).filter((c) => !c.tabs);
    check(defaultCases.length > 0, 'the shared cases gate the DEFAULT tab set',
      'every case overrides the tabs — nothing pins what ships');
    const expected = new Set();
    for (const c of defaultCases) for (const key of c.expected_visible_keys ?? []) expected.add(key);
    for (const key of expected) {
      check(shippedTabs.includes(key), `the menu ships tab "${key}", which a shared case expects to see`,
        'a tab the other ports show and this one does not is a divergence the cases cannot catch');
    }
    for (const key of shippedTabs) {
      check(expected.has(key), `shipped tab "${key}" is one a shared case expects`,
        'a tab only Godot has renders in one port and not the others');
    }
    for (const c of defaultCases) {
      const want = (c.expected_visible_keys ?? []).filter((k) => shippedTabs.includes(k));
      const got = shippedTabs.filter((k) => (c.expected_visible_keys ?? []).includes(k));
      check(want.join(',') === got.join(','), `case "${c.name}" expects the tabs in declaration order`,
        `corpus [${want}] vs shipped order [${got}]`);
    }
  }

  // 9. Anything that mounts other panels lives under check 4's rule.
  console.log('\n9. a resolver spells no panel key');
  let resolvers = 0;
  for (const [file, source] of Object.entries(uiSources)) {
    if (file === path.relative(REPO, REGISTRY_GD).split(path.sep).join('/')) continue;
    const code = stripComments(source);
    if (!RESOLVER_CALLS.some((call) => code.includes(call))) continue;
    resolvers += 1;
    for (const key of keys) {
      check(!namesWord(code, key), `${file} resolves panels and names none of them ("${key}")`,
        'a file that mounts panels reads which ones from the manifest, like the registry does');
    }
  }
  check(resolvers > 0, 'something resolves panels through the registry',
    'no ui/ file mounts another panel — the composite and the menu shell both should');

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
    menuModelText: read(MENU_MODEL_GD),
    menuCases: readJson(MENU_CASES),
    files,
    sceneTexts,
    uiSources,
  };
}

/** The first ahead-of-corpus panel key — the controls break the tier through it. */
function firstPending(i) {
  return Object.keys(i.manifest.panels).find((k) => i.manifest.panels[k].pending_corpus);
}

/** The first panel that mounts children (the HUD). */
function firstComposite(i) {
  return Object.keys(i.manifest.panels).find((k) => (i.manifest.panels[k].children ?? []).length > 0);
}

const input = readInput();
console.log('check-ui: the default-UI panel registry');
runChecks(input);

if (process.argv.includes('--self-test')) {
  console.log('\n10. negative controls');
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
    ['the waiting-room check fails when an ahead-of-corpus key is already in the corpus', (i) => {
      const key = firstPending(i);
      return { ...i, panelKeys: [...i.panelKeys, key] };
    }],
    ['the waiting-room check fails when pending_corpus is a bare flag', (i) => {
      const key = firstPending(i);
      const panels = { ...i.manifest.panels, [key]: { ...i.manifest.panels[key], pending_corpus: 'soon' } };
      return { ...i, manifest: { ...i.manifest, panels } };
    }],
    ['the waiting-room check fails when an ungated new panel says nothing about why', (i) => {
      const key = Object.keys(i.manifest.panels).find(
        (k) => i.manifest.panels[k].pending_corpus && (i.manifest.panels[k].requires ?? []).length === 0,
      );
      const { gate_note: _dropped, ...rest } = i.manifest.panels[key];
      return { ...i, manifest: { ...i.manifest, panels: { ...i.manifest.panels, [key]: rest } } };
    }],
    ['the composite check fails when the HUD mounts a panel nobody has', (i) => {
      const key = firstComposite(i);
      const entry = { ...i.manifest.panels[key], children: ['not_a_panel'] };
      return { ...i, manifest: { ...i.manifest, panels: { ...i.manifest.panels, [key]: entry } } };
    }],
    ['the composite check fails when the HUD mounts itself', (i) => {
      const key = firstComposite(i);
      const entry = { ...i.manifest.panels[key], children: [key] };
      return { ...i, manifest: { ...i.manifest, panels: { ...i.manifest.panels, [key]: entry } } };
    }],
    ['the composite check fails when its script spells a child key', (i) => {
      const key = firstComposite(i);
      const script = scriptOfScene(i, i.manifest.panels[key].scene);
      const child = i.manifest.panels[key].children[0];
      return {
        ...i,
        uiSources: { ...i.uiSources, [script]: `${i.uiSources[script]}\nfunc _shortcut() -> String:\n\treturn "${child}"\n` },
      };
    }],
    ['the composite check fails when nothing is a composite at all', (i) => {
      const panels = {};
      for (const [key, entry] of Object.entries(i.manifest.panels)) {
        const { children: _dropped, ...rest } = entry;
        panels[key] = rest;
      }
      return { ...i, manifest: { ...i.manifest, panels } };
    }],
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
    ['the tab-map check fails when a tab mounts a panel nobody has', (i) => {
      const tab = Object.keys(i.manifest.pauseMenuTabs)[0];
      const pauseMenuTabs = { ...i.manifest.pauseMenuTabs, [tab]: 'not_a_panel' };
      return { ...i, manifest: { ...i.manifest, pauseMenuTabs } };
    }],
    ['the tab-map check fails when a tab has neither a body nor a note', (i) => {
      const tab = Object.keys(i.manifest.pauseMenuTabNotes).find((t) => t !== i.manifest.pauseMenuCloseTab);
      const { [tab]: _dropped, ...pauseMenuTabNotes } = i.manifest.pauseMenuTabNotes;
      return { ...i, manifest: { ...i.manifest, pauseMenuTabNotes } };
    }],
    ['the tab-map check fails when a tab has both a body and a note', (i) => {
      const tab = Object.keys(i.manifest.pauseMenuTabs)[0];
      const pauseMenuTabNotes = { ...i.manifest.pauseMenuTabNotes, [tab]: 'a reason long enough to pass' };
      return { ...i, manifest: { ...i.manifest, pauseMenuTabNotes } };
    }],
    ['the tab-map check fails on an entry for a tab the menu does not ship', (i) => ({
      ...i,
      manifest: { ...i.manifest, pauseMenuTabs: { ...i.manifest.pauseMenuTabs, ghost: 'inventory' } },
    })],
    ['the tab-map check fails when the close tab is not a shipped tab', (i) => ({
      ...i, manifest: { ...i.manifest, pauseMenuCloseTab: 'not_a_tab' },
    })],
    ['the tab-map check fails when a note is a bare flag', (i) => {
      const tab = Object.keys(i.manifest.pauseMenuTabNotes)[0];
      const pauseMenuTabNotes = { ...i.manifest.pauseMenuTabNotes, [tab]: 'later' };
      return { ...i, manifest: { ...i.manifest, pauseMenuTabNotes } };
    }],
    ['the tab-set check fails when the menu drops a tab the shared cases expect', (i) => ({
      ...i,
      menuModelText: i.menuModelText.replace(/\{"key": "inventory".*\n/, ''),
    })],
    ['the tab-set check fails on a tab only this port ships', (i) => ({
      ...i,
      menuModelText: i.menuModelText.replace('const DEFAULT_TABS: Array = [',
        'const DEFAULT_TABS: Array = [\n\t{"key": "cheats", "label": "Cheats"},'),
    })],
    ['the tab-set check fails when the shipped order contradicts a case', (i) => ({
      ...i,
      menuModelText: i.menuModelText
        .replace('{"key": "journal", "label": "Journal"},', '')
        .replace('{"key": "settings", "label": "Settings"},',
          '{"key": "settings", "label": "Settings"},\n\t{"key": "journal", "label": "Journal"},'),
    })],
    ['the resolver check fails when a menu shell spells a panel key', (i) => {
      const file = Object.keys(i.uiSources).find(
        (f) => f !== 'addons/insimul/ui/insimul_ui_registry.gd'
          && RESOLVER_CALLS.some((call) => stripComments(i.uiSources[f]).includes(call)),
      );
      return {
        ...i,
        uiSources: { ...i.uiSources, [file]: `${i.uiSources[file]}\nfunc _shortcut() -> String:\n\treturn "${i.panelKeys[0]}"\n` },
      };
    }],
    ['the resolver check fails when nothing resolves panels at all', (i) => {
      const uiSources = {};
      for (const [file, source] of Object.entries(i.uiSources)) {
        uiSources[file] = RESOLVER_CALLS.reduce((acc, call) => acc.split(call).join('.gone('), source);
      }
      return { ...i, uiSources };
    }],
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
