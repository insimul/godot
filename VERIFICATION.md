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
   `expected` solution in the vendored `conformance/prolog/*.json` through the
   extension's marshalling layer. Expect **76 cases / 97 solutions green** across
   10 corpus files. This gate **decodes solution sets; it does not run queries** —
   see `RUNTIME_CORE_ADOPTION.md` §6.5 for which half of parity it covers. It was
   41 cases until tasklist 100's US-3 re-vendored the drifted corpus (§10.2), and
   it now asserts a file/case floor so a corpus that shrinks again fails instead
   of printing a smaller green number.
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

## In-editor NPC Conversation Tester (US-GE3)

A dock for testing a world's NPC conversations from the editor over the US-GE1
session: pick a character from imported world data, send a line, and watch the
character response stream into a transcript — with a **PIE-style recorded-reasoning
fallback** for when editor-process streaming misbehaves. The view-model logic is the
tested contract; the Control dock is UI, reviewed at merge. Constraints are documented
in `addons/insimul/editor/conversation/README.md`.

### Runs on any box (no Godot toolchain)

- **Conversation view-model** (`npm test`) —
  `packages/core/src/editor/__tests__/conversation-tester.test.ts` (18 cases): the
  character picker (`extractCharacters` from imported world data, entries without an
  id dropped, name falling back to `firstName`+`lastName` then the id); the SSE-frame
  parser (`parseConversationEvent`: text/reasoning/action/error/done, blank
  keep-alives + unknown types → null); the transcript reducer over a **mocked
  stream** (text chunks append, a final chunk closes the turn → `awaiting`, actions
  recorded, a `done` frame closes the turn, a second player line appends a new pair,
  events after a turn closes ignored, `end` freezes the conversation).
- **Recorded-reasoning fallback** (`npm test`) — the PIE-style **auto-switch**: a
  stream error on a live stream flips to the recorded mode (`recording`) instead of
  failing; `streamFailed` forces the fallback and a `recorded` action completes the
  turn (`fromRecording = true`); an error while **already** in the fallback is a hard
  `error`.
- **Editor-restart safety / teardown** (`npm test`) — the
  `ConversationController` teardown: a stream frame arriving **after** `dispose()` is
  **dropped** (no `onUpdate`, the late chunk never applied) — the zombie-frame
  guarantee; `dispose()` is idempotent; a keep-alive frame fires no update.
- **Operation-table conformance** (`npm test`) — the US-GE1 guard now also pins the
  two conversation operations the tester uses (`streamConversation`,
  `endConversation`) across `V1_OPERATIONS` ⟷ `USED_OPERATION_IDS` ⟷ the GDScript
  `OPERATIONS`/`USED_OPERATIONS` tables (both already in the spec since US-GE1).
- **GDScript structural lint** — the four new `conversation/*.gd` files (reducer,
  controller, dock, test) are covered by `gdscript_structural_lint.py`.

### Needs a `godot` binary — human two-turn checklist

- [ ] **Logic-layer headless** —
      `bash addons/insimul/editor/conversation/run_conversation_headless.sh` (with a
      `godot` binary on PATH) runs `conversation_test.gd`: the GDScript mirrors of the
      picker, frame parser, transcript reducer, recorded-fallback auto-switch, and the
      controller teardown (late frame dropped, no update). Expect all PASS.
- [ ] **Two-turn conversation in the editor** — against a running platform server
      with an imported world: pick a character in the dock, send **turn 1** and watch
      the response stream into the transcript, then send **turn 2** and confirm it
      appends a new player/character pair below the first. The picker lists the
      imported world's characters; switching character starts a fresh transcript.
- [ ] **Recorded-reasoning fallback** — force a stream failure (stop the server
      mid-turn, or a world with no streaming route) and confirm the dock shows the
      `[recorded reasoning fallback]` marker and the turn is completed from a recorded
      trace rather than the conversation erroring out.
- [ ] **Editor-restart safety** — start a turn, then **reload the dock / restart the
      editor mid-stream** and confirm no late SSE frame touches a freed node (the
      controller is disposed in `_exit_tree`).

## Status on this machine (US-GE3)

`npm run check` exit 0; `npm test` green incl. **18 new US-GE3 conversation
view-model tests** + the extended operation-table conformance (`streamConversation` /
`endConversation` pinned three ways); `npm run engines:check` green (structural lint
clean incl. the four new `conversation/*.gd`; the new headless runner SKIPs without a
`godot` binary). The editor two-turn checklist above is unchecked pending a `godot`
binary + platform server — reviewed at merge (`autoMerge` is off).

---

## Default-UI quest journal/tracker/offer + inventory/container/merchant (US-GU2)

The stable quest + trade UI is lifted into `addons/insimul/ui/` behind the panel
registry (US-GU1). The behavior lives in two engine-neutral view-models mirrored
1:1 in GDScript, so both legs run the SAME shared matrices:

- **Quest**: `packages/core/src/ui/quest-journal-model.ts` ⟷
  `addons/insimul/ui/quest_journal_model.gd` — tab filtering (all/active/completed/
  available) + counts, the bounded tracker HUD (`max_tracked`, auto-untrack on
  complete), and offer accept/decline; radiant arrivals land via `upsert`. The
  transitions mirror the real `InsimulQuestSystem` signals (quest_accepted /
  quest_completed / quest_offered). Thin Control binders:
  `quest_journal_panel.gd`, `quest_tracker_panel.gd`, `quest_offer_panel.gd`.
- **Trade**: `packages/core/src/ui/trade-model.ts` ⟷
  `addons/insimul/ui/trade_model.gd` — inventory / container transfer / merchant
  buy+sell, backed EXCLUSIVELY by `save.currentState` (`player.gold` /
  `player.inventory`, `containers.containers[id].items`,
  `npcs.merchantStates[id].{goldReserve,items}`). Thin Control binders:
  `inventory_panel.gd`, `container_panel.gd`, `merchant_panel.gd`.

### Runs on any box (no Godot toolchain) — the merge gate

