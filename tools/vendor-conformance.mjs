#!/usr/bin/env node
// vendor-conformance.mjs — re-vendor (and verify) the shared conformance corpus.
//
// WHY THIS EXISTS. `conformance/` is a MIRROR of `packages/core/conformance/`,
// the cross-runtime source of truth. This repository is standalone by design, so
// it cannot path-resolve into core — it carries a copy. A copy with no guard
// silently rots: at the start of tasklist 100 the vendored Prolog corpus was
// **41 of core's 76 cases**, `gameplay.json` was a pre-KINP snapshot, and
// `conformance/content/README.md` claimed to be a mirror of a core file that
// does not exist. Nothing failed, because nothing was checking.
//
// Same discipline (and same two modes) as tools/vendor-core-bundle.mjs:
//
//   node tools/vendor-conformance.mjs --core <path-to-packages/core>
//       Re-vendor from a core checkout: copy every mirrored file and rewrite
//       conformance/VENDORED.json with the source commit + per-file sha256.
//
//   node tools/vendor-conformance.mjs --check
//       Verify the checked-in corpus against VENDORED.json — every mirrored file
//       present, hashing what the manifest records, and nothing extra hiding
//       inside a mirrored directory. Needs no core checkout, so it runs in this
//       repo's gates. Pass --core as well for the REAL drift check: a
//       byte-for-byte diff against the source tree.
//
// LOCAL, NOT MIRRORED. A few paths under conformance/ are this repo's own and
// have no counterpart in core; they are listed in `local` in the manifest and
// are skipped by both modes. Anything not mirrored and not declared local is an
// error — that is how an undeclared local file (the old `content/` fixture)
// stops looking like a mirror.

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..');
const CORPUS = path.join(REPO, 'conformance');
const MANIFEST = path.join(CORPUS, 'VENDORED.json');

// Paths (repo-relative to conformance/) that are this repo's own, not a mirror.
// Kept here as well as in the manifest so `--core` can regenerate the manifest
// without being told again.
const LOCAL = [
  'VENDORED.json',
  'VENDORED.md',
  'content/README.md',
  'content/library.json',
];

// CORE-SIDE PATHS DELIBERATELY NOT MIRRORED HERE — the mirror image of LOCAL.
// LOCAL declares files that are this repo's own and have no counterpart in
// core; this declares corpora that DO exist in core and are deliberately not
// vendored, with the reason. Without it, every corpus core adds for a surface
// this repo has not adopted reads as DRIFT, and the real signal drowns in it.
//
// Prefix match. Every exclusion is PRINTED on each --core run, with a count:
// an exclusion nobody sees is exactly how a corpus silently stops being
// checked, and this repo has shipped that failure before. Removing a corpus
// from the mirror by adding it here is a visible act, not a quiet one.
const NOT_MIRRORED = [
  {
    prefix: 'editor/',
    why:
      'the editor-core corpora (tasklist 101). This repo ships the RUNTIME; ' +
      'editor-core adoption is a later wave — see RUNTIME_CORE_ADOPTION.md. ' +
      'Vendor these when this repo implements the editor core, not before: a ' +
      'corpus with no runner here would be a checked-in file nothing executes.',
  },
  {
    prefix: 'ai/',
    why:
      'the agentAi module\u2019s selector vectors. `agentAi` is not one of the seven ' +
      'band-120 modules this repo adopted (tools/verify-mechanics/MODULE_HOSTS.json ' +
      'is the list), so there is no decision layer here to run them against. ' +
      'NOTE the deliberate asymmetry: conformance/prolog/agent-ai.json IS mirrored, ' +
      'because the Prolog runner is generic and executes any pack\u2019s vocabulary ' +
      'without the module being adopted. The DECISION vectors need the layer.',
  },
  {
    prefix: 'map/',
    why:
      'the map module\u2019s region and jurisdiction vectors — same reason as ai/: ' +
      '`map` is not one of the seven adopted modules, and conformance/prolog/' +
      'geo-map.json is mirrored for the same reason agent-ai.json is.',
  },
  {
    prefix: 'generation/',
    why:
      'the world-generation corpora (bridges, buildings). Generation is an ' +
      'authoring-time surface this repo does not adopt at all — see ' +
      'RUNTIME_CORE_ADOPTION.md \u00a77, "What we should NOT adopt".',
  },
  {
    prefix: 'grounding/',
    why:
      'the grounding pack fixtures (roman-cuisine). Not a case corpus and not a ' +
      'runtime surface: it pins how a content pack is stamped, which is the ' +
      'platform repo\u2019s job, not the engine plugin\u2019s.',
  },
  {
    prefix: 'modules/',
    why:
      'genre-activation.json — genre bundle to active module set. This is US-3\u2019s ' +
      'corpus, not US-2\u2019s: the plugin has no bundle reader yet, so vendoring it ' +
      'now would check in the one file this repo has already shipped once before ' +
      'with nothing running it. US-3 removes this entry and adds the runner in the ' +
      'same commit.',
  },
];

