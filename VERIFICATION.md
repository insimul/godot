# Godot native-Prolog verification (US-GP3)

How to verify the Godot leg — the machine-runnable gates that pass **here**, and
the end-to-end template smoke checklist that needs a `godot` binary + the built
GDExtension (run by a human at review, since `autoMerge` is off).

## Runs on any box (no Godot toolchain) — the merge gate

```sh
npm run engines:check        # only runs the godot gates when packages/godot/** changed
```

which executes, in order:

1. **Host C++ marshalling tests** (US-GP1) —
   `bash packages/godot/gdextension/test/run_host_tests.sh`. Builds the
   dependency-free `prolog_value.*` core with `clang++` and drives
   atoms/ints/floats/lists/compounds/escapes/unicode + malformed-input rejections
   through the real `parse_binding_set`. Expect **24/24**.
2. **Conformance corpus** (US-GP2) —
   `bash packages/godot/gdextension/test/run_conformance.sh`. Drives every
   `expected` solution in `packages/core/conformance/prolog/*.json` through the
   extension's marshalling layer. Expect **41 cases / 49 solutions green**.
3. **GDScript structural lint** (US-GP3, the `godot --check-only` stand-in) —
   `python3 packages/godot/gdextension/tests/gdscript_structural_lint.py`. Scans
   the template tree + GDExtension `.gd` + addons for unbalanced brackets,
   unterminated strings, missing block `:`, and space-based indentation. Expect
   **0 issues**.

Also keep the repo-root gates green (they don't cover the C++/GDScript but must
not regress): `npm run check` (tsc, exit 0) and `npm test` (vitest).

> **What the lint does NOT check:** types, name resolution, autoload wiring, or
> runtime semantics. It is an honest structural stand-in, not a parser. Those need
> the checklist below.

## Needs a `godot` binary + built extension — human end-to-end checklist

Prereqs (see `gdextension/README.md` and `gdextension/THIRD_PARTY.md`):

```sh
cd packages/godot/gdextension
git submodule add https://github.com/godotengine/godot-cpp godot-cpp
git -C godot-cpp checkout godot-4.2-stable          # the documented pin
export INSIMUL_NATIVE_DIST=/path/to/insimul-native/dist/<platform>
scons target=template_debug                          # builds insimul_godot
# install insimul.gdextension + the built lib into the template project's addon dir
```

Then:

- [ ] **Extension smoke** — `godot --headless -s gdextension/smoke/test_smoke.gd`
      prints `[insimul-smoke] OK` and exits 0 (consult/query/assert/snapshot/restore).
- [ ] **Corpus end-to-end** —
      `godot --headless -s gdextension/tests/conformance_runner.gd` reports every
      corpus case green (the same JSON the host harness reads), exit 0.
- [ ] **Template parses** — open the template project in the editor (or
      `godot --headless --check-only --path templates/project`); no parse/type
      errors across `scripts/**`. In particular `prolog_engine.gd` and
      `rule_enforcer.gd` resolve `InsimulProlog` via `ClassDB` with no warnings
      beyond the intended "not available" push_warning when the extension is absent.
- [ ] **PrologEngine adapter** — in a scratch scene, instantiate
      `prolog_engine.gd`, `initialize({"content": "quest_complete(player, q1)."})`,
      then assert `is_quest_complete("q1", "player") == true` and
      `is_quest_available("q2", "player") == true`. Round-trip:
      `save_snapshot()` → new engine → `restore_snapshot(image)` → same result.
- [ ] **RuleEnforcer gating (the real bug fix)** — call
      `set_prolog_knowledge_base("quest_complete(player, find_the_sword).")`, then a
      rule with a `quest_complete` condition on quest id `Find the Sword` must now
      evaluate **true** (the old substring check returned false — the sanitized-atom
      vs quoted-string mismatch documented in `MIGRATION.md`). With the extension
      absent, confirm graceful degradation: the check falls back to the substring
      scan and the export still runs.
- [ ] **Graceful degradation** — run the template with the extension NOT installed;
      the game boots, `PrologEngine`/`RuleEnforcer` log the "native not available"
      warning once, and no crash occurs (queries return permissive defaults).

## Status on this machine

The Ralph harness has no `scons`/`godot`/`godot-cpp` and libinsimul is unbuilt, so
only the "runs on any box" gates above were executed here (all green). The
end-to-end checklist is unchecked pending a toolchain — reviewed at merge.