- **Shared view-model cases (quests + trade matrices)** (`npm test`) — the runner
  `packages/core/src/ui/__tests__/quest-trade-corpus.test.ts` executes
  `packages/core/conformance/ui/{quest-journal-cases,trade-cases}.json` against the
  TS models: 7 quest cases (filter partition, accept, complete+untrack, decline,
  max-tracked, non-active track rejection, radiant arrival) + 9 trade cases (take /
  take-clamp / take-all, buy affordable/insufficient-gold/out-of-stock, sell /
  merchant-broke / player-lacks-item).
- **State-location invariant** (`npm test`) — same test file: the trade model keeps
  no private store (reads return the live `currentState` arrays; two models over two
  states never share state), and every op conserves the census — a merchant trade
  conserves gold (`player.gold + merchant.goldReserve`), a container take conserves
  the item census (items move, never created/destroyed).
- **GDScript structural lint** (`npm run engines:check`) — the five new `ui/*.gd`
  view-models/panels + the `tests/quest_trade_test.gd` mirror are covered.
- **Headless GDScript parity** (`npm run engines:check`) —
  `run_quest_trade_headless.sh` runs `quest_trade_test.gd` (the SAME shared JSON +
  the state-location invariant, incl. a true reference-identity probe) when a
  `godot` binary is on PATH; it **SKIPs** cleanly on the bare Ralph box, where the
  structural lint + the TS corpus run cover the contract.

### Needs a `godot` binary — human end-to-end checklist

- [ ] **Quest journal + tracker** — open the journal (registry key `quest_journal`),
      switch tabs and confirm the list partitions by status; track up to
      `max_tracked` active quests and confirm the tracker HUD (`quest_tracker`)
      mirrors them; complete a quest and confirm it drops off the tracker and lands
      under Completed.
- [ ] **Radiant offer** — trigger a radiant arrival (or an NPC offer) and confirm the
      offer dialog (`quest_offer`) appears; Accept moves it to Active in the journal,
      Decline removes it.
- [ ] **Inventory / container / merchant against a save** — loot a container into the
      inventory and confirm the item count moves (not duplicates); buy/sell at a
      merchant and confirm gold + stock update on BOTH sides and that a re-open reads
      the same values from `save.currentState` (no separate store).

### Status on this machine (US-GU2)

`npm run check` exit 0; `npm test` green incl. **21 new US-GU2 tests** (quest + trade
shared matrices + the state-location invariant); `npm run engines:check` green
(structural lint clean incl. the new `ui/*.gd`; `run_quest_trade_headless.sh` SKIPs
without a `godot` binary as designed). The human checklist above is unchecked pending
a `godot` binary — reviewed at merge (`autoMerge` is off).

---

## Default-UI dialogue panel + pause/main menu + save/load (US-GU3)

The last default-UI slice: the streaming NPC dialogue panel, the unified ESC menu
with module-bundle-gated tabs, the main menu, and the save/load slot UI with
integrity-failure messaging. Three engine-neutral view-models mirrored 1:1 in
GDScript, so both legs run the SAME shared matrices:

- **Dialogue**: `packages/core/src/ui/chat-model.ts` ⟷
  `addons/insimul/ui/chat_model.gd` — the streaming SDK turn lifecycle (a player
  line opens a turn, `appendChunk` accumulates the NPC bubble, `triggerAction`
  records KB actions, `completeTurn`/`failTurn` close it), plus the
  `save.conversations` (`ConversationSummary.recentTurns`) history projection. The
  thin Control (`dialogue_panel.gd`) wires the `AIService` streaming signals and the
  engine-coupled hooks: **TTS**, **`insimul_lip_sync`**, and asserting each action's
  Prolog fact into the **KB** (PrologEngine).
- **Pause menu**: `packages/core/src/ui/pause-menu-model.ts` ⟷
  `addons/insimul/ui/pause_menu_model.gd` — tab visibility gated by the feature
  modules the active genre bundle enabled (an ungated core tab always shows; a gated
  tab shows only when every required module is enabled), plus the open/active-tab
  reducer. Thin Control `pause_menu.gd` owns `get_tree().paused` + the ESC toggle;
  `main_menu.gd` is the title screen (Continue/Load gate on `has_any_loadable`).
- **Save/load**: `packages/core/src/ui/save-slot-model.ts` ⟷
  `addons/insimul/ui/save_slot_model.gd` — codec-reported slot outcome (empty / ok /
  `invalid_format` / `missing_save_file` / `integrity_mismatch`) → a rendered row
  (status/title/message/can_load/can_save). The corrupted-envelope messaging is a
  cross-engine contract. Thin Control `save_load_panel.gd`.

### Runs on any box (no Godot toolchain) — the merge gate

- **Streaming / action / history + tab-gating + save-slot shared cases** (`npm test`)
  — the runner `packages/core/src/ui/__tests__/dialogue-menu-save-corpus.test.ts`
  executes `packages/core/conformance/ui/{chat-cases,pause-menu-cases,save-slot-cases}.json`
  against the TS models: 7 chat cases (single/two-turn streaming, full-text override,
  KB action trigger, error bubble drops the turn from history, reject-while-streaming,
  no-op complete), 7 pause-menu cases (language-learning / rpg / strategy / empty
  module sets, AND-gating, the open+active-tab reducer, hidden-tab fallback), and 6
  save-slot cases (empty / ok-summary / integrity-mismatch / bad-format / missing /
  mixed sorted).
- **Corrupted-envelope integrity chain** (`npm test`) — same test file: it builds a
  real `SaveFileEnvelope`, tampers the payload, and runs the actual SHA-256
  `validateSaveFileEnvelope` through `SaveSlotModel.classifyEnvelope`, asserting the
  `integrity_mismatch` verdict renders the corrupted row + message (a null candidate
  is `empty`, a wrong-format blob is `invalid_format`).
- **GDScript structural lint** (`npm run engines:check`) — the seven new `ui/*.gd`
  view-models/panels + the `tests/dialogue_menu_save_test.gd` mirror are covered.
