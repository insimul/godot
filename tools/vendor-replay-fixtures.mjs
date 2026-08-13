#!/usr/bin/env node
// vendor-replay-fixtures.mjs — mint (and guard) the portable input-trace corpus
// the bridge's replay leg is held to.
//
// WHY THIS FILE EXISTS. Tasklist 180 shipped, in core, a portable
// content-addressed input-trace artifact (`insimul-input-trace-v1`), a replay
// driver, and the outcome document a four-way comparison diffs
// (`insimul-replay-outcome-v1`). §8.6 is explicit about what that artifact is
// FOR: TBP refuses a foreign-session `trace_ref` by design (Talos RISK-60), so
// the trace — not `play_input_trace` — is how one recorded session reaches four
// engines. This repository is the Godot leg of that comparison.
//
// It cannot simply CALL core's driver. `entry.js` adopts core across the C ABI
// through QuickJS, and `src/replay/` opens with `import { createHash } from
// 'node:crypto'` — which `gdextension/corebridge/js/host-crypto.js` deliberately
// makes throw, for the reason written there: "if a future slice DOES need
// hashing across the boundary, the right fix is to route it to libinsimul/the C
// host rather than to grow a second SHA-256 here." This repository already has
// that C host hash — `gdextension/src/sha256.cpp` and `canonical_json.cpp`, both
// byte-pinned to `packages/core/src/save-envelope.ts` — so the replay leg is a
// PORT over the hash this project already owns, in the same shape as the
// refuse-at-hello decision (talos_bridge.cpp).
//
// And a port is worth exactly what the evidence that it agrees is worth. So this
// tool bundles core's OWN `src/replay/index.ts` under Node (where `node:crypto`
// works), runs it, and writes down what it answered: the content addresses it
// mints, the documents it refuses and with which code, the entropy it derives
// per tick, and the outcome its own driver produces from a declared world
// program. `test_talos_replay.cpp` replays all of it. A C++ leg that computes a
// different digest, refuses a different document, or drives a different tick
// sequence fails here rather than in a four-way run, where it would read as
// Godot diverging from Babylon.
//
// THE WORLD PROGRAM IS DATA, and that is the point. A hand-written reference
// world in JS and a hand-written one in C++ would be two implementations to
// disagree, and their disagreement would be indistinguishable from a driver bug
// — which is the only thing this corpus is trying to measure. `program.json`
// declares the world as a table (signal -> fact, an idle rule keyed on the
// tick's entropy), so both sides interpret one specification and every remaining
// difference is in the DRIVER: the tick loop, the bucketing of inputs, the
// entropy derivation and the final KB digest. Those four are the bridge's whole
// job; the KB itself is Insimul's.
//
// TWO MODES, matching the sibling vendor tools:
//
//   node tools/vendor-replay-fixtures.mjs --core <path-to-packages/core>
//       Re-mint from a core checkout and write. Run it when core's replay
//       module moves.
//
//   node tools/vendor-replay-fixtures.mjs --check
//       Verify the checked-in corpus against its own recorded hashes and floors.
//       Needs no core checkout, so it runs in this repo's gates. Pass --core as
//       well when one IS available and it additionally re-mints into a temporary
//       directory and diffs — that is the only real drift check.
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..');
const FIXTURES = path.join(REPO, 'gdextension', 'test', 'fixtures', 'replay');
const MANIFEST = path.join(FIXTURES, 'VENDORED.json');
// The input vocabulary SHIPS with the addon rather than living in the corpus,
// because it is not test data: core refuses a trace whose `signal` names an
// Insimul action id, and a port that cannot see the action ids would silently
// admit a document core refuses. Nothing is compiled in that core publishes —
// the same rule supported-versions.json obeys.
const VOCABULARY = path.join(REPO, 'addons', 'insimul_talos', 'input-vocabulary.json');
const VOCABULARY_FORMAT = 'insimul.talos-bridge.input-vocabulary/1';

// Floored by hand, per the discipline tools/vendor-conformance.mjs uses: growing
// the corpus must not break the gate, shrinking it must. A corpus that quietly
// lost its refusal cases would still be two-sided and would still pass.
const FLOORS = Object.freeze({
  traces: 12,
  outcomes: 7,
  comparisons: 6,
  runs: 4,
});

