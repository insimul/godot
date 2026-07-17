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