- **Headless GDScript parity** (`npm run engines:check`) —
  `run_dialogue_menu_save_headless.sh` runs `dialogue_menu_save_test.gd` (the SAME
  shared JSON) when a `godot` binary is on PATH; it **SKIPs** cleanly on the bare
  Ralph box, where the structural lint + the TS corpus cover the contract.

### Needs a `godot` binary — human full-loop checklist

- [ ] **Dialogue streaming** — open the dialogue panel (registry key `dialogue`) on
      an NPC; the greeting shows, a sent line streams the response chunk-by-chunk into
      the NPC bubble, and the input is locked until the turn completes. A stream error
      renders an `[Error: …]` bubble and unlocks input.
- [ ] **TTS + lip-sync** — with a TTS provider + `insimul_lip_sync` hook registered,
      the settled NPC line is spoken and the speaker's visemes animate; neither fires
      for an errored turn.
- [ ] **KB action trigger** — an NPC response that triggers an action (e.g.
      `give_item(sword)`) asserts the mapped fact (`has_item(player,sword)`) into the
      PrologEngine KB exactly once.
- [ ] **History persists** — close the conversation and confirm
      `model.history()` lands in `save.conversations` (recentTurns + totalTurnCount);
      errored/in-flight bubbles are excluded.
- [ ] **ESC menu tab-gating** — with an RPG bundle, the pause menu hides the
      Assessment tab; with a language-learning bundle every gated tab (Character /
      Vocabulary / Skills / Analytics / Assessment) appears. ESC toggles the menu and
      pauses the tree; switching tabs updates the active tab (a hidden tab is
      unselectable).
- [ ] **Main menu** — Continue/Load are disabled on a fresh install (no loadable
      slot) and enabled once a slot exists; New Game starts a fresh run.
- [ ] **Save/load slots incl. corrupted** — a healthy slot shows its summary and
      loads; a slot whose codec integrity check fails renders as **Corrupted Save**
      with the integrity message, is not loadable, but can be overwritten.

### Status on this machine (US-GU3)

`npm run check` exit 0; `npm test` green incl. **23 new US-GU3 tests** (dialogue /
pause-menu / save-slot shared matrices + the real SHA-256 corrupted-envelope chain);
`npm run engines:check` green (structural lint clean incl. the new `ui/*.gd`;
`run_dialogue_menu_save_headless.sh` SKIPs without a `godot` binary as designed). The
human full-loop checklist above is unchecked pending a `godot` binary — reviewed at
merge (`autoMerge` is off).

---

# `@insimul/core` adoption verification (tasklist 100, US-2)

The first slice of the shared runtime core — **radiant quest generation** —
running through `libinsimulcore` (`gdextension/corebridge/`). This is the gate
that proves the language-boundary decision of `RUNTIME_CORE_ADOPTION.md` §4:
core's real TypeScript, in an embedded QuickJS, on the natively linked Trealla,
against the same 11 vectors `packages/core` runs.

## Runs on any box **with libinsimul built**

```sh
npm run test:radiant                                        # source=core
bash gdextension/test/run_radiant_tests.sh --source none    # pre-adoption leg
```

Expect **11 cases executed / 5 areas / 0 failures** on the `core` leg. The count
is *asserted*, not merely printed: an empty corpus dir, a shrunken corpus, a
missing area file, a duplicate case name or a bundle that no longer exposes
`radiant.generate` all fail the gate. This repo has shipped gates that could not
fail; this one can.

The `none` leg reproduces pre-adoption behaviour (no generation) and, since
US-3, **classifies** rather than merely counts: **4 AGREE, 7 GAIN, 0
REGRESSION**. The four cases that expect zero quests agree; the seven that expect
quests are the capability core adds. It fails if the pre-adoption path ever
produces a quest of its own (a regression), and it also fails if GAIN reaches
zero — a comparison that has quietly stopped comparing must not read as green.

```sh
npm run test:quest-parity                                     # both legs
bash gdextension/test/run_quest_parity_tests.sh --source cpp  # hand-port alone
```

The **two-implementation diff** (`RUNTIME_CORE_ADOPTION.md` §10.3). Runs
`conformance/quests/{hydration,radiant}-cases.json` through both this repo's
hand-ported `gdextension/src/quest_system.cpp` and `@insimul/core` through
`libinsimulcore`, reducing all three legs (corpus / cpp / core) with the same C++
canonicalizer, and classifies every case **AGREE / FIX / SHAPE / REGRESSION**.
Result: **7 AGREE, 0 FIX, 0 SHAPE, 0 REGRESSION** — total agreement. A regression
blocks the gate. The classifier is exercised against five synthetic triples
before the corpus runs, so "everything agrees" is a finding rather than the only
sentence the code can produce.

> **Unlike every other host gate here, this one links libinsimul**, because
> core's radiant algorithm is Prolog-driven and the whole point of the adoption
> is that it runs on the engine this plugin already ships rather than a wasm copy
> of it. It therefore **fails loudly** when the library is absent rather than
> skipping. Point it at a build with `INSIMUL_NATIVE_DIR=<insimul-native
> checkout>` or `INSIMUL_NATIVE_DIST=<dist/platform>`; otherwise it probes the
> usual sibling layouts. No cmake, scons, godot-cpp or Godot binary is needed —
> it builds QuickJS and the bridge with a plain C/C++ compiler in a few seconds.

## Runs on any box, no libinsimul

```sh
npm run check          # GDScript structural lint + bundle drift guard + corpus drift guard
```

The second part verifies that `corebridge/vendor/core/`'s bundle, its generated C
array and its `VENDORED.json` provenance all agree. The third
(`tools/vendor-conformance.mjs --check`) verifies the vendored `conformance/`
tree against the per-file sha256 in `conformance/VENDORED.json`, and rejects any
file that is neither mirrored nor declared local — the guard that did not exist
while the Prolog corpus quietly rotted to 41 of 76 cases. To check for drift
against core *itself* — which needs a checkout that has `packages/core` — add
`--core`:

```sh
node tools/vendor-conformance.mjs --check --core ../babylon/packages/core
```

```sh
node tools/vendor-core-bundle.mjs --check --core ../babylon/packages/core
```

That re-bundles and diffs byte-for-byte, so a core change under an adopted method
cannot slip in unnoticed.

## Status on this machine

| gate | result |
| --- | --- |
| `npm run check` | ✅ 173 `.gd` files structurally sound; bundle + corpus artifacts consistent |
| `node tools/vendor-core-bundle.mjs --check --core …` | ✅ re-bundle reproduces the vendored artifact byte-for-byte |
| `node tools/vendor-conformance.mjs --check --core …` | ✅ 34 mirrored files byte-identical to `packages/core/conformance` |
| `npm run test:conformance` | ✅ **10 files, 76 cases, 76 passed** (was 41 — see §10.2) |
| `npm run test:radiant` | ✅ **11 cases, 5 areas, 0 failures** |
| `run_radiant_tests.sh --source none` | ✅ **4 AGREE, 7 GAIN, 0 REGRESSION** |
| `npm run test:quest-parity` | ✅ **7 AGREE, 0 FIX, 0 SHAPE, 0 REGRESSION** (+ 5/5 classifier self-test) |
| `run_quest_parity_tests.sh --source cpp` | ✅ 7 cases, hand-port alone (no libinsimul needed) |
| `bash gdextension/test/run_host_tests.sh` | ✅ 24/24 |
| `bash gdextension/test/run_save_tests.sh` | ✅ 58 checks, 0 failures |
| `bash gdextension/test/run_quest_tests.sh` | ✅ 33 checks, 0 failures |
| `bash gdextension/test/run_bootstrap_tests.sh` | ✅ 42 checks, 0 failures |
| `bash gdextension/test/run_binding_tests.sh` | ✅ |
| `bash gdextension/test/run_placement_tests.sh` | ✅ |
| `bash gdextension/test/run_reimport_tests.sh` | ✅ |

The last three save/quest/bootstrap rows were **failing before this story** — not
semantically, but because they hardcoded a monorepo corpus path and this repo is
standalone (`RUNTIME_CORE_ADOPTION.md` §6.4). They now resolve the vendored
corpus first, and hit exactly the counts this document always claimed.

Still needs a `godot` binary **and a built GDExtension**, and so is unchecked
here: `InsimulCore` and `InsimulRadiantSource` running inside the editor/exported
game, `gdextension/tests/conformance_runner.gd` (the only thing that executes the
Prolog corpus as *queries*), and the `addons/insimul/tests/run_*_headless.sh`
suites. A bare `godot` binary on PATH is not enough — those runners want the
extension, which needs godot-cpp + scons; they hang rather than skip in this
harness. What the host gates cover is the entire path below GDScript — the same C
ABI calls, the same bundle, the same Prolog engine — so what is unverified is the
GDScript wrapper itself, not the adoption.

---

# Band-120 mechanic modules (tasklist 147, US-1)

The seven mechanic modules — combat, stamina, perception, traversal, skill,
equipment, routine — running through `libinsimulcore` as **27 rows** in
`gdextension/corebridge/js/entry.js`, with all **eight** host interfaces they
declare implemented in GDScript. `RUNTIME_CORE_ADOPTION.md` §11 is the design and
the findings; this is how to check it.

## Runs on any box (no Godot toolchain, no libinsimul)

```sh
npm run check
```

The fourth stage is new: `tools/verify-mechanics/check-mechanics.mjs --self-test`.
It mirrors this repo against a vendored derivation of core's own module manifest
(`tools/verify-mechanics/MODULE_HOSTS.json`) six ways —

1. **manifest** — the seven modules are present and each names a host interface
   and a decision layer;
2. **contract** — every interface's member list has a matching method on the
   GDScript base class in `addons/insimul/runtime/mechanics/insimul_mechanic_hosts.gd`;
3. **implementation** — every interface is extended by at least one GDScript
   class, or declared in `stubbed` **with a stated consequence** (that is what
   makes "no silent no-op" checkable, and `stubbed` is currently empty);
4. **bridge** — `entry.js`'s module table agrees with core on host interfaces and
   decision layers, and every row it declares exists in its `METHODS` table;
5. **orders** — every order the adapter can emit has a dispatch branch in
   `insimul_mechanic_session.gd`;
6. **corpus** (US-2) — every module's declared conformance corpus is vendored,
   every vendored decision area has a runner in
   `gdextension/corebridge/js/host-corpus.js`, every runner has a corpus, and
   every directory under `conformance/` is accounted for by a named gate or by an
   explicit "nothing here runs it". Both directions, because each catches a
   different way of ending up with a checked-in file nobody executes.

`--self-test` breaks each check on purpose first and requires it to fail, so a
green run means six checks that *can* fail did not. To check drift against core
itself — which needs a checkout that has `packages/core`:

```sh
node tools/verify-mechanics/check-mechanics.mjs --core ../babylon/packages/core
node tools/verify-mechanics/check-mechanics.mjs --core ../babylon/packages/core --write   # re-derive
```

## Runs on any box **with libinsimul built**

```sh
npm run test:mechanics
```

Drives all seven decision layers end to end — core's real TypeScript in QuickJS,
on the natively linked Trealla — and asserts **43 checks**. It fails loudly when
libinsimul is absent rather than skipping, like the radiant gate; point it at a
build with `INSIMUL_NATIVE_DIR=` or `INSIMUL_NATIVE_DIST=`.

What the 43 cover, and why each is worth a gate rather than an argument:

| claim | how it is checked |
| --- | --- |
| the rows are REACHABLE | `mechanic.modules` names seven modules; every row it declares is in `core.methods`; the row count has a floor so a surface that shrinks fails |
| readings reach core | a blocked line-of-fire reading refuses the shot; `ICombatStatSink.getBaseStats` is asked exactly once per equip |
| orders reach the host | `applyDamage` carries the resolution's own number; `registerEntity` is an order rather than a bridge-side write; one movement produces exactly one `travel` |
| the host cannot DECIDE | the same shot is fired with a clear line, a blocked line and no reading at all — the difference is core's, and a missing reading still fights |
| sessions are real | two sessions of one module do not share state; a disposed handle is an ERROR, not an empty answer; no session outlives the gate |
| the Prolog seam works | `applied: true` with a KB wired, and three spends of five leaving 85 — the assert/retract path that did not exist before this story |