const args = process.argv.slice(2);
const coreArg = argValue('--core') ?? process.env.INSIMUL_CORE_DIR ?? null;
const checkOnly = args.includes('--check') || coreArg === null;

function argValue(flag) {
  const i = args.indexOf(flag);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

function sha256(text) {
  return createHash('sha256').update(text).digest('hex');
}

function fail(message) {
  console.error(`vendor-replay-fixtures: ${message}`);
  process.exit(1);
}

function write(dir, rel, value) {
  const abs = path.join(dir, rel);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, `${JSON.stringify(value, null, 2)}\n`);
}

// ── The world program: one specification, two interpreters ──────────────────
//
// `$tick`, `$entropy` and the payload of the input that fired the rule are
// substituted; everything else is a literal. Numbers stay numbers, because a
// host that stringifies `18` on the way out has diverged and `digestKBFacts`
// must be able to say so.
const PROGRAM = Object.freeze({
  description:
    'The reference world both the JS minting side and gdextension/src/talos_replay.cpp interpret. Declared as data so that a divergence between the two is a DRIVER divergence — the tick loop, the input bucketing, the per-tick entropy, the KB digest — and never two hand-written toy worlds disagreeing about a toy.',
  on_open: [
    { predicate: 'world_open', args: ['$seed'] },
    { predicate: 'root_entropy', args: ['$entropy'] },
  ],
  on_signal: {
    'button.interact': { predicate: 'interacted', args: ['$tick', '$edge'] },
    'button.jump': { predicate: 'jumped', args: ['$tick'] },
    'axis.move_x': { predicate: 'moved', args: ['$tick', '$value'] },
    'pointer.aim': { predicate: 'aimed', args: ['$tick', '$x', '$y'] },
    'text.entry': { predicate: 'typed', args: ['$text'] },
  },
  // Fires only on a tick that carried NO input, and only when the tick's own
  // entropy says so. Idle ticks are where a routine or a radiant beat decides
  // something, and a driver that skipped them would replay a different session
  // from the one that was recorded — so the corpus makes skipping them visible.
  on_idle: { modulo: 5, predicate: 'beat', args: ['$tick', '$entropy'] },
});

function resolveArg(token, context) {
  if (typeof token !== 'string' || !token.startsWith('$')) return token;
  switch (token) {
    case '$seed':
      return context.seed;
    case '$tick':
      return context.tick;
    case '$entropy':
      return context.entropy;
    case '$edge':
      return context.input?.edge ?? '';
    case '$value':
      return context.input?.value ?? 0;
    case '$x':
      return context.input?.x ?? 0;
    case '$y':
      return context.input?.y ?? 0;
    case '$text':
      return context.input?.text ?? '';
    default:
      return token;
  }
}

/** The `IReplayWorld` core's driver is handed. Interprets PROGRAM, nothing else. */
function programWorld() {
  let facts = [];
  return {
    open(setup) {
      facts = setup.world.facts.map((fact) => ({ predicate: fact.predicate, args: [...fact.args] }));
      for (const rule of PROGRAM.on_open) {
        facts.push({
          predicate: rule.predicate,
          args: rule.args.map((token) => resolveArg(token, { seed: setup.seed, entropy: setup.entropy })),
        });
      }
    },
    applyInputs(step) {
      if (step.inputs.length === 0) {
        const idle = PROGRAM.on_idle;
        if (step.entropy % idle.modulo === 0) {
          facts.push({
            predicate: idle.predicate,
            args: idle.args.map((token) => resolveArg(token, { tick: step.tick, entropy: step.entropy })),
          });
        }
        return;
      }
      for (const input of step.inputs) {
        const rule = PROGRAM.on_signal[input.signal];
        if (rule === undefined) continue;
        facts.push({
          predicate: rule.predicate,
          args: rule.args.map((token) => resolveArg(token, { tick: step.tick, entropy: step.entropy, input })),
        });
      }
    },
    readFacts() {
      return facts;
    },
  };
}

// ── The world the corpus is recorded against ────────────────────────────────

