// Shared runner for the native-tree static syntax gates (US-EP3).
// Enumerates the git-tracked source files of one engine package, runs the
// structural scanner over each, and reports a per-gate pass/fail summary.
// No third-party deps (matches scripts/engines/*.mjs).

import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join, extname } from 'node:path';
import { scanText } from './structural-syntax.mjs';

export const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

/**
 * Git-tracked files under `dir` whose extension is in `exts`.
 * @param {string} dir  repo-relative dir (e.g. "packages/unity")
 * @param {string[]} exts  e.g. [".cs"]
 */
export function trackedSources(dir, exts) {
  const out = execFileSync('git', ['ls-files', dir], { cwd: REPO_ROOT, encoding: 'utf8' });
  return out
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean)
    .filter((p) => exts.includes(extname(p).toLowerCase()))
    .sort();
}

/**
 * Run the structural gate for one engine.
 * @param {{name:string, lang:'cs'|'cpp'|'gd', dir:string, exts:string[]}} gate
 * @returns {{name:string, ok:boolean, scanned:number, failures:{file:string,errors:any[]}[]}}
 */
export function runGate(gate) {
  const files = trackedSources(gate.dir, gate.exts);
  const failures = [];
  for (const rel of files) {
    let text;
    try {
      text = readFileSync(join(REPO_ROOT, rel), 'utf8');
    } catch (e) {
      failures.push({ file: rel, errors: [{ line: 0, col: 0, msg: `read failed: ${e.message}` }] });
      continue;
    }
    const errs = scanText(text, gate.lang);
    if (errs.length) failures.push({ file: rel, errors: errs });
  }
  return { name: gate.name, ok: failures.length === 0, scanned: files.length, failures };
}

export function printGate(res) {
  if (res.ok) {
    console.log(`  ✓ ${res.name}: ${res.scanned} file(s) structurally sound`);
    return;
  }
  console.log(`  ✗ ${res.name}: ${res.failures.length}/${res.scanned} file(s) FAILED`);
  for (const f of res.failures) {
    for (const e of f.errors) {
      console.log(`      ${f.file}:${e.line}:${e.col} ${e.msg}`);
    }
  }
}
