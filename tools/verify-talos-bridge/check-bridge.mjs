#!/usr/bin/env node
// check-bridge.mjs — the structural gate for `insimul-talos-bridge`
// (TALOS_INSIMUL_BRIDGE.md §7.5, tasklist 183).
//
// The C++ gate (gdextension/test/run_talos_bridge_tests.sh) proves the DECISIONS.
// This one proves the things a decision cannot see, all of which are ways a
// perfectly correct bridge is still not installed:
//
//   1. THE ARTIFACT IS SEPARATE. §7.5's premise, held literally rather than
//      described: the bridge has its own plugin.cfg, `addons/insimul/` never
//      mentions it, and nothing in it names a Talos symbol. Two of those are
//      checkable by grep and the third is what makes the Godot bridge possible
//      at all — Talos's game-side contract is duck-typed, so a compile-time
//      dependency would be a self-inflicted one.
//
//   2. THE GROUPS AGREE, BOTH WAYS. This is the one thing an installer must get
//      right (§7.4): the adapter's participation is invisible unless
//      `talos.game.yaml` NAMES its groups. A group in the contract and not the
//      manifest is an adapter the Bridge never finds; a group in the manifest and
//      not the contract is a hook nobody implements, and Talos answers that with
//      `no_checkpoint_hooks` — correctly, and after the run started.
//
//   3. THE HOOKS EXIST. Every method and signal the six group contracts name is
//      really defined in the adapter. Duck-typing means a typo here fails at
//      runtime, in someone else's process, as an absence.
//
//   4. THE VERB MAP IS TOTAL. All 25 TBP v1 verbs are accounted for, and every
//      verb this bridge does not answer carries a why-not token rather than a
//      generic failure (§2.11, §3.2).
//
//   5. NO UNPUBLISHED TOKEN. Every `insimul_*` token spelled anywhere in the
//      artifact or its decision core is published in a vocabulary — the
//      workspace matrix's 42 for the hello and restore stages, the contract's own
//      for the verb stage. A refusal carrying a token nobody published is a
//      refusal a Conductor cannot act on.
//
// Every check has a NEGATIVE CONTROL: the gate breaks its own input and demands
// that the check goes red. A gate that cannot fail is worse than no gate, and
// this repository has shipped that mistake before.
//
// Usage:
//   node tools/verify-talos-bridge/check-bridge.mjs
//   node tools/verify-talos-bridge/check-bridge.mjs --self-test   (adds the controls)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '../..');
const ADDON = path.join(REPO, 'addons', 'insimul_talos');
const INSIMUL_ADDON = path.join(REPO, 'addons', 'insimul');
const CORE_CPP = path.join(REPO, 'gdextension', 'src', 'talos_bridge.cpp');
const ADAPTER = path.join(ADDON, 'insimul_talos_adapter.gd');
const PLUGIN_GD = path.join(ADDON, 'insimul_talos_plugin.gd');
const MANIFEST = path.join(ADDON, 'talos.game.yaml');

const selfTest = process.argv.includes('--self-test');

// TBP v1's verb inventory (talos:docs/03-engine-bridge.md §2.3, tabulated in
// BRIDGE §3.2). Twenty-five, and the count is the point: a bridge that answered
// twenty-four and said nothing about the twenty-fifth would leave a Conductor
// planning against a silence.
const TBP_VERBS = [
  'hello', 'inject_input', 'probe_injection_paths', 'execute_skill', 'cancel_skill',
  'query_state', 'query_objects', 'save_checkpoint', 'restore_checkpoint', 'teleport',
  'set_progress_var', 'play_input_trace', 'step_frames', 'set_seed', 'set_fixed_timestep',
  'set_time_scale', 'load_level', 'screenshot', 'start_frame_tap', 'stop_frame_tap',
  'mark_event', 'run_native_test', 'declare_context', 'clock_sync', 'shutdown',
];

// The manifest sections §7.4 names, and the contract key each corresponds to.
const GROUP_SECTIONS = ['checkpoint', 'markers', 'readiness', 'rng', 'contexts', 'events'];

