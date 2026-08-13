#!/usr/bin/env node
// vendor-supported-versions.mjs — mirror the workspace's published engine-version
// matrix into the insimul-talos-bridge addon, and guard it against drift.
//
// WHY THIS FILE EXISTS. `docs/REFUSE_AT_HELLO.md` states the rule the bridge
// implements: the hello decision is computed **from the published matrix, never
// from the running build's opinion of itself** — "the answer is knowable before a
// run, from artifacts, and a build that likes itself is not evidence." The matrix
// lives in the workspace parent (`docs/supported-versions.json`, tasklist 182),
// which this repository does not contain: it is standalone by design and vendors
// what it needs. So the matrix is a THIRD vendored artifact here, held to the same
// discipline as `vendor/core/` and `conformance/` — a recorded source, a recorded
// hash, and a drift guard that fails loudly rather than shipping a stale matrix.
//
// Vendored WHOLE and verbatim rather than reduced to the godot row. A slice would
// be a second opinion about which parts of the decision matter, and the decision
// order reads `counterparty.claims` and `refuse_at_hello.tokens` as well as the
// row. The bytes are the artifact.
//
// TWO MODES, matching the sibling vendor tools:
//
//   node tools/vendor-supported-versions.mjs --matrix <workspace docs/supported-versions.json>
//       Re-mirror and write. Run it when 182's matrix moves.
//
//   node tools/vendor-supported-versions.mjs --check
//       Verify the checked-in mirror against its own recorded hash. Needs no
//       workspace checkout, so it runs in this repo's gates. Pass --matrix as
//       well when one IS available and it additionally diffs against the source,
//       which is the only real drift check.
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..');
const ADDON = path.join(REPO, 'addons', 'insimul_talos');
const MIRROR = path.join(ADDON, 'supported-versions.json');
const MANIFEST = path.join(ADDON, 'VENDORED.json');
// The reference implementation's own 21 cases, mirrored so the C++ port is held to
// the SAME decisions rather than to a second opinion about them. Two-sided by
// construction: the suite carries an admitted hello and a restored archive, so a
// port that refused everything fails here (docs/REFUSE_AT_HELLO.md, 'Running it').
const CASES = path.join(REPO, 'gdextension', 'test', 'fixtures', 'refuse-at-hello');
// A case whose `matrix` resolves to the workspace matrix itself is rewritten to this
// sentinel, because the mirrored tree has no `docs/` above it. Everything else keeps
// its relative path and is mirrored alongside.
const PUBLISHED = 'published';

const args = process.argv.slice(2);
const matrixArg = argValue('--matrix') ?? process.env.INSIMUL_MATRIX ?? null;
const checkOnly = args.includes('--check') || matrixArg === null;

