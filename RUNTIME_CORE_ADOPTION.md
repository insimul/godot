# Adopting `@insimul/core` in the Godot plugin — the adoption plan (US-1 of 100)

> **US-2 has landed, and the plan held.** `libinsimulcore` exists
> (`gdextension/corebridge/`), and all **11** radiant conformance vectors pass
> through core's real TypeScript running in an embedded QuickJS on the natively
> linked Trealla — `npm run test:radiant`. The language boundary of §4 is no
> longer a proposal. Two things the plan did not predict were found by being the
> first code to actually *link* libinsimul: §6.6 (the vendored ABI header was
> wrong, and the Prolog wrapper inverted every result because of it) and §6.7 (a
> libinsimul KB-lifecycle crash). §6.4's three broken gates are fixed and green.

**Status: design document. No code changes accompany it.** It reads
`packages/core/docs/runtime-contract.md` (US-4 of `93-runtime-logic-to-core`) and
turns it into a concrete plan for *this* repo — its GDScript classes, its
GDExtension C++ core, its libinsimul link, and its vendored conformance corpus.

This is the **first** native adapter designed against that contract. Its §5.5
says so explicitly: *"No native adapter has been built against this contract yet.
Every interface here is derived from exactly one implementation — Babylon's."*
So this document also answers the one question the contract left open and that
`98-unity`, `99-unreal` and `101-babylon-editor-core` are parked waiting for —
**the language boundary** (§4). That answer is meant to be copied, not
re-derived; Appendix A is the drop-in text for `docs/UNIFICATION_ROADMAP.md`
Decision 1.

**Verdict up front:** adopt, but only through a bridge that does not yet exist,
and only for the decision layer. The first slice is **radiant quest generation**
(§5). The recommended boundary is **one C ABI — `libinsimulcore` — shaped exactly
like `libinsimul`'s**, with TypeScript running behind it inside an embedded JS
engine today and Rust behind the *same* ABI later (§4). §7 lists what we should
*not* adopt, and §6 lists seven things this repo believes about itself that turned
out to be false.

---

## 0. Where this engine actually stands

Before mapping anything, the starting position — measured, because the numbers
this tasklist was written against are wrong (§6.1).

| surface | files | lines | what it is |
| --- | --- | --- | --- |
| `addons/insimul/**` (SDK) | 77 `.gd` | 10,690 | the plugin: runtime (5/1,172), default UI (21/2,205), editor docks, generated DTOs, headless tests (9/1,601) |
| `templates/scripts/**` (game template) | 93 `.gd` | 24,875 | the exported-game template: 26 systems (7,825), 26 world scripts (8,210), 21 UI (5,476), 15 character (1,965) |
| `gdextension/src/**` | 30 `.cpp`/`.h` | 5,196 | the portable C++ core + the Godot-facing GDExtension classes |
| `gdextension/test/**` | 7 `.cpp` + 8 `.sh` | — | plain-`clang++` host gates that need no Godot toolchain |
| `conformance/**` | 31 JSON | — | the vendored cross-engine corpus |

Three of those matter to this plan:

- **`gdextension/src/` is already a runtime core** — dependency-free C++ that
  hand-ports core's semantics (`quest_system.cpp` 649, `save_file.cpp` 390,
  `json_value.cpp` 401, `prolog_value.cpp` 469, `bootstrap.cpp` 200) and is pinned
  to the TypeScript authority by the shared corpus. This is a **fourth answer to
  the language boundary that the roadmap does not list, and it is already
  shipping.** §4.4 says why it cannot be the strategy.
- **libinsimul is already linked** through `InsimulProlog`
  (`gdextension/src/insimul_prolog.cpp` → `vendor/insimul/insimul.h`). Its C ABI is
  the precedent §4 builds on: **this repo has consumed a shared native core across
  the language boundary before, and it worked.**
- **`conformance/` is vendored, not referenced** — this repo is standalone
  (commit `4c1a0f7`), so it holds its own copy of core's corpus. That copy has
  drifted (§6.3).

---

## 1. The contract, in this engine's terms

The contract has three halves. Restated against the classes in this repo rather
than abstractly.

### 1.1 `system-contracts.ts` — nine interfaces the engine implements and owns

Core declares them; each engine ports its own. The contract even names our
filenames (`ICombatSystem` → `combat_system.gd`). These are **not** things we
adopt — they stay ours. §3 is where they get compared against core's modules.

### 1.2 `host-contracts.ts` — five hooks core calls back into us

