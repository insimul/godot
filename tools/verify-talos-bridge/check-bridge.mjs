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
//   5. THE §7.5 RULE, STATICALLY. The adapter may never read the knowledge base
//      while it is being constructed. That is a rule about a code path, not about
//      a value, so it is checked as one: `_init`, `_ready` and everything they
//      reach inside this file must not touch `_kb` or ask the world anything. A
//      convention holds until someone adds one convenient line to `_ready`; this
//      fails instead. And every state answer must pass `_gate()` BEFORE it
//      touches the KB, because §7.5's whole point is that an early query comes
//      back refused rather than as an empty success a Conductor reads as "no
//      facts".
//
//   6. THE INSTALL DIAGNOSIS AGREES, BOTH WAYS (§7.8). The failure modes the
//      decision half compiles in and the install-stage tokens the contract
//      publishes must be the same set. And the adapter must join its groups
//      BEFORE it configures — a half-installed adapter that never joined would be
//      INVISIBLE, and a Bridge that finds no adapter degrades to generic scene
//      queries, which is the silent failure the whole design exists to remove.
//
//   7. THE REPLAY LEG IS TOTAL (§8.6). Every refusal code core's replay module
//      can produce maps to a published why-not token, and every one of those
//      tokens is really emitted by the port. A leg that refused a trace with a
//      code nobody mapped would be refusing in core's vocabulary and nobody
//      else's.
//
//   8. NO UNPUBLISHED TOKEN. Every `insimul_*` token spelled anywhere in the
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
const REPLAY_CPP = path.join(REPO, 'gdextension', 'src', 'talos_replay.cpp');
const WRAPPER_CPP = path.join(REPO, 'gdextension', 'src', 'insimul_talos_bridge.cpp');
const VOCABULARY = path.join(ADDON, 'input-vocabulary.json');
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

// Anything in the adapter that means "the knowledge base was read". §7.5 forbids
// every one of them on a construction-time path — including the world identity,
// because `kb_ready()` reads it and a `_ready` that consulted it would be making
// the ordering decision this design exists to delete.
const KB_READS = ['_kb', '_world_id', '_state_goals', '_progress', '_replay_world'];

// The state answers. Each must reach `_gate()` before it reaches the KB: an
// early one comes back as a retryable refusal, never as an empty success.
const GATED_ANSWERS = ['_query_state', 'talos_save', 'talos_load', 'replay_input_trace'];

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

/**
 * A GDScript file with its comments removed.
 *
 * §7.5 is a rule about a CODE PATH, so the check that enforces it must not fire
 * on a file that merely explains the rule — and this adapter's `_configure()`
 * says in prose that it does not touch `_kb`, which a naive scan would read as
 * touching `_kb`. (Note this is the opposite of check-mechanics.mjs's seventh
 * check, which greps comments ON PURPOSE: a comment listing the active module
 * set rots exactly like code, whereas a comment describing a rule is the rule
 * being documented.)
 */
function stripGdComments(text) {
  return text
    .split('\n')
    .map((line) => {
      let quote = null;
      for (let i = 0; i < line.length; i++) {
        const c = line[i];
        if (quote !== null) {
          if (c === '\\') i++;
          else if (c === quote) quote = null;
          continue;
        }
        if (c === '"' || c === "'") quote = c;
        else if (c === '#') return line.slice(0, i);
      }
      return line;
    })
    .join('\n');
}

/**
 * Every top-level `func` in a GDScript file, as `name -> body`. Deliberately a
 * tiny reader over the subset this file uses (tab-indented bodies, one `func`
 * per line) — the same trade `manifestGroups` makes, and for the same reason:
 * pulling a GDScript parser into this repository to read one file would cost
 * more than it could ever catch.
 */
function gdFunctions(text) {
  const out = new Map();
  const lines = stripGdComments(text).split('\n');
  let name = null;
  let body = [];
  for (const line of lines) {
    const declared = /^func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/.exec(line);
    if (declared) {
      if (name !== null) out.set(name, body.join('\n'));
      name = declared[1];
      body = [];
      continue;
    }
    if (name === null) continue;
    // A non-indented, non-empty line ends the function.
    if (line.trim() !== '' && !/^[\t ]/.test(line)) {
      out.set(name, body.join('\n'));
      name = null;
      body = [];
      continue;
    }
    body.push(line);
  }
  if (name !== null) out.set(name, body.join('\n'));
  return out;
}

