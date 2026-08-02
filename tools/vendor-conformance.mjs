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
  const files = walk(src);
  for (const rel of files) {
    const dest = path.join(CORPUS, rel);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(path.join(src, rel), dest);
  }
  writeManifest(coreDir, files);
  console.log(`vendor-conformance: mirrored ${files.length} file(s) from core ${gitCommit(path.resolve(coreDir))}`);
  console.log(`  prolog cases now: ${prologCaseCount()}`);
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

  if (problems.length > 0) {
    for (const p of problems) console.error(`vendor-conformance: ${p}`);
    fail(`${problems.length} corpus drift problem(s) — re-vendor with --core <packages/core>`);
  }
  console.log(
    `vendor-conformance: ${mirrored.length} mirrored file(s) consistent, ` +
      `${cases} prolog cases, core ${manifest.coreCommit}`,
  );

  if (coreDir) {
    const src = corpusDir(coreDir);
    const srcFiles = walk(src);
    const drift = [];
    for (const rel of srcFiles) {
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