// `insimul_*` identifiers that are NOT why-not tokens: libinsimul's own C ABI, and
// the artifact's group names. Listed rather than pattern-matched, because a
// pattern is how a real token slips through as an exemption.
const NOT_TOKENS = new Set([
  'insimul_kb_snapshot', 'insimul_kb_restore', 'insimul_kb_create', 'insimul_kb_destroy',
  'insimul_kb_consult', 'insimul_kb_assert', 'insimul_kb_retract', 'insimul_assert',
  'insimul_query_start', 'insimul_query_next', 'insimul_query_stop', 'insimul_version',
  'insimul_last_error', 'insimul_core_call', 'insimul_core_create', 'insimul_talos',
  'insimul_talos_adapter', 'insimul_talos_plugin', 'insimul_talos_bridge',
]);

// Talos symbols the artifact may never name. `talos_*` METHOD and SIGNAL names are
// exactly what the duck-typed contract is made of and are not symbols, so the list
// is about scripts, classes and paths. Matched on a word boundary, because this
// artifact's OWN class is `InsimulTalosBridge` and a substring match would
// convict it of naming Talos's.
const TALOS_SYMBOLS = [
  'res://addons/talos', 'addons/talos/', 'TalosBridge', 'TalosInputTrace',
  'TalosSnapshot', 'TalosYamlSubset', 'TalosWalkGrid', 'TalosSceneQuery',
];

function namesTalosSymbol(text, symbol) {
  return new RegExp(`(?<![A-Za-z0-9_])${symbol.replace(/[/:.]/g, '\\$&')}`).test(text);
}

let failures = 0;
let checks = 0;

function ok(what) {
  checks++;
  console.log(`  ✓ ${what}`);
}

function bad(what, detail) {
  checks++;
  failures++;
  console.log(`  ✗ ${what}\n      ${detail}`);
}

function check(condition, what, detail = 'expectation not met') {
  if (condition) ok(what);
  else bad(what, detail);
}

function read(file) {
  return fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
}

/**
 * The `groups:` lists of a talos.game.yaml, per section. A deliberately tiny
 * reader over the subset this fragment uses (block mappings and sequences of
 * scalars) — the same subset Talos's own `core/yaml_subset.gd` implements, and
 * pulling a YAML dependency into this repository to read eighteen lines would be
 * a poor trade.
 */
