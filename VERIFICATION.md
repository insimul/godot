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

---

# Godot runtime core verification (US-GC1..GC4)

A second verification surface (distinct from the native-Prolog migration above):
the **portable runtime core** that mirrors the Unreal/Unity legs against the shared
golden fixtures. Same two tiers — machine gates that pass **here**, plus a live
full-loop checklist that needs a `godot` binary + the built GDExtension.

## Runs on any box (no Godot toolchain) — the merge gate

`npm run engines:check` (runs the godot gates only when `packages/godot/**`
changed) executes, in addition to the native-Prolog gates above:

1. **Portable save-system host tests** (US-GC2) —
   `gdextension/test/run_save_tests.sh`. Canonical vectors, integrity vs the shared
   golden vectors, v1→v3 migration + round-trip, KB round-trip, and a Godot-produced
   envelope byte-matching the committed cross-check golden. Expect **58 checks**.
2. **Portable quest-system host tests** (US-GC3) —
   `gdextension/test/run_quest_tests.sh`. Hydration + radiant parity vs the golden
   corpus, query-driven completion + transitions, save round-trip. Expect
   **33 checks**.
3. **Startup-orchestrator host tests** (US-GC4, the full loop) —
   `gdextension/test/run_bootstrap_tests.sh`. Boot-resume the golden save (entity
   counts = the parity numbers), new-game + corrupt-save fallback, and the full
   radiant → objective → save → reload sequence with the `worldSnapshot` hash stable
   throughout. Expect **42 checks**.

Plus the root gates (must not regress): `npm run check` (tsc, exit 0), `npm test`
(vitest — includes the save-integrity + quest goldens drift guards that pin the
C++/GDScript output to the TS authority).

## Needs a `godot` binary + built extension — human end-to-end checklist

Prereqs: build the GDExtension (see `gdextension/README.md` /
`gdextension/THIRD_PARTY.md`) and install `insimul.gdextension` + the built lib into
the template project's addon dir. The headless test runners
(`addons/insimul/tests/run_*_headless.sh`) SKIP cleanly without them.

### Per-surface headless tests

- [ ] **World source** — `run_world_source_headless.sh`: golden v2-typical entity
      counts, version gate, malformed handling.
- [ ] **Save system** — `run_save_system_headless.sh`: new-game → save → load with
      integrity, KB round-trip, tamper detection.
- [ ] **Quest system** — `run_quest_system_headless.sh`: hydration + radiant parity,
      completion transitions + signals, save round-trip.

### <a name="godot-runtime-core-full-loop-us-gc4"></a>Full gameplay loop (US-GC4)

Drive the whole loop the way `test_bootstrap.cpp` does, but in a live Godot build.
`run_runtime_bootstrap_headless.sh` automates this; a person confirms it in a real
project (or a Play run of the template with a portable worldSnapshot export staged
at `res://data/world_snapshot.json`):

- [ ] **New game on the golden world.** Boot slot 0 with no existing save →
      `InsimulRuntime.boot(...)` returns `resumed_save == false`; the log prints
      `runtime booted (new game): world source + save slot + KB + quests`.
- [ ] **Spawner reads the world source.** `NPCSpawner` logs `N characters from the
      world source`, and the spawned character ids/roles match the world's
      characters (identity from the world source; positional data overlaid from the
      legacy render export where present).
- [ ] **Radiant quest.** A radiant-tagged quest is offered deterministically
      (same offering the `radiant-cases.json` corpus + host test pin); re-running
      from the same state offers the same quest(s) in the same order (RNG-free).
- [ ] **Objective.** Completing an objective's trigger (e.g. `talked_to(player,
      npc)`) broadcasts `objective_completed`, then `quest_completed`, and asserts
      a `quest_complete(<id>)` fact into the KB.
- [ ] **Save.** `InsimulRuntime.save_game()` writes a canonical, integrity-stamped
      envelope to the slot under `user://saves/`.
- [ ] **Reload.** Re-boot the same slot → `did_resume_save()` is true; the completed
      quest stays completed and the offered radiant quest is still offered (KB facts
      round-tripped).
- [ ] **World-hash stability.** `world_snapshot_integrity()` is unchanged across the
      save/reload boundary (a `currentState`-only mutation must never perturb the
      world hash) — the host `bootstrap` test asserts this; confirm no world-drift in
      the log.
- [ ] **Graceful degradation.** With the GDExtension absent, `InsimulRuntime` reports
      via `last_error()` and `GameManager` falls back to the legacy startup path
      without crashing.

## <a name="deliberate-deltas-runtime-core-target-zero"></a>Deliberate deltas (runtime core) — target zero

The portable core ports the semantics authority (`packages/core`, TypeScript)
byte-for-byte where it matters, pinned by the shared corpora + drift guards. Known,
**intentional** seams (none change observable save/quest/world semantics):

| Delta | Where | Why it is not a semantic difference |
| ----- | ----- | ----------------------------------- |
| Slot timestamps (`createdAt`/`lastSavedAt`/envelope `exportedAt`) are caller-supplied at write time. | `InsimulSaveSystem` / codec | Timestamps are identity metadata, not part of the integrity-hashed contract; the golden envelope uses a fixed timestamp so the byte-pin holds. |
| Corrupt/incompatible save slot falls back to a new game instead of aborting boot. | `RuntimeContext::boot` / `InsimulRuntime.boot` | Resilience choice, not a semantic difference; a valid save always resumes. Matches the "never brick startup" intent. |
| Spawn positional/schedule data still comes from the legacy render export; the world source supplies only character identity. | `npc_spawner.gd` | The world source DTO is authoring data (no render transform); identity is the portable, cross-runtime contract, positions are engine-render detail. |
| The GDScript world source is not embedded in the C++ bootstrap core; entity counts are read off the loaded `worldSnapshot` JSON. | `bootstrap.cpp` | Same entity numbers as every runtime; the DTO-typed accessors live in `world_source.gd` (host-parity is the counts, which match). |

Any delta discovered during the human pass that is **not** listed here is a bug —
file it against this story rather than accepting it.

## Status on this machine (runtime core)

The Ralph harness has no `scons`/`godot`/`godot-cpp` and libinsimul is unbuilt, so
only the "runs on any box" gates were executed here (all green: save 58, quest 33,
bootstrap 42, structural lint 0 issues, `npm run check` exit 0, `npm test` 442
passed). The live full-loop checklist is unchecked pending a toolchain — reviewed at
merge (`autoMerge` is off).