`EngineHostAdapter` = `{ debug?, lifecycle?, speech?, resources?, combatStats? }`.
Every field is optional and degrades to a documented fallback, so an adapter can
come up in stages. The contract already guesses our implementations
(`print_debug`, `NOTIFICATION_WM_CLOSE_REQUEST`, `DisplayServer.tts_speak`,
`combat_system.gd`'s entity dictionary). §2 checks those guesses against what is
actually here.

### 1.3 `data-source.ts` — `IDataSource`, the one required interface

~90 `Promise`-returning methods covering world/character/quest/settlement
loading, playthroughs, inventories, containers and game-state save/load. In this
repo that surface is spread across five classes and does not look like
`IDataSource` at all:

| `IDataSource` area | this engine today |
| --- | --- |
| `loadWorld` / `loadCharacters` / `loadSettlements` / `loadQuests` | `InsimulWorldSource` (`runtime/world_source.gd`) — reads a `SaveFile.worldSnapshot` through the **generated** DTOs (`addons/insimul/generated/InsimulSaveFile.gd`), version-gated to save schema 1–3 |
| content packs (items/characters/towns/quests/narratives) | `InsimulContentLibrary` (`runtime/content_library.gd`) — a *different*, engine-neutral library format, schema-gated 1–1 |
| `saveGameState` / `loadGameState` | `InsimulSaveSystem` (`runtime/save_system.gd`) over `InsimulSaveCodec` (C++), canonical JSON + SHA-256 integrity envelope, `user://saves/` |
| `loadPrologContent` | `InsimulProlog.consult()` — libinsimul, not a fetch |
| everything network-shaped (playthroughs, dynamic quests, merchant inventories, NPC guidance) | `InsimulHttpClient` / `InsimulClient` — the authoring-server path, **only** used by the editor docks and the conversation SDK, not by an exported game |

**The structural mismatch that matters:** `IDataSource` is `async` end to end
because it was derived from a browser client talking to an authoring server. An
exported Godot game has no server; its world is a file that is already on disk,
and its persistence is synchronous. Adopting `IDataSource` verbatim would mean
wrapping synchronous file reads in promises so that a JS runtime can await them —
and then pumping that runtime's job queue from `_process`. That is real work and
it is the largest single cost item in §4.

**This is a contract revision, not an adapter contortion** (§5.5 invites it):
`IDataSource` should be split into the ~20 methods an exported game needs
(load-only, sync-satisfiable) and the ~70 authoring/session methods only the
platform client calls. Recorded in §8 as the first proposed amendment.

### 1.4 The lifecycle, in Godot terms

Core assumes a host that constructs a game object, drives it, and tears it down.
This repo's equivalent already exists and is corpus-pinned:
`InsimulRuntimeCore::boot()` (`insimul_runtime_core.h`) — world source → save
slot → KB → systems, exposed to GDScript as `InsimulRuntime.boot()` in
`runtime/runtime_bootstrap.gd`, with `run_radiant_tick()`, `evaluate_all_quests()`,
`commit_to_save()`, `serialize_canonical()`. **Any core adoption must enter
through `boot()`**, not alongside it, or the world hash stability that
`test_bootstrap.cpp` asserts (42 checks) stops meaning anything.

---

## 2. Host-capability map — have / must write / no counterpart

The third column is the interesting one and is listed explicitly, as the story
asks.

### 2.1 Already have it — the adapter is a wrapper

| core hook | what this engine already has | gap |
| --- | --- | --- |
| `IHostLifecycle` | `NOTIFICATION_WM_CLOSE_REQUEST` via `Node._notification`; already used in `templates/scripts/ui/hud.gd` and elsewhere | none. ~20 lines. The contract's guess was right. |
| `IDebugSink` | `print_debug` plus `InsimulNotifications` (`ui/insimul_notifications.gd`) and the template's `error_reporter.gd` (82) | none of substance. `DebugSinkEvent`'s six fields (`timestamp`/`category`/`level`/`tag`/`summary`/`detail`/`source`) map to a Dictionary. ~40 lines. |
| persistence (`IDataSource`'s save half) | `InsimulSaveSystem` + `InsimulSaveCodec`: canonical JSON, SHA-256 integrity, v1→v3 migration, KB round-trip — **already byte-pinned against the TS authority** (`tools/cross-check/cpp-produced.envelope.json`) | none. This is the strongest thing in the repo. Do not replace it (§7). |
| world/content loading (`IDataSource`'s load half) | `InsimulWorldSource` + `InsimulContentLibrary`, both DTO-typed and version-gated | shape only — sync vs `Promise`. See §1.3. |
| Prolog | `InsimulProlog` → libinsimul/Trealla, the *same engine source* core's browser runtime now runs (contract §5, blocker 1 RESOLVED) | none. This is why Godot was chosen to go first. |

### 2.2 Must be written, but the pieces exist

| core hook | what exists | what must be written |
| --- | --- | --- |
| `ISpeechSynthesizer` | `InsimulAudioPlayer`, `InsimulLipSync`, `InsimulMicrophone`, `InsimulLocalProvider` — the conversation SDK's audio path, which plays **server-supplied** audio | a synthesis source. `DisplayServer.tts_speak` exists on desktop but is a *speaker*, not a byte producer — it cannot return `SynthesizedSpeech.audio`. Either return a `uri` handle and play it host-side (a contract-friendly reading), or add a TTS backend. **Returning `null` is a documented, normal outcome**, so this can ship as a stub. Est. 80 lines for the `uri` reading. |
| `IResourceStore` | `templates/scripts/systems/resource_system.gd` (363) — but it is a *world-node harvesting* system (spawn nodes, gather with a tool, deplete, respawn). It has no `hasResources` / `consumeResources`. | the two-method affordance query over the player's inventory. `inventory_system.gd` (292) holds the counts. Est. 60 lines of glue; the `ResourceType` union must be mapped to this engine's resource-type strings. |

### 2.3 **No counterpart — the honest list**

These are the ones with nothing behind them in this repo.

1. **`ICombatStatSink` — nothing to sink into.** The contract guesses
   "`combat_system.gd`'s entity dictionary". `templates/scripts/systems/combat_system.gd`
   is **38 lines**: `load_from_data`, `calculate_damage`, `can_attack`,
   `register_attack`. There is no entity registry, no `attackPower`/`defense`/
   `dodgeChance`, no equipment. (`fighting_combat_system.gd` 165,
   `ranged_combat_system.gd` 240 and `turn_based_combat_system.gd` 335 are three
   separate, unreconciled combat implementations, none of which owns stats
   either.) `EquipmentManager` — the only core-side consumer — is one of the
   **seven un-inverted modules** anyway, so this hook has no caller today.
   **Implication: stub it, and do not let the stub imply combat is wired.**
2. **The whole language-acquisition stack has no host.** Core's §1.2 is 13
   modules / 3,057 lines and the contract calls it *"the product, not a
   subsystem"*. This engine has `vocabulary_panel.gd` (a panel) and the
   conversation SDK (a transport). There is no vocabulary state, no CEFR
   tracking, no pronunciation scoring, no learning drills. `LanguageProgressTracker`
   (1,313) and `AssessmentEngine` (1,042) are **both un-inverted**, so this is not
   adoptable yet regardless — but when it is, it needs a host that does not exist.
3. **`GameTruthSync` (926) has no counterpart and no obvious home.** It is what
   keeps the Prolog KB and the live world in agreement. This engine keeps
   `currentState.prologFacts` as an `Array[Dictionary]` mirrored into
   `InsimulProlog` by hand (`quest_system.gd::assert_fact` →
   `_fact_to_prolog_text`). That mirror is *not* a truth sync: it is one-way,
   append-only, and has no reconciliation. The contract flags this module
   specifically — *"without it an engine has a KB and a world that drift."*
4. **Social simulation (§1.4, 7 modules / 2,207) has no counterpart.** Volition,
   relationships, romance, residence/business behaviour, cultural events.
   `templates/scripts/systems/npc_business_interaction_system.gd` (128) and
   `reputation_manager.gd` (90) are the nearest things and are not the same
   shape. `AmbientLifeBehaviorSystem` is un-inverted, so `NpcPersonalityTraits`
   currently has no consumer either.
5. **No host for `async`.** Godot has `await` on signals, and GDScript is
   single-threaded on the main loop. Core is `Promise`-based throughout
   (`IDataSource`, `ISpeechSynthesizer`, `generateRadiantQuests` is itself
   `async`). Nothing in this repo pumps a job queue. **This is not a missing
   *capability* — it is a missing *mechanism*, and it is §4's problem, not §2's.**
   It is listed here because it is the reason the first slice is chosen the way
   it is.

---

## 3. Systems this engine implements that core also implements

The contract's §4.1 is the honest framing and it holds here: our ports are
**execution surfaces**; core is the **decision layer** behind them. So most rows
below are *neither* "adopt core's" *nor* "keep ours" — they are "keep ours, put
core's behind it", which is the shape `InsimulQuestSystem` (GDScript) →
`InsimulQuestCore` (C++) already has.

| area | this engine | core | recommendation |
| --- | --- | --- | --- |
| **Quests — hydration + radiant tick + completion** | `InsimulQuestSystem` (258 gd) → `InsimulQuestCore` → `quest_system.cpp` (649 C++), corpus-pinned to `quest-hydrator.ts` | `QuestCompletionEngine` (1,897) + 15 more (6,312 total) | **Reconcile, later.** Ours is a hand-port of a *slice* of core's, already proven equal on the vectors it covers. Replacing it is a like-for-like swap with no capability gain and high churn. **But it is the ideal diff instrument** — see §5.3. |
| **Quests — the template's tracker** | `templates/scripts/systems/quest_system.gd` (1,324) — an objective-tracking state machine with ~40 `track_*` methods (conversation turns, pronunciation attempts, romance stages, item delivery) | `QuestCompletionEngine`'s Prolog-backed objective evaluation | **Adopt core's, eventually — and this is a BEHAVIOURAL change.** Ours decides completion by imperative bookkeeping; core's decides it by proving a goal. The set of things that complete a quest is not the same set. Silently switching this changes shipped games. Not in this tasklist. |
| **Prolog** | `InsimulProlog` (libinsimul) — real unification | core's `src/prolog/` toolchain over the same libinsimul/Trealla source, wasm-compiled | **Already adopted.** Blocker 1 is resolved; both sides run the same engine source. Nothing to do. |
| **Prolog (template)** | `templates/scripts/systems/prolog_engine.gd` (1,295) — rewritten off the substring fake onto `InsimulProlog` (see `MIGRATION.md`), and **still an orphan**: not an autoload, not `preload`ed by anything | `GamePrologEngine` (2,267) — **un-inverted**, still in `packages/babylon` | **Keep ours.** Core's is not available. Ours is a mirror with no live callers; MIGRATION.md is honest about that. |
| **Save / persistence** | `InsimulSaveSystem` + `InsimulSaveCodec` + `save_file.cpp` (390), canonical JSON + SHA-256, v1→v3 migration, **byte-matched against a TS-produced golden envelope** | the save-file format + migrations (contract layer), `SaveConflictResolver` (377) | **Keep ours.** It is byte-identical to the authority already — adopting core's would be strictly worse (a bridge crossing where there is now a proof). `SaveConflictResolver` has no counterpart and is a future addition, not a replacement. |
| **Crafting** | `templates/scripts/systems/crafting_system.gd` — **29 lines** | `RecipeCraftingSystem` (665) + farming (534) + herbalism (534) + mining (384) + fishing (340) | **Adopt core's.** Pure capability gain; there is effectively nothing to reconcile. Blocked only on §4. (Note core's `CraftingSystem`, 521, is un-inverted — but `RecipeCraftingSystem` is not, and it is the one that matters.) |
| **Inventory / containers** | `inventory_system.gd` (292) + the UI trade/container models (`ui/trade_model.gd` 198, corpus-pinned) | `ContainerManager` (151) | **Keep ours.** Ours is larger than core's and already pinned by `conformance/ui/trade-cases.json`. No gain. |
| **Resources** | `resource_system.gd` (363) — world nodes, gathering, respawn | the four gathering systems (1,792) | **Reconcile.** Ours is the *spatial/interaction* half; core's is the *yield/table* half. They compose rather than compete: ours becomes `IResourceStore`'s backing (§2.2). |
| **Dialogue** | `dialogue_system.gd` (177) + `ui/chat_model.gd` (corpus-pinned by `chat-cases.json`) + the conversation SDK | §1.2's 13 modules (3,057) | **Adopt core's, eventually.** Ours is a dialogue-tree cursor plus a transport; core's is utterance-driven action detection and live CEFR difficulty. Different thing, not a bigger version of the same thing. Blocked on §4 *and* on the un-inverted `LanguageProgressTracker`/`AssessmentEngine`. |
| **Actions** | `action_system.gd` (287) | `actions/ActionManager` (421) + the four drills | **Reconcile.** Ours executes; core's registers and dispatches. Low priority. |
| **Rules** | `rule_enforcer.gd` (320) — migrated to real Prolog queries (`MIGRATION.md` §"rule_enforcer.gd") | **no core counterpart** (contract §4.1: rules stay engine-side; core supplies the rule *data*) | **Keep ours.** By design. |
| **Combat / survival** | 4 combat scripts (778 total) + `survival_system.gd` (330) | **no core counterpart** | **Keep ours.** By design. Separately: the four unreconciled combat scripts are a local mess worth cleaning up, unrelated to this program. |
| **Event bus** | `templates/scripts/systems/event_bus.gd` (498) | `GameEventBus` (285) | **Reconcile.** Core's `GameEventType` is what `GameQuestManager` wires itself to for automatic triggers, so adopting quest orchestration later means adopting this. Ours is bigger and load-bearing across 26 template systems. Do not touch until something needs it. |
| **Radiant quest *generation*** | **nothing** | `generateRadiantQuests` (`src/radiant/`, 678) | **Adopt core's. This is the first slice** (§5). |

### 3.1 The behavioural-difference callout

Two rows above are behaviour changes if adopted, and both are deliberately
excluded from this tasklist:

- **Template quest completion.** Imperative tracking → Prolog proof. Changes what
  completes.
- **Dialogue.** Tree cursor → utterance-driven detection. Changes what a player
  can say to make something happen.

Everything else is either additive (crafting, radiant, social sim, language) or
a no-op (Prolog, save).

---

## 4. Decision 1 — the language boundary

**The question:** core is 60 modules / 18,959 lines of TypeScript. Godot is
C++/GDScript, Unity is C#, Unreal is C++. Nothing yet says how they run it.
`docs/UNIFICATION_ROADMAP.md` lists three options; this repo is quietly running a
fourth. All four, costed:

### 4.1 Option A — embed a JS engine, expose it through a C ABI *(recommended)*

Vendor **QuickJS** (pure C, MIT, single file family — the *same vendoring shape*
as Trealla inside libinsimul), bundle `@insimul/core` to one ES module with
esbuild, and wrap both in a C shim: `insimul_core_create()` / `insimul_core_call(handle,
"module.method", json_args) -> json_result` / `insimul_core_last_error()` /
`insimul_core_free()`. Ship it as **`libinsimulcore`**, a sibling to
`libinsimul`, built by the same CMake and packaged by the same `scripts/package.sh`.

- **Godot consumes it exactly as it consumes libinsimul today** — a `RefCounted`
  GDExtension wrapper (`InsimulCore`) beside `InsimulProlog`, same
  `binding_json_to_dictionary` marshalling pattern, same `last_error()` idiom.
- Unity P/Invokes it. Unreal links it as a module. The browser needs no bridge —
  it already *is* the JS runtime.
- **Cost:** the shim + build + bundling, ≈ the scope of libinsimul's US-LI1+LI2
  (skeleton + C ABI). Weeks. **Zero lines of core reimplemented; TypeScript stays
  the single semantics authority.**
- **Costs that are real and must be budgeted:**
  - **The async pump.** Core is `Promise`-based (`IDataSource`,
    `ISpeechSynthesizer`, `generateRadiantQuests` itself). The shim must drive
    QuickJS's job queue from the host's frame loop and let host callbacks resolve
    promises. This is the single hardest piece and it is why §5 picks a slice
    whose only async is its own return.
  - **Marshalling.** JSON in / JSON out per call. Fine for a decision layer
    called at gameplay-event rate; **fatal if called per frame.** Hard rule: the
    hot path never crosses the boundary (§4.5).
  - **Bundling in a standalone repo.** This repo cannot run esbuild against
    `packages/core` — it does not contain it. The bundle must be a **vendored
    build artifact** with a recorded source commit and a drift guard, exactly as
    `conformance/` is vendored today. Design this in US-2; do not discover it.
  - QuickJS is single-threaded. Contract §5.5 warns of *"shapes that assumed a
    single-threaded, garbage-collected host"* — under option A that assumption
    stays true, which turns the warning into a non-issue.

### 4.2 Option B — port core to Rust behind the same C ABI

The roadmap's option and the user's stated preference. `native/rust/`
(`insimul-sys` + `insimul`) already proves the crate layout and the
C-ABI-from-Rust pattern **in this codebase**.

- **Cost:** 18,959 lines, ported and kept correct. Months.
- **The structural problem:** TypeScript cannot be retired, because it *is* the
  browser runtime. A Rust port therefore creates a **second** implementation of
  the thing this program exists to de-duplicate — unless the browser then
  consumes the Rust build via wasm, at which point option B has swallowed option
  A's tooling anyway.
- **Verdict: the right destination, the wrong first move.**

### 4.3 Option C — a service boundary

Rejected, as the roadmap already says: wrong for a shipping single-player game.
Keep it for *editor*-time only, where this repo already has it
(`InsimulHttpClient`).

### 4.4 Option D — hand-port to portable C++ and pin with the corpus *(what we do today)*

`gdextension/src/` is 3,861 lines of exactly this, and it works: the save
envelope byte-matches a TS-produced golden, quest hydration and the radiant tick
pass the shared corpus, and the whole thing is testable under plain `clang++`
with no Godot toolchain. It deserves credit, and it deserves to be rejected as a
*strategy*:

- 3,861 lines buys a fraction of core. Extrapolated to the full surface across
  three engines it is **tens of thousands of lines of hand-maintained
  re-implementation plus per-engine drift guards** — precisely the duplication
  the program was created to delete.
- Every future core change must then be made four times and re-pinned four times.

**Keep it as a tactic** for the small, hot, already-done surfaces (canonical
JSON, SHA-256, the save codec, quest hydration), where the port exists and is
proven. **Never extend it to new core surface.**

### 4.5 The decision

> **Adapters bind to a C ABI, not to a language.** The one artifact all four
> runtimes share is **`libinsimulcore`** — an opaque handle, JSON in, JSON out,
> an explicit error string — shaped exactly like `libinsimul`'s ABI, which this
> repo, Unity and Unreal already consume successfully. Behind that ABI runs
> **TypeScript inside an embedded QuickJS (option A) now**, and **Rust (option B)
> later if and when it is funded.** Which one is behind it is invisible to every
> adapter, so the Rust port can land without touching Unity, Unreal or Godot
> code.
>
> **Corollary for 98 / 99 / 101: do not invent a second mechanism.** If Unity
> needs core, it P/Invokes `libinsimulcore`. If Unreal needs core, it links
> `libinsimulcore`. The bridge is built **once**, in `native/`, not three times.
>
> **The hard rule that makes this safe:** nothing on a per-frame path crosses the
> boundary. Core is the *decision* layer — it is called when a quest is offered,
> an objective is evaluated, a recipe is crafted. Rendering, input, animation and
> physics stay engine-side, which is what contract §3 already mandates.

**Cost of being wrong:** low. If option A's async pump proves unworkable, the ABI
is unchanged and option B (or a per-surface option D fallback) slots in behind
it. That reversibility is the main reason to specify the ABI rather than the
language.

---

## 5. The first slice — radiant quest generation

### 5.1 What it is

`generateRadiantQuests` — `packages/core/src/radiant/radiant-engine.ts` (547) +
`base-templates.ts` (131), **678 lines**, pinned by
`conformance/radiant/*.json`: **5 files, 11 cases** (`empty` 2, `single-slot` 3,
`multi-slot` 1, `maxquests` 2, `exclusion-cooldown` 3).

### 5.2 Why this one

- **The vectors are already here and byte-identical.** `conformance/radiant/`
  matches `packages/core/conformance/radiant/` exactly (verified: `diff -rq`
  reports no difference).
- **Nothing in this repo reads them.** `grep` for `conformance/radiant`,
  `exclusion-cooldown`, `maxquests`, `single-slot` across the whole repo outside
  `conformance/` returns **zero** hits. So the gate goes from 0 executed cases to
  11, and it **cannot be a gate that silently executes nothing** — the thing US-3
  explicitly guards against.
- **It needs no host hooks at all.** Every `EngineHostAdapter` field is optional,
  and this path uses none of them. So the slice tests the **language boundary and
  nothing else**. That is the whole point: isolate the unknown.
- **It is data in, data out.** World/settlement/character records and
  `RadiantOptions` in; `GeneratedRadiantQuest[]` out. No scene graph, no frame
  loop, no `IDataSource`.
- **Zero regression risk is structural, not asserted.** This engine generates no
  radiant quests today. Nothing shipped can change behaviour.
- **It is genuine capability gain**, not a like-for-like swap — the thing §4.1 of
  the contract says adoption should be.

Explicitly *not* chosen, and why: **quest hydration** (a like-for-like swap of an
area already proven equal — churn with no gain); **crafting** (the biggest gain,
but it needs `IResourceStore`, which needs the inventory glue of §2.2 — two
unknowns at once); **the language stack** (blocked on the un-inverted modules);
**save** (ours is already byte-identical to the authority, §7).

### 5.3 How US-2 keeps both implementations reachable

US-2 requires the existing implementation to stay reachable so US-3 can diff.
For this slice **there is no existing implementation** — the honest statement,
not a shortcut. So:

- The radiant source becomes selectable — `core` (through `libinsimulcore`) or
  `none` (today's shipped behaviour: no radiant quests). US-3 runs both over the
  same 11 vectors; every difference classifies as **new capability**, and a
  regression is not constructible.
- **Because that diff is trivial, US-3 gets a second, real one at near-zero
  cost:** run the *same bridge* over `conformance/quests/hydration-cases.json`
  and `radiant-cases.json`, which `quest_system.cpp` (649 lines, option D)
  **already implements**. That is a genuine two-implementation comparison over
  identical vectors — hand-ported C++ vs core-through-the-bridge — and it is the
  evidence needed to decide whether option D can eventually be retired. It adds
  **no adopted surface**: `quest_system.cpp` is not replaced, only compared.

### 5.4 The adapter boundary

Per US-2's rule that no Godot type crosses into core and translation is not
scattered:

```
templates / addons GDScript
        │  Godot Dictionary / Array / String
        ▼
InsimulRadiantSource  (addons/insimul/runtime/radiant_source.gd)  ← the ONLY translation site
        │  canonical JSON
        ▼
InsimulCore  (gdextension/src/insimul_core.{h,cpp})               ← RefCounted wrapper, mirrors InsimulProlog
        │  C ABI: insimul_core_call(handle, "radiant.generate", json)
        ▼
libinsimulcore  (gdextension/corebridge/) = QuickJS + the vendored core bundle
```

One-way by construction: core never learns a Godot type, and this repo gains no
edge into core beyond the vendored bundle + corpus.

### 5.5 Gate

A `gdextension/test/run_radiant_tests.sh` host gate in the established pattern —
plain `clang++`, no godot-cpp, no Godot binary — that loads `conformance/radiant/*.json`,
drives each case through the bridge, and **asserts the executed-case count is 11
and non-zero before comparing anything**.

### 5.6 Abort condition

If US-2 cannot stand up a bridge that passes the 11 cases inside this tasklist,
the correct outcome is to **report the blocker and stop**. It is *not* to
hand-port `radiant-engine.ts` into `gdextension/src/` — that is option D again,
and shipping it would answer the tasklist's central question with the wrong
answer while appearing to succeed.

---

## 6. Seven things that turned out to be false

*(Five found by US-1's audit; §6.6 and §6.7 added by US-2, which found them by
linking libinsimul for the first time.)*

Recorded because the next three tasklists will otherwise inherit them.

### 6.1 "Godot has 10 GDScript files / 1.5k LOC"

That figure — in the tasklist description and in `docs/UNIFICATION_ROADMAP.md` —
counts only `addons/insimul/*.gd` (top level): 10 files, 1,491 lines. The repo
actually holds **172 `.gd` files / 35,565 lines** plus **5,196 lines of C++**.

The *reason* Godot was picked to go first still holds — its runtime is the
youngest, its Prolog is already the shared one, and its C++ core is already
corpus-pinned — but "an order of magnitude smaller than Unity" is not true, and
sizing 98/99 against it would be wrong.

### 6.2 The contract's own figures moved

The tasklist description cites **59 modules / 17,946 lines** and *"GameQuestManager
ships as a `.d.ts` type surface injected at export time"*. The contract as merged
says **60 modules / 18,959 lines**, and `GameQuestManager` (1,013) is now **real
code in core** with its generator dependency inverted behind `IQuestSeedSource`
(US-2 of `94-quest-manager-interface`; the `.d.ts` surfaces are gone). Contract §3
still carries the stale "platform surface" claim — a defect in the contract, noted
in §8.

### 6.3 The vendored Prolog corpus is a 54% subset, and one file is stale

`conformance/VENDORED.md` calls this directory a *"mirror of `packages/core/conformance/`"*.
For `prolog/` it is not:

| | source | vendored |
| --- | --- | --- |
| files | 10 | **7** |
| cases | **76** | **41** |
| missing | — | `identity.json` (11), `equivalence.json` (11), `worlds.json` (12) — the entire KINP pack |
| drifted | — | `gameplay.json`: 7 cases against the source's 8, and its terms are **pre-KINP** (`quest(q1, …)` where the source has `quest(id(ent, 'insimul:world:alderforest', 'q1'), …)`) |

`npm run test:conformance` prints `7 corpus files, 41 cases … 41 passed` and
exits 0. It is not lying — but a reader who has been told 76 will believe the
corpus passed. **US-3 must re-vendor** (its criterion 4) and the case count must
be asserted against the source, not just against zero.

Also unvendored: `predicate-schema-hash.json`. And `conformance/content/library.json`
is **not** a mirror of anything — core has `content-library/{minimal,riverside-starter}.json`
instead. `saves/`, `quests/`, `radiant/` and `ui/` are byte-identical and fine.

> **Fixed in US-3.** Re-vendored to byte-identity — 34 mirrored files, prolog now
> **76 of 76 cases**, `gameplay.json` on KINP terms, `predicate-schema-hash.json`
> and `content-library/` present, `README.md` current. The marshalling gate runs
> all 76. `content/library.json` is now *declared* local rather than mis-described
> as a mirror, and `tools/vendor-conformance.mjs` is the guard that would have
> caught all of this. See §10.2.

### 6.4 Three of the four host gates fail in a standalone checkout

`run_conformance.sh` resolves the corpus with a vendored-first fallback. The other
three do not — they hardcode the monorepo sibling path `../../core/conformance`.
In this worktree:

| gate | expected (VERIFICATION.md) | actual here |
| --- | --- | --- |
| `run_save_tests.sh` | 58 checks, 0 failures | **46 checks, 20 failures** — every one `could not open …/core/conformance/saves/*.json` |
| `run_quest_tests.sh` | 33 checks, 0 failures | **13 checks, 6 failures** — same cause |
| `run_bootstrap_tests.sh` | 42 checks, 0 failures | **42 checks, 21 failures** — same cause |
| `run_conformance.sh` | — | 41 cases, 41 passed ✓ (has the fallback) |

Every failure is a missing path, not a semantic disagreement. But **US-3 cannot
claim a gate that does not run**, so giving the three C++ gates the same
vendored-first fallback is the first task of US-2 — a handful of lines, and it
restores the repo's own stated merge gate.

> **Fixed in US-2.** All three now resolve the vendored corpus first and pass at
> exactly the counts VERIFICATION.md states: save **58/0**, quest **33/0**,
> bootstrap **42/0**. No test logic changed — only the path resolution.

### 6.6 The vendored libinsimul header was wrong, and the wrapper believed it

`gdextension/vendor/insimul/insimul.h` was written *before* libinsimul existed —
a hand-authored "contract copy" the C++ was syntax-gated against. US-2 is the
first story to LINK the shipping library, and the copy turned out to disagree
with it on three points:

| | the vendored copy said | libinsimul actually does |
| --- | --- | --- |
| `consult` / `assert` / `restore` | 1 = success, 0 = error | **0 = success, -1 = error** |
| `retract` | 1 = success | **0 = removed, 1 = nothing matched, -1 = error** |
| `last_error` when clear | `""` | **`NULL`** |
| `assert` / `retract` argument | `"quest(q1, active)."` | term text **without** the trailing full stop |

The polarity error was live: `insimul_prolog.cpp` tested `!= 0`, so
`InsimulProlog.consult()` returned **`false` on success and `true` on failure**,
and likewise for `assert_fact`, `retract_fact` and `restore`. Nothing caught it
because nothing had ever linked the library — the host gates deliberately avoid
it, and the GDScript end-to-end runner needs a Godot binary.

Fixed in US-2: the header is now a verbatim copy of the shipping one, and the
four call sites compare against a named `INSIMUL_OK`. **The lesson generalises to
98 and 99** — Unity and Unreal carry their own copies of this ABI, written from
the same source. Check their polarity before trusting a green syntax gate.

### 6.7 libinsimul crashes when a KB is created after the live count reaches zero

Reproduced with no Godot, no QuickJS and no core involved — create a KB, use it,
destroy it, create another, use that one:

```c
for (int i = 0; i < 3; i++) {
	insimul_kb *kb = insimul_kb_create();
	insimul_kb_consult(kb, "threat_species(wolves).\n");
	insimul_query *q = insimul_query_start(kb, "threat_species(X)");   /* SIGTRAP on i == 1 */
	while (insimul_query_next(q)) {}
	insimul_query_stop(q);
	insimul_kb_destroy(kb);
}
```

Keeping any one KB alive across the cycle makes it disappear, which points at a
global engine bootstrap torn down with the last KB and not surviving
re-initialisation.

This is not academic: a radiant tick builds a **throwaway** KB and releases it
(`radiant-engine.ts` destroys it deliberately, because wasm has no finalizers),
so a game ticking its director would hit this on the second tick.

`libinsimulcore` works around it by holding one `keepalive` KB open for the
lifetime of the handle — a few KB of memory, and the comment in
`corebridge/src/insimulcore.c` says to delete it when the library is fixed. **The
fix belongs in `native/`, which is outside this tasklist's worktree**, so it is
reported rather than fixed here. Unity and Unreal will hit the same wall the
moment they create and release KBs.

### 6.5 The Prolog conformance gate does not run Prolog

`gdextension/test/conformance_host.cpp` feeds each corpus case's *expected*
binding-set JSON through `insimul::parse_binding_set` and checks it decodes. It
never consults a program or runs a query — by design and documented in the file,
because libinsimul is not built in this harness. So `76 passed` means **76
solution sets decoded**, not 76 queries proved. The real query-execution parity
lives in `native/` (`ctest -R conformance`, 76/76, byte-identical native vs
wasm32 per `native/conformance/WASM_PARITY.md`) and in
`gdextension/tests/conformance_runner.gd` when a `godot` binary is present.

That is a defensible split, but the gate's name oversells it and `VERIFICATION.md`
should say which half it covers.

---

## 7. What we should *not* adopt

Stated because AC6 makes "don't adopt" a valid outcome, and it is the right
outcome for part of this surface:

- **The save system.** `InsimulSaveCodec` + `save_file.cpp` produce an envelope
  that **byte-matches a TypeScript-produced golden** (`tools/cross-check/cpp-produced.envelope.json`).
  Replacing a proof with a bridge crossing is a strict downgrade.
- **Prolog.** Already the same engine source on both sides. Blocker 1 is closed.
- **Rules, combat, survival.** No core counterpart, by design (contract §4.1).
- **Inventory and the corpus-pinned UI view models.** Ours are larger and already
  pinned by `conformance/ui/*.json`.
- **Anything needing the seven un-inverted modules** — `GamePrologEngine` (2,267),
  `LanguageProgressTracker` (1,313), `AssessmentEngine` (1,042), `CraftingSystem`
  (521), `AmbientLifeBehaviorSystem` (460), `RadiantQuestDirector` (186),
  `EquipmentManager` (111). **5,900 lines that are not in core yet.** An adapter
  that "adopts" these adopts nothing.
- **Quest completion in the game template.** Real capability gain, real
  behavioural change (§3.1). It needs its own tasklist with its own before/after
  evidence, not a slice of this one.

---

## 8. Proposed amendments to the runtime contract

§5.5 invites revision. Three, in priority order:

1. **Split `IDataSource`.** Its ~90 `async` methods conflate *loading an exported
   world* (~20, sync-satisfiable, what every native adapter needs) with
   *authoring-server session management* (~70: playthroughs, dynamic quest
   creation, merchant inventories, NPC guidance — what only the platform client
   calls). Requiring a native adapter to implement or stub 70 methods it will
   never call is the largest avoidable cost in this plan. Proposal:
   `IWorldSource` (the load-only subset) extended by `IDataSource`.
2. **Contract §3 is stale on `GameQuestManager`.** It still says the class is a
   `.d.ts` injected by the platform at export time; §1.1 and §2.2 say it is real
   code in core with `IQuestSeedSource` inverted. §3 should be corrected, since
   §3 is what an adapter author reads to decide what they must implement
   themselves.
3. **Say which interfaces are sync-safe.** `ISpeechSynthesizer` returning a
   `Promise` is right; `IResourceStore` and `ICombatStatSink` being sync is right;
   `IDataSource` being fully async is a browser artifact. A native adapter needs
   to know which is which before it designs its pump.

*(Added by US-3, found the same way §6.6 and §6.7 were — by being the first
consumer outside Node/the browser.)*

4. **Declare the host builtins core imports, and keep them off wide modules.**
   `src/save-envelope.ts` opens with `import { createHash } from 'crypto'` — a
   bare **Node** builtin, at module scope. `save-envelope` is a wide module
   (canonical JSON stringify + envelope build/validate), so importing *any* of
   its exports drags the Node import in and the module will not bundle for a
   non-Node host at all. That is what blocked US-3's quest diff until the adapter
   supplied `js/host-crypto.js`. Two asks: list the host builtins core assumes
   (alongside §2's five host hooks), and move `computeSaveFileIntegrity` behind
   an injected hasher or into a narrow module so `canonicalJSONStringify` can be
   imported without it. The `prolog-engine` seam (§5.3) is the precedent — that
   one is *designed* to be re-resolved; `crypto` is an accident.

---

## 9. What the next stories do

| story | work |
| --- | --- |
| **US-2** ✅ | (a) three host gates fixed, 58/33/42 green; (b) `libinsimulcore` built — in `gdextension/corebridge/`, **not** `native/`, because that is a sibling submodule outside this worktree; the header is the part that must not fork when it moves; (c) `InsimulCore` GDExtension wrapper; (d) `InsimulRadiantSource` as the single translation site, selectable `core` \| `none`. All 11 vectors pass. |
| **US-3** ✅ | (a) `run_radiant_tests.sh` over all **11** vectors, count asserted; (b) corpus re-vendored to the full 76 with a drift guard; (c) the §5.3 diff built and run — **7/7 AGREE**; (d) `quest_system.cpp` retained, reason recorded. Full report: **§10**. |

---

## 10. US-3 — the parity report

Three questions, three gates. Every number below is printed by a command in
Appendix B and was green on this machine at the time of writing.

### 10.1 The adopted slice against the corpus

`npm run test:radiant` → **11 of 11 radiant vectors pass** through core's real
TypeScript, unreduced: the same five files packages/core's own runner reads,
byte-identical to the source copy (asserted by §10.2's guard, not by inspection).

The count is asserted, not merely printed. The gate fails if the corpus directory
is empty, if fewer than 11 cases run, if any of the five areas is missing, if two
cases share a name, or if the bundle no longer exposes `radiant.generate`. The
same discipline was retro-fitted to the **marshalling** gate this story, which
until now returned 0 on an empty corpus directory — a gate that could not fail.

| gate | before US-3 | after |
| --- | --- | --- |
| `npm run test:conformance` | 41 cases, **no floor** | **76 cases**, floors on files *and* cases |
| `npm run test:radiant` | 11 cases, floor 11 | unchanged |
| `npm run test:quest-parity` | did not exist | 7 cases, floors on both areas |

### 10.2 The corpus is byte-identical again — it was not

§6.3 found the mirror had rotted to **41 of 76** Prolog cases with a pre-KINP
`gameplay.json`. Re-vendored from `packages/core` @ `443cce78`:

| | before | after |
| --- | --- | --- |
| mirrored files | 27, unverified | **34, hash-pinned** |
| `prolog/` cases | 41 (54%) | **76 (100%)** |
| KINP `identity` / `equivalence` / `worlds` | absent | present (34 cases) |
| `gameplay.json` | pre-KINP atoms | `id/3` terms |
| `predicate-schema-hash.json`, `content-library/` | absent | mirrored |

**The guard matters more than the copy.** `tools/vendor-conformance.mjs`
(`npm run vendor:conformance`) mirrors `tools/vendor-core-bundle.mjs`'s two
modes: `--check` verifies every mirrored file against the sha256 in
`conformance/VENDORED.json` and rejects any file that is neither mirrored nor
*declared local*, needing no core checkout so it runs in `npm run check`; adding
`--core` does the real byte-for-byte diff against the source tree. The rot
happened because nothing ever ran that diff.

The "declared local" list is the other half. `conformance/content/library.json`
claimed in its own README to be a mirror of core and never was — core's shared
content-library golden is `content-library/*.json`, a *different and current*
shape (`manifest.contractVersion` vs a top-level `schemaVersion`). It is now
listed as local, its README says so, and core's real fixtures sit beside it. They
are not interchangeable; reconciling the Godot importer onto the shared golden is
content-portability work, not runtime-core adoption.

### 10.3 The two-implementation diff, and the classification

Two diffs, because the honest one is weak and the useful one is cheap.

**Diff 1 — the adopted slice vs what shipped** (`run_radiant_tests.sh --source none`).
This engine never generated radiant quests, so the pre-adoption leg emits
nothing. All 11 vectors classify:

| | cases | meaning |
| --- | --- | --- |
| AGREE | 4 | the corpus expects zero quests; both legs produce zero |
| **GAIN** | **7** | core produces quests where this engine produced none |
| REGRESSION | 0 | not constructible — the old leg emits nothing at all |

"Not constructible" is now **asserted** rather than argued: the leg fails if the
pre-adoption path ever produces a quest, and it also fails if GAIN is zero (which
would mean the comparison had quietly stopped comparing).

**Diff 2 — hand-ported C++ vs core, over identical vectors**
(`npm run test:quest-parity`, the diff §5.3 promised). `gdextension/src/quest_system.cpp`
(649 lines, option D) already implements quest hydration and the radiant tick;
core implements both; `conformance/quests/{hydration,radiant}-cases.json` pins
both. Three legs — committed corpus, the hand-port, core through libinsimulcore —
reduced to a canonical string by the **same** C++ serializer, so a difference is
semantic and never a formatting artifact.

```
classifier self-test: 5/5 verdicts reachable
7 case(s) executed: 4 hydration + 3 radiant
classification: 7 AGREE, 0 FIX, 0 SHAPE, 0 REGRESSION
```

**Result: total agreement. Zero differences to classify, and therefore zero
regressions — the classification asked for by US-3's third criterion is empty
because there is nothing in it, not because nothing was compared.** The gate runs
its classifier over five synthetic triples first and asserts every verdict
(AGREE / FIX / REGRESSION / two flavours of SHAPE) is reachable, so "7 AGREE" is
a result rather than the only thing the code can say.

What this is evidence *for*: the hand-port is a faithful port on the surface the
corpus covers, and a future tasklist can retire it in favour of core without
behaviour change **on that surface**. What it is not evidence for: the corpus
covers 4 hydration cases and 3 tick cases, while `quest_system.cpp` is 649 lines
including query-driven completion and fact-asserting transitions that no shared
vector touches. Agreement here does not license deleting it — see §10.4.

Reaching core's side of this diff required one adapter module that did not exist:
`js/host-crypto.js` (§8 amendment 4). It throws rather than computing, because
nothing on the adopted surface hashes and a stub that returns a plausible wrong
digest is worse than one that stops.

### 10.4 What was removed, and what was retained

US-3's last criterion: *remove the superseded implementation, or retain it
explicitly with a reason.* Nothing was removed. Both retentions are deliberate.

| thing | decision | reason |
| --- | --- | --- |
| `InsimulRadiantSource.SOURCE_NONE` | **retained** | It is not a superseded implementation — there is no second implementation of radiant generation, `none` is the *off* setting, and a game that wants no procedurally generated quests still needs it. It is also now load-bearing evidence: the 4/7/0 classification above is what keeps "strict capability gain" true after somebody edits the generator. It is additionally the fallback for a build without libinsimulcore. |
| `gdextension/src/quest_system.cpp` (option D) | **retained** | US-2 adopted radiant *generation* only; quest hydration was never adopted, so this is not superseded by anything shipped. §5.3 was explicit that the diff "adds no adopted surface — `quest_system.cpp` is not replaced, only compared." Deleting a passing 649-line implementation on the strength of 7 agreeing vectors would be retiring it on evidence that covers a fraction of it. |

The retention of option D is **not** an endorsement of option D. §4.4 and §7 stand:
do not extend the hand-port to new core surface. This story's job was to produce
the evidence a future retirement needs, and it did.

### 10.5 The honest gaps

- **The GDScript-level gates did not run here.** A `godot` binary is on PATH in
  this worktree but `addons/insimul/tests/run_*_headless.sh` hangs past three
  minutes (it wants a built GDExtension, which needs godot-cpp + scons). That is
  pre-existing and unrelated to these changes — no GDScript behaviour was
  modified beyond a doc comment — but it means the numbers in §10.1–§10.3 are all
  from the **C++ host gates**, which is what this harness can actually check.
  `gdextension/tests/conformance_runner.gd` remains the only thing that executes
  the Prolog corpus as *queries*; §6.5 still stands.
- **`content-library/` and `predicate-schema-hash.json` have no reader here.**
  Mirrored for provenance; noted as orphans in `conformance/VENDORED.md` rather
  than left to look like coverage.
- **The quest corpus is small.** 4 + 3 cases. A stronger retirement case for
  option D would need vectors for completion evaluation and the fact-asserting
  transition, which do not exist in any runtime's corpus yet.

---

## 11. The band-120 mechanic modules (tasklist 147, US-1)

Core landed nine Insimul modules; the seven in band 120–125 name **eight distinct
host interfaces** between them. This story implemented all eight in Godot **and
made all seven modules reachable across the C ABI** — 27 rows in
`gdextension/corebridge/js/entry.js`, executed end to end by
`gdextension/test/run_mechanic_tests.sh`.

Unity was the probe (tasklist 145). Its findings are inherited rather than
rediscovered, and the one difference in outcome has a boring cause: **its bridge
lives in a repository a Unity worktree cannot edit, and ours is in-tree.** Unity
could write the host half and had to report `BridgeHasNoRow` for every module;
this repo owns `gdextension/corebridge/`, so it could write both halves. Nothing
about the engines made the difference.

### 11.1 What the binary answers now

`core.methods` is the only honest way to ask a build what it can do — not a
version stamp, not a sibling checkout. Before this story:

```
{"methods":["core.methods","quest.hydrate","quest.radiantTick",
            "radiant.baseTemplates","radiant.generate"]}
```

After it, 32: the same five plus 27 mechanic rows. `mechanic.modules` reports
which module owns which, so `InsimulMechanicSurface` can tell a creator at boot
whether combat is live instead of leaving them to infer it from a component that
exists.

### 11.2 The three findings Unity said were core-side, answered

Unity's §12.2 listed three things that had to be resolved before any row could be
written, and said all three landed on whoever wrote them. That turned out to be
this tasklist, so here are the answers as built.

**1. Every host interface is a callback, and the C ABI has none.** Resolved by
inverting the direction — **readings in, orders out** — implemented in
`gdextension/corebridge/js/host-mechanics.js`:

- everything core would ASK (`ITrajectoryProbe.query`, `IPerceptionProbe.sense`,
  `ITraversalProbe.query`, `ICombatStatSink.getBaseStats`) is gathered by the
  engine BEFORE the call and travels in as an argument; the adapter's shim serves
  core's question from what arrived;
- everything core would TELL (`ICombatSystem.applyDamage`,
  `ISurvivalSystem.consumeStamina`, `ILocomotionHost.travel`,
  `ISkillModifierSink.applyModifiers`, `ICombatStatSink.applyStats`) is recorded
  as an order and returned in the result; `InsimulMechanicSession._drain()` calls
  the wired host implementation for each one, in core's order.

The engine therefore executes exactly what it would have executed in-process,
with the same arguments — and `insimulcore.h` still has no function pointers.
This is glue, not a fork: `host-mechanics.js` contains no damage number, no
suspicion curve, no traversal cost and no price.

**2. The decision layers are stateful sessions, and a bridge call is not.**
Resolved with a session table: `<module>.create` returns a handle, every verb
takes one, and `mechanic.dispose` releases it along with the KB it owns.

*Deviation from Unity's proposal, and why.* Its §12.3 sketched a per-module
`<module>.dispose`; there is one `mechanic.dispose` instead, because a handle
already names its module and seven identical functions differing only in an
argument they ignore is a bigger surface for no information. `mechanic.sessions`
lists what is open, so a leak in a game is visible rather than inferred — and the
gate uses it: `test_mechanic_bridge.cpp` fails if any session it opened outlives
it, which is how the create-rows' leak-on-failure bug was found (a `create` that
threw during registration used to leave a session no caller had a handle to).

**3. Arrival is not a return value when a body takes seconds to move.** Answered
the same way Unity answered it, for the same reason: what the host already knows
is reported immediately (no body, unknown destination, a `NavigationAgent3D`
path that stops short → `arrived: false` with a reason), and anything else
dispatches the agent and reports `arrived: true`, so world state moves at the
decision moment and the body catches up. Reporting `arrived: false` for every
movement that takes time would make `LocomotionDirector` count a successful walk
as a failure and re-plan against a wall that is not there.

There is also a **strict path** this repo could offer because it owns the rows:
`traversal.traverse` takes an `arrival` reading, read by core BEFORE the order
goes out, so a host that already knows the body cannot get there says so and the
meter is never spent (`GodotLocomotionHost.arrival_reading()`).

### 11.3 Four findings this story added

**1. The Prolog seam had to grow — and the growth is where the wasm engine and a
native one genuinely differ.** The mechanic layers call four `PrologEngine`
members between them: `query`, `assertFact`, `retractFact`, `queryOnce`. Only
`query` existed; the other three threw. Core's `WasmPrologEngine` implements every
mutation as **rebuild** — record the fact, destroy the KB, re-consult the whole
accumulated program — and its own header says why, which is not a correctness
reason: *"Trealla supports incremental assert/retract properly, so this class does
NOT have to rebuild... It does anyway, [so that] US-2's diff of the two engines
sees only real disagreements."*

This engine IS that Trealla, linked natively, so `host-prolog-engine.js` asserts
and retracts in place. The bookkeeping mirrors core's exactly (de-duplication by
normalized fact text, a retract of something CONSULTED rather than asserted
changing nothing, a `:- dynamic` directive once per signature), so the divergence
is in mechanism and not in anything a caller can observe. A rebuild would have
been fewer lines and would re-consult every rule pack the world loaded on every
attack — and would churn KB handles, which is the failure mode the `keepalive` KB
in `insimulcore.c` exists to work around (§6.7). Executing the mechanic corpora
against it (US-2) is what holds the claim to account.

**2. QuickJS has no `TextEncoder`, and core's identity layer constructs one at
module scope.** `identity/kinp.ts` percent-encodes non-ASCII local ids, and
`identity/` is reached by every mechanic module — an observer, a target and an
agent are all KINP identifiers. The whole bundle failed to evaluate with
`ReferenceError: 'TextEncoder' is not defined`, at LOAD, not at the call.
`js/host-text-codec.js` is a UTF-8 polyfill installed before core's modules
initialise. It is a polyfill and not a seam — nothing about it is
adapter-specific and core has no import for it to resolve — which is why it
installs globals and is imported FIRST in `entry.js`.

**3. A session's KB must carry the packs the module's gates read.** Core's
`checkAction` THROWS when `forbidden_by/4` raises rather than reading an undefined
procedure as a permit (`ai/rule-enforcement.ts`'s `solve`), and Trealla raises
`existence_error` for a predicate no program defined. So a traversal or skill
session opened against a KB of bare facts fails the call. That is core's
deliberate design and identical on the wasm engine, so it is a **host
obligation**, not a bridge defect: pass the rule packs the world loaded, not just
its facts. Stated on `InsimulMechanicSession.open()`, where a caller will hit it.

**4. This template already had a second damage formula.**
`templates/scripts/systems/combat_system.gd` carries `calculate_damage()` with its
own critical multiplier and its own `randf_range` variance — the pre-adoption
combat, which existing games call. `GodotCombatHost` deliberately does not use
it, call it, or agree with it: damage arrives already decided through
`ICombatSystem.applyDamage`. The two are not a contradiction but a **migration**,
and it is named in the host's header rather than quietly resolved, because
deleting the old one is a change to shipped games and belongs to whoever makes
that call.

### 11.4 What the host half cost, and the two gaps it did not paper over

Eight interfaces, eight implementations, no stubs. Two are narrower than the
interface, and each says so where a reader will hit it rather than only here.

| interface | where | the honest edge |
| --- | --- | --- |
| `ICombatSystem` | `templates/scripts/mechanics/godot_combat_host.gd` | `execute_attack()` **refuses and warns** rather than rolling. Core never calls it; implementing it would be the second damage pipeline finding 4 describes. |
| `ICombatStatSink` | same file | Deliberately the same component as `ICombatSystem`: they are two views of one roster, and splitting them would mean two rosters that have to agree. |
| `ISurvivalSystem` | `godot_survival_host.gd` | `update(delta)` is a **no-op by design** — `survival_system.gd` owns the clock and ticks itself; ticking it twice would decay hunger at double rate. `add_modifier` forwards `modifier.id` as an authored PRESET id and warns when the world has no such preset, so a modifier core invents at runtime does not silently apply. |
| `ISkillModifierSink` | `godot_skill_modifier_sink.gd` | `move_speed`, `jump_height` and `reach` land on the body's exported properties. **`carry_capacity` lands nowhere**: `inventory_system.gd` limits by `max_slots` and has no weight capacity, so applying it would invent a limit no rule reads. Recorded (`unapplied()`) and announced, not applied. The same gap Unity found. |
| `ITrajectoryProbe`, `IPerceptionProbe`, `ITraversalProbe` | `godot_geometry_probes.gd` | Real `PhysicsDirectSpaceState3D.intersect_ray` and `NavigationServer3D.map_get_path`. `light_level/2` is an **approximation**: Godot exposes no runtime per-point lightmap read, so it is an ambient floor plus a linecast at the sun. It is a measurement either way — what darkness is WORTH is authored. |
| `ILocomotionHost` | `godot_locomotion_host.gd` | §11.2 finding 3. Also: with no `NavigationAgent3D` under the body it teleports rather than refusing, because a world that moves without animating (a strategy map, a test scene) is a legitimate world. |

One thing had to be built underneath all of it and did not exist:
`InsimulActorRegistry` (actor atom → `Node3D`, place atom → position), because
core names `nessa` and `forge_gate` and a raycast needs a body. It holds no state
of any kind — a registry that started caching health would be the beginning of a
second world model.

### 11.5 What is gated, and what still is not

| gate | what it proves |
| --- | --- |
| `npm run check` → `check-mechanics.mjs` | Five mirrors: core's manifest against the vendored `MODULE_HOSTS.json`, every interface's member list against the GDScript base class, every interface against *some* implementation (or a `stubbed` entry with a stated consequence), `entry.js`'s module table against core's, and every order the adapter can emit against a dispatch in `insimul_mechanic_session.gd`. `--core` re-derives from core's TypeScript; `--self-test` runs five negative controls that prove no check is vacuous. |
| `npm run test:mechanics` | 43 checks driving all seven modules end to end through libinsimulcore over the natively linked libinsimul. Reachability, the inversion in both directions, that a host CANNOT decide (the same shot with a clear line, a blocked line and no reading at all), session isolation, and the seam's assert/retract path. |

What is **not** gated is what no gate here can be: no GDScript is executed. The
Godot implementations live in `templates/`, which is the exported game and is in
no compiled assembly, so a raycast, a `NavigationAgent3D` and an equipment panel
are VERIFICATION.md's human checklist in a project with a scene.

### 11.6 What Unreal inherits

1. **The rows exist and are the same rows.** `entry.js` is in `gdextension/` only
   because tasklist 100's worktree was this repo; when the bridge moves to
   `native/corebridge` beside libinsimul (§7), Unreal and Unity link the same 27
   rows and only the host half is theirs to write.
2. **Readings in, orders out** is the shape. Do not invent a callback ABI for it.
3. **Ask `core.methods`, never a version.**
4. **The KB obligation (§11.3 finding 3) will bite every engine**, because it is
   core's behaviour and not this bridge's.

---

## Appendix A — drop-in text for `docs/UNIFICATION_ROADMAP.md` Decision 1

That file lives in the **project checkout**, outside this submodule, so this
tasklist cannot edit it. Paste the following over Decision 1's `STATUS` block at
merge time; the full reasoning stays here, in the repo that will hold the proof.

> **STATUS (answered by `100-godot-runtime-adapter` US-1):** the boundary is a
> **C ABI, not a language**. All four runtimes bind one artifact —
> **`libinsimulcore`** in `native/`, an opaque handle with JSON in / JSON out and
> an explicit error string, shaped exactly like `libinsimul`'s ABI that Godot
> (GDExtension), Unity (P/Invoke) and Unreal (module link) already consume.
> Behind that ABI runs **TypeScript inside an embedded QuickJS today** — zero
> lines of core reimplemented, TypeScript stays the single semantics authority —
> and **Rust later**, invisibly to every adapter. The hard rule: nothing on a
> per-frame path crosses the boundary; core is the decision layer, rendering and
> input stay engine-side (contract §3).
>
> **98, 99 and 101 must not invent a second mechanism.** The bridge is built once,
> in `native/`, not three times. Rationale, costs and the rejected options —
> including the hand-ported-C++ approach Godot is running today and why it cannot
> scale — are in `godot/RUNTIME_CORE_ADOPTION.md` §4.

Two further roadmap corrections, from §6.1 and §6.2: Godot's runtime is **172
`.gd` files / 35,565 lines + 5,196 lines of C++**, not "1.5k"; and the contract's
current figures are **60 modules / 18,959 lines**, with `GameQuestManager` real
code in core rather than an injected `.d.ts`.

---

## Appendix B — how to reproduce the measurements

```bash
# LOC (§0, §6.1)
find addons  -name '*.gd' | wc -l; find addons  -name '*.gd' -exec cat {} + | wc -l
find templates -name '*.gd' | wc -l; find templates -name '*.gd' -exec cat {} + | wc -l
wc -l gdextension/src/*.cpp gdextension/src/*.h | tail -1

# corpus drift (§6.3, §10.2) — CORE is the packages/core checkout
node tools/vendor-conformance.mjs --check --core "$CORE"     # byte-identical (was: 9 diffs)
node -e "const fs=require('fs');let t=0;for(const f of fs.readdirSync('conformance/prolog'))
  t+=JSON.parse(fs.readFileSync('conformance/prolog/'+f,'utf8')).cases.length;console.log(t)"   # 76 (was 41)

# the radiant corpus had no readers before US-2 (§5.2); it has one now
grep -rn 'conformance/radiant\|exclusion-cooldown\|maxquests\|single-slot' . \
  --exclude-dir=.git --exclude-dir=conformance          # run_radiant_tests.sh + the bridge gate

# gates (§6.4 → §10.1). All green on this machine.
npm run check                       # 173 .gd + bundle guard + corpus guard
npm run test:conformance            # 10 files, 76 cases, 76 passed
npm run test:radiant                # 11 case(s), all 5 areas
npm run test:quest-parity           # 7 AGREE, 0 FIX, 0 SHAPE, 0 REGRESSION
bash gdextension/test/run_radiant_tests.sh --source none       # 4 AGREE, 7 GAIN, 0 REGRESSION
bash gdextension/test/run_quest_parity_tests.sh --source cpp   # the hand-port alone, no libinsimul
bash gdextension/test/run_save_tests.sh       # 58 checks, 0 failures  (was 46/20, path)
bash gdextension/test/run_quest_tests.sh      # 33 checks, 0 failures  (was 13/6,  path)
bash gdextension/test/run_bootstrap_tests.sh  # 42 checks, 0 failures  (was 42/21, path)

# the vendored bundle really is core (needs the checkout)
node tools/vendor-core-bundle.mjs --check --core "$CORE"
```