const WORLD = Object.freeze({
  worldId: 'w-riverwatch',
  facts: [
    { predicate: 'at', args: ['hero', 'gate'] },
    { predicate: 'at', args: ['bandit', 'road'] },
    { predicate: 'health', args: ['bandit', 30, 30] },
    { predicate: 'carries', args: ['hero', 'lantern'] },
  ],
  rules: ['blocked(X) :- at(X, gate), locked(gate).'],
  packs: ['base', 'rpg'],
});

const OTHER_WORLD = Object.freeze({
  ...WORLD,
  facts: [...WORLD.facts, { predicate: 'locked', args: ['gate'] }],
});

const SEED = 'riverwatch-0001';

const INPUTS = Object.freeze([
  { tick: 0, channel: 'button', signal: 'button.interact', edge: 'down' },
  { tick: 0, channel: 'axis', signal: 'axis.move_x', value: 0.5 },
  { tick: 3, channel: 'button', signal: 'button.interact', edge: 'up' },
  { tick: 7, channel: 'pointer', signal: 'pointer.aim', x: 0.25, y: -0.75 },
  { tick: 11, channel: 'text', signal: 'text.entry', text: 'yes' },
  { tick: 11, channel: 'button', signal: 'button.jump', edge: 'down' },
  { tick: 18, channel: 'axis', signal: 'axis.move_x', value: -1 },
]);

// ── Minting ─────────────────────────────────────────────────────────────────

async function loadCore(core) {
  if (!fs.existsSync(path.join(core, 'src', 'replay', 'index.ts'))) {
    fail(`${core} does not look like packages/core (no src/replay/index.ts)`);
  }
  // esbuild is resolved FROM the core checkout, exactly as vendor-core-bundle.mjs
  // does it: this repository has no node_modules of its own.
  const require = createRequire(path.join(core, 'package.json'));
  let esbuild;
  try {
    esbuild = await import(require.resolve('esbuild'));
  } catch {
    fail(`esbuild is not resolvable from ${core} — run this from a checkout with core's node_modules installed`);
  }
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'insimul-replay-'));
  const bundle = async (entry, name) => {
    const out = path.join(dir, name);
    await esbuild.build({
      entryPoints: [path.join(core, entry)],
      bundle: true,
      format: 'esm',
      platform: 'node',
      target: 'node18',
      outfile: out,
      // Node's own builtins stay external: this bundle runs under Node, and the
      // whole reason the fixtures exist is that the ADAPTER's runtime cannot.
      external: ['node:crypto', 'crypto'],
      logLevel: 'warning',
    });
    return import(out);
  };
  return {
    module: await bundle('src/replay/index.ts', 'replay.mjs'),
    actions: await bundle('src/game-engine/action-matrix.ts', 'action-matrix.mjs'),
  };
}

/** A trace case: the document, and what core's own reader answered about it. */
function traceCase(core, name, why, document, world = WORLD) {
  const result = core.openInputTrace(document, world);
  return {
    file: `traces/${name}.json`,
    body: {
      case: name,
      why,
      world: world === WORLD ? 'world.json' : 'world-other.json',
      document,
      expect: result.ok
        ? { ok: true, id: result.artifact.id }
        : { ok: false, code: result.refusal.code, message: result.refusal.message },
    },
  };
}

function outcomeCase(core, name, why, document) {
  const result = core.readReplayOutcome(document);
  return {
    file: `outcomes/${name}.json`,
    body: {
      case: name,
      why,
      document,
      expect: result.ok
        ? { ok: true, digest: result.outcome.digest }
        : { ok: false, code: result.refusal.code, message: result.refusal.message },
    },
  };
}

function comparisonCase(core, name, why, recorded, replayed) {
  const comparison = core.compareReplayOutcomes(recorded, replayed);
  return {
    file: `comparisons/${name}.json`,
    body: {
      case: name,
      why,
      recorded,
      replayed,
      expect: {
        converged: comparison.converged,
        kinds: comparison.divergences.map((d) => d.kind),
        ...(comparison.firstDivergentTick === undefined
          ? {}
          : { firstDivergentTick: comparison.firstDivergentTick }),
      },
    },
  };
}

