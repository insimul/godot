# Migrating the Godot template off the fake Prolog engine (US-GP3)

The exported-game template used to ship a **fake, substring-matching** Prolog
"engine" in `templates/scripts/systems/prolog_engine.gd` (~1.3k LOC). It never
performed unification: a goal was considered "true" if its text happened to
appear somewhere in the knowledge-base string, and dynamic facts lived in an
in-memory `Array[String]` scanned by prefix. This document records what changed
when that stub was replaced by the native **`InsimulProlog`** GDExtension
(`packages/godot/gdextension`), which wraps libinsimul's real Prolog runtime.

## The honest orphan note (read this first)

`prolog_engine.gd` is **not wired into the shipped template**. It is:

- **Not** an autoload (`templates/project/project.godot` `[autoload]` lists
  `EventBus`, `QuestSystem`, `RuleEnforcer`, … but **not** `PrologEngine`).
- **Not** `preload`/`load`/`.new()`-ed by any other script
  (`grep -rn "prolog_engine\|PrologEngine" templates` matches only the file
  itself). `quest_system.gd` — named in the PRD as a caller — contains **zero**
  Prolog references.

So the file mirrors the Babylon.js `GamePrologEngine.ts` surface for cross-engine
parity and future wiring, but migrating it changes no *live* behaviour today. It
was still rewritten (not left as a fake) so that when the template does wire it
up, it gets real logic — and so the three engine legs stay honest mirrors of one
another. The **one genuinely-wired substring consumer**, `rule_enforcer.gd`, is
migrated for real (see below).

## `prolog_engine.gd` — fake substring KB → native adapter

The file is now a **thin adapter** over `InsimulProlog`. The public method surface
is preserved (every `func` name/signature is unchanged) so existing/future callers
keep compiling; the internals changed as follows.

| Concern | Before (fake) | After (native) |
|---|---|---|
| Fact store | `_facts: Array[String]` + `_kb_content: String` | libinsimul KB via `InsimulProlog` |
| Assert | append to `_facts` | `assert_fact("<term>.")` |
| Retract by pattern | prefix-scan + `Array.erase` | `retract_fact` looped over a term with `_` wildcards |
| Query | `_has_fact()` / `_kb_content.contains()` | `query(goal)` — real resolution; `.size() > 0` = provable |
| Enumerate (e.g. topics, volition) | prefix-scan + `substr` string parsing | `query("pred(x, Var)")` and read `Var` bindings |
| Save/load | `_facts` array only | `save_snapshot()`/`restore_snapshot()` (canonical Prolog text) **plus** the retained `get_player_facts()`/`restore_player_facts()` array bridge |
| Program load | string concatenation into `_kb_content` | `consult(program)` in `initialize()` / `load_*_rules()` |

**Behaviour change per call site.** Every predicate that used to "match" now has to
be **provable**:

- `is_quest_complete`, `is_quest_available`, `is_stage_complete`,
  `can_perform_action`, `should_mention_weather`, `get_player_attitude`,
  `wants_to_socialize`, `is_grieving`, `is_willing_to_share`,
  `can_perform_romance_action`, `evaluate_condition` — were substring/`_has_fact`
  boolean lookups; now each runs a real goal. Rules in the KB (`:-` clauses) now
  **fire**, so e.g. an `item_is_a/2` chain or `cefr_gte/2` comparison resolves
  instead of only matching literally-asserted ground facts.
- `get_applicable_rules`, `who_should_talk_to`, `get_preferred_topics`,
  `get_conflict_style`, `who_to_avoid`, `get_romance_stage`,
  `evaluate_volition_rules`, `get_bonus_rewards`, objective enumeration in
  `reconcile`/`_check_objective_completion` — were brittle `substr`/`split` string
  parses of fact text; now they bind a query variable and read the decoded term
  (atom→`String`, int→`int`, …), which is both correct and far less fragile.
- `query(goal)` — return shape changed. The fake returned an ad-hoc
  `[{result:true, goal:...}]`; it now returns the real
  `Array[Dictionary]` of variable bindings (one Dictionary per solution, `[]` on
  failure, `[{}]` on success-with-no-bindings) — the documented `InsimulProlog`
  contract.
- `export_knowledge_base()` now returns the native `snapshot()` (dynamic facts
  only) rather than the whole KB string; it stays `@deprecated`.

**Graceful degradation.** When the GDExtension is not loaded (editor without the
built binary, or a plain parse), `_native_available` is `false`: the adapter
skips native calls and returns each method's safe permissive default (actions
allowed, quests available, completions `false`, enumerations empty). The game
keeps running, just without logic-driven gating. Detection is string-based
(`ClassDB.class_exists("InsimulProlog")` / `ClassDB.instantiate(...)`), the same
pattern as `smoke/test_smoke.gd`, so the script still parses with no extension
present.

## `rule_enforcer.gd` — 3 substring checks → native queries (with a bug fix)