// MINIMUM case counts per corpus area, hand-maintained. `prologCases` alone
// cannot catch a shrink: it is written FROM the corpus on every re-vendor, so a
// corpus that lost half its cases upstream re-vendors to a smaller number and
// the guard agrees with it. A floor is the number a human wrote down, and
// re-vendoring never lowers it — so losing a case is an ERROR here and raising
// the bar is a deliberate edit. Keyed by the directory under conformance/;
// `prolog` is the whole directory because its files are one corpus with one
// runner. Counts are core 84be9ad's, minus nothing.
const CASE_FLOORS = {
  prolog: 255,
  'combat/action-table.json': 5,
  'combat/resolution.json': 16,
  'items/equipping.json': 12,
  'items/placement.json': 7,
  'items/pricing.json': 12,
  'items/transactions.json': 12,
  'routines/goals.json': 14,
  'routines/intents.json': 21,
  'routines/interruption.json': 10,
  'skills/advancement.json': 12,
  'skills/effects.json': 11,
  'skills/trees.json': 6,
  'skills/unlocks.json': 12,
  'stealth/actions.json': 6,
  'stealth/detection.json': 16,
  'traversal/affordances.json': 14,
  'traversal/fast-travel.json': 10,
  'traversal/vehicles.json': 14,
};

/** `cases.length` of one vendored corpus file, or 0 when it is not there. */
function caseCount(rel) {
  const p = path.join(CORPUS, rel);
  if (!fs.existsSync(p)) return 0;
  const doc = JSON.parse(fs.readFileSync(p, 'utf8'));
  return Array.isArray(doc.cases) ? doc.cases.length : 0;
}

/** Every floor that is not met, as a problem line each. */
function floorProblems() {
  const out = [];
  for (const [key, floor] of Object.entries(CASE_FLOORS)) {
    const actual = key === 'prolog' ? prologCaseCount() : caseCount(key);
    if (actual < floor) {
      out.push(
        `conformance/${key} holds ${actual} case(s), below the floor of ${floor} — ` +
          'a corpus that shrinks is a contract that quietly stopped being pinned',
      );
    }
  }
  return out;
}

/** The NOT_MIRRORED entry covering `rel`, or undefined. */
function excludedBy(rel) {
  return NOT_MIRRORED.find((n) => rel.startsWith(n.prefix));
}

/** Print every exclusion that actually matched something, so it stays visible. */
function reportExclusions(srcFiles) {
  for (const n of NOT_MIRRORED) {
    const hits = srcFiles.filter((rel) => rel.startsWith(n.prefix));
    if (hits.length > 0) {
      console.log(
        `vendor-conformance: NOT MIRRORED: ${hits.length} file(s) under conformance/${n.prefix} — ${n.why}`,
      );
    }
  }
}

const args = process.argv.slice(2);
const coreArg = argValue('--core') ?? process.env.INSIMUL_CORE_DIR ?? null;
const checkOnly = args.includes('--check');

function argValue(flag) {
  const i = args.indexOf(flag);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

function fail(message) {
  console.error(`vendor-conformance: ${message}`);
  process.exit(1);
}

function sha256(buf) {
  return createHash('sha256').update(buf).digest('hex');
}

/** Every file under `dir`, as POSIX paths relative to it, sorted. */
function walk(dir, prefix = '') {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) out.push(...walk(path.join(dir, entry.name), rel));
    else if (entry.isFile()) out.push(rel);
  }
  return out.sort();
}

function corpusDir(coreDir) {
  const dir = path.resolve(coreDir, 'conformance');
  if (!fs.existsSync(path.join(dir, 'prolog'))) {
    fail(`--core ${coreDir} does not look like packages/core (no conformance/prolog)`);
  }
  return dir;
}

