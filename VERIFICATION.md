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

---

# Godot scene generation + Asset Binding Layer verification (US-GB1..GB3)

A third verification surface: the **editor-time** (`@tool`) scene-generation
pipeline and the Asset Binding Layer — binding resolver, placeholder pack,
placement manifest, re-import diff policy, and the Binding Editor dock. Same two
tiers: machine gates that pass **here**, plus a live editor checklist that needs a
`godot` binary.

## Runs on any box (no Godot toolchain) — the merge gate

`npm run engines:check` (runs the godot gates only when `packages/godot/**`
changed) executes, in addition to the gates above:

1. **Binding-resolver host tests** (US-GB1) —
   `gdextension/test/run_binding_tests.sh`. The shared resolver matrix, the
   cross-engine Unity pack round-trip, and sorted-serialization determinism.
2. **Scene-placement host tests** (US-GB2) —
   `gdextension/test/run_placement_tests.sh`. The placement manifest computed
   from the golden IR matches the committed golden; placeholder coverage;
   determinism.
3. **Re-import diff host tests** (US-GB3) —
   `gdextension/test/run_reimport_tests.sh`. The dry-run report from the shared
   old/new manifests matches the golden; every one of the five actions
   (added/updated/unchanged/skipped/deprecated) is exercised; the hand-edit
   invariant (a `generated:false` node is only ever *skipped*) holds; determinism
   + no-op re-import. Expect **11 checks**.
4. **GDScript structural lint** — covers every `@tool` twin, the dock UI/model,
   and the re-import GDScript on a bare box (0 issues).

The headless GDScript legs (`editor/*/run_*_headless.sh`) SKIP cleanly without a
`godot` binary; the host C++ gates hold each contract.

## Needs a `godot` binary — human end-to-end checklist

### <a name="bind-custom-scene-regenerate-us-gb3"></a>Bind a custom scene + regenerate (US-GB3)

The core re-import safety property: a human-bound / hand-edited node survives a
regenerate. Open the template (or any project with the addon) in the editor with
the Binding Editor dock docked (top-right):

- [ ] **Generate.** Run the `@tool` pipeline (`InsimulSceneGenerator.generate`) on
      a world IR; confirm the scene tree materializes with terrain chunks, roads,
      buildings, props, interiors, a `NavigationRegion3D`, and that every generated
      node carries `insimul_entity_id` + `insimul_generated = true` metadata.
- [ ] **Bind a custom scene.** In the dock, select an unbound (red) archetype,
      click **Bind Scene…**, pick a `.tscn`; the row turns green and shows the path.
      Binding a non-leaf key (**Bind Descendants…**) covers all its `*.` children.
- [ ] **Suggestions.** For an archetype like `building.residential`, the scene
      picker surfaces project assets whose name/tags contain `building` /
      `residential` ranked first; unrelated assets are excluded.
- [ ] **Hand-edit a node.** Move/replace a generated node in the scene and set its
      `insimul_generated` metadata to `false` (marking it a manual override).
- [ ] **Regenerate (dry-run first).** Re-run the pipeline and inspect the re-import
      report: the hand-edited node is **skipped**, a re-bound archetype's node is
      **updated** to the new asset, brand-new entities are **added**, and any entity
      the new IR dropped shows as **deprecated**.
- [ ] **Apply.** `InsimulReimport.apply_reimport(existing, fresh)`: confirm the
      hand-edited node is untouched (position + custom scene preserved), the
      deprecated node is reparented under a **Deprecated** group (not deleted, and
      in the `insimul_deprecated` group), and the new nodes are present. Re-running
      with no IR change is a **no-op** (report shows only unchanged/skipped).
- [ ] **Pack round-trip.** **Export Pack…** to JSON, **Import Pack…** it back into a
      fresh dock; the bindings survive and the re-exported pack is byte-identical
      (the `insimul-binding-pack` interchange shared with Unity/Unreal).
- [ ] **Determinism.** Two generate runs on the same IR produce an identical scene
      tree (serialized comparison) — the host `run_placement_tests.sh` /
      `run_reimport_tests.sh` gates pin this on the bare box.

## Status on this machine (scene/binding)

`npm run engines:check` is green here: binding-resolver 19, scene-placement 3,
re-import diff 11, structural lint 0 issues, plus root `npm run check` (exit 0) and
`npm test` (442 passed). The editor checklist above is unchecked pending a `godot`
binary — reviewed at merge (`autoMerge` is off).

## Editor backend connection (US-GE1)

The editor's own v1 client + session foundation (separate from the runtime
`insimul_client.gd` autoload). Machine-runnable gates pass **here**; the editor
end-to-end needs a `godot` binary and a running platform server (reviewed at merge).

### Runs on any box (no Godot toolchain)

- **Operation-table conformance** (`npm test`) —
  `packages/core/src/editor/__tests__/operations.test.ts` pins three copies of the
  v1 table together: the generated `openapi/operations.json`, the core
  `V1_OPERATIONS` const, and the GDScript `v1_client.gd` `OPERATIONS` table. Any
  drift in an operationId, method, or path fails the guard. Every `USED_OPERATIONS`
  id must resolve.
- **Session lifecycle** (`npm test`) —
  `packages/core/src/editor/__tests__/editor-session.test.ts` drives the reference
  `EditorSession` over a mocked transport: health 200 → ok + parsed `healthy`,
  login 200 keeps the token, login 401/403 **clears** the token, request carries
  base-URL-joined path + bearer auth. The GDScript `insimul_editor_session.gd`
  mirrors this contract (`connect_test.gd`, below).
- **Secret-storage rule** (`npm test`) — the same conformance suite statically
  asserts the token key (`insimul/editor/api_token`) **never** appears on a
  `ProjectSettings` line and is persisted only via the `EditorSettings` handle,
  while the non-secret server URL (`insimul/editor/server_url`) goes to
  `ProjectSettings`. Documented in `addons/insimul/editor/connect/README.md`.