/** Every function `from` can reach, transitively, inside this file. */
function reachable(functions, from) {
  const seen = new Set();
  const queue = [...from].filter((name) => functions.has(name));
  while (queue.length > 0) {
    const name = queue.pop();
    if (seen.has(name)) continue;
    seen.add(name);
    for (const call of (functions.get(name) ?? '').matchAll(/([A-Za-z_][A-Za-z0-9_]*)\s*\(/g)) {
      if (functions.has(call[1]) && !seen.has(call[1])) queue.push(call[1]);
    }
  }
  return seen;
}

function runChecks({ contract, matrix, manifestText, adapterText, pluginText, coreText, insimulAddonHits, vocabulary, replayText }) {
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
      namesTalosSymbol(coreText, symbol) ||
      namesTalosSymbol(replayText, symbol)
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

  // ── 5. The §7.5 rule, statically ───────────────────────────────────────
  const functions = gdFunctions(adapterText);
  const constructionPath = reachable(functions, ['_init', '_ready']);
  const early = [];
  for (const name of constructionPath) {
    const body = functions.get(name) ?? '';
    for (const read of KB_READS) {
      if (new RegExp(`(?<![A-Za-z0-9_])${read}(?![A-Za-z0-9_])`).test(body)) {
        early.push(`${name}() reads ${read}`);
      }
    }
  }
  check(
    constructionPath.has('_ready') && early.length === 0,
    'nothing reachable from _init/_ready reads the knowledge base — §7.5 as a code path, not a convention',
    early.length > 0 ? early.join('; ') : 'the adapter declares no _ready at all',
  );
  const ungated = [];
  for (const answer of GATED_ANSWERS) {
    const body = functions.get(answer);
    if (body === undefined) {
      ungated.push(`${answer}() is not defined`);
      continue;
    }
    const gate = body.search(/_gate\(|install_diagnosis/);
    const touch = body.search(/(?<![A-Za-z0-9_])_kb(?![A-Za-z0-9_])|_replay_world\./);
    if (gate < 0) ungated.push(`${answer}() never gates`);
    else if (touch >= 0 && touch < gate) ungated.push(`${answer}() touches the KB before it gates`);
  }
  check(
    ungated.length === 0,
    'and every state answer gates BEFORE it touches the KB, so an early one is refused rather than answered "no facts"',
    ungated.join('; '),
  );

  // ── 6. The install diagnosis agrees, both ways ─────────────────────────
  const compiledModes = [...coreText.matchAll(/\{\s*"(insimul_bridge_[a-z_]+)"\s*,/g)].map((m) => m[1]);
  const declaredInstall = Object.entries(contract.tokens ?? {})
    .filter(([, row]) => row.stage === 'install')
    .map(([token]) => token);
  const onlyCompiled = compiledModes.filter((t) => !declaredInstall.includes(t));
  const onlyDeclared = declaredInstall.filter((t) => !compiledModes.includes(t));
  check(
    compiledModes.length >= 6 && onlyCompiled.length === 0 && onlyDeclared.length === 0,
    'every install failure mode the bridge can name is published, and every published one is reachable',
    `compiled-only: [${onlyCompiled.join(', ')}] declared-only: [${onlyDeclared.join(', ')}] (${compiledModes.length} mode(s))`,
  );
  const ready = functions.get('_ready') ?? '';
  check(
    ready.indexOf('add_to_group') >= 0 &&
      (ready.indexOf('_configure') < 0 || ready.indexOf('add_to_group') < ready.indexOf('_configure')),
    'the adapter joins its groups BEFORE it configures — a half-installed adapter must be found, so its refusal can be heard (§7.8)',
    'a broken install that never joined its groups is invisible, and Talos degrades to generic scene queries',
  );
  check(
    /push_error\(/.test(adapterText),
    'and a half-present install is reported as an ERROR, not a warning',
    'push_error is never called',
  );

  // ── 7. The replay leg is total ─────────────────────────────────────────
  const codes = contract.replay?.codes ?? {};
  const unmapped = Object.entries(codes).filter(([, token]) => !(token in (contract.tokens ?? {})));
  const unreachable = Object.entries(codes).filter(([, token]) => !replayText.includes(`"${token}"`));
  const replayStage = Object.entries(contract.tokens ?? {})
    .filter(([, row]) => row.stage === 'replay')
    .map(([token]) => token);
  const unmappedStage = replayStage.filter(
    (token) => !Object.values(codes).includes(token) && !adapterText.includes(token) && !replayText.includes(`"${token}"`),
  );
  check(
    Object.keys(codes).length >= 8 &&
      unmapped.length === 0 &&
      unreachable.length === 0 &&
      unmappedStage.length === 0,
    'every refusal code the portable input-trace artifact can produce maps to a published token the leg really emits',
    `codes: ${Object.keys(codes).length} unmapped: [${unmapped.map((e) => e[0]).join(', ')}] never emitted: [${unreachable.map((e) => e[1]).join(', ')}] orphaned: [${unmappedStage.join(', ')}]`,
  );
  check(
    vocabulary.format === 'insimul.talos-bridge.input-vocabulary/1' &&
      (vocabulary.action_ids ?? []).length > 0 &&
      (vocabulary.action_layer_keys ?? []).length > 0,
    'the shipped input vocabulary carries core\'s action ids, so an action-layer trace is refused here as it is there',
    `format ${vocabulary.format}, ${(vocabulary.action_ids ?? []).length} action id(s)`,
  );

  // ── 8. No unpublished token ────────────────────────────────────────────
  const published = new Set([
    ...Object.keys(matrix.refuse_at_hello?.tokens ?? {}),
    ...Object.keys(contract.tokens ?? {}),
  ]);
  const groupNames = new Set(Object.values(contractGroups).map((g) => g.group));
  const spelled = new Set([
    ...insimulIdentifiers(coreText),
    ...insimulIdentifiers(replayText),
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
    vocabulary: JSON.parse(read(VOCABULARY) || '{}'),
    manifestText: read(MANIFEST),
    adapterText: read(ADAPTER),
    pluginText: read(PLUGIN_GD),
    coreText: read(CORE_CPP),
    // The wrapper is scanned for Talos symbols alongside the decision half: it is
    // the file most likely to acquire one, being the only one that speaks Godot.
    replayText: `${read(REPLAY_CPP)}\n${read(WRAPPER_CPP)}`,
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
    ['the §7.5 rule fails when _ready reads the KB', (i) => ({
      ...i,
      adapterText: i.adapterText.replace(
        'func _ready() -> void:',
        'func _ready() -> void:\n\tif _kb != null:\n\t\tpass',
      ),
    })],
    ['the §7.5 rule fails when _ready calls something that reads the KB', (i) => ({
      ...i,
      adapterText: i.adapterText.replace('\t_configure()', '\t_configure()\n\tkb_ready()'),
    })],
    ['the gate order fails when a state answer touches the KB before it gates', (i) => ({
      ...i,
      adapterText: i.adapterText.replace(
        'func _query_state(key: String) -> Variant:',
        'func _query_state(key: String) -> Variant:\n\tvar peek: Variant = _kb',
      ),
    })],
    ['visibility fails when a broken install joins no groups', (i) => ({
      ...i,
      adapterText: i.adapterText.replace(
        /func _ready\(\) -> void:[\s\S]*?\n\t_configure\(\)/,
        'func _ready() -> void:\n\t_configure()\n\tfor group in _declared_groups():\n\t\tadd_to_group(group)',
      ),
    })],
    ['the install diagnosis fails when a compiled mode is not published', (i) => {
      const tokens = { ...i.contract.tokens };
      delete tokens.insimul_bridge_vocabulary_absent;
      return { ...i, contract: { ...i.contract, tokens } };
    }],
    ['the replay map fails when a refusal code names no token', (i) => ({
      ...i,
      contract: {
        ...i.contract,
        replay: { ...i.contract.replay, codes: { ...i.contract.replay.codes, id_mismatch: 'insimul_made_up' } },
      },
    })],
    ['the replay map fails when a mapped token is never emitted', (i) => ({
      ...i,
      replayText: i.replayText.replace('"insimul_trace_world_content_mismatch"', '"insimul_trace_other"'),
    })],
    ['the vocabulary check fails when core\'s action ids are absent', (i) => ({
      ...i,
      vocabulary: { ...i.vocabulary, action_ids: [] },
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