`_check_quest_complete_condition`, `_check_quest_available_condition`, and
`_check_cefr_level_condition` used `_prolog_content.contains(pattern)` where the
pattern quoted the raw id, e.g.:

```gdscript
var pattern := 'quest_complete(player, "%s")' % quest_id   # quoted STRING id
return _prolog_content.contains(pattern)
```

**Latent bug fixed here:** the generated KB stores quests as *sanitized atoms*
(`ir-generator` `sanitizeAtom`, e.g. `find_the_sword`), never as quoted strings
(`"Find the Sword"`). The old substring pattern therefore **never matched** a real
KB — the check silently returned `false` for every quest. The migrated code
consults the KB into a native `InsimulProlog` in `set_prolog_knowledge_base()` and
queries the **atom** form:

```gdscript
return _prove_or_scan(
    "quest_complete(player, %s)" % sanitize_to_atom(quest_id),   # atom, real query
    'quest_complete(player, "%s")' % quest_id)                   # legacy fallback
```

`_prove_or_scan` runs the native query when the extension is available, else falls
back to the original substring scan (so the export still runs without the binary,
preserving the *old* — buggy — behaviour only in that degraded path).

## Files with a Prolog *mention* but no behaviour change

- `data_loader.gd` — `load_prolog_knowledge_base()` / `load_prolog_content()` just
  read the exported `.pl` text off disk; untouched.
- `event_bus.gd` — a single doc-comment references Prolog fact assertion; no code
  change.

## What is verified, and where

See `VERIFICATION.md`. On a box with **no** Godot toolchain (the Ralph harness),
the migration is gated by the host C++ marshalling + conformance harnesses and the
**structural GDScript lint** (`gdextension/tests/gdscript_structural_lint.py`, the
`godot --check-only` stand-in), all wired into `npm run engines:check`. Real
end-to-end proof (types, name resolution, runtime) requires a `godot` binary and
the built extension — `autoMerge` is off so a human runs that at review.

---

# Godot runtime core — portable cross-runtime parity (US-GC1..GC4)

A separate migration from the native-Prolog work above: the Godot SDK is growing
a **portable runtime core** (`addons/insimul/runtime/` + the host-tested
`gdextension/src/` cores) that mirrors the Unreal `FInsimul*` / Unity legs
byte-for-byte against the shared golden fixtures. Babylon (`packages/core`,
TypeScript) is the semantics authority; the same corpora
(`packages/core/conformance/{saves,quests,prolog,radiant}`) pin every runtime.

The pattern each story followed: put the exactness (canonical save, migration,
quest hydration, radiant facts, the full-loop orchestration) in a **dependency-free
C++ core** that host-tests under `clang++` (no godot-cpp/libinsimul), wrap it in a
**syntax-gated godot-cpp class**, and expose a **GDScript runtime surface** that
owns the Godot-specific I/O + signals. All additive — the legacy template
prototypes stay in place until US-GC4 re-points startup.

## US-GC1 — World source on generated DTOs

`addons/insimul/runtime/world_source.gd` (`InsimulWorldSource`) loads a SaveFile's
embedded `worldSnapshot` (or a bare WorldIR) through the generated DTO classes,
gates on the save-format schema version (`[1, SAVE_FILE_VERSION]`), and exposes
typed accessors + entity counts. Replaces ad-hoc `world_export.json` reads for the
covered world shapes; the conversation-oriented export path
(`insimul_world_export.gd`) is untouched.

## US-GC2 — Portable save system

`addons/insimul/runtime/save_system.gd` (`InsimulSaveSystem`) owns slot I/O on
`user://` and the envelope read/verify/write flow. The exactness — canonical
key-sorted JSON + SHA-256 **byte-identical to `save-envelope.ts`** — lives in the
`InsimulSaveCodec` GDExtension (`gdextension/src/{json_value,sha256,canonical_json,
save_file}.cpp`). Version-gated v1→v3 migration, KB snapshot/restore into
`currentState.prologFacts`. The portability proof: a Godot-produced envelope
validates against `save-file.schema.json` via the TS cross-check
(`packages/core/src/conformance/__tests__/save-integrity-crosscheck-godot.test.ts`),
and its integrity hash is byte-identical to Unreal's for the same fixture.

## US-GC3 — Quest system + radiant tick

`addons/insimul/runtime/quest_system.gd` (`InsimulQuestSystem`) drives quest
hydration, query-driven completion with fact-asserting transitions, and the
deterministic radiant tick — all delegated to the `InsimulQuestCore` GDExtension
(`gdextension/src/quest_system.cpp`, validated against
`conformance/quests/{hydration,radiant}-cases.json`). Signals
(`quest_completed` / `objective_completed` / `quest_offered`) are preserved for UI.
`attach_kb()` mirrors assertions into a live `InsimulProlog` engine for real
queries.

## US-GC4 — Template bootstrap integration + human checklist

### What changed