function gitCommit(dir) {
  try {
    return execFileSync('git', ['-C', dir, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
  } catch {
    return 'unknown';
  }
}

/** Prolog case count per file — reported so a shrinking corpus is visible. */
function prologCaseCount() {
  const dir = path.join(CORPUS, 'prolog');
  if (!fs.existsSync(dir)) return 0;
  let total = 0;
  for (const f of fs.readdirSync(dir).filter((n) => n.endsWith('.json'))) {
    const doc = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
    total += Array.isArray(doc.cases) ? doc.cases.length : 0;
  }
  return total;
}

function write(coreDir) {
  const src = corpusDir(coreDir);
  const srcFiles = walk(src);
  reportExclusions(srcFiles);
  const files = srcFiles.filter((rel) => !excludedBy(rel));
  for (const rel of files) {
    const dest = path.join(CORPUS, rel);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(path.join(src, rel), dest);
  }
  writeManifest(coreDir, files);
  console.log(`vendor-conformance: mirrored ${files.length} file(s) from core ${gitCommit(path.resolve(coreDir))}`);
  console.log(`  prolog cases now: ${prologCaseCount()}`);
  // A re-vendor is exactly when a shrink would slip through, because the
  // manifest is being rewritten from the very data that shrank.
  const short = floorProblems();
  if (short.length > 0) {
    for (const p of short) console.error(`vendor-conformance: FLOOR: ${p}`);
    fail(`${short.length} corpus area(s) came back below their case floor`);
  }
}

function writeManifest(coreDir, files) {
  const manifest = {
    description:
      'Provenance + drift guard for the vendored conformance corpus. `files` is a ' +
      'byte-for-byte mirror of packages/core/conformance; `local` is this repo’s own ' +
      'and mirrors nothing. Regenerate with `npm run vendor:conformance -- --core <packages/core>`.',
    source: '@insimul/core (packages/core/conformance)',
    coreCommit: coreDir ? gitCommit(path.resolve(coreDir)) : 'unknown',
    prologCases: prologCaseCount(),
    caseFloors: CASE_FLOORS,
    files: Object.fromEntries(
      files.map((rel) => [rel, sha256(fs.readFileSync(path.join(CORPUS, rel)))]),
    ),
    local: LOCAL,
  };
  fs.writeFileSync(MANIFEST, `${JSON.stringify(manifest, null, 2)}\n`);
}

function check(coreDir) {
  if (!fs.existsSync(MANIFEST)) fail('conformance/VENDORED.json is missing — run without --check');
  const manifest = JSON.parse(fs.readFileSync(MANIFEST, 'utf8'));
  const mirrored = Object.keys(manifest.files);
  if (mirrored.length === 0) fail('VENDORED.json records ZERO mirrored files — the guard would check nothing');

  const problems = [];
  for (const rel of mirrored) {
    const p = path.join(CORPUS, rel);
    if (!fs.existsSync(p)) {
      problems.push(`missing mirrored file conformance/${rel}`);
      continue;
    }
    const actual = sha256(fs.readFileSync(p));
    if (actual !== manifest.files[rel]) {
      problems.push(`conformance/${rel} hashes ${actual}, manifest records ${manifest.files[rel]}`);
    }
  }

  // Undeclared files: neither mirrored nor declared local. An unnoticed extra
  // file under a mirrored directory is how a "mirror" stops being one.
  const declared = new Set([...mirrored, ...(manifest.local ?? [])]);
  for (const rel of walk(CORPUS)) {
    if (!declared.has(rel)) {
      problems.push(`conformance/${rel} is neither mirrored nor declared local in VENDORED.json`);
    }
  }

  const cases = prologCaseCount();
  if (cases !== manifest.prologCases) {
    problems.push(`prolog corpus holds ${cases} case(s), manifest records ${manifest.prologCases}`);
  }
  problems.push(...floorProblems());

  if (problems.length > 0) {
    for (const p of problems) console.error(`vendor-conformance: ${p}`);
    fail(`${problems.length} corpus drift problem(s) — re-vendor with --core <packages/core>`);
  }
  console.log(
    `vendor-conformance: ${mirrored.length} mirrored file(s) consistent, ` +
      `${cases} prolog cases, core ${manifest.coreCommit}`,
  );
  console.log(
    `vendor-conformance: ${Object.keys(CASE_FLOORS).length} case floor(s) met ` +
      `(${Object.values(CASE_FLOORS).reduce((a, b) => a + b, 0)} cases pinned as a minimum)`,
  );

  if (coreDir) {
    const src = corpusDir(coreDir);
    const srcFiles = walk(src);
    reportExclusions(srcFiles);
    const drift = [];
    for (const rel of srcFiles) {
      if (excludedBy(rel)) continue;
      const here = path.join(CORPUS, rel);
      if (!fs.existsSync(here)) {
        drift.push(`core has conformance/${rel}, this repo does not`);
      } else if (!fs.readFileSync(here).equals(fs.readFileSync(path.join(src, rel)))) {
        drift.push(`conformance/${rel} differs from core's copy`);
      }
    }
    for (const rel of mirrored) {
      if (!srcFiles.includes(rel)) drift.push(`conformance/${rel} is recorded as a mirror but core has no such file`);
    }
    if (drift.length > 0) {
      for (const d of drift) console.error(`vendor-conformance: DRIFT: ${d}`);
      fail(`the vendored corpus differs from ${coreDir} in ${drift.length} place(s) — re-vendor with --core`);
    }
    console.log(`vendor-conformance: byte-identical to ${path.relative(process.cwd(), src) || src}`);
  } else {
    console.log('vendor-conformance: no --core given, so drift against core itself was NOT checked');
  }
}

if (checkOnly) {
  check(coreArg);
} else if (coreArg) {
  write(coreArg);
} else {
  fail('usage: vendor-conformance.mjs --core <path-to-packages/core> | --check [--core <path>]');
}