function runCase(core, name, why, trace, options) {
  const result = core.replayInputTrace(trace, WORLD, programWorld(), options);
  if (!result.ok) fail(`run fixture ${name} was refused by core: ${result.refusal.message}`);
  return {
    file: `runs/${name}.json`,
    body: {
      case: name,
      why,
      trace,
      options,
      // The whole per-tick plan, so a C++ driver that bucketed inputs onto the
      // wrong tick, skipped an idle tick or derived a different entropy fails on
      // the STEP rather than four thousand facts later on the digest.
      steps: expectedSteps(core, trace, options),
      expect: {
        traceId: result.artifact.id,
        finalTick: result.outcome.finalTick,
        inputTicks: result.outcome.inputTicks,
        ticks: result.ticks,
        inputsApplied: result.inputsApplied,
        outcome: result.outcome,
      },
    },
  };
}

/** The `(tick, inputs, entropy)` sequence core's driver produced, tick by tick. */
function expectedSteps(core, trace, options) {
  const inputs = trace.body.inputs;
  const last = inputs.length === 0 ? -1 : inputs[inputs.length - 1].tick;
  const finalTick = Math.max(last, options.throughTick ?? -1);
  const steps = [];
  for (let tick = 0; tick <= finalTick; tick++) {
    steps.push({
      tick,
      inputs: inputs.filter((input) => input.tick === tick),
      entropy: core.replayEntropy(trace.body.seed, tick),
    });
  }
  return steps;
}

