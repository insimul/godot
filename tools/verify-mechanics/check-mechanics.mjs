#!/usr/bin/env node
// check-mechanics.mjs — the band-120 mechanic mirror gate (tasklist 147, US-1).
//
// WHAT IT GUARDS. Core declares, per mechanic module, the host interface an
// engine must implement (`src/modules/module-contract.ts`, part 4). This repo
// implements them in GDScript and reaches the modules through rows in
// `gdextension/corebridge/js/entry.js`. Three artifacts that must agree, in a
// repository that is standalone by design and therefore cannot import core to
// check. So the agreement is checked against a VENDORED derivation of core's own
// declaration (MODULE_HOSTS.json) exactly as the conformance corpus and the core
// bundle are, with the same discipline: a recorded core commit, recorded input
// hashes, and a `--core` mode that re-derives and fails on drift.
//
// SEVEN CHECKS, and each one exists because its absence has already cost somebody
// something in this ecosystem:
//
//   1. MANIFEST — every band-120 module in MODULE_HOSTS.json names the same host
//      interfaces and decision layers core does. (`--core` re-derives; without a
//      core checkout the vendored copy's own hashes are verified.)
//   2. CONTRACT — every interface's member list matches the GDScript base class
//      in `addons/insimul/runtime/mechanics/insimul_mechanic_hosts.gd`. A member
//      core adds and this plugin does not is how a binding table rots.
//   3. IMPLEMENTATION — every interface has at least one GDScript class that
//      extends its base class, or an entry in `stubbed` with a stated
//      consequence. That is what makes "no silent no-op" checkable.
//   4. BRIDGE — `entry.js`'s `MECHANIC_MODULES` table agrees with the manifest,
//      and every row it declares exists in its `METHODS` table. A module claimed
//      but unreachable is exactly what Unity's probe had to report for all seven.
//   5. ORDERS — every host member the ADAPTER can emit as an order has a
//      dispatch entry in `insimul_mechanic_session.gd`. An order with no branch
//      is a game that quietly stops applying damage.
//   6. CORPUS — every module's vectors are vendored AND something runs them, in
//      both directions, plus a total accounting of every conformance/ directory.
//      A vendored corpus nothing executes is a checked-in file (tasklist 147 US-2).
//   7. ACTIVATION — the vendored genre table agrees with the manifest, the rows
//      that read it exist, and the GDScript that activates names no module, no
//      pack area and no genre. "Adding a module to a bundle needs no engine code
//      change" is a claim, and this is the only way to check it (US-3).
//
// WHAT IT DOES NOT PROVE, stated because a gate that overclaims is worse than
// none: it executes no GDScript. Signatures, semantics and behaviour are
// unchecked here — `gdextension/test/run_mechanic_tests.sh` is what executes the
// rows end to end, and the human checklist in VERIFICATION.md is what proves a
// raycast and a NavigationAgent3D behave in a real scene.
//
// Run `--self-test` to see every check fail on purpose.

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..');
const MANIFEST_PATH = path.join(HERE, 'MODULE_HOSTS.json');

const HOSTS_GD = path.join(REPO, 'addons/insimul/runtime/mechanics/insimul_mechanic_hosts.gd');
const SESSION_GD = path.join(REPO, 'addons/insimul/runtime/mechanics/insimul_mechanic_session.gd');
const ENTRY_JS = path.join(REPO, 'gdextension/corebridge/js/entry.js');
const HOST_MECHANICS_JS = path.join(REPO, 'gdextension/corebridge/js/host-mechanics.js');
const HOST_CORPUS_JS = path.join(REPO, 'gdextension/corebridge/js/host-corpus.js');
const ACTIVATION_GD = [
  path.join(REPO, 'addons/insimul/runtime/mechanics/insimul_module_activation.gd'),
  path.join(REPO, 'addons/insimul/runtime/mechanics/insimul_mechanic_activator.gd'),
];
const ACTIVATION_TABLE = path.join(REPO, 'conformance/modules/genre-activation.json');
const CORPUS_DIR = path.join(REPO, 'conformance');

/**
 * The modules this repo adopts. Core's manifest has nine; `agentAi` and `map`
 * are not band 120–125 and tasklist 147 does not adopt them — `map` names
 * traversal's `ILocomotionHost` and would be adopted for free, `agentAi` needs
 * `AgentPlanner` and a row that does not exist. Naming the seven here rather
 * than "all of them" is what keeps the gate honest about scope.
 */
const BAND_120 = ['combat', 'perception', 'skill', 'traversal', 'equipment', 'stamina', 'routine'];