## Needs a `godot` binary + a built extension — human checklist

No GDScript is executed by any gate here, and the Godot implementations live in
`templates/`, which is the exported game and is in no compiled assembly. So the
following is a human pass in a project with a scene, a `NavigationRegion3D` and a
`CharacterBody3D`:

1. **Boot report.** `print()` `InsimulMechanicSurface.new().report()`. Expect one
   line per module reading `ready`, and the interfaces each executes through. A
   module reading `bridge_has_no_row` means the installed `libinsimulcore`
   predates this story.
2. **Combat.** Open a `combat` session with two combatants and a `projectile`
   action; wire `GodotCombatHost.combat_system()` and
   `GodotGeometryProbes.trajectory()`. Fire with a crate between the two: expect
   `blockedBy` to name the crate's node and the health bar not to move. Step
   aside and fire again: expect health to drop by exactly the number in the
   report, and no second roll anywhere.
3. **Traversal + locomotion.** Author a `geometric` link, bind both ends with
   `InsimulActorRegistry.bind_place`, and call `traversal.traverse`. Expect the
   NPC to walk the `NavigationAgent3D` path, `movement_ordered` to carry the
   urgency atom core resolved, and the stamina bar to move by the resolved cost
   (link cost × the world's mode multiplier) — once, not twice.
4. **Skills.** Unlock a node whose effect is `modifies(move_speed, 10)` and watch
   the body's `move_speed` rise by 10%. Unlock it again (or reload a save): the
   value must not move a second time — the totals are absolute.
5. **The recorded gap.** A node with `modifies(carry_capacity, N)` must print the
   `carry_capacity` warning and appear in `unapplied()`, and must NOT invent an
   inventory limit.

## Status on this machine

| gate | result |
| --- | --- |
| `npm run check` | ✅ 182 `.gd` files structurally sound; bundle + corpus artifacts consistent; 19 case floors met; 7 modules / 8 interfaces / 27 rows; 6/6 negative controls fail as designed |
| `check-mechanics.mjs --core …` | ✅ manifest matches core `76782e5` |
| `npm run test:mechanics` | ✅ **43 checks, 0 failures** |
| `npm run test:corpus` | ✅ **467 cases** — 254 AGREE / 1 AMEND / 0 DIVERGE prolog, 212 AGREE / 0 DIVERGE decisions |
| `npm run test:conformance` | ✅ 255 cases / 217 solutions marshalled across 21 files (was 76 / 10) |
| `npm run test:radiant` | ✅ 11 cases, 5 areas — unchanged by the new bundle |
| `npm run test:quest-parity` | ✅ 7 AGREE, 0 REGRESSION — unchanged |
| every other host gate | ✅ 24 / 42 / 19 / 3 / 33 / 11 / 58 — unchanged |
| human checklist above | ⬜ needs a Godot editor; unchecked here |

---

# Band-120 corpora, executed (tasklist 147, US-2)

The seven modules' **parity**, as distinct from their reachability above:
`RUNTIME_CORE_ADOPTION.md` §12 is the report, this is how to run it.

## Runs on any box **with libinsimul built**

```sh
npm run test:corpus        # bash gdextension/test/run_corpus_tests.sh
```

**467 cases in two halves**, both through the same bundle a shipped game loads:

| half | what runs | count |
| --- | --- | --- |
| vocabulary | every `conformance/prolog/*.json` case consulted and **queried** on the natively linked Trealla, solutions compared as an unordered multiset | 255 cases, 21 files |
| decision | every `conformance/{combat,items,routines,skills,stealth,traversal}/` case resolved by core's own `resolveAttack`, `runDetection`, `findRoute`, `resolvePrice`, `resolveAdvance`, `RoutineDirector` …, deep-compared to the pinned `expected` | 212 cases, 18 areas |

Every case is classified — **AGREE / AMEND / DIVERGE / ERROR** — and the counts
are printed. Only AGREE and AMEND are green. Expect:

```
prolog vocabulary : 254 AGREE, 1 AMEND, 0 DIVERGE, 0 ERROR  (255 case(s), 21 file(s))
module decisions  : 212 AGREE, 0 AMEND, 0 DIVERGE, 0 ERROR  (212 case(s), 18 area(s))
47 check(s), 0 failure(s)
```

The one `AMEND` is `assert-retract.json::asserta-prepends` and it prints a
`[AMEND]` line saying why. It is not a defect of this repo — no Trealla runs that
case as authored, and all five legs that read the file rename the predicate in
memory rather than editing the corpus. §12.3 classifies it.

Like the other libinsimul-linked gates it **fails loudly when the library is
absent** rather than skipping; point it at a build with `INSIMUL_NATIVE_DIR=` or
`INSIMUL_NATIVE_DIST=`.

### The seven checks on the gate itself

Because a parity gate that quietly stopped visiting an area would print a
smaller green number rather than red:

1–4. file, case and area **floors** for both halves (21 / 255 / 18 / 212);
5. every vendored area ran through a **declared** runner;
6. every runner the build declares had a vendored corpus **to** run;
7. every listed amendment was **still needed** — a stale one fails like a
   divergence, because an engine that got better and a table nobody re-validated
   look identical from the outside.

## Drift against core — the check that actually diffs

```sh
CORE=../babylon/packages/core
node tools/vendor-conformance.mjs  --check --core "$CORE"   # byte-for-byte, + 19 case floors
node tools/vendor-core-bundle.mjs  --check --core "$CORE"   # re-bundles and diffs
node tools/verify-mechanics/check-mechanics.mjs --core "$CORE"
```

All three print their NOT_MIRRORED exclusions with a count on every run. Without
`--core` they only verify the artifact's own hashes and say so.

## Status on this machine

| gate | result |
| --- | --- |
| `npm run test:corpus` | ✅ **47 checks, 0 failures — 467 cases, 0 divergences** |
| `vendor-conformance --check --core` | ✅ byte-identical to core `76782e5`; 63 files, 19 floors met |
| `vendor-core-bundle --check --core` | ✅ re-bundle reproduces the artifact byte-for-byte |
| `check-mechanics --core` | ✅ manifest matches core `76782e5` |
| `conformance/ui/*.json` | ⬜ **executed by nothing on this tier** — declared, not hidden (§12.5) |

---

# Genre-bundle activation (tasklist 147, US-3)

Which modules a world actually runs, and what a module it did *not* select costs.
`RUNTIME_CORE_ADOPTION.md` §13 is the report.

## Runs on any box (no Godot toolchain, no libinsimul)

```sh
npm run check     # includes check-mechanics' SEVENTH check
```

Check 7 is the one that holds US-3's claim to account: it greps
`addons/insimul/runtime/mechanics/insimul_module_activation.gd` and
`insimul_mechanic_activator.gd` for **every module id, pack area and genre id**
in `conformance/modules/genre-activation.json` — comments included — and fails on
a hit. It also fails when the vendored table and `MODULE_HOSTS.json` disagree
about a module's host interfaces (two artifacts, two tools, one core manifest),
and when a bundle activates a module that is neither adopted nor declared
unadopted. Its negative control plants a genre id in a fake source file.

## Runs on any box **with libinsimul built**

```sh
npm run test:activation     # bash gdextension/test/run_activation_tests.sh
```

**30 checks**, in four parts:

| part | what runs | count |
| --- | --- | --- |
| the table | `modules.table` deep-compared to the vendored `genre-activation.json` | 1 |
| the bundles | every genre resolved through `modules.activate`, by genre id **and** through a World IR's `meta.genreConfig.id`, deep-compared to the committed set | 8 genres, 24 activations |
| the edges | unknown genre → shared vocabulary only; nothing declared → every pack; a World IR with no `genreConfig` → undeclared, with the reason | 5 |
| the witness | for every genre × pack: consult exactly the active packs on the native Trealla and ask `current_predicate/1` for that pack's measured signature | 8 × 11 = 88 pairs |
| the scene | `templates/project/insimul/scenarios/dark-courtyard.json` replayed through the same rows the Godot scene calls | 6 steps, 2 modules |

Expect:

```
  ✓ `modules.table` is byte-equal to conformance/modules/genre-activation.json
  ✓ rpg                8 module(s), 10 pack(s), 8 host interface(s)
  ✓ rpg                10 of 11 pack(s) in the KB, and exactly the active ones
  ✓ puzzle             2 of 11 pack(s) in the KB, and exactly the active ones
  ✓ dark-courtyard     rpg: 6 step(s) across 2 module(s), every expectation met
30 check(s), 0 failure(s)
```

Like the other libinsimul-linked gates it **fails loudly when the library is
absent** rather than skipping.

## <a name="godot-activation-sample-scene"></a>Needs a `godot` binary — human scene pass

The half no host gate reaches: the raycasts, the lights and the bodies.

```sh
godot --path templates/project -s scripts/mechanics/mechanic_courtyard_demo.gd
```

- [ ] The boot log prints the activation block — the genre, where it came from
      (`worldIr` / `genre` / `undeclared`), one line per selected module, and the
      pack list.
- [ ] It prints **`selected but not runnable`** for `agentAi` and `map` under an
      `rpg` world. That is the honest state, not a bug: their packs are consulted,
      their decision layers are not bundled (§13.3).
- [ ] The guard detects the wanderer when the wanderer crosses the lantern's pool
      of light and not when they are in the dark — with the visibility number
      coming from `godot_geometry_probes.gd`'s raycast, not from the scenario.
- [ ] The spear thrust moves the wanderer's health by the number core decided
      (the `ICombatSystem.applyDamage` order), and the crossbow shot with the
      crate in the way applies nothing and reports `blockedBy: crate`.
- [ ] With a world whose genre is `puzzle`, the same scene activates nothing and
      says so — no session opens and the steps report `SKIPPED`.

## Status on this machine (activation)

| gate | result |
| --- | --- |
| `npm run check` (7 checks + 7 negative controls) | ✅ 186 `.gd` files, 0 problems |
| `npm run test:activation` | ✅ **30 checks, 0 failures** — 8 bundles, 88 KB witnesses, 6 scenario steps |
| `vendor-conformance --check --core` | ✅ byte-identical to core `76782e5`; 64 files, 19 case floors + the table floors met |
| the human scene pass | ⬜ needs a `godot` binary + a built extension |

---

# `insimul-talos-bridge` (tasklist 183)

The third artifact of `TALOS_INSIMUL_BRIDGE.md` §7.5 — the Talos bridge for an
Insimul game, which depends on both projects and is depended on by neither. Its
two halves gate separately: the DECISIONS under a plain C++ compiler, the
INSTALL under Node.

## Runs on any box — no Godot binary, and no libinsimul either

```sh
npm run test:talos-bridge   # bash gdextension/test/run_talos_bridge_tests.sh
npm run test:replay         # bash gdextension/test/run_talos_replay_tests.sh
npm run check               # includes tools/verify-talos-bridge/check-bridge.mjs --self-test
```

Nothing in the decision half touches a knowledge base, so unlike the corpus
gates this one has nothing it could be faking and always runs.

**73 checks**, in seven parts:

| part | what runs | count |
| --- | --- | --- |
| parity | every case `scripts/engine-versions/check-hello.mjs` publishes, mirrored into `gdextension/test/fixtures/refuse-at-hello/` and replayed through this port, demanding the same verdict AND the same token | 21 |
| the controls | the untouched hello admitted; one axis nudged refused; the SAME hello refused once the matrix demotes an axis | 3 |
| §7.5 | a state verb before a world is loaded is refused as `insimul_kb_uninitialized`, retryable, with its unblock recipe — never an empty success; and the refusal carries NO solution set while a genuinely empty query IS an admitted success with zero, so "no facts" and "no world yet" are different documents | 8 |
| §7.8 | every way this artifact can be half-installed is named — the extension absent, each of the three shipped files absent, and each of them present but not the file it claims to be — with what installs it, and an install missing everything names the FIRST piece in decision order | 3 |
| the mapping | six groups, the `capabilities.insimul` payload (null world half until there is a world; tier 1 / `kb_authoritative`), the four-axis checkpoint stamp, one refusal per verb class, the §3.6 template-write refusal | 22 |
| §3.4 | two enumeration orders produce one digest, and the cap truncates deterministically because the sort happens first | 5 |
| an unconfigured bridge | a bridge with no contract decides nothing rather than defaulting to something | 5 |

The parity suite is **two-sided by construction** — it carries an admitted hello
and a restored archive — because a decision procedure that refused everything
would otherwise pass every refusal case. Proven to fail: making
`evaluate_hello` stop reading the published axis status turns the run red on 4
checks.

**21 checks + 14 negative controls** in `check-bridge.mjs`, covering what a
decision cannot see: the artifact is separate (its own `plugin.cfg`,
`addons/insimul/` never mentions it, no Talos symbol anywhere in it), the six
groups agree between `bridge-contract.json` and `talos.game.yaml` **in both
directions**, every method and signal the group contracts name is really defined,
all 25 TBP verbs are accounted for with a why-not token on every one this bridge
does not answer, and no `insimul_*` token is spelled that a published vocabulary
does not carry.

Four of those checks are US-2's, and three of them are about code paths rather
than data:

- **§7.5 as a call graph.** Nothing reachable from `_init`/`_ready` may name
  `_kb`, `_world_id`, `_state_goals`, `_progress` or `_replay_world`, and every
  state answer must reach `_gate()` before it reaches the KB. Comments are
  stripped first — the adapter is allowed to *describe* the rule it obeys.
- **§7.8 visibility.** `_ready()` joins the groups BEFORE it configures, so a
  half-installed adapter is found and its refusal is heard rather than being an
  absence; and a broken install is a `push_error`, not a warning.
- **§7.8 vocabulary.** The failure modes compiled into `talos_bridge.cpp` and the
  contract's `stage: "install"` tokens are the same set, in both directions.
- **§8.6 totality.** Every refusal code core's replay module can produce maps to
  a published token the port really emits, and the shipped `input-vocabulary.json`
  carries core's action ids.

## The replay leg — one recorded session, four engines (§8.6)

```sh
npm run test:replay         # 20 checks, no libinsimul and no Godot binary
```

Tasklist 180 shipped, in core, a portable content-addressed input-trace artifact
(`insimul-input-trace-v1`), a replay driver, and the outcome document a four-way
comparison diffs (`insimul-replay-outcome-v1`). This is the Godot leg of that
comparison, and it is a **port** rather than an adoption for one reason:
`gdextension/corebridge/js/host-crypto.js` makes `createHash` throw on purpose
and core's replay module hashes. The fix that file names for a slice that DOES
need hashing is "route it to libinsimul/the C host rather than grow a second
SHA-256 here" — and the C host hash already exists and is already the pinned one.

The evidence that the port agrees is core's own answers.
`tools/vendor-replay-fixtures.mjs` bundles `packages/core/src/replay/index.ts`
under Node (where `node:crypto` works), runs it, and writes down every answer it
gave into `gdextension/test/fixtures/replay/`:

| part | what runs | count |
| --- | --- | --- |
| the addresses | the world-content digest core minted, for two worlds that differ by one authored fact | 2 |
| entropy | `replayEntropy(seed)` and `replayEntropy(seed, tick)` for 24 ticks across 2 seeds — FNV-1a over UTF-16 code units, not bytes | 1 |
| traces | 12 documents core read: 2 admitted with the id it minted, 10 refused with its own code — an action-layer key, an action id spelled as a signal, a payload on the wrong channel, ticks going backwards, an edited input with a stale id, the wrong world, a moved world | 3 |
| outcomes | 7 documents core validated, including a digest that does not describe its own facts and a fact arg that is not a string or a finite number | 2 |
| comparisons | 6 verdicts, kind for kind: converged, reordered (clause order is solution order), a localized checkpoint divergence, a truncated leg, two different sessions, differing counts | 2 |
| runs | 4 whole replays compared step for step — the bucketing of inputs onto ticks, the ticks that carry NO input, the per-tick `uint32` — and then digest for digest against the KB core's own driver produced | 3 |
| the control | the same run with every input applied ONE TICK LATE must diverge, and `compare()` must say so | 1 |
| refusals and tokens | an unconfigured leg refuses rather than reading a trace loosely; an outcome of another session is refused, not compared; every token the leg can emit is published in the contract | 6 |

The corpus is two-sided by construction (3 admitted, 16 refused) and floored per
area, so an upstream corpus that lost its refusal cases fails rather than
shrinking quietly.

**Proven to fail**, twice, by sabotage on a scratch copy:

| sabotage | result |
| --- | --- |
| the driver skips ticks that carry no input | ❌ 2 failures — the step plan and the KB digest |
| `streamKey` counts bytes instead of UTF-16 code units | ❌ 3 failures — entropy, the step plan, the KB digest |

The world both sides drive is DATA — `fixtures/replay/program.json`, a table of
signal → fact plus an idle rule keyed on the tick's entropy. Two hand-written toy
worlds would be two implementations to disagree, and their disagreement would be
indistinguishable from the driver bug this corpus exists to measure.

## Needs a `godot` binary + Talos — human end-to-end checklist

The half no host gate reaches: whether the Bridge actually FINDS the adapter.

- [ ] With `addons/insimul_talos/` enabled and its `talos.game.yaml` fragment
      merged, a Talos session's `save_checkpoint` finds the hook rather than
      refusing with `no_checkpoint_hooks`.
- [ ] With the fragment **not** merged, it refuses with `no_checkpoint_hooks` and
      the "would report success both times" message — the loud failure §7.4 says
      a mis-installed adapter must produce.
- [ ] Before `attach_world()`, `talos_ready_state()` is false and a `query_state`
      answer carries the `insimul_kb_uninitialized` envelope rather than an empty
      digest.
- [ ] `InsimulTalos.hello_decision()` refuses on today's published matrix with
      `insimul_engine_version_declared`, and the refusal reaches the run as an
      `assert_failed` telemetry event.
- [ ] With `input-vocabulary.json` deleted from the installed addon,
      `InsimulTalos.install_diagnosis` names `insimul_bridge_vocabulary_absent`,
      the node still joins its six groups, and the editor shows the pushed error.
- [ ] `InsimulTalos.replay_input_trace()` over a real world, driven through a
      game-supplied replay world, produces an `insimul-replay-outcome-v1`
      document whose digest a Babylon leg can diff.

## Status on this machine (talos-bridge)

| gate | result |
| --- | --- |
| `npm run test:talos-bridge` | ✅ **73 checks, 0 failures** — 21 reference cases replayed, 3 controls, 7 install modes |
| `npm run test:replay` | ✅ **20 checks, 0 failures** — 29 case files minted from core, 1 mis-ticked control |
| `npm run check` | ✅ 188 `.gd` files; check-bridge 21 checks + 14 negative controls |
| `vendor-supported-versions --check` | ✅ 3 engine rows, 42 why-not tokens, 21 reference cases |
| `vendor-replay-fixtures --check` | ✅ 12 trace / 7 outcome / 6 comparison / 4 run cases, 133 action ids |
| the human end-to-end checklist | ⬜ needs a `godot` binary, a built extension and Talos |

---

# Default UI in this repo (tasklist 192)

The standalone Godot repo's own default-UI legs. The `US-GU*` sections above are
the pre-standalone record and describe a `packages/` layout this repo no longer
has; what follows is what runs here.

## Runs on any box — no Godot binary, no libinsimul

```sh
npm run check               # includes tools/verify-ui/check-ui.mjs --self-test
```

`check-ui.mjs` is the whole data side of the panel registry, and every one of its
checks has a negative control:

| check | claim |
| --- | --- |
| 1 | the PINNED panel set equals `conformance/ui/registry-cases.json -> panel_keys`, both ways |
| 1b | every ahead-of-corpus entry (`pending_corpus`) says what it waits for, is not already in the corpus, and — when it gates on nothing — carries a `gate_note` |
| 1c | a composite's `children` are panels the manifest has and never itself; its script names no panel key |
| 2 | every panel's scene, and every resource that scene loads, is a real file |
| 3 | every `requires` id is in the band-111 activation table AND some genre bundle activates it |
| 4 | `insimul_ui_registry.gd` names no panel key and no module id |
| 5 | `insimul_ui_tokens.gd` mirrors `conformance/ui/theme-tokens.json`, both ways |
| 6 | nothing under `addons/insimul/ui/` names `InsimulCore` |

## Needs a `godot` binary (this box has one)

```sh
npm run test:ui              # addons/insimul/tests/run_ui_registry_headless.sh
npm run test:ui-quest-trade  # addons/insimul/tests/run_quest_trade_headless.sh
```

Both stage **only** `addons/insimul/ui/` plus the one test into a throwaway
project, run `--import` first (without it Godot registers no global `class_name`,
every script fails to parse, and `godot -s` still exits 0), and then fail on any
`SCRIPT ERROR` in the log as well as on a non-clean pass line. Both SKIP with exit
0 when no `godot` binary is on PATH.

`test:ui` covers the shared registry + loading-phase + theme cases, the shipped
manifest, the creator override through a project setting, the module gate across
every genre bundle, **every shipped panel instantiating and reaching `_ready()`
inside a real tree**, and the composite HUD mounting exactly the children the
world's modules allow.

`test:ui-quest-trade` runs the shared quest + trade matrices
(`conformance/ui/{quest-journal-cases,trade-cases}.json`) against
`InsimulQuestJournalModel` / `InsimulTradeModel`, the state-location invariant,
the real-quest-system binding (a `quest_offered` radiant arrival reaching the
journal as available), and the view-models behind the ahead-of-corpus panels
(map projection, skill-tree unlock rules, document pagination, radial selection,
quickbar slots, notice board).

## Needs a `godot` binary + a game — human end-to-end checklist

- [ ] **Quest journal + tracker** — open `quest_journal`, switch tabs and confirm
      the list partitions by status; track up to `max_tracked` active quests and
      confirm `quest_tracker` mirrors them **without a manual refresh**; complete a
      quest and confirm it drops off the tracker and lands under Completed.
- [ ] **Radiant offer** — run a radiant tick and confirm the arrival appears under
      Available with the quest system's own title, and that `quest_offer` Accept
      moves it to Active while Decline removes it.
- [ ] **Trade against a live save** — loot a container into the inventory with both
      panels open and confirm the inventory redraws itself; buy and sell at a
      merchant and confirm gold + stock update on BOTH sides; reload the save and
      confirm the same numbers come back (there is no store but `currentState`).
- [ ] **The module gate, visibly** — run an `educational` world and confirm the HUD
      comes up with no minimap and no quickbar and the menus offer no skill tree,
      no merchant and no container, while the notice board and the document reader
      are still there; run an `rpg` world and confirm all of them appear.
- [ ] **A creator override** — point `insimul/ui/panel_overrides` at a replacement
      `quest_journal` scene and confirm it is what opens, with no engine code
      changed.

## Status on this machine (default UI)

| gate | result |
| --- | --- |
| `npm run check` | ✅ 198 `.gd` files; check-ui **281 checks, 0 failures** (17 negative controls) |
| `npm run test:ui` | ✅ **637 checks, 0 failures** (godot 4.6) |
| `npm run test:ui-quest-trade` | ✅ **172 checks, 0 failures** (godot 4.6) |
| the human checklist above | ⬜ needs a game project — reviewed at merge |
