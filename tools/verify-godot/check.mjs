#!/usr/bin/env node
// Godot GDScript static syntax gate (US-EP3).
//
// COVERAGE: structural only. The Godot editor / headless binary is NOT available
// in this harness (`godot --headless --check-only` would be the real check, and
// gdtoolkit's `gdparse` is not installed either), so we scan every .gd source
// (addons/insimul/ SDK + templates/ game-template scripts) with the structural
// lexer in tools/lib/structural-syntax.mjs: balanced ( [ { }, terminated single
// / double / triple-quoted strings, `#` line comments. GDScript blocks are
// indentation- rather than brace-delimited, so this gate is weaker for .gd than
// for C#/C++ (it validates bracket + string structure, not block nesting). See
// tools/README.md.

import { runGate, printGate } from '../lib/run-gate.mjs';

export const GATE = { name: 'godot/GDScript', lang: 'gd', dir: '.', exts: ['.gd'] };

export function run() {
  return runGate(GATE);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const res = run();
  console.log('Godot GDScript structural syntax gate');
  printGate(res);
  process.exit(res.ok ? 0 : 1);
}