/** Core files the manifest is derived from, relative to `packages/core`. */
const CORE_SOURCES = [
  'src/modules/module-contract.ts',
  'src/game-engine/host-contracts.ts',
  'src/game-engine/system-contracts.ts',
];

const args = process.argv.slice(2);
const coreArg = argValue('--core') ?? process.env.INSIMUL_CORE_DIR ?? null;
const writeMode = args.includes('--write');
const selfTest = args.includes('--self-test');

function argValue(flag) {
  const i = args.indexOf(flag);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

function sha256(text) {
  return createHash('sha256').update(text).digest('hex');
}

function read(file) {
  return fs.readFileSync(file, 'utf8');
}

// ── deriving core's declaration ─────────────────────────────────────────────
//
// Regex over TypeScript rather than a TS parse, for the reason vendor-core-
// bundle.mjs bundles rather than imports: this repo has no node_modules and no
// TypeScript. The shapes read here are small, flat and stable (a string literal,
// an array of string literals), and every one of them is re-derived and diffed
// by `--core`, so a shape that changes enough to break the parse fails loudly.

/** `INSIMUL_MODULES` as `{ id: { hostInterface, decisionLayer, ... } }`. */
export function parseModules(source) {
  const start = source.indexOf('export const INSIMUL_MODULES');
  if (start < 0) throw new Error('module-contract.ts: no INSIMUL_MODULES');
  const body = source.slice(start);
  const modules = {};
  const idRe = /^\s{4}id: '([a-zA-Z]+)',$/gm;
  const ids = [...body.matchAll(idRe)];
  for (let i = 0; i < ids.length; i++) {
    const from = ids[i].index;
    const to = i + 1 < ids.length ? ids[i + 1].index : body.length;
    const entry = body.slice(from, to);
    modules[ids[i][1]] = {
      predicatePack: stringField(entry, 'predicatePack'),
      irSection: stringField(entry, 'irSection'),
      decisionLayer: arrayField(entry, 'decisionLayer'),
      hostInterface: arrayField(entry, 'hostInterface'),
      conformanceCorpus: arrayField(entry, 'conformanceCorpus'),
      genreBundles: arrayField(entry, 'genreBundles'),
    };
  }
  return modules;
}

function stringField(entry, name) {
  const match = entry.match(new RegExp(`\\b${name}: '([^']*)'`));
  return match ? match[1] : null;
}

function arrayField(entry, name) {
  const match = entry.match(new RegExp(`\\b${name}: \\[([^\\]]*)\\]`));
  if (!match) return [];
  return [...match[1].matchAll(/'([^']+)'/g)].map((m) => m[1]);
}

/** Every `export interface IName { ... }`, as `{ IName: [members] }`. */
export function parseInterfaces(source) {
  const out = {};
  const re = /export interface (I[A-Za-z]+) \{([\s\S]*?)\n\}/g;
  let match;
  while ((match = re.exec(source)) !== null) {
    const members = [];
    for (const line of match[2].split('\n')) {
      const member = line.match(/^\s{2}([a-zA-Z][a-zA-Z0-9]*)\s*[(?:]/);
      if (member) members.push(member[1]);
    }
    out[match[1]] = members;
  }
  return out;
}

function deriveFromCore(coreDir) {
  const core = path.resolve(coreDir);
  const sources = {};
  for (const rel of CORE_SOURCES) {
    const file = path.join(core, rel);
    if (!fs.existsSync(file)) fail(`--core ${core}: missing ${rel}`);
    sources[rel] = read(file);
  }
  const modules = parseModules(sources['src/modules/module-contract.ts']);
  const interfaces = {
    ...parseInterfaces(sources['src/game-engine/host-contracts.ts']),
    ...parseInterfaces(sources['src/game-engine/system-contracts.ts']),
  };

  const declared = {};
  const needed = new Set();
  for (const id of BAND_120) {
    if (!modules[id]) fail(`core's INSIMUL_MODULES has no module "${id}"`);
    declared[id] = modules[id];
    for (const name of modules[id].hostInterface) needed.add(name);
  }
  const kept = {};
  for (const name of [...needed].sort()) {
    if (!interfaces[name]) fail(`core declares host interface "${name}" but no file exports it`);
    kept[name] = interfaces[name];
  }

  return {
    coreCommit: gitCommit(core),
    sourceHashes: Object.fromEntries(
      CORE_SOURCES.map((rel) => [rel, sha256(sources[rel])]),
    ),
    modules: declared,
    interfaces: kept,
  };
}

function gitCommit(core) {
  // Same provenance vendor-core-bundle.mjs records: the commit of the checkout
  // the derivation was taken from, so a stale manifest is attributable.
  try {
    return execFileSync('git', ['-C', core, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
  } catch {
    return 'unknown';
  }
}

// ── reading this repo ───────────────────────────────────────────────────────

/** The base classes in insimul_mechanic_hosts.gd, as `{ Class: [methods] }`. */
export function parseGdClasses(source) {
  const out = {};
  const lines = source.split('\n');
  let current = null;
  for (const line of lines) {
    const classDecl = line.match(/^class ([A-Za-z_]\w*) extends/);
    if (classDecl) {
      current = classDecl[1];
      out[current] = [];
      continue;
    }
    if (/^\S/.test(line) && !line.startsWith('#')) current = null;
    const func = line.match(/^\tfunc ([a-z_]\w*)\(/);
    if (func && current) out[current].push(func[1]);
  }
  return out;
}

/** Every GDScript class that extends one of the host base classes. */
export function findImplementations(root) {
  const found = {};
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === '.git' || entry.name === 'node_modules') continue;
        walk(full);
      } else if (entry.name.endsWith('.gd')) {
        const source = read(full);
        const re = /extends InsimulMechanicHosts\.([A-Za-z]\w*)/g;
        let match;
        while ((match = re.exec(source)) !== null) {
          const base = match[1];
          (found[base] ??= []).push(path.relative(REPO, full));
        }
      }
    }
  };
  walk(path.join(root, 'addons'));
  walk(path.join(root, 'templates'));
  return found;
}

/** `MECHANIC_MODULES` and the `METHODS` keys out of entry.js. */
export function parseBridge(source) {
  const start = source.indexOf('const MECHANIC_MODULES = {');
  if (start < 0) throw new Error('entry.js: no MECHANIC_MODULES table');
  const table = source.slice(start, source.indexOf('\n};', start));
  const modules = {};
  const idRe = /^\t([a-zA-Z]+): \{$/gm;
  const ids = [...table.matchAll(idRe)];
  for (let i = 0; i < ids.length; i++) {
    const from = ids[i].index;
    const to = i + 1 < ids.length ? ids[i + 1].index : table.length;
    const entry = table.slice(from, to);
    modules[ids[i][1]] = {
      layers: arrayField(entry, 'layers'),
      hostInterfaces: arrayField(entry, 'hostInterfaces'),
      rows: arrayField(entry, 'rows'),
    };
  }
  const methods = [...source.matchAll(/^\t'([a-z]+\.[a-zA-Z]+)':/gm)].map((m) => m[1]);
  return { modules, methods };
}

/** Which `{interface, member}` pairs the adapter can emit as an order. */
export function parseAdapterOrders(source) {
  return [...source.matchAll(/order\(s, '(I[A-Za-z]+)', '([a-zA-Z]+)'/g)].map((m) => ({
    host: m[1],
    call: m[2],
  }));
}

/** Which `{interface, member}` pairs the session knows how to dispatch. */
export function parseSessionOrders(source) {
  const start = source.indexOf('const ORDER_METHODS := {');
  if (start < 0) throw new Error('insimul_mechanic_session.gd: no ORDER_METHODS table');
  const table = source.slice(start, source.indexOf('\n}', start));
  const out = [];
  let current = null;
  for (const line of table.split('\n')) {
    const iface = line.match(/^\t"(I[A-Za-z]+)": \{/);
    if (iface) {
      current = iface[1];
      // A one-line entry: "IFoo": {"bar": "baz"},
      for (const m of line.matchAll(/"([a-zA-Z]+)": "([a-z_]+)"/g)) {
        if (m[1] !== current) out.push({ host: current, call: m[1] });
      }
      continue;
    }
    const member = line.match(/^\t\t"([a-zA-Z]+)": "([a-z_]+)",/);
    if (member && current) out.push({ host: current, call: member[1] });
  }
  return out;
}

/**
 * `CORPUS_AREAS` and `CORPUS_AREAS_BY_MODULE` out of host-corpus.js — which
 * decision corpora this build can EXECUTE, and which module owns each.
 */
export function parseCorpusRunners(source) {
  const areas = [];
  const areaTable = source.slice(
    source.indexOf('export const CORPUS_AREAS = {'),
    source.indexOf('\n};', source.indexOf('export const CORPUS_AREAS = {')),
  );
  for (const m of areaTable.matchAll(/^\t'([a-z-]+)': /gm)) areas.push(m[1]);

  const byModule = {};
  const moduleTable = source.slice(
    source.indexOf('export const CORPUS_AREAS_BY_MODULE = {'),
    source.indexOf('\n};', source.indexOf('export const CORPUS_AREAS_BY_MODULE = {')),
  );
  for (const m of moduleTable.matchAll(/^\t([a-z]+): \[([^\]]*)\]/gm)) {
    byModule[m[1]] = [...m[2].matchAll(/'([a-z-]+)'/g)].map((x) => x[1]);
  }
  return { areas, byModule };
}

/**
 * The rows tasklist 147 US-3 adopted, and what each one is for. Named here
 * rather than in the check so the gate's subject is readable as data.
 */
/**
 * Modules a genre bundle ACTIVATES that this repo does not adopt, and what a
 * game of that genre actually gets for them. Total by construction: check 7
 * fails on any activated module that is in neither {@link BAND_120} nor this
 * list, so core adding a module to a bundle surfaces here as a decision to make
 * rather than as a mechanic that quietly does nothing.
 *
 * The two halves of activation are why this list can exist at all without a
 * hole: the PACK half needs only the pack text, which the bundle carries for
 * every pack in the build, so an unadopted module's vocabulary IS in the KB and
 * its authored gates evaluate. The SESSION half needs a decision layer behind a
 * bridge row, which these two do not have.
 */
const NOT_ADOPTED = {
  agentAi:
    'the game-AI substrate. Its four packs are consulted (they are in the build, ' +
    'and `AgentPlanner` reads what the other packs populate), but no bridge row ' +
    'constructs the planner, so no session opens. InsimulMechanicActivator reports ' +
    'it as ACTIVE BUT UNREACHABLE rather than skipping it silently.',
  map:
    'the region and jurisdiction layer. Same shape: its pack is consulted, its ' +
    'decision layers are not bundled. It names ILocomotionHost, which IS ' +
    'implemented here, so adopting it later is a row and not a host.',
};

const ACTIVATION_ROWS = {
  'modules.activate': 'resolve one world (or one genre) to its active module set',
  'modules.table': "the whole committed table, from core's own emitter",
  'prolog.packs': 'the rule-pack TEXT the active set names but does not carry',
};

/** The vendored activation table, or null when it is not on disk. */
export function readActivationTable(file = ACTIVATION_TABLE) {
  if (!fs.existsSync(file)) return null;
  return JSON.parse(read(file));
}

/** Every activation-reading GDScript file's text, keyed by repo-relative path. */
export function readActivationSources(files = ACTIVATION_GD) {
  const out = {};
  for (const file of files) {
    if (fs.existsSync(file)) out[path.relative(REPO, file)] = read(file);
  }
  return out;
}

/**
 * The band-120 DECISION corpora — the six directories US-2 taught this repo to
 * execute through `conformance.run`.
 */
const DECISION_DIRS = ['combat', 'items', 'routines', 'skills', 'stealth', 'traversal'];

/**
 * Every OTHER vendored corpus directory, and what executes it. Hand-maintained,
 * total, and the reason it is here rather than in prose: a directory that
 * appears under conformance/ and is in neither list fails this gate, which is
 * the only mechanism that stops the next corpus from being vendored with
 * nothing behind it. `null` means nothing here runs it — allowed, but it has to
 * be SAID, with where the claim is written up.
 */
const CORPUS_RUN_ELSEWHERE = {
  modules:
    'gdextension/test/run_activation_tests.sh — every genre bundle in ' +
    'genre-activation.json is resolved through `modules.activate` and compared to ' +
    'the committed set, and the packs it names are witnessed in a real KB',
  prolog:
    'gdextension/test/run_corpus_tests.sh runs every query on the native Trealla; ' +
    'run_conformance.sh marshals every pinned solution',
  quests: 'gdextension/test/run_quest_parity_tests.sh and run_quest_tests.sh',
  radiant: 'gdextension/test/run_radiant_tests.sh',
  saves: 'gdextension/test/run_save_tests.sh and run_bootstrap_tests.sh',
  ui:
    'addons/insimul/tests/run_ui_registry_headless.sh (npm run test:ui) runs the ' +
    'registry, loading-phase and token cases against the GDScript view-models on a ' +
    'real Godot binary, and SKIPS without one; tools/verify-ui/check-ui.mjs holds ' +
    'the shipped panel manifest and the token set to the same corpus with nothing ' +
    'but Node, so the parity claim still has a gate on a box with no Godot',
  'content-library': null, // documented in RUNTIME_CORE_ADOPTION.md §10.5: no reader here
  content: null, // this repo's own fixture, declared local in conformance/VENDORED.json
};

/**
 * What is actually VENDORED under conformance/ — the Prolog corpus files by
 * base name, every `area` a band-120 decision corpus declares, and any
 * directory that is accounted for by neither list.
 *
 * Read from disk rather than from the manifest on purpose: the manifest says
 * what was copied, this says what is there to run, and US-2's whole subject is
 * the gap between those two.
 */
export function readVendoredCorpus(root = CORPUS_DIR) {
  const prolog = new Set();
  const prologDir = path.join(root, 'prolog');
  if (fs.existsSync(prologDir)) {
    for (const f of fs.readdirSync(prologDir)) {
      if (f.endsWith('.json')) prolog.add(f.slice(0, -'.json'.length));
    }
  }
  const decisionAreas = new Set();
  const unaccounted = [];
  for (const dir of fs.readdirSync(root, { withFileTypes: true })) {
    if (!dir.isDirectory()) continue;
    if (!DECISION_DIRS.includes(dir.name)) {
      if (!(dir.name in CORPUS_RUN_ELSEWHERE)) unaccounted.push(dir.name);
      continue;
    }
    for (const f of fs.readdirSync(path.join(root, dir.name))) {
      if (!f.endsWith('.json')) continue;
      let doc;
      try {
        doc = JSON.parse(read(path.join(root, dir.name, f)));
      } catch {
        continue;
      }
      if (typeof doc.area === 'string' && Array.isArray(doc.cases)) decisionAreas.add(doc.area);
    }
  }
  return { prolog, decisionAreas, unaccounted };
}

// ── the checks ──────────────────────────────────────────────────────────────

const problems = [];

function problem(check, message) {
  problems.push(`${check}: ${message}`);
}

function same(a, b) {
  return a.length === b.length && a.every((item, i) => item === b[i]);
}

/**
 * @param {object} manifest the vendored (or freshly derived) declaration
 * @param {object} repo     `{ gdClasses, implementations, bridge, adapterOrders, sessionOrders }`
 */
export function runChecks(manifest, repo) {
  problems.length = 0;

  // 1. MANIFEST — the seven modules are all here, with parts.
  for (const id of BAND_120) {
    const module = manifest.modules[id];
    if (!module) {
      problem('manifest', `no entry for module "${id}"`);
      continue;
    }
    if (module.hostInterface.length === 0) {
      problem('manifest', `module "${id}" names no host interface`);
    }
    if (module.decisionLayer.length === 0) {
      problem('manifest', `module "${id}" names no decision layer`);
    }
  }

  // 2. CONTRACT — every interface's members exist on the GDScript base class.
  for (const [name, members] of Object.entries(manifest.interfaces)) {
    const gdName = name.replace(/^I/, '');
    const gdMembers = repo.gdClasses[gdName];
    if (!gdMembers) {
      problem('contract', `${name} has no base class ${gdName} in insimul_mechanic_hosts.gd`);
      continue;
    }
    for (const member of members) {
      const snake = member.replace(/([A-Z])/g, '_$1').toLowerCase();
      if (!gdMembers.includes(snake)) {
        problem('contract', `${name}.${member} has no ${gdName}.${snake}() in GDScript`);
      }
    }
  }

  // 3. IMPLEMENTATION — somebody actually implements each one.
  for (const name of Object.keys(manifest.interfaces)) {
    const gdName = name.replace(/^I/, '');
    const implementations = repo.implementations[gdName] ?? [];
    const stub = manifest.stubbed?.[name];
    if (implementations.length === 0 && !stub) {
      problem(
        'implementation',
        `${name} is implemented by nothing — add a class extending InsimulMechanicHosts.${gdName}, or a "stubbed" entry stating the consequence`,
      );
    }
    if (stub && !stub.consequence) {
      problem('implementation', `${name} is stubbed with no stated consequence`);
    }
  }

  // 4. BRIDGE — the adapter's table agrees with core, and its rows exist.
  for (const id of BAND_120) {
    const declared = manifest.modules[id];
    const bridged = repo.bridge.modules[id];
    if (!bridged) {
      problem('bridge', `entry.js has no rows for module "${id}"`);
      continue;
    }
    if (!declared) continue;
    if (!same([...bridged.hostInterfaces].sort(), [...declared.hostInterface].sort())) {
      problem(
        'bridge',
        `module "${id}" host interfaces disagree: entry.js has [${bridged.hostInterfaces}], core declares [${declared.hostInterface}]`,
      );
    }
    for (const layer of bridged.layers) {
      if (!declared.decisionLayer.includes(layer)) {
        problem('bridge', `module "${id}" names decision layer "${layer}", which core does not`);
      }
    }
    if (bridged.rows.length === 0) problem('bridge', `module "${id}" declares no rows`);
    for (const row of bridged.rows) {
      if (!repo.bridge.methods.includes(row)) {
        problem('bridge', `row "${row}" is declared but has no entry in entry.js's METHODS`);
      }
    }
  }

  // 5. ORDERS — everything the adapter can emit, the session can carry out.
  for (const order of repo.adapterOrders) {
    const known = repo.sessionOrders.some((o) => o.host === order.host && o.call === order.call);
    if (!known) {
      problem(
        'orders',
        `the adapter can emit ${order.host}.${order.call} and insimul_mechanic_session.gd has no dispatch for it`,
      );
    }
  }

  // 6. CORPUS — every module's vectors are vendored AND have something that
  //    runs them. This is US-2's whole subject: a corpus copied into
  //    conformance/ that nothing executes is a checked-in file, and this
  //    repository has shipped exactly that. Both directions are checked,
  //    because each catches a different way of ending up back there.
  const runners = repo.corpusRunners;
  const vendored = repo.vendoredCorpus;
  for (const id of BAND_120) {
    const declared = manifest.modules[id];
    if (!declared) continue;
    // 6a. Core names a Prolog corpus per module; it must be on disk here.
    for (const name of declared.conformanceCorpus) {
      if (!vendored.prolog.has(name)) {
        problem(
          'corpus',
          `module "${id}" declares conformance corpus "${name}", which is not vendored — ` +
            're-vendor with `npm run vendor:conformance -- --core <packages/core>`',
        );
      }
    }
    if (declared.conformanceCorpus.length === 0) {
      problem('corpus', `module "${id}" declares no conformance corpus at all`);
    }
    // 6b. Its DECISION areas (host-corpus.js) must be vendored and runnable.
    const owned = runners.byModule[id];
    if (owned === undefined) {
      problem(
        'corpus',
        `module "${id}" has no entry in host-corpus.js's CORPUS_AREAS_BY_MODULE — ` +
          'list its decision areas, or an empty list with the reason there are none',
      );
      continue;
    }
    for (const area of owned) {
      if (!runners.areas.includes(area)) {
        problem('corpus', `module "${id}" claims decision area "${area}", which has no runner`);
      }
      if (!vendored.decisionAreas.has(area)) {
        problem('corpus', `module "${id}" claims decision area "${area}", which is not vendored`);
      }
    }
  }
  // 6c. Nothing vendored is orphaned, and no runner is unreachable. The first
  //     is the checked-in file; the second is a runner whose corpus was quietly
  //     dropped from the mirror, which reads as green because it never runs.
  for (const area of vendored.decisionAreas) {
    if (!runners.areas.includes(area)) {
      problem(
        'corpus',
        `conformance/ vendors decision area "${area}" and nothing executes it — ` +
          'add a runner in host-corpus.js, or exclude the corpus in vendor-conformance.mjs\'s NOT_MIRRORED with a reason',
      );
    }
    if (!Object.values(runners.byModule).some((areas) => areas.includes(area))) {
      problem('corpus', `decision area "${area}" is vendored and run but belongs to no module`);
    }
  }
  for (const area of runners.areas) {
    if (!vendored.decisionAreas.has(area)) {
      problem('corpus', `host-corpus.js can run "${area}" and no vendored corpus declares it`);
    }
  }
  // 6d. Every vendored directory is accounted for by SOMETHING — a band-120
  //     runner, or a named gate, or an explicit "nothing here runs it".
  for (const dir of vendored.unaccounted ?? []) {
    problem(
      'corpus',
      `conformance/${dir}/ is vendored and appears in neither DECISION_DIRS nor ` +
        'CORPUS_RUN_ELSEWHERE — say what runs it, or say that nothing does and where that is written up',
    );
  }

  // 7. ACTIVATION — the active module set is DATA, and the engine reads it.
  //    US-3's acceptance is "adding a module to a bundle requires no engine
  //    code change", which is only checkable one way: the GDScript that
  //    activates must name NO module, NO pack area and NO genre. A gate that
  //    took the claim on trust would pass over a hardcoded list forever.
  const table = repo.activationTable;
  if (table === null || table === undefined) {
    problem(
      'activation',
      'conformance/modules/genre-activation.json is not vendored — re-vendor with ' +
        '`npm run vendor:conformance -- --core <packages/core>`',
    );
  } else {
    for (const row of Object.keys(ACTIVATION_ROWS)) {
      if (!repo.bridge.methods.includes(row)) {
        problem('activation', `entry.js has no "${row}" row — ${ACTIVATION_ROWS[row]}`);
      }
    }
    const genres = Object.entries(table.genres ?? {});
    if (genres.length === 0) problem('activation', 'the activation table declares no genre bundles');

    // 7a. The table and the manifest are two derivations of ONE core manifest,
    //     vendored by two different tools. A table at one core sha beside a
    //     MODULE_HOSTS.json at another is exactly the drift CLAUDE.md warns
    //     about, and this is where it becomes visible without a core checkout.
    for (const [genre, set] of genres) {
      for (const module of set.modules ?? []) {
        const declared = manifest.modules[module.id];
        if (!declared) {
          if (!(module.id in NOT_ADOPTED)) {
            problem(
              'activation',
              `genre "${genre}" activates module "${module.id}", which this repo neither adopts ` +
                '(BAND_120) nor declares unadopted (NOT_ADOPTED) — say which, with what a game ' +
                'of that genre gets for it',
            );
          }
          continue;
        }
        if (!same([...module.hostInterface].sort(), [...declared.hostInterface].sort())) {
          problem(
            'activation',
            `module "${module.id}" names host interfaces [${module.hostInterface}] in the ` +
              `activation table and [${declared.hostInterface}] in MODULE_HOSTS.json`,
          );
        }
      }
    }

    // 7b. Nothing in the reader names a mechanic. Every module id, pack area
    //     and genre id in the table is searched for as a whole word in the
    //     GDScript that resolves and activates — comments included, because a
    //     comment that lists the modules rots exactly like code does.
    const forbidden = new Set();
    for (const [genre, set] of genres) {
      forbidden.add(genre);
      for (const area of set.predicatePacks ?? []) forbidden.add(area);
      for (const module of set.modules ?? []) forbidden.add(module.id);
    }
    for (const area of table.alwaysActivePacks ?? []) forbidden.add(area);
    for (const [file, source] of Object.entries(repo.activationSources)) {
      for (const name of forbidden) {
        if (new RegExp(`(^|[^A-Za-z0-9_-])${name}([^A-Za-z0-9_-]|$)`).test(source)) {
          problem(
            'activation',
            `${file} names "${name}" — the active set is data, and a reader that ` +
              'spells a module, a pack or a genre stops answering when core adds one',
          );
        }
      }
    }
    if (Object.keys(repo.activationSources).length === 0) {
      problem('activation', 'no activation reader in addons/ — nothing reads the table');
    }
  }

  return problems.slice();
}

// ── driver ──────────────────────────────────────────────────────────────────

function fail(message) {
  console.error(`check-mechanics: ${message}`);
  process.exit(1);
}

function readRepo() {
  return {
    gdClasses: parseGdClasses(read(HOSTS_GD)),
    implementations: findImplementations(REPO),
    bridge: parseBridge(read(ENTRY_JS)),
    adapterOrders: parseAdapterOrders(read(HOST_MECHANICS_JS)),
    sessionOrders: parseSessionOrders(read(SESSION_GD)),
    corpusRunners: parseCorpusRunners(read(HOST_CORPUS_JS)),
    vendoredCorpus: readVendoredCorpus(),
    activationTable: readActivationTable(),
    activationSources: readActivationSources(),
  };
}

function loadManifest() {
  if (!fs.existsSync(MANIFEST_PATH)) fail(`no MODULE_HOSTS.json — run with --core <packages/core> --write`);
  return JSON.parse(read(MANIFEST_PATH));
}

/** Four mutations, one per check, proving none of them is vacuous. */
function runSelfTest(manifest, repo) {
  const controls = [
    [
      'manifest',
      () => {
        const copy = structuredClone(manifest);
        delete copy.modules.combat;
        return [copy, repo];
      },
    ],
    [
      'contract',
      () => {
        const copy = structuredClone(manifest);
        copy.interfaces.ICombatSystem = [...copy.interfaces.ICombatSystem, 'inventedMember'];
        return [copy, repo];
      },
    ],
    [
      'implementation',
      () => {
        const copy = structuredClone(repo);
        copy.implementations = {};
        return [manifest, copy];
      },
    ],
    [
      'bridge',
      () => {
        const copy = structuredClone(repo);
        copy.bridge.modules.combat.rows = ['combat.invented'];
        return [manifest, copy];
      },
    ],
    [
      'orders',
      () => {
        const copy = structuredClone(repo);
        copy.sessionOrders = [];
        return [manifest, copy];
      },
    ],
    [
      // The control that matters most: a corpus present on disk with nothing
      // behind it is the failure this repo has actually shipped.
      'corpus',
      () => {
        const copy = structuredClone(repo);
        copy.corpusRunners = { areas: [], byModule: {} };
        return [manifest, copy];
      },
    ],
    [
      // The control for US-3's whole subject: a reader with a mechanic's name
      // in it is a hardcoded list wearing a table's clothes.
      'activation',
      () => {
        const copy = structuredClone(repo);
        const first = Object.keys(copy.activationTable?.genres ?? {})[0] ?? 'rpg';
        copy.activationSources = { 'invented.gd': `if module == "${first}":` };
        return [manifest, copy];
      },
    ],
  ];

  let ok = true;
  for (const [name, mutate] of controls) {
    const [m, r] = mutate();
    const found = runChecks(m, r);
    const fired = found.some((p) => p.startsWith(`${name}:`));
    console.log(`  ${fired ? '✓' : '✗'} negative control: ${name} fails when broken`);
    ok = ok && fired;
  }
  return ok;
}

function main() {
  const repo = readRepo();

  if (coreArg && writeMode) {
    const derived = deriveFromCore(coreArg);
    fs.writeFileSync(
      MANIFEST_PATH,
      `${JSON.stringify({ description: DESCRIPTION, ...derived, stubbed: loadStubbed() }, null, 2)}\n`,
    );
    console.log(
      `check-mechanics: wrote MODULE_HOSTS.json from core ${derived.coreCommit.slice(0, 7)} ` +
        `(${Object.keys(derived.modules).length} modules, ${Object.keys(derived.interfaces).length} interfaces)`,
    );
  }

  const manifest = loadManifest();

  if (coreArg && !writeMode) {
    // The real drift check: re-derive and diff against what is vendored.
    const derived = deriveFromCore(coreArg);
    const vendored = JSON.stringify({ modules: manifest.modules, interfaces: manifest.interfaces });
    const fresh = JSON.stringify({ modules: derived.modules, interfaces: derived.interfaces });
    if (vendored !== fresh) {
      fail(
        `MODULE_HOSTS.json has DRIFTED from core ${derived.coreCommit.slice(0, 7)} — ` +
          `re-derive with --core <packages/core> --write and fix what the diff reveals`,
      );
    }
    console.log(`check-mechanics: manifest matches core ${derived.coreCommit.slice(0, 7)}`);
  }

  if (selfTest) {
    console.log('check-mechanics: negative controls');
    if (!runSelfTest(manifest, repo)) fail('a negative control did NOT fail — a check is vacuous');
  }

  const found = runChecks(manifest, repo);
  if (found.length > 0) {
    for (const line of found) console.error(`  ✗ ${line}`);
    fail(`${found.length} problem(s)`);
  }

  const interfaces = Object.keys(manifest.interfaces).length;
  const rows = Object.values(repo.bridge.modules).reduce((n, m) => n + m.rows.length, 0);
  console.log(
    `check-mechanics: ${BAND_120.length} module(s), ${interfaces} host interface(s) implemented, ` +
      `${rows} bridge row(s), core ${String(manifest.coreCommit).slice(0, 7)}`,
  );
  const activated = new Set(
    Object.values(repo.activationTable?.genres ?? {}).flatMap((set) =>
      (set.modules ?? []).map((m) => m.id),
    ),
  );
  console.log(
    `check-mechanics: ${Object.keys(repo.activationTable?.genres ?? {}).length} genre bundle(s) ` +
      `activate ${activated.size} module(s); ${[...activated].filter((id) => id in NOT_ADOPTED).length} ` +
      `of them are declared unadopted (${Object.keys(NOT_ADOPTED).join(', ')})`,
  );
  console.log(
    `check-mechanics: ${repo.vendoredCorpus.prolog.size} vendored Prolog corpus file(s), ` +
      `${repo.corpusRunners.areas.length} decision area(s) with a runner — ` +
      'executed by gdextension/test/run_corpus_tests.sh',
  );
  if (!coreArg) {
    console.log('check-mechanics: no --core given, so drift against core itself was NOT checked');
  }
}

const DESCRIPTION =
  'GENERATED by tools/verify-mechanics/check-mechanics.mjs --core <packages/core> --write. ' +
  'A vendored derivation of core\'s own module manifest (`src/modules/module-contract.ts`) and the ' +
  'host-interface declarations it names, so this standalone repo can check its GDScript hosts and its ' +
  'bridge rows against core without importing it. `stubbed` is hand-maintained and is the ONLY place an ' +
  'unimplemented interface may be declared — with the consequence stated.';

/** Hand-maintained; preserved across a re-derivation. */
function loadStubbed() {
  if (!fs.existsSync(MANIFEST_PATH)) return {};
  return JSON.parse(read(MANIFEST_PATH)).stubbed ?? {};
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