- **GDScript structural lint** — the six new `connect/*.gd` files are covered by
  `gdscript_structural_lint.py` (0 issues).

### Needs a `godot` binary — human end-to-end checklist

- [ ] **Logic-layer headless** —
      `bash addons/insimul/editor/connect/run_connect_headless.sh` (with a `godot`
      binary on PATH) runs `connect_test.gd`: client resolve, unknown-op guard,
      request build, health probe, login success, and login-401-clears-token over
      `InsimulV1MockTransport`. Expect all PASS.
- [ ] **Settings split in the editor** — set the server URL in Project Settings
      (`insimul/editor/server_url`) and confirm it persists to `project.godot`; set
      the API token via the editor session and confirm it lands in `EditorSettings`
      (per-machine, e.g. `editor_settings-*.tres`) and **not** in any committed
      project file (`git status` shows no token in `project.godot`).
- [ ] **Live health/verify** — against a running platform server, `verify()` on a
      valid token returns ok (`healthy: true`); an invalid token returns 401 and the
      session clears it (`is_authenticated()` false).

## Status on this machine (editor-connect)

`npm run engines:check` is green here (structural lint 0 issues incl. the new
`connect/*.gd`; the editor-connect headless runner SKIPs without a `godot` binary),
plus root `npm run check` (exit 0) and `npm test` (459 passed, incl. 17 editor
tests). The editor checklist above is unchecked pending a `godot` binary +
platform server — reviewed at merge (`autoMerge` is off).

## World Browser + Generation Console docks (US-GE2)

Two in-editor docks over the US-GE1 session: the **World Browser** (worlds
list/detail/stats, compatibility badge, Import/Sync with a dry-run report,
open-in-web) and the **Generation Console** (start a generator as a job, track
progress via SSE with a polling fallback, sync-now). The view-model logic is the
tested contract; the Control docks are UI, reviewed at merge.

### Runs on any box (no Godot toolchain)

- **World Browser view-model** (`npm test`) —
  `packages/core/src/editor/__tests__/world-browser.test.ts` (16 cases): the
  compatibility badge vs `SAVE_FILE_VERSION` (equal→compatible, older→warning,
  newer→incompatible), `listWorlds` / `importWorld` body parsing (malformed
  entries dropped, bad bodies tolerated), the dry-run report summary, the
  open-in-web URL, and the list+selection reducer — including a re-fetch that
  drops the selected world clearing the dangling selection.
- **Job-lifecycle view-model** (`npm test`) —
  `generation-console.test.ts` (12 cases): `queued → running → succeeded/failed`
  over mocked SSE frames + a poll response, progress clamped to `[0,1]`,
  succeeded forcing progress to 1 with the diff, error frames failing the job, and
  the **terminal-freeze** rule (a terminal job ignores later events, so the SSE and
  polling paths can safely overlap).
- **Editor-restart safety / teardown** (`npm test`) —
  `job-poller.test.ts` (7 cases): the poller stops on its own at a terminal
  status; `dispose()` cancels the pending timer (**no live timer survives**); a
  fetch callback returning **after** dispose is **dropped** (no `onUpdate`, no next
  poll) — the zombie-request guarantee; `maxPolls` safety valve; idempotent
  `dispose()`/`start()`. Uses a fake `Scheduler` (tracks live timers) + a
  manually-fired `JobFetch` so the whole lifecycle runs with no real clock/HTTP.
- **Operation-table conformance** (`npm test`) — the US-GE1 guard now also pins the
  seven new worlds/generation operations (`listWorlds`, `getWorldDetail`,
  `importWorld`, `startGenerationJob`, `getGenerationJob`, `streamGenerationJob`,
  `syncGenerationJob`) across `operations.json` ⟷ `V1_OPERATIONS` ⟷ the GDScript
  `OPERATIONS`/`USED_OPERATIONS` tables. `npm run codegen` regenerated the spec +
  C# client (codegen drift guard green).
- **GDScript structural lint** — the eight new `browser/*.gd` + `generation/*.gd`
  files (models, docks, tests) are covered by `gdscript_structural_lint.py`
  (0 issues, 141 files).

### Needs a `godot` binary — human end-to-end checklist

- [ ] **Logic-layer headless** —
      `bash addons/insimul/editor/browser/run_browser_headless.sh` and
      `bash addons/insimul/editor/generation/run_generation_headless.sh` (with a
      `godot` binary on PATH) run `browser_test.gd` / `generation_test.gd`: the
      GDScript mirrors of the compatibility badge, parsers, browser reducer, job
      reducer, and the poller teardown (late response dropped, no orphaned timer).
      Expect all PASS.
- [ ] **World Browser in the editor** — against a running platform server, the dock
      lists worlds, shows the detail + stats + compatibility badge for a selection,
      an Import (dry run) shows a change summary without writing, and Open-in-Web
      opens the world in the browser.
- [ ] **Generation Console in the editor** — starting a generator shows live
      progress (SSE, or the polling fallback when the stream can't be held), reaches
      `succeeded`, and Sync Now applies the diff. Then **reload the dock / restart
      the editor mid-job** and confirm no orphaned timer or request (the poller is
      disposed in `_exit_tree`).

## Status on this machine (US-GE2)

`npm run check` exit 0; `npm test` **494 passed** (incl. 35 new US-GE2 view-model
tests + the extended conformance guard); `npm run engines:check` green (structural
lint 0 issues across 141 `.gd`; the two new headless runners SKIP without a `godot`
binary). The editor checklists above are unchecked pending a `godot` binary +
platform server — reviewed at merge (`autoMerge` is off).