- **New host-tested core:** `gdextension/src/bootstrap.{h,cpp}` (`RuntimeContext`)
  — the **startup orchestrator**. It ties the US-GC1..GC3 cores into the single
  template-startup loop — **world source → save slot → KB → systems init** — with
  entry points: `boot()` (resume a valid save slot, else new game from the world
  snapshot; a corrupt slot falls back to a new game rather than bricking startup),
  `start_new_game()` / `load_from_save()`, `commit_to_save()` (snapshot the live KB
  into `currentState.prologFacts`), and `evaluate_all_quests()` /
  `run_radiant_tick()` (drive the quest + radiant transitions).
  `world_snapshot_integrity()` exposes the world-hash-stability check. It counts
  the world's entities directly off the loaded SaveFile's embedded `worldSnapshot`
  (the Godot world source is GDScript over the generated DTOs, so this core does
  not embed a C++ world source). Twin of Unreal `FInsimulRuntimeContext`.
- **New godot-cpp shim:** `gdextension/src/insimul_runtime_core.{h,cpp}`
  (`InsimulRuntimeCore`, RefCounted) — wraps `RuntimeContext` for GDScript.
  Registered in `register_types.cpp`. Named `InsimulRuntimeCore` (not
  `InsimulRuntime`) to leave that `class_name` free for the GDScript runtime
  (mirrors the `InsimulSaveCodec`/`InsimulSaveSystem` and
  `InsimulQuestCore`/`InsimulQuestSystem` splits). **Syntax-gated** (needs
  godot-cpp), so its real gate is the host test.
- **New worldSnapshot-only integrity:** `SaveSystem::world_snapshot_integrity()`
  (host-tested) hashes the `worldSnapshot` sub-object alone; exposed through
  `InsimulSaveCodec` so GDScript can assert the world hash is stable across a
  `currentState`-only commit + save/reload.
- **New GDScript runtime:** `addons/insimul/runtime/runtime_bootstrap.gd`
  (`InsimulRuntime`) — the runtime facade that composes `InsimulWorldSource` +
  `InsimulSaveSystem` + `InsimulQuestSystem` (+ an optional live `InsimulProlog`)
  into the boot loop, re-broadcasts the quest signals, and owns slot save/resume.
  Twin of Unreal `UInsimulRuntimeSubsystem`.
- **Re-pointed template startup (additive, guarded):**
  - `core/game_manager.gd` — `_boot_insimul_runtime()` boots `InsimulRuntime` from
    a portable `res://data/world_snapshot.json` export when the addon + the
    GDExtension are present, and exposes `get_world_source()`. When either is
    absent (the default template state) the legacy DataLoader/SaveSystem/QuestSystem
    autoloads drive startup **unchanged**.
  - `characters/npc_spawner.gd` — `_resolve_npc_list()` prefers the booted world
    source as the authoritative source of character **identity** (id + role), and
    overlays positional/schedule data from a matching legacy entry; falls back to
    the legacy `entities.npcs` export when no world source is booted. Mirrors the
    Unreal `AInsimulSpawner::PopulateSpawnDataFromWorldSource` re-point.

### The full loop is host-tested

`gdextension/test/test_bootstrap.cpp` (the `run_bootstrap_tests.sh` gate,
**42 checks**, wired into `npm run engines:check`) drives the whole loop in the
portable core: boot-resume the golden save (entity counts match the cross-runtime
parity numbers), new-game + corrupt-save fallback, and the full **radiant →
objective → save → reload** sequence with quest + radiant facts round-tripping and
the `worldSnapshot` hash stable throughout. The human pass
([VERIFICATION.md](./VERIFICATION.md#godot-runtime-core-full-loop-us-gc4)) confirms
the same loop in a live Godot build.

### Startup-path deprecation (legacy template systems)

The template's `systems/{save_system,quest_system}.gd` prototypes and the
per-entity `core/data_loader.gd` reads are superseded by the portable runtime for
the covered shapes once a worldSnapshot export is present:

| Old (template prototype)                         | New (portable runtime)                              |
| ------------------------------------------------ | --------------------------------------------------- |
| Hardcoded / legacy `entities.npcs` character ids | `GameManager.get_world_source().characters()`       |
| `systems/save_system.gd` ad-hoc slot JSON        | `InsimulSaveSystem` canonical envelope + integrity  |
| `systems/quest_system.gd` ad-hoc KB              | `InsimulQuestSystem` hydration + KB transitions     |
| Ad-hoc "new game vs load" startup branching      | `InsimulRuntime.boot()` (resume-or-new, corrupt-safe) |

**Compatibility path retained.** The template prototypes are NOT removed; the
legacy startup path runs whenever the addon, the GDExtension, or the portable
worldSnapshot export is absent. Deliberate deltas vs the Babylon/Unity/Unreal
reference (**target zero**) are documented in
[VERIFICATION.md §deltas](./VERIFICATION.md#deliberate-deltas-runtime-core-target-zero).