function manifestGroups(text) {
  const out = {};
  let section = null;
  let inGroups = false;
  for (const raw of text.split('\n')) {
    const line = raw.replace(/#.*$/, '').trimEnd();
    if (line.trim() === '') continue;
    const indent = line.length - line.trimStart().length;
    if (indent === 0) {
      const key = line.split(':')[0].trim();
      section = GROUP_SECTIONS.includes(key) ? key : null;
      inGroups = false;
      if (section) out[section] = [];
      continue;
    }
    if (section === null) continue;
    if (line.trim() === 'groups:') {
      inGroups = true;
      continue;
    }
    if (inGroups && line.trim().startsWith('- ')) {
      out[section].push(line.trim().slice(2).trim());
      continue;
    }
    if (inGroups && !line.trim().startsWith('- ')) inGroups = false;
  }
  return out;
}

/**
 * Every complete `insimul_*` identifier spelled in `text`. A trailing underscore
 * means the identifier was a CONCATENATION PREFIX in the decision core
 * (`"insimul_checkpoint_" + axis`), and the tokens those compose into are checked
 * where they can be enumerated rather than guessed at — by the C++ gate, which
 * asks the bridge itself for every token it can emit.
 */
function insimulIdentifiers(text) {
  const found = new Set();
  for (const match of text.matchAll(/insimul_[a-z0-9_]+/g)) {
    if (!match[0].endsWith('_')) found.add(match[0]);
  }
  return found;
}

function runChecks({ contract, matrix, manifestText, adapterText, pluginText, coreText, insimulAddonHits }) {
  const before = failures;

  // ── 1. The artifact is separate ────────────────────────────────────────
  check(
    contract.artifact === 'insimul-talos-bridge' && contract.engine === 'godot',
    'the contract declares the artifact §7.5 names',
    `saw ${contract.artifact} / ${contract.engine}`,
  );
  check(
    insimulAddonHits.length === 0,
    'addons/insimul/ never mentions the bridge — Insimul takes no dependency on it',
    `mentioned in: ${insimulAddonHits.join(', ')}`,
  );
  const talosHits = [];
  for (const symbol of TALOS_SYMBOLS) {
    if (
      namesTalosSymbol(adapterText, symbol) ||
      namesTalosSymbol(pluginText, symbol) ||
      namesTalosSymbol(coreText, symbol)
    ) {
      talosHits.push(symbol);
    }
  }
  check(
    talosHits.length === 0,
    'the bridge names no Talos symbol — the contract it implements is duck-typed',
    `named: ${talosHits.join(', ')}`,
  );

  // ── 2. The groups agree, both ways ─────────────────────────────────────
  const declared = manifestGroups(manifestText);
  const contractGroups = contract.groups ?? {};
  const missingSections = GROUP_SECTIONS.filter((s) => !(s in contractGroups));
  check(
    missingSections.length === 0,
    'the contract declares all six group families of §7.4',
    `missing: ${missingSections.join(', ')}`,
  );
  const disagreements = [];
  for (const section of GROUP_SECTIONS) {
    const fromContract = contractGroups[section]?.group ?? null;
    const fromManifest = declared[section] ?? [];
    if (fromContract === null) continue;
    if (!fromManifest.includes(fromContract)) {
      disagreements.push(`${section}: contract says "${fromContract}", manifest declares [${fromManifest.join(', ')}]`);
    }
    for (const group of fromManifest) {
      if (group !== fromContract) disagreements.push(`${section}: manifest declares "${group}", which the contract does not`);
    }
  }
  check(
    disagreements.length === 0,
    'every group is declared in the manifest AND in the contract — an undeclared adapter is invisible',
    disagreements.join('; '),
  );
  const joinedFromCode = [...adapterText.matchAll(/add_to_group\(([^)]*)\)/g)].map((m) => m[1].trim());
  check(
    joinedFromCode.length > 0 && joinedFromCode.every((arg) => !arg.startsWith('"')),
    'the adapter joins its groups from the contract rather than from literals in its own source',
    `literal group joins: ${joinedFromCode.filter((a) => a.startsWith('"')).join(', ')}`,
  );

  // ── 3. The hooks exist ─────────────────────────────────────────────────
  const missingHooks = [];
  for (const section of GROUP_SECTIONS) {
    const spec = contractGroups[section];
    if (!spec) continue;
    for (const method of spec.methods ?? []) {
      if (!new RegExp(`\\bfunc\\s+${method}\\s*\\(`).test(adapterText)) missingHooks.push(`func ${method}()`);
    }
    for (const signal of spec.signals ?? []) {
      if (!new RegExp(`\\bsignal\\s+${signal}\\s*\\(`).test(adapterText)) missingHooks.push(`signal ${signal}`);
    }
  }
  check(
    missingHooks.length === 0,
    'every method and signal the six contracts name is defined in the adapter',
    `missing: ${missingHooks.join(', ')}`,
  );

  // ── 4. The verb map is total ───────────────────────────────────────────
  const verbs = contract.verbs ?? {};
  const missingVerbs = TBP_VERBS.filter((v) => !(v in verbs));
  const extraVerbs = Object.keys(verbs).filter((v) => !TBP_VERBS.includes(v));
  check(
    missingVerbs.length === 0 && extraVerbs.length === 0,
    `all ${TBP_VERBS.length} TBP v1 verbs are accounted for, and no others`,
    `missing: [${missingVerbs.join(', ')}] unknown: [${extraVerbs.join(', ')}]`,
  );
  const untokened = [];
  for (const [name, row] of Object.entries(verbs)) {
    if (row.answered_by === 'insimul') {
      if (row.why_not) untokened.push(`${name} answers and still carries a why-not token`);
      continue;
    }
    if (!row.why_not) untokened.push(`${name} is not answered and names no why-not token`);
  }
  check(
    untokened.length === 0,
    'every verb this bridge does not answer is refused with a why-not token, not a generic failure',
    untokened.join('; '),
  );
  const answered = Object.entries(verbs).filter(([, r]) => r.answered_by === 'insimul');
  check(
    answered.length >= 8,
    'and the bridge really answers a substantial part of the inventory',
    `answers ${answered.length}`,
  );

  // ── 5. No unpublished token ────────────────────────────────────────────
  const published = new Set([
    ...Object.keys(matrix.refuse_at_hello?.tokens ?? {}),
    ...Object.keys(contract.tokens ?? {}),
  ]);
  const groupNames = new Set(Object.values(contractGroups).map((g) => g.group));
  const spelled = new Set([
    ...insimulIdentifiers(coreText),
    ...insimulIdentifiers(adapterText),
    ...insimulIdentifiers(JSON.stringify(contract)),
    ...insimulIdentifiers(manifestText),
  ]);
  const unpublished = [...spelled].filter(
    (id) => !published.has(id) && !groupNames.has(id) && !NOT_TOKENS.has(id),
  );
  check(
    unpublished.length === 0,
    'every insimul_* token the artifact spells is published in a vocabulary',
    `unpublished: ${unpublished.join(', ')}`,
  );
  const declaredTokens = Object.keys(contract.tokens ?? {});
  const unusedTokens = declaredTokens.filter((t) => !spelled.has(t));
  check(
    unusedTokens.length === 0,
    'and every verb-stage token the contract declares is really reachable',
    `declared and never emitted: ${unusedTokens.join(', ')}`,
  );
  check(
    (matrix.refuse_at_hello?.tokens ?? null) !== null &&
      Object.keys(matrix.refuse_at_hello.tokens).length >= 40,
    'the mirrored matrix still carries the whole hello/restore vocabulary',
    `saw ${Object.keys(matrix.refuse_at_hello?.tokens ?? {}).length}`,
  );

  return failures - before;
}