async function mint(core, outDir, vocabularyPath) {
  const { module: replay, actions } = await loadCore(core);

  // ── the shipped input vocabulary ──
  const actionIds = actions.ACTION_MATRIX.map((entry) => entry.actionId).sort();
  if (actionIds.length === 0) fail('core published no action ids — the vocabulary would refuse nothing');
  fs.mkdirSync(path.dirname(vocabularyPath), { recursive: true });
  fs.writeFileSync(
    vocabularyPath,
    `${JSON.stringify(
      {
        format: VOCABULARY_FORMAT,
        description:
          "The engine-input layer's vocabulary, mirrored from core. `channels` is the closed set of device concepts an input-trace record may name; `action_ids` is what a `signal` may NOT be. §8.7 step 3: a trace of already-decided actions begs the question the trace exists to answer, so `attack` is refused as a signal even though `button.attack` is fine. GENERATED by tools/vendor-replay-fixtures.mjs — do not hand-edit.",
        source: 'packages/core/src/game-engine/action-matrix.ts + src/replay/input-trace.ts',
        channels: ['button', 'axis', 'pointer', 'text'],
        action_layer_keys: [...replay.ACTION_LAYER_KEYS],
        action_ids: actionIds,
      },
      null,
      2,
    )}\n`,
  );

  const worldDigest = replay.digestWorldContent(WORLD);
  const otherDigest = replay.digestWorldContent(OTHER_WORLD);
  const descriptor = replay.describeWorldContent(WORLD, 'Riverwatch');
  const otherDescriptor = replay.describeWorldContent(OTHER_WORLD, 'Riverwatch (locked gate)');

  const trace = replay.buildInputTrace(
    { seed: SEED, world: descriptor, inputs: INPUTS },
    { recorder: 'core@replay-fixtures', note: 'minted by tools/vendor-replay-fixtures.mjs' },
  );
  const emptyTrace = replay.buildInputTrace({ seed: SEED, world: descriptor, inputs: [] });

  // ── world.json / program.json / entropy.json ──
  write(outDir, 'world.json', {
    description:
      'The authored world every trace in this corpus was recorded against, and the digest core computed for it. The C++ leg must reproduce that digest from the same bytes, or it cannot refuse a mismatched world before replaying — which is the one refusal §8.6 wants decided by arithmetic.',
    world: WORLD,
    contentDigest: worldDigest,
    descriptor,
  });
  write(outDir, 'world-other.json', {
    description:
      'The same world with one authored fact added. Present so world_content_mismatch is a REAL case rather than a hand-edited digest: a world that changed since recording makes a divergence say nothing about determinism.',
    world: OTHER_WORLD,
    contentDigest: otherDigest,
    descriptor: otherDescriptor,
  });
  write(outDir, 'program.json', PROGRAM);
  write(outDir, 'entropy.json', {
    description:
      'replayEntropy(seed) and replayEntropy(seed, tick) as core derives them — FNV-1a over the same length-prefixed key derivedStream mixes. A world seeds its PRNG from these numbers, so a leg that derives a different one diverges in the KB for a reason that has nothing to do with its mechanics.',
    seeds: [SEED, 'w-empty', ''].filter((seed) => seed.length > 0).map((seed) => ({
      seed,
      root: replay.replayEntropy(seed),
      ticks: Array.from({ length: 24 }, (_, tick) => ({ tick, entropy: replay.replayEntropy(seed, tick) })),
    })),
  });

  const files = [];

  // ── traces/ ──
  files.push(
    traceCase(replay, 'admit-recorded-session', 'The corpus\'s two-sided half: a well-formed trace, accepted, with the content address core minted for it.', trace),
    traceCase(replay, 'admit-empty-trace', 'A session in which nobody touched a control is a legitimate session — it still has a seed, a world and an id.', emptyTrace),
    traceCase(replay, 'refuse-not-an-object', 'A trace arrives as parsed JSON from a file, a socket or the C ABI, and none of those is a type system.', [1, 2, 3]),
    traceCase(replay, 'refuse-unknown-format', 'A format tag this leg cannot interpret is refused rather than read optimistically.', { ...trace, format: 'insimul-input-trace-v2' }),
    traceCase(replay, 'refuse-id-not-a-digest', 'The id is a content address; a document whose id is not one cannot be checked against its contents.', { ...trace, id: 'not-a-digest' }),
    traceCase(replay, 'refuse-id-mismatch', 'The whole value of a content-addressed trace is that it cannot quietly become a different one — an input was edited and the id was not.', {
      ...trace,
      body: { ...trace.body, inputs: [...INPUTS.slice(0, 6), { tick: 18, channel: 'axis', signal: 'axis.move_x', value: -0.5 }] },
    }),
    traceCase(replay, 'refuse-action-layer-record', '§8.7 step 3: a trace of already-decided actions begs the question the trace exists to answer, so a record carrying an action-layer key is refused BY NAME.', {
      ...trace,
      body: { ...trace.body, inputs: [{ tick: 0, channel: 'button', signal: 'button.interact', edge: 'down', action: 'attack' }] },
    }),
    traceCase(replay, 'refuse-action-id-as-signal', 'Signals are device-first (`button.interact`) so the input and action vocabularies cannot collide by convention — and an Insimul action id spelled as a signal is refused even so.', {
      ...trace,
      body: { ...trace.body, inputs: [{ tick: 0, channel: 'button', signal: 'attack', edge: 'down' }] },
    }),
    traceCase(replay, 'refuse-wrong-channel-payload', 'A record that carries another channel\'s field is malformed rather than tolerated: a trace whose extra fields are silently dropped is a trace whose id is a lie.', {
      ...trace,
      body: { ...trace.body, inputs: [{ tick: 0, channel: 'button', signal: 'button.interact', value: 0.5 }] },
    }),
    traceCase(replay, 'refuse-ticks-go-backwards', 'Inputs are recorded in sample order; a tick that goes backwards is a recorder fault, not a session.', {
      ...trace,
      body: { ...trace.body, inputs: [{ tick: 4, channel: 'button', signal: 'button.jump', edge: 'down' }, { tick: 1, channel: 'button', signal: 'button.jump', edge: 'up' }] },
    }),
    traceCase(replay, 'refuse-world-id-mismatch', 'A trace recorded against another world is refused before a single input is applied.', replay.buildInputTrace({ seed: SEED, world: replay.describeWorldContent({ ...WORLD, worldId: 'w-elsewhere' }), inputs: INPUTS })),
    traceCase(replay, 'refuse-world-content-mismatch', 'The world moved since recording. A divergence caused by that says nothing about determinism, so it is caught by arithmetic instead of by watching a replay go wrong.', trace, OTHER_WORLD),
  );

  // ── outcomes/ ──
  const run = replay.replayInputTrace(trace, WORLD, programWorld(), {
    engine: 'core-reference',
    throughTick: 23,
    checkpointEvery: 6,
  });
  if (!run.ok) fail(`core refused its own trace: ${run.refusal.message}`);
  const recorded = run.outcome;

  files.push(
    outcomeCase(replay, 'admit-recorded-outcome', 'The two-sided half: the outcome core\'s own driver produced, accepted, with the KB digest it computed.', recorded),
    outcomeCase(replay, 'refuse-unknown-format', 'An outcome document whose format tag this leg cannot interpret.', { ...recorded, format: 'insimul-replay-outcome-v2' }),
    outcomeCase(replay, 'refuse-trace-id-absent', 'An outcome that cannot name its session cannot be compared with another engine\'s.', { ...recorded, traceId: 'sess-1' }),
    outcomeCase(replay, 'refuse-engine-absent', 'The producer id is what a four-way report labels its columns with.', { ...recorded, engine: '' }),
    outcomeCase(replay, 'refuse-digest-mismatch', 'A document that disagrees with itself: whichever half a consumer believed, it would be believing the wrong one.', { ...recorded, facts: [...recorded.facts, { predicate: 'ghost', args: ['x'] }] }),
    outcomeCase(replay, 'refuse-fact-arg-type', 'A host that stringifies `30` on the way out has diverged, and the reader says so rather than digesting the difference away.', {
      ...recorded,
      facts: [{ predicate: 'health', args: ['bandit', true] }],
      digest: replay.digestKBFacts([{ predicate: 'health', args: ['bandit', true] }]),
    }),
    outcomeCase(replay, 'refuse-checkpoints-not-ascending', 'Checkpoints localize a divergence to a tick; out-of-order ones localize it to nothing.', {
      ...recorded,
      checkpoints: [...(recorded.checkpoints ?? [])].reverse(),
    }),
  );

  // ── comparisons/ ──
  const reordered = replay.buildReplayOutcome({
    traceId: recorded.traceId,
    engine: 'godot-reordered',
    finalTick: recorded.finalTick,
    facts: [recorded.facts[1], recorded.facts[0], ...recorded.facts.slice(2)],
  });
  const divergent = replay.buildReplayOutcome({
    traceId: recorded.traceId,
    engine: 'godot-divergent',
    finalTick: recorded.finalTick,
    facts: recorded.facts.map((fact, i) => (i === 4 ? { predicate: fact.predicate, args: [...fact.args.slice(0, -1), 'drift'] } : fact)),
    checkpoints: (recorded.checkpoints ?? []).map((point, i) =>
      i === 0 ? point : { ...point, digest: replay.digestKBFacts([{ predicate: 'drifted', args: [point.tick] }]) },
    ),
  });
  const truncated = replay.buildReplayOutcome({
    traceId: recorded.traceId,
    engine: 'godot-truncated',
    finalTick: recorded.finalTick - 4,
    facts: recorded.facts.slice(0, -2),
  });
  const foreign = replay.buildReplayOutcome({
    traceId: emptyTrace.id,
    engine: 'godot-foreign',
    finalTick: recorded.finalTick,
    facts: recorded.facts,
  });

  files.push(
    comparisonCase(replay, 'converged-identical', 'Two engines that agree. Present because a comparator that reported a divergence for everything would pass every divergence case.', recorded, { ...recorded, engine: 'godot-4.3' }),
    comparisonCase(replay, 'diverge-reordered', 'Both hold the same facts in a different KB order. Clause order is solution order to a Prolog engine, so this is a real divergence and not a formatting difference.', recorded, reordered),
    comparisonCase(replay, 'diverge-facts', 'One fact differs, and a checkpoint already knew: the report localizes to a tick instead of to a digest.', recorded, divergent),
    comparisonCase(replay, 'diverge-truncated', 'A leg that stopped early. The tick count is compared before the facts are.', recorded, truncated),
    comparisonCase(replay, 'diverge-foreign-trace', 'Two outcomes of two different sessions. There is nothing to compare, and saying so is not the same as saying they disagree.', recorded, foreign),
    comparisonCase(replay, 'diverge-count', 'Different fact counts, so the report names the count before it walks the facts.', recorded, replay.buildReplayOutcome({ traceId: recorded.traceId, engine: 'godot-short', finalTick: recorded.finalTick, facts: recorded.facts.slice(0, 3) })),
  );

  // ── runs/ ──
  files.push(
    runCase(replay, 'riverwatch-through-23', 'The whole leg: core\'s own driver over the declared world program, every tick from 0 to 23 including the idle ones, with checkpoints.', trace, { engine: 'core-reference', throughTick: 23, checkpointEvery: 6 }),
    runCase(replay, 'riverwatch-inputs-only', 'The same trace driven only as far as its last input, so `throughTick` is proven to be a policy rather than a constant.', trace, { engine: 'core-reference' }),
    runCase(replay, 'riverwatch-checkpoint-ticks', 'Explicit checkpoint ticks alongside the periodic ones, deduplicated and ascending.', trace, { engine: 'core-reference', throughTick: 20, checkpointEvery: 7, checkpointTicks: [1, 7, 19] }),
    runCase(replay, 'empty-trace-idle-only', 'A session with no inputs at all, driven to tick 15: every fact in the outcome came from an IDLE tick, which is exactly the half a driver that skipped empty ticks would lose.', emptyTrace, { engine: 'core-reference', throughTick: 15 }),
  );

  for (const entry of files) write(outDir, entry.file, entry.body);
  return { files, recorded };
}