function argValue(flag) {
  const i = args.indexOf(flag);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

function sha256(text) {
  return createHash('sha256').update(text).digest('hex');
}

function fail(message) {
  console.error(`vendor-supported-versions: ${message}`);
  process.exit(1);
}

function gitCommit(file) {
  try {
    return execFileSync('git', ['-C', path.dirname(file), 'rev-parse', 'HEAD'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch {
    return null;
  }
}

/** The engines the bridge artifacts exist for, and the axes each row must carry. */
const AXES = ['engine_version', 'c_abi', 'snapshot_version', 'plugin_version'];

function validate(matrix) {
  if (!matrix || typeof matrix !== 'object') fail('the matrix is not an object');
  const row = (matrix.engines || []).find((e) => e.engine === 'godot');
  if (!row) fail('the matrix publishes no `godot` row — this bridge has nothing to decide from');
  for (const axis of AXES) {
    if (!row.axes?.[axis]) fail(`the godot row publishes no \`${axis}\` axis`);
  }
  const tokens = matrix.refuse_at_hello?.tokens;
  if (!tokens || Object.keys(tokens).length === 0) {
    fail('the matrix publishes no refuse_at_hello.tokens — the why-not vocabulary is the half this bridge emits');
  }
  if (!Array.isArray(matrix.refuse_at_hello?.decision_order) || matrix.refuse_at_hello.decision_order.length !== 6) {
    fail('refuse_at_hello.decision_order is not the six rungs the bridge ports');
  }
  return { row, tokenCount: Object.keys(tokens).length };
}

/** Mirror the reference cases, rewriting each one's pointer at the matrix. */
function mirrorCases(sourceDir, matrixPath) {
  if (!fs.existsSync(sourceDir)) {
    fail(`the reference cases are missing beside the matrix (${sourceDir}) — the port would have nothing to be held to`);
  }
  fs.rmSync(CASES, { recursive: true, force: true });
  const files = [];
  const walk = (dir, rel) => {
    for (const entry of fs.readdirSync(dir).sort()) {
      const abs = path.join(dir, entry);
      const relPath = rel ? `${rel}/${entry}` : entry;
      if (fs.statSync(abs).isDirectory()) {
        walk(abs, relPath);
        continue;
      }
      if (!entry.endsWith('.json')) continue;
      const spec = JSON.parse(fs.readFileSync(abs, 'utf8'));
      if (spec.matrix) {
        const resolved = path.resolve(path.dirname(abs), spec.matrix);
        if (path.resolve(resolved) === path.resolve(matrixPath)) spec.matrix = PUBLISHED;
      }
      const out = path.join(CASES, relPath);
      fs.mkdirSync(path.dirname(out), { recursive: true });
      fs.writeFileSync(out, `${JSON.stringify(spec, null, 2)}\n`);
      files.push(relPath);
    }
  };
  walk(sourceDir, '');
  const decided = files.filter((f) => !f.startsWith('matrix/'));
  if (decided.length === 0) fail('the mirrored case tree decides nothing');
  return files;
}

function caseHashes() {
  const out = {};
  const walk = (dir, rel) => {
    for (const entry of fs.readdirSync(dir).sort()) {
      const abs = path.join(dir, entry);
      const relPath = rel ? `${rel}/${entry}` : entry;
      if (fs.statSync(abs).isDirectory()) walk(abs, relPath);
      else out[relPath] = sha256(fs.readFileSync(abs, 'utf8'));
    }
  };
  walk(CASES, '');
  return out;
}

function write(source) {
  const text = fs.readFileSync(source, 'utf8');
  const matrix = JSON.parse(text);
  const { tokenCount } = validate(matrix);
  const mirrored = mirrorCases(path.join(path.dirname(source), '..', 'scripts', 'engine-versions', 'fixtures'), source);
  const manifest = {
    description:
      'The workspace engine-version matrix (tasklist 182), mirrored for the insimul-talos-bridge addon. GENERATED by tools/vendor-supported-versions.mjs — do not hand-edit supported-versions.json. The bridge decides admit/refuse FROM these bytes; docs/REFUSE_AT_HELLO.md is the contract.',
    source: 'insimul workspace docs/supported-versions.json',
    sourceCommit: gitCommit(source),
    matrixVersion: matrix.version ?? null,
    measuredAt: matrix.measured_at ?? null,
    tokens: tokenCount,
    referenceImplementation: 'scripts/engine-versions/check-hello.mjs',
    files: { 'supported-versions.json': sha256(text) },
    cases: {},
  };
  fs.mkdirSync(ADDON, { recursive: true });
  fs.writeFileSync(MIRROR, text);
  manifest.cases = caseHashes();
  fs.writeFileSync(MANIFEST, `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(
    `vendor-supported-versions: mirrored ${matrix.engines.length} engine row(s), ${tokenCount} why-not token(s), ${mirrored.length} reference case file(s) from ${manifest.sourceCommit ?? 'an unversioned checkout'}`,
  );
}

function check(source) {
  if (!fs.existsSync(MIRROR) || !fs.existsSync(MANIFEST)) {
    fail(`the mirror is missing (${path.relative(REPO, MIRROR)}) — run with --matrix <workspace docs/supported-versions.json>`);
  }
  const text = fs.readFileSync(MIRROR, 'utf8');
  const manifest = JSON.parse(fs.readFileSync(MANIFEST, 'utf8'));
  const actual = sha256(text);
  const recorded = manifest.files?.['supported-versions.json'];
  if (actual !== recorded) {
    fail(`supported-versions.json hash ${actual} != recorded ${recorded} — the mirror was hand-edited; re-vendor`);
  }
  const matrix = JSON.parse(text);
  const { tokenCount } = validate(matrix);
  if (tokenCount !== manifest.tokens) {
    fail(`the mirror carries ${tokenCount} token(s), VENDORED.json records ${manifest.tokens}`);
  }
  if (!fs.existsSync(CASES)) {
    fail(`the reference case mirror is missing (${path.relative(REPO, CASES)}) — re-vendor`);
  }
  const hashes = caseHashes();
  const recordedCases = manifest.cases ?? {};
  for (const [file, hash] of Object.entries(recordedCases)) {
    if (hashes[file] !== hash) fail(`case ${file} was hand-edited (${hashes[file] ?? 'missing'} != ${hash})`);
  }
  for (const file of Object.keys(hashes)) {
    if (!(file in recordedCases)) fail(`case ${file} is not recorded in VENDORED.json — re-vendor`);
  }
  const decided = Object.keys(hashes).filter((f) => !f.startsWith('matrix/'));
  console.log(
    `vendor-supported-versions: mirror consistent (${matrix.engines.length} engine row(s), ${tokenCount} why-not token(s), ${decided.length} reference case(s), matrix ${manifest.matrixVersion ?? '?'})`,
  );

  if (source === null) {
    console.log('vendor-supported-versions: no --matrix given, so drift against the workspace matrix was NOT checked');
    return;
  }
  const upstream = fs.readFileSync(source, 'utf8');
  if (sha256(upstream) !== actual) {
    fail(`the workspace matrix has moved (${sha256(upstream)}) — re-vendor with --matrix ${source}`);
  }
  console.log('vendor-supported-versions: mirror matches the workspace matrix byte-for-byte');
}

if (checkOnly) {
  if (matrixArg !== null && !fs.existsSync(matrixArg)) fail(`--matrix not found: ${matrixArg}`);
  check(matrixArg);
} else {
  if (!fs.existsSync(matrixArg)) fail(`--matrix not found: ${matrixArg}`);
  write(matrixArg);
}