function load() {
  const contract = JSON.parse(read(path.join(ADDON, 'bridge-contract.json')) || '{}');
  const matrix = JSON.parse(read(path.join(ADDON, 'supported-versions.json')) || '{}');
  const insimulAddonHits = [];
  const walk = (dir) => {
    if (!fs.existsSync(dir)) return;
    for (const entry of fs.readdirSync(dir)) {
      const abs = path.join(dir, entry);
      if (fs.statSync(abs).isDirectory()) walk(abs);
      else if (/\.(gd|cfg|json)$/.test(entry) && /insimul_talos|InsimulTalos/.test(read(abs))) {
        insimulAddonHits.push(path.relative(REPO, abs));
      }
    }
  };
  walk(INSIMUL_ADDON);
  return {
    contract,
    matrix,
    manifestText: read(MANIFEST),
    adapterText: read(ADAPTER),
    pluginText: read(PLUGIN_GD),
    coreText: read(CORE_CPP),
    insimulAddonHits,
  };
}

console.log('insimul-talos-bridge: the artifact (TALOS_INSIMUL_BRIDGE.md §7.5)\n');
const input = load();
runChecks(input);

if (selfTest) {
  console.log('\ncheck-bridge: negative controls');
  const controls = [
    ['group agreement fails when the manifest drops a group', (i) => ({
      ...i,
      manifestText: i.manifestText.replace('- insimul_talos_checkpoint', '- insimul_talos_something_else'),
    })],
    ['hook presence fails when a contract method is not implemented', (i) => ({
      ...i,
      adapterText: i.adapterText.replace('func talos_save(', 'func talos_save_renamed('),
    })],
    ['the verb map fails when a verb goes missing', (i) => {
      const verbs = { ...i.contract.verbs };
      delete verbs.teleport;
      return { ...i, contract: { ...i.contract, verbs } };
    }],
    ['the verb map fails when an unanswered verb names no token', (i) => ({
      ...i,
      contract: {
        ...i.contract,
        verbs: { ...i.contract.verbs, screenshot: { ...i.contract.verbs.screenshot, why_not: null } },
      },
    })],
    ['the vocabulary fails on an unpublished token', (i) => ({
      ...i,
      coreText: `${i.coreText}\nrefuse("insimul_made_up_reason", "", {});\n`,
    })],
    ['separation fails when the bridge names a Talos symbol', (i) => ({
      ...i,
      adapterText: `${i.adapterText}\nconst X := preload("res://addons/talos/plugin.gd")\n`,
    })],
    ['separation fails when addons/insimul mentions the bridge', (i) => ({
      ...i,
      insimulAddonHits: ['addons/insimul/pretend.gd'],
    })],
  ];
  const quiet = console.log;
  for (const [what, mutate] of controls) {
    console.log = () => {};
    const before = failures;
    const beforeChecks = checks;
    const broke = runChecks(mutate(input));
    failures = before;
    checks = beforeChecks;
    console.log = quiet;
    check(broke > 0, `negative control: ${what}`, 'the gate stayed green on broken input');
  }
}

console.log(`\ncheck-bridge: ${checks} check(s), ${failures} failure(s)`);
process.exit(failures > 0 ? 1 : 0);