// ── Reading the corpus back ─────────────────────────────────────────────────

function corpusFiles(dir) {
  const out = [];
  const walk = (sub) => {
    const abs = path.join(dir, sub);
    if (!fs.existsSync(abs)) return;
    for (const entry of fs.readdirSync(abs).sort()) {
      const rel = path.join(sub, entry);
      if (fs.statSync(path.join(dir, rel)).isDirectory()) walk(rel);
      else if (entry.endsWith('.json') && entry !== 'VENDORED.json') out.push(rel);
    }
  };
  walk('.');
  return out.map((rel) => rel.replace(/^\.\//, '').split(path.sep).join('/')).sort();
}

function countsOf(files) {
  const counts = { traces: 0, outcomes: 0, comparisons: 0, runs: 0 };
  for (const file of files) {
    const area = file.split('/')[0];
    if (area in counts) counts[area] += 1;
  }
  return counts;
}

function gitCommit(dir) {
  try {
    return execFileSync('git', ['-C', dir, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
  } catch {
    return null;
  }
}

async function doMint() {
  fs.rmSync(FIXTURES, { recursive: true, force: true });
  fs.mkdirSync(FIXTURES, { recursive: true });
  const { files } = await mint(coreArg, FIXTURES, VOCABULARY);
  const present = corpusFiles(FIXTURES);
  const counts = countsOf(present);
  for (const [area, floor] of Object.entries(FLOORS)) {
    if (counts[area] < floor) fail(`minted ${counts[area]} ${area} case(s), the floor is ${floor}`);
  }
  const manifest = {
    description:
      'Core\'s own answers about the portable input-trace artifact (tasklist 180), mirrored so gdextension/src/talos_replay.cpp is held to them rather than to a second opinion. GENERATED by tools/vendor-replay-fixtures.mjs — do not hand-edit.',
    source: 'packages/core/src/replay/',
    sourceCommit: gitCommit(coreArg),
    traceFormat: 'insimul-input-trace-v1',
    outcomeFormat: 'insimul-replay-outcome-v1',
    counts,
    floors: FLOORS,
    // The shipped vocabulary is hashed here rather than in the addon's own
    // VENDORED.json because this tool is what mints it; one generator, one guard.
    vocabulary: {
      path: 'addons/insimul_talos/input-vocabulary.json',
      sha256: sha256(fs.readFileSync(VOCABULARY, 'utf8')),
      actionIds: JSON.parse(fs.readFileSync(VOCABULARY, 'utf8')).action_ids.length,
    },
    files: Object.fromEntries(present.map((rel) => [rel, sha256(fs.readFileSync(path.join(FIXTURES, rel), 'utf8'))])),
  };
  fs.writeFileSync(MANIFEST, `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(
    `vendor-replay-fixtures: minted ${files.length} case file(s) — ${counts.traces} trace, ${counts.outcomes} outcome, ${counts.comparisons} comparison, ${counts.runs} run — plus ${manifest.vocabulary.actionIds} action id(s), from ${manifest.sourceCommit ?? 'an unversioned checkout'}`,
  );
}

async function doCheck() {
  if (!fs.existsSync(MANIFEST)) fail('gdextension/test/fixtures/replay/VENDORED.json is missing — re-vendor');
  const manifest = JSON.parse(fs.readFileSync(MANIFEST, 'utf8'));
  const present = corpusFiles(FIXTURES);
  const recorded = manifest.files ?? {};

  for (const rel of present) {
    if (!(rel in recorded)) fail(`${rel} is not recorded in VENDORED.json — re-vendor`);
    const actual = sha256(fs.readFileSync(path.join(FIXTURES, rel), 'utf8'));
    if (actual !== recorded[rel]) fail(`${rel} has been hand-edited (${actual} != ${recorded[rel]}) — re-vendor`);
  }
  for (const rel of Object.keys(recorded)) {
    if (!present.includes(rel)) fail(`VENDORED.json records ${rel}, which is not in the corpus — re-vendor`);
  }
  const counts = countsOf(present);
  for (const [area, floor] of Object.entries(FLOORS)) {
    if (counts[area] < floor) fail(`the corpus carries ${counts[area]} ${area} case(s), the floor is ${floor}`);
  }
  // Two-sided by construction, per the discipline the refuse-at-hello mirror uses:
  // a corpus of nothing but refusals would be passed by a leg that refused
  // everything, and a corpus of nothing but admissions by one that admitted
  // everything.
  const sides = { admitted: 0, refused: 0 };
  for (const rel of present) {
    if (!rel.startsWith('traces/') && !rel.startsWith('outcomes/')) continue;
    const body = JSON.parse(fs.readFileSync(path.join(FIXTURES, rel), 'utf8'));
    if (body.expect?.ok === true) sides.admitted += 1;
    else if (body.expect?.ok === false) sides.refused += 1;
  }
  if (sides.admitted < 2) fail(`only ${sides.admitted} admitted case(s) — a leg that refused everything would pass`);
  if (sides.refused < 8) fail(`only ${sides.refused} refusal case(s) — a leg that admitted everything would pass`);

  if (!fs.existsSync(VOCABULARY)) fail('addons/insimul_talos/input-vocabulary.json is missing — re-vendor');
  const vocabularyText = fs.readFileSync(VOCABULARY, 'utf8');
  if (sha256(vocabularyText) !== manifest.vocabulary?.sha256) {
    fail('addons/insimul_talos/input-vocabulary.json has been hand-edited — re-vendor');
  }
  const vocabulary = JSON.parse(vocabularyText);
  if (vocabulary.format !== VOCABULARY_FORMAT) fail(`the vocabulary is not a ${VOCABULARY_FORMAT} document`);

  if (coreArg !== null) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'insimul-replay-check-'));
    const tmp = path.join(root, 'corpus');
    await mint(coreArg, tmp, path.join(root, 'input-vocabulary.json'));
    const drifted = [];
    for (const rel of corpusFiles(tmp)) {
      const mintedText = fs.readFileSync(path.join(tmp, rel), 'utf8');
      if (!present.includes(rel)) drifted.push(`${rel} (new upstream)`);
      else if (sha256(mintedText) !== recorded[rel]) drifted.push(rel);
    }
    if (sha256(fs.readFileSync(path.join(root, 'input-vocabulary.json'), 'utf8')) !== manifest.vocabulary.sha256) {
      drifted.push('addons/insimul_talos/input-vocabulary.json');
    }
    fs.rmSync(root, { recursive: true, force: true });
    if (drifted.length > 0) {
      fail(`core's replay module has moved — re-vendor with --core ${coreArg}\n  drifted: ${drifted.join(', ')}`);
    }
  }

  console.log(
    `vendor-replay-fixtures: corpus consistent (${counts.traces} trace, ${counts.outcomes} outcome, ${counts.comparisons} comparison, ${counts.runs} run case(s); ${sides.admitted} admitted, ${sides.refused} refused; ${vocabulary.action_ids.length} action id(s) published)`,
  );
}

if (checkOnly) await doCheck();
else await doMint();
