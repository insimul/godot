# @insimul/core conformance corpus

Language-neutral, data-only fixtures that pin the **engine-agnostic contract**
carved out of `shared/` into `@insimul/core`. Everything here is JSON (plus the
golden save files) so every harness — `libinsimul`'s C, Rust and wasm legs for
the Unreal/Unity/Godot plugins and the Rust server, and the TypeScript runner in
this package — consumes the **same** cases and proves semantic parity. Since
tasklist 91 the web runtime executes that same engine (libinsimul compiled to
wasm32), so this corpus now gates one engine across every platform rather than
two against each other. **Write cases as data, never as code.**

## Layout

- `saves/` — three golden save-file fixtures (`v1-minimal.json`,
  `v2-typical.json`, `v2-with-extensions.json`), copied read-only from
  `insimul-platform/shared/__tests__/fixtures/saves/`. They are runtime-format
  artifacts (the transport shape validated by the US-CE4 zod schemas). A migration
  test (`src/conformance/__tests__/saves-migration.test.ts`) asserts
  `migrateSaveFile` lifts `v1-minimal` to the current `SAVE_FILE_VERSION`.
- `prolog/*.json` — the golden Prolog query corpus (this file's main subject).
  `prolog/mechanic-*.json` are the mechanic vocabulary's seven areas (see "The
  mechanic vocabulary in the corpus" below).
- `predicate-schema-hash.json` — the committed `predicateSchemaHash` (the Prolog
  contract's fingerprint, stamped on a canonical world export and carried in a
  save's WorldSnapshot). `src/conformance/__tests__/predicate-schema-hash.test.ts`
  fails when the schema moves without the artifact being regenerated; the file
  itself documents the regenerate command.
- `radiant/*.json` — the radiant quest-generation corpus (see "Radiant case
  format" below). Pins `generateRadiantQuests` — the contract the future native
  `insimul_radiant_tick()` must match.
- `content-library/*.json` — portable content-library (world artifact) fixtures
  (see "Content-library fixture format" below). The shared golden every
  per-engine importer validates against, run by
  `src/conformance/__tests__/content-library-corpus.test.ts`.
- `grounding/*.json` — KGP grounding packs (US-2 of `152-koine-kgp-alignment`).
  `roman-cuisine.json` is a `pinakes` snapshot of real Roman-cuisine facts at
  `pinakes:world:consensus-reality` — the shared golden every runtime's importer
  validates, verifies (KGP §3/§4.1) and admits (§7.1) against. Its `pack_id` and
  every claim `id` are content addresses of its own bytes and are DERIVED:
  regenerate with `npm run grounding-packs`; `src/grounding/__tests__/pack-round-trip.test.ts`
  fails if the committed file is not already stamped. Three records are
  `CC-BY-SA-4.0` on purpose, so the default consumer allowlist
  (`public-domain + attribution`) has something real to exclude.
- `editor/*.json` — the **edit-time** corpus (US-2 of `101-editor-plugin-core`;
  see "Editor fixture format" below). Pins the binding resolution chain, the
  scene-placement math and the five-way re-import diff — the three capabilities
  every engine editor plugin implemented and core did not, which is why they had
  already drifted with nothing to catch it. Run by
  `src/conformance/__tests__/editor-corpus.test.ts`; regenerate the derived
  `expected*` values with `npm run editor-goldens`.
- `ui/*.json` — the default-UI view-model corpus (US-GU1). `theme-tokens.json` is
  the single-source-of-truth design token set every engine's theme maps;
  `registry-cases.json` pins the panel-registry behavior (default lookup, creator
  override precedence, missing-panel diagnostics); `loading-phases.json` pins the
  loading-screen view-model (weighted-cumulative monotonic progress, phase label,
  deterministic tip). Run by the TS view-models (`src/ui/__tests__/ui-corpus.test.ts`)
  and the Godot headless leg (`packages/godot/addons/insimul/tests/ui_registry_test.gd`)
  — the two can never disagree on the contract. Scene refs are opaque strings so
  every engine runs the same cases.
  US-GU2 adds `quest-journal-cases.json` (journal tab filtering + counts, tracker
  HUD `max_tracked`, offer accept/decline, radiant `upsert` arrivals — lifecycle
  mirrors the real quest-system signals) and `trade-cases.json` (inventory /
  container transfer / merchant buy+sell, backed exclusively by `save.currentState`;
  each case is an initial currentState slice + one op + expected result/quantities/
  gold, with item + gold conservation as the invariant). Run by
  `src/ui/__tests__/quest-trade-corpus.test.ts` and the Godot headless leg
  (`packages/godot/addons/insimul/tests/quest_trade_test.gd`).
  US-GU3 adds `chat-cases.json` (dialogue streaming: an ordered event stream —
  greeting/begin/chunk/action/complete/fail — pinning the transcript, streaming
  flag, triggered KB actions, completed-turn count, and the `save.conversations`
  history projection), `pause-menu-cases.json` (module-bundle-gated tab visibility +
  the open/active-tab reducer) and `save-slot-cases.json` (codec-reported slot
  outcome → rendered row status/title/message/can_load/can_save, incl. the
  corrupted-envelope messaging). Run by
  `src/ui/__tests__/dialogue-menu-save-corpus.test.ts` (which also proves the real
  SHA-256 corrupted-envelope chain via `SaveSlotModel.classifyEnvelope`) and the
  Godot headless leg (`packages/godot/addons/insimul/tests/dialogue_menu_save_test.gd`).

- `ai/action-selection.json` — the **game-AI decision corpus** (US-2 of
  `113-game-ai-substrate`; see "AI selection case format" below). Pins what each
  agent decides for a fixed `(kb, seed, tick, roster, weights)`: the candidates
  enumerated from the action block, every candidate's utility, the verdict of the
  Prolog gate `permissible/3`, and the winner. Every case carries
  `src/ai/action-predicates.ts` verbatim at the head of its `kb`, so a C, Rust or
  wasm harness runs it unaided. Regenerate with `npm run ai-goldens`; run by
  `src/conformance/__tests__/ai-selection-corpus.test.ts`. See
  `packages/core/docs/game-ai-substrate.md` §4.

- `prolog/agent-ai.json` — the **`agentAi` module's corpus** (US-4 of
  `113-game-ai-substrate`), part 5 of its module contract. Ordinary
  `{ kb, query, expected }` cases in the `prolog/` format, so the C, Rust and wasm
  harnesses run it with no new machinery: what an agent could do, which of those it
  may do, what its goal still wants, and which steps serve it now versus once an
  earlier step has run. Each case carries `src/ai/action-predicates.ts` and
  `src/ai/planning-predicates.ts` verbatim — in that order, the only order they
  consult in. Two cases are its teeth: a forbidden step that is the cheapest route
  to the goal and is offered at NO depth, and a permitted, feasible step that is
  still not takeable because the plan owes it a prerequisite. Regenerate with
  `npm run ai-corpus`. See `packages/core/docs/game-ai-substrate.md` §7.

- `combat/*.json` — the **combat resolution corpus** (US-4 of
  `120-combat-and-stamina`; see "Combat case format" below). `resolution.json`
  pins one attack or one defensive action for a wholly self-contained input — both
  combatants, the authored action row, the fully resolved `CombatTuning`, the
  scalar separation, the seed and the tick — down to the stage-by-stage damage
  breakdown and the `{ retract, assert }` fact delta it becomes.
  `action-table.json` pins how a world's authored rows become combat actions
  (combat column → shared `systems.actions` row → unset). It is the counterpart to
  `prolog/mechanic-combat.json`, which pins the combat *vocabulary*: no rule
  computes a damage number, so a query corpus cannot pin one. Regenerate with
  `npm run combat-corpus`; run by `src/conformance/__tests__/combat-corpus.test.ts`,
  which derives outcome coverage from the pinned data rather than from a label.

- `stealth/*.json` — the **stealth/perception corpus** (US-3 of
  `121-stealth-and-perception`; see "Stealth case format" below).
  `detection.json` pins one detection tick for a wholly self-contained input — the
  observer roster with its per-channel acuities, the targets with the host's
  measurements of them, the host's readings, the memory carried in from the
  previous tick, the fully resolved `DetectionTuning`, the seed and the tick — down
  to the rung each pair lands on, what each observer now BELIEVES about where its
  target is, the `{ retract, assert }` fact delta, and the substrate's own
  perception pass verbatim. `actions.json` pins how a world's authored rows become
  stealth actions and what performing one does. It is the counterpart to
  `prolog/mechanic-perception.json`, which pins the perception *vocabulary*: no
  rule computes a suspicion level, so a query corpus cannot pin one. Regenerate
  with `npm run stealth-corpus`; run by
  `src/conformance/__tests__/stealth-corpus.test.ts`, which derives rung coverage
  from the pinned data rather than from a label and re-runs every case with the
  roster reversed. The headless reference host that drives the same module end to
  end with no engine is `src/conformance/__tests__/headless-stealth-host.ts`.

- `traversal/*.json` — the **traversal corpus** (US-4 of `122-traversal-and-travel`;
  see "Traversal case format" below). `affordances.json` pins what the world affords
  an actor out of one place, what each way costs the shared `energy/3` meter, the
  cheapest route to somewhere else, and the authored graph as the KB carries it —
  for a wholly self-contained input (the link graph, the actor's modes, the runtime
  closures, the host's geometric answers, the meter, the fully resolved tuning).
  `vehicles.json` pins the three vehicle verbs — board, drive, disembark — their
  refusals, the state each produces and the fact delta it becomes.
  `fast-travel.json` pins a **world advance**: the route the journey is priced from,
  the elapsed world hours, the bounded step schedule with its derived draws, the
  authored ceiling, and the arrival and discovery deltas. It is the counterpart to
  `prolog/mechanic-traversal.json`, which pins the traversal *vocabulary*: no rule
  computes a cost, a route or an elapsed journey, so a query corpus cannot pin one.
  Regenerate with `npm run traversal-corpus`; run by
  `src/conformance/__tests__/traversal-corpus.test.ts`, which derives coverage from
  the pinned data rather than from a label and re-runs every case with the link
  list, the modes and the closures REVERSED. The headless reference host that drives
  the same module end to end with no engine — the probe, the locomotion host, the
  arrival-failure path and the world clock — is
  `src/conformance/__tests__/headless-traversal-host.ts`.

- `skills/*.json` — the **skill corpus** (US-3 of `123-skill-trees-and-progression`;
  see "Skill case format" below). `advancement.json` pins what a level PRICES and
  whether an actor may take it; `unlocks.json` pins what a node costs, every goal
  it asks (parents desugared into the same gate an authored requirement is) and
  why it is refused; `effects.json` pins what a taken node DOES to the snapshot the
  module it affects was already going to resolve from; `trees.json` pins the whole
  panel a host draws, rows and edges derived from the authored parent edges rather
  than from a `tier` field. Each case carries the whole input — the authored skill
  or node, the actor's levels, bank and pool, and the fully resolved `SkillTuning`
  — so a harness in any language reproduces it with no defaults table, no world
  file and no KB. It is the counterpart to `prolog/mechanic-skill.json`, which pins
  the skill *vocabulary*: no rule computes a price, a cost, a refusal or a panel,
  so a query corpus cannot pin one. Regenerate with
  `npm run skill-resolution-corpus`; run by
  `src/conformance/__tests__/skills-corpus.test.ts`, which derives coverage from
  the pinned data rather than from a label and re-runs every case with the parent,
  goal and effect lists REVERSED. The headless reference host that renders a tree
  the package has never heard of, with no engine under it, is
  `src/conformance/__tests__/headless-skill-host.ts`.

- `map/*.json` — the **map corpus** (US-3 of `133-map-and-geopolitical-layer`; see
  "Map case format" below). `resolution.json` pins what a caller gets back when it
  asks where a position is and whose it is: the innermost region per kind with its
  KINP identity, every authority innermost-level first with the duplicate
  authoring folded, the three land descriptors read independently, and the
  conflicts NAMED rather than resolved. `surface.json` pins the value an engine
  draws a map from — regions, borders with the stretch of world time they held
  over, the quest markers the game already had and what this playthrough has found
  — with no colour, icon, projection or visibility rule anywhere in it. It is the
  counterpart to `prolog/geo-map.json`, which pins the region *vocabulary*: no
  rule folds a duplicate, orders a solution set or builds a surface, so a query
  corpus cannot pin one. Hand-authored as data (the surface cases carry a whole
  input and a whole output, so a harness needs no KB at all) and run by
  `src/conformance/__tests__/map-corpus.test.ts`, which re-runs every resolution
  case with the world's facts REVERSED and requires a byte-identical result —
  "the innermost region" must never mean "the first solution the engine
  enumerated". Two cases are negative in the strong sense: the strip between two
  countries resolves to nothing at all, and a playthrough that has found nothing
  produces a map that says so rather than an empty one.

- `routines/*.json` — the **routine corpus** (US-4 of
  `125-npc-routines-and-locomotion`; see "Routine case format" below).
  `goals.json` pins which authored block of a routine is open at a given hour on a
  given day, what goal that puts the NPC in pursuit of, what it is worth, where it
  is pursued, the authored facts the KB carries and everything wrong with the
  authoring. `interruption.json` pins a whole lifecycle as an ordered script —
  assigned, adopted, preempted, released, picked back up — down to the
  `{ retract, assert }` each step writes, whose plan it invalidated and the save
  state it ends in. `intents.json` pins the two things core says to a host about a
  routine: where to go and how pressing it is (US-2), and what the body looks like
  doing it (US-3). It is the counterpart to `prolog/mechanic-routine.json`, which
  pins the routine *vocabulary*: no rule breaks a tie between two open blocks, runs
  a state machine or resolves an intent, so a query corpus cannot pin one.
  Regenerate with `npm run routine-resolution-corpus`; run by
  `src/conformance/__tests__/routines-corpus.test.ts`, which derives coverage from
  the pinned data rather than from a label and re-runs every case with the block
  list, the roster and the declarations REVERSED. The headless reference host that
  drives the same module end to end with no engine — the locomotion host, the agent
  action host, the arrival-failure path, the world clock and the intent→clip table
  core never sees — is `src/conformance/__tests__/headless-routine-host.ts`.

- `items/*.json` — the **item corpus** (US-4 of `124-items-equipment-economy`; see
  "Items case format" below). `equipping.json` pins whether an actor may put a
  thing on, into which slot, and what wearing it comes to; `pricing.json` pins what
  a thing costs HERE and from whom, term by named term; `transactions.json` pins
  whether a trade may happen and at what price, including a REFUSED PURCHASE;
  `placement.json` pins what a host materializes out of a world's own placement
  table, and that a hand-moved chest is the same chest. Each case carries the whole
  input — the catalogue rows it names, the WORLD's own slot table, the shelf, the
  purses, the seed and the fully resolved tuning — so a harness in any language
  reproduces it with no defaults table, no world file and no KB. It is the
  counterpart to `prolog/mechanic-equipment.json`, which pins the equipment
  *vocabulary*: no rule computes a price, a refusal, a hoard or a placement's
  identity, so a query corpus cannot pin one. Regenerate with `npm run items-corpus`;
  run by `src/conformance/__tests__/items-corpus.test.ts`, which derives coverage
  from the pinned data rather than from a label and re-runs every case with the
  slot table, the stacks, the catalogue, the placements and the loot-table entries
  REVERSED. The headless reference host that drives the same module end to end with
  no engine — the stat sink, the scene, the paper doll and the shop panel — is
  `src/conformance/__tests__/headless-items-host.ts`.

- `modules/genre-activation.json` — the **genre bundle → active Insimul module**
  table (US-3 of `111-insimul-module-contract`). Wholly derived from
  `INSIMUL_MODULES`' part-6 registrations and committed because it is what an
  engine plugin reads: given `ir.meta.genreConfig.id`, which mechanic rule packs
  to consult and which host systems to register, with no list of mechanics
  hardcoded in the plugin. Regenerate with `npm run module-activation`;
  `src/modules/__tests__/module-activation.test.ts` fails when the committed file
  and the manifest disagree, and separately proves against a real KB that a module
  the genre did not select is absent from it. See
  `packages/core/docs/module-contract.md` §7.

- `generation/bridge-cases.json` — the **generation VM's C-ABI parity corpus**
  (US-4 of `130-generation-vm-and-packs`). One case per call across the adopted
  surface — method, arguments, and either the result the TypeScript path produced
  or the classified error code a rejection must carry — so `libinsimulcore`'s
  QuickJS leg and core's V8 leg are held to one expectation instead of two
  restatements of it. Regenerate with `npm run generation-corpus`;
  `src/generation/__tests__/bridge-corpus.test.ts` fails when the committed file
  and the bridge disagree, and `bridge-bundle.test.ts` replays the same corpus
  through a real esbuild bundle in a realm with no host globals.
  **Every pack in it is a `probe/` pack built from invented tables** — a
  generation pack is closed content and never ships in an open repository
  (`npm run pack-provenance`). See `conformance/generation/README.md` and
  `packages/core/docs/generation-vm.md` §10.

## Prolog case format

Each file in `prolog/` is a JSON object:

```jsonc
{
  "area": "unification",           // semantic area this file covers
  "description": "…",              // one line, human-facing
  "cases": [
    {
      "name": "simple-fact-binding",     // unique within the file
      "kb": ["parent(tom, bob)."],       // clauses consulted before the query
      "query": "parent(tom, X)",         // a single Prolog goal (no trailing '.')
      "expected": [{ "X": "bob" }]       // see semantics below
    }
  ]
}
```

Field semantics (a conforming engine MUST reproduce these):

- **`kb`** — an array of Prolog clause strings (facts, rules, and directives such
  as `:- dynamic(counter/1).` or `:- use_module(library(lists)).`). The harness
  consults the whole array as one program before running the query. Lists-library
  predicates (`member/2`, `length/2`, `nth0/3`, …) are resident in the runtime
  engine, but cases carry `:- use_module(library(lists)).` anyway: it was
  required by tau-prolog, it is harmless here, and a conforming engine that needs
  it must not be broken by its absence.
- **`query`** — one Prolog goal, without the trailing `.`. It may be a conjunction
  (`p(X), q(Y)`) and may contain side-effecting builtins (`assertz/1`, `retract/1`)
  whose effects must be visible later in the *same* query.
- **`expected`** — the **complete set of solutions**, as an array of
  variable-binding objects:
  - `[]` — the query has **no** solutions (fails).
  - `[{}]` — the query **succeeds once with no variable bindings** (a ground/yes
    query, e.g. `member(b, [a,b,c])`).
  - `[{ "X": "bob" }, …]` — one object per solution; keys are the query's named
    variables, values are the bound atoms (as JSON strings) / integers (as JSON
    numbers). Only variables that appear **in the query goal itself** are reported;
    anonymous `_` and variables local to rule bodies never appear.

**Order-independence.** `expected` is compared as an unordered multiset — a
conforming engine need not enumerate solutions in any particular order, only
produce the same set. Do not rely on solution order in a case.

**Amendments (US-2/US-3, 91-babylon-prolog-wasm).** The corpus was authored
against tau-prolog and is deliberately left **unamended on disk**: it is the
source copy the native repos vendor byte-identically, so editing a case to please
one engine would erase the evidence downstream. Exactly one case needs a rewrite
to run, and every harness applies the SAME one, in memory, with a printed
`[AMEND]` line — never a skip:

- **`assert-retract.json::asserta-prepends`** uses `log/1` as a user dynamic
  predicate. ISO reserves `log` only as an evaluable functor, so tau-prolog
  accepted it; Trealla additionally registers the arithmetic/list functors
  (`log`, `sin`, `max`, `gcd`, `sum_list`, …) as **static builtin predicates**,
  so `asserta(log(0))` raises `permission_error(modify, static_procedure,
  log/1)`. The amendment renames the predicate to `entry`. **A new case must not
  use a Trealla builtin name as a user predicate.**

The tables live in `src/conformance/__tests__/prolog-corpus.test.ts`
(`AMENDMENTS`) here and in `tests/conformance.c`,
`rust/insimul/tests/conformance.rs` and `tests/wasm_conformance.mjs` in
`insimul-native` — keep them in lockstep. The TS runner executes every case
UNAMENDED first, so a stale entry fails as stale rather than masking a
regression. Full report and classification:
`packages/core/docs/tau-wasm-parity.md`.

## KINP identifiers in the corpus

Entity ids in the corpus are **KINP identifiers** (`koine/specs/identity.md`
§3.3), not bare atoms. The canonical Prolog form is the compound term

```prolog
id(Kind, Namespace, LocalId)     % e.g. id(ent, 'insimul:world:alderforest', 'q1')
```

with three interchangeable views of the same identifier:

| form | example |
|---|---|
| Prolog term (canonical) | `id(ent, 'insimul:world:alderforest', 'npc-renaud')` |
| CURIE (§3.2) | `insimul:world:alderforest:ent:npc-renaud` |
| IRI (§3.1) | `https://id.koine.example/ent/insimul:world:alderforest/npc-renaud` |

Insimul's binding: a world is `insimul:world:<w>`, an entity inside that world is
`insimul:world:<w>:ent:<id>` — **a world-scoped entity's namespace is its world's
own CURIE**, so the world is recoverable from the identifier alone, with no side
table and no string parsing. A global (cross-world) entity is `insimul:ent:<id>`
and a provisional offline-minted local is `insimul:local:ent:<id>` (§6).

The `<local-id>` is the collection document's sanitized Mongo `_id`. Sanitization
(`sanitizeLocalId` in `src/identity/kinp.ts`) is **lossless** — the §3.1 charset
`[a-z0-9][a-z0-9._-]*` with everything else percent-encoded — so
`_id` atom ⇄ CURIE ⇄ `id/3` term round-trips for every collection in
`COLLECTION_PROLOG_MODE`. A 24-char ObjectId hex passes through untouched.

Two corpus conventions follow from this:

- **`prolog/identity.json` (`area: kinp-identity`)** pins the accessor rules
  (`id_kind/2`, `id_namespace/2`, `id_local/2`), the legacy-atom bridge
  (`entity_id/2`, `entity_curie/2`, `curie/2`), and world scoping (`id_world/2`,
  `same_world/2`). Its `kb` clauses mirror `src/identity/identity-predicates.ts`
  verbatim — a native engine consults the same text.
- **Bindings stay scalar.** A case must never bind a query variable directly to
  an `id/3` term: the binding format (§ "Prolog case format") is atoms/numbers,
  and engines render compound terms differently. Project the column through a
  rule instead — `quest_available(L) :- quest(id(ent, _, L), _, _, _, active).`
  — exactly like the anonymous-variable rule. Literal `id/3` terms in the *query
  goal* are fine (`quest_objective(id(ent, 'insimul:world:alderforest', 'q1'),
  Idx, Goal)`), which is how `gameplay.json` addresses a specific quest.

**Amendments for the native harness (US-83 re-vendor).** `gameplay.json` was
rewritten in lockstep with this change and `identity.json` is new, so a native
harness re-vendoring the corpus must:

1. Parse compound terms in `kb`/`query` — the corpus is no longer atom-only.
   `expected` is unchanged (still scalar bindings).
2. Reproduce `libinsimul`'s JSON binding shape for compounds
   (`{"functor":…, "args":[…]}`) only if it chooses to expose them; no case
   requires it, by the scalar-binding rule above.
3. Keep the two identifier spellings distinct: `'insimul:world:alderforest'` is
   an **atom** (quoted — it contains `:`), never a term to be decomposed.

Nothing in `insimul-native` was edited from this story.

## The equivalence layer in the corpus

`prolog/equivalence.json` (`area: kinp-equivalence`) pins the KINP **equivalence
layer** (`koine/specs/identity.md` §4) — the links between identifiers that
different projects mint for the same thing. Its `kb` clauses mirror
`src/identity/equivalence-predicates.ts` verbatim, exactly as `identity.json`
mirrors the identity pack.

Links are assertions, so they carry annotations rather than bare arguments:

```prolog
based_on(id(ent, 'insimul:world:alderforest', 'npc-renaud'),
         id(ent, pinakes, 'napoleon-i'), confidence(0.8)).
same_as(id(ent, pinakes, 'napoleon-i'), id(ent, wikidata, q517),
        confidence(1.0), src('pinakes:anchor/wikidata')).
```

Both arities are legal — §4.3's worked example spells a link with
`confidence(_)` alone, §4.2's adds `src(_)` — so every rule reads links through
the single normalized `equiv_link/5`.

The whole §4.3 **firewall** is one asymmetry: `same_as_closure/2` walks
`same_as` edges only, `based_on` is never fed into it, and
`licenses_fact_transfer(same_as)` is the only such fact. A fictional entity
modeled on a real one therefore emits `based_on` and never `same_as`, its
in-fiction claims never reach the real entity (`fact_of/4`, `real_fact/3`), and
a `based_on` chain is never promoted to `same_as` by transitivity (§4.5). The
cases reproduce `koine/scenarios/e2e-worlds-to-fabric.md`'s two cross-project
queries against one graph.

Three conventions a native harness must honour:

- **Declare every link arity dynamic.** The pack declares all eight
  (`same_as/3,4`, `based_on/3,4`, `part_of/3,4`, `instance_of/3,4`) precisely so
  a partially-populated link set does not raise `existence_error` from
  `equiv_link/5`. A case that supplies only the arity-4 facts must still carry
  `:- dynamic(same_as/3).` — one case does, deliberately.
- **`kinp_member/2` is local on purpose.** The cycle-safe closure walker needs a
  membership check; using `member/2` would require `:- use_module(library(lists)).`
  in every case for any engine that does not have the module resident, so the
  pack ships its own two-clause predicate and stays library-free.
- **Bindings stay scalar**, as everywhere else: project each `id/3` column
  through `id_local/2` / `id_namespace/2` rather than binding the term.

**Amendments for the native harness (US-83 re-vendor).** In addition to the
identity-corpus amendments above:

4. `equivalence.json` is new; add `kinp-equivalence` to the required-areas list.
5. The `confidence(C)` argument binds a **float** (`0.8`), so the harness's
   binding comparison must treat JSON numbers as numbers, not strings.
6. `claim/4`'s fourth argument is the world, spelled with the ratified
   `@world(W)` context argument (see the next section) — `claim(S, P, O,
   '@world'(id(world, …)))`. US-1's/US-2's earlier bare-world spelling is gone.

Nothing in `insimul-native` was edited from this story either.

## Worlds and the `@world(W)` context argument in the corpus

`prolog/worlds.json` (`area: kinp-worlds`) pins the KINP **world model**
(`koine/specs/identity.md` §5) and the ratified context argument (§11 decision
3). Its `kb` clauses mirror `src/identity/world-predicates.ts` verbatim, exactly
as `identity.json` and `equivalence.json` mirror their packs.

Insimul's chain, and the identifier each level uses:

```
pinakes:world:consensus-reality          id(world, pinakes, 'consensus-reality')
└── insimul:world:alderforest            id(world, insimul, alderforest)
    └── insimul:world:alderforest#save-7f
                                         id(world, insimul, 'alderforest%23save-7f')
```

Editor canon is a world, a playthrough is a *child* world that forks it — not a
foreign key stamped on every row. §5 writes the playthrough separator literally
(`#save-`); §3.1's local-id charset requires percent-encoding, so the stored
local id is `<w>%23save-<id>` and `unsanitizeLocalId` recovers §5's spelling.

An assertion carries its world as an explicit argument:

```prolog
claim(id(ent, 'insimul:world:alderforest', 'npc-renaud'), garrisons,
      id(ent, 'insimul:world:alderforest', northkeep),
      '@world'(id(world, insimul, alderforest))).

?- holds(id(ent, 'insimul:world:alderforest', 'npc-renaud'), garrisons, O,
         '@world'(id(world, insimul, 'alderforest%23save-7f'))).
```

Four conventions a native harness must honour:

- **`'@world'` is a QUOTED atom used as a functor.** `@` is a symbolic
  character, so a bare `@world(W)` would need a custom prefix operator, and a
  `:- op/3` directive does not survive a KB snapshot (clauses only). Parsing
  `'@world'(X)` as an ordinary compound is all that is required.
- **Resolve the parent BEFORE the override check.** `world_resolve/4`'s second
  clause is `world_parent(W, P), world_resolve(P, S, Pr, O), \+ claim_defined(W,
  S, Pr)` in that order, so the negation always runs on ground arguments. With
  the goals swapped, an unbound `(S, P)` makes `\+ claim_defined/3` mean "W
  asserts nothing at all" and inheritance collapses — one case enumerates an
  unbound `(P, O)` at a world that does hold an override, precisely to pin this.
- **An override masks, it never rewrites.** A playthrough claim shadows the
  canon value *in the playthrough only*; `claim_at/4` (no inheritance) still
  shows the canon world holding exactly what the editor authored. The
  "never-written-back" case asserts that directly.
- **Inheritance is declared, not assumed.** A fiction reaches consensus reality
  only when a `world_parent/2` edge says so (§5: it MAY inherit) — one case runs
  the same query with the edge absent and expects no solutions. And facts never
  travel *up*: a query at consensus reality sees no in-fiction claim.

Inheritance (down a world chain) and `same_as` transfer (across identifiers) are
orthogonal: `equivalence-predicates.ts` reads `claim/4` at the world it was
asserted at and does not walk `world_parent/2`, `world-predicates.ts` walks the
chain and knows nothing about links. A KB that consults both composes them in a
rule of its own; neither pack calls into the other, so each stands alone.

**Amendments for the native harness (US-83 re-vendor).** In addition to the
amendments above:

7. `worlds.json` is new; add `kinp-worlds` to the required-areas list.
8. A world's local id may contain a percent escape (`alderforest%23save-7f`).
   It is an ordinary atom — do not decode it in the engine; decoding is a
   presentation concern (`unsanitizeLocalId`).

Nothing in `insimul-native` was edited from this story either.

## The mechanic vocabulary in the corpus

`prolog/mechanic-*.json` (seven files, areas `mechanic-combat`,
`mechanic-perception`, `mechanic-skill`, `mechanic-traversal`,
`mechanic-equipment`, `mechanic-stamina`, `mechanic-gameplay-state`) pin the
**mechanic decision vocabulary** — `packages/core/docs/mechanic-predicates.md`
§4–§9 and §10.1 — exactly as `identity.json` pins the identity pack. Each case's
`kb` mirrors the shipped rule pack in `packages/core/src/prolog/mechanics/`
verbatim: `src/conformance/__tests__/mechanic-corpus.test.ts` asserts the mirror
clause by clause, so a rule edited in the pack fails the build rather than
leaving four engines conforming to a contract core no longer implements.

This is the vocabulary layer only. Combat, stealth, skills, traversal, equipment
and stamina exist here as *decisions* — may this actor attack that one, does this
observer detect that one, is this link open, may this be equipped, can this be
afforded — and nowhere as behaviour. Hit detection, damage rolls, initiative, a
navmesh query, an animation blend and a physics impulse are host concerns and
have no predicates at all (design §11), so no case pins one.

Five conventions a native harness must honour, in addition to the general ones
above:

- **Bindings stay scalar**, as everywhere else. Every id argument in these areas
  is an atom, so no case needs a projection rule — but no case may bind a list
  either, which is why the traversal cases query `reachable/3` rather than the
  `Seen` accumulator `reachable_via/4` carries.
- **The packs are library-free, so the cases are too.** Unlike the older files,
  a mechanic case carries no `:- use_module(library(lists)).`: the packs must
  load into libinsimul, whose consult is transactional, and
  `traversal_member/2` / `equipment_sum/2` exist precisely so no list library is
  needed. A harness that adds the directive is not running what core ships.
  Note in particular that **`aggregate_all/3` is not available** — it lives in
  Trealla's `library(aggregate)` — which is why the equipment totals are
  `findall/3` + a recursive sum.
- **Every area carries a pack-only case**: its `kb` is the rule pack with **no**
  world facts, and its `expected` is `[]`. That is not a filler negative — it
  pins that a KB carrying no facts for a predicate makes the query **fail**
  rather than raise `existence_error`, which is what the packs' `:- dynamic`
  declarations buy and what lets an authored rule ask about state a save has not
  written yet. An engine that raises there fails the case, because the runner
  treats a query error as a failure of the case rather than as no solutions.
- **Every area carries a negative and a positive**, enforced by the runner
  (`AREAS_REQUIRING_A_NEGATIVE`). A permission vocabulary — `can_attack/2`,
  `can_equip/2`, `detects/2`, `can_traverse/3` — is satisfiable by an engine
  that says yes to everything unless something pins a no.
- **`traversal_link/3` is directed and never symmetrised**, and an authored
  `traversal_requires/3` goal is rebound to the *caller's* actor before it is
  called (`traversal_goal_met/2`, using `=..`). Two cases pin each; an engine
  that calls the stored term as-is passes the first and fails the second, which
  is the entire point of pinning it.

Case counts are floored per file in
`src/conformance/__tests__/prolog-corpus.test.ts` (`CASE_FLOOR`) — a floor per
file rather than one total, because a total lets one area be gutted while
another grows.

**Vendoring (US-4 AC4).** These files are **not** yet referenced by an engine
repo's vendoring manifest, and that is deliberate rather than an omission:
`tools/vendor-conformance.mjs` and the per-engine drift guards live in the engine
repositories (`insimul-native`, `insimul-godot`, unity, unreal), not in
`packages/core`, so nothing in this package can add them — the manifest edit is a
commit in each engine repo. It belongs to the **vendoring band (145)** alongside
the re-vendor of the other corpora, for the reason
`docs/editor-plugin-core-analysis.md` §5.2 records: partial, unguarded vendoring
is worse than none, because the headers then claim a parity that does not exist.
The in-repo half of the manifest — what a re-vendoring harness must add — is the
amendment list below.

**Amendments for the native harness (110 mechanic vocabulary).** In addition to
the amendments above:

9. The seven `mechanic-*.json` files are new; add `mechanic-combat`,
   `mechanic-perception`, `mechanic-skill`, `mechanic-traversal`,
   `mechanic-equipment`, `mechanic-stamina` and `mechanic-gameplay-state` to the
   required-areas list, and mirror `CASE_FLOOR` in the harness so a shrunken
   corpus fails there too.
10. No new rewrite is needed — every name in these packs was probed against the
    shipped Trealla engine by `engine-builtin-collisions.test.ts` and collides
    with no builtin, so the `AMENDMENTS` table is unchanged at one entry.

Nothing in `insimul-native` was edited from this story either.

## Radiant case format

Each file in `radiant/` is a JSON object with the same `{ area, description,
cases }` envelope as the Prolog corpus, but each case pins the output of the
**radiant quest generator** (`generateRadiantQuests`, in `src/radiant/`) rather
than a single Prolog query:

```jsonc
{
  "area": "radiant-single-slot",     // scenario this file covers
  "description": "…",                // one line, human-facing
  "cases": [
    {
      "name": "single-slot-fill-one-candidate",  // globally unique across radiant/
      "kb": [                          // world facts + `:- dynamic(...)` decls
        ":- dynamic(radiant_generated/3).",
        "threat_species(wolves)."
      ],
      "templates": [                   // the radiant_* template pack
        "radiant_template(rt_bounty, [category(bounty), title('Cull the {target}'), quest_type(bounty), difficulty(3)]).",
        "radiant_precondition(rt_bounty, target, threat_species(Target)).",
        "radiant_objective(rt_bounty, defeat(Target, 4))."
      ],
      "seed": "contract",              // RNG seed (string hashed to uint32, or a number)
      "now": 1000,                     // in-game time (seconds): cooldowns + quest id/provenance
      "maxQuests": 1,                  // OPTIONAL cap on quests generated this tick
      "expected": {
        "quests": [                    // one per generated quest, in engine output order
          {
            "questId": "radiant_rt_bounty_1000",
            "templateId": "rt_bounty",
            "content": [ "quest(…).", "quest_objective(…).", "quest_reward(…)." ],
            "factsToAssert": [ "radiant_generated(…).", "radiant_cooldown_until(…)." ],
            "factsToRetract": []
          }
        ]
      }
    }
  ]
}
```

Field semantics (a conforming engine MUST reproduce these):

- **`kb`** — world facts + rules and the `:- dynamic(radiant_generated/3).` /
  `:- dynamic(radiant_cooldown_until/2).` (and any other runtime) declarations.
  Pre-seeded `radiant_generated/3` or `radiant_cooldown_until/2` facts here model
  prior-tick state that drives exclusion / cooldown suppression.
- **`templates`** — the `radiant_*` template pack (`radiant_template/2`,
  `radiant_precondition/3`, `radiant_objective/2`, `radiant_reward/3`,
  `radiant_cooldown/2`, `radiant_exclusion/2`). The harness concatenates `kb` +
  `templates` into one program (`generateRadiantQuests(kb ⧺ templates, …)`).
- **`seed`** / **`now`** / **`maxQuests`** — the generator options. `seed` drives
  the deterministic candidate pick (a string is hashed to a uint32); `now` sets the
  quest id suffix, `radiant_generated/3` timestamp, and cooldown arithmetic;
  `maxQuests` caps the tick (templates process in sorted `TplId` order).
- **`expected.quests`** — the generated quests. `content` (quest clauses) and
  `factsToAssert` / `factsToRetract` are each compared as a **sorted set** (clause
  order within a quest is irrelevant). An empty `quests` array means the tick
  generated nothing (all templates skipped / suppressed).

**Determinism is the whole point.** Unlike the Prolog corpus (unordered solution
*set*), the radiant engine picks exactly ONE candidate per template via a seeded
RNG over the *canonically sorted* candidate list, so `(kb, templates, seed, now)`
pins an exact quest — `single-slot-fill-multi-candidate` and
`single-slot-fill-alt-seed` share a KB and differ only by seed, and the expected
giver differs accordingly. A native engine that sorts candidates or seeds its RNG
differently will diverge here — which is exactly the contract violation this
corpus exists to catch. The quest-list order is the deterministic sorted-`TplId`
order.

## AI selection case format

`ai/action-selection.json` uses the same `{ area, description, cases }` envelope
and pins one **decision tick** of the game-AI substrate
(`selectActions`, in `src/ai/action-selection.ts`):

```jsonc
{
  "area": "ai-action-selection",
  "description": "…",
  "cases": [
    {
      "name": "a-forbidden-high-utility-action-loses-to-a-permitted-low-utility-one",
      "note": "…",                     // what this case is FOR, in a sentence
      "kb": [                          // the shipped pack VERBATIM, then the case content
        ":- dynamic(action/4).",
        "candidate_action(A, Act, T) :- nonvar(A), action(Act, _, _, _), …",
        "action(brawl, 'Brawl', social, 20).",
        "forbids(hearth_taboo, npc_gorm, brawl, priest)."
      ],
      "seed": "corpus",                // string hashed to uint32, or a number
      "tick": 2,
      "agents": ["npc_gorm"],          // the roster; ORDER MUST NOT MATTER
      "weights": {                     // fully resolved UtilityWeights — no defaults table
        "appeal": 1, "targetAppeal": 0.3, "cost": 0.1,
        "bias": 0.5, "jitter": 0, "costScale": 100
      },
      "expected": {
        "tick": 2,
        "decisions": [                 // one per roster agent, sorted by agent key
          {
            "agent": "npc_gorm",
            "tick": 2,
            "selected": { "action": "brawl", "target": "patron", "utility": 0.7 },
            "considered": [            // EVERY candidate, sorted by (action, target)
              { "action": "brawl", "target": "patron", "utility": 0.7,  "permitted": true },
              { "action": "brawl", "target": "priest", "utility": 0.88, "permitted": false,
                "forbiddenBy": "hearth_taboo" }
            ]
          }
        ]
      },
      "expectedWithoutLastClause": { … } // OPTIONAL: the same case with the final
                                         // kb clause dropped — the before/after of
                                         // one authored rule
    }
  ]
}
```

Field semantics (a conforming engine MUST reproduce these):

- **`kb`** — the whole program, consulted as one. It **opens with every clause of
  `src/ai/action-predicates.ts`, in order**, so the case is self-contained;
  `src/conformance/__tests__/ai-selection-corpus.test.ts` asserts that mirror, the
  same way `mechanic-corpus.test.ts` does for the mechanic packs.
- **`weights`** — every field of `UtilityWeights`, resolved. A port reproduces a
  case without knowing this package's defaults.
- **`considered`** — every candidate the KB offered, **including the forbidden
  ones**, each with its score and gate verdict. A forbidden candidate is scored
  and then cannot be selected: permissibility is a gate, not a penalty, and at
  least one case has a forbidden candidate outscoring the winner precisely so that
  a penalty-based implementation fails.
- **`selected`** — the winner, or `null` when nothing was permissible. At least
  one case stands its agent down, so an implementation that always returns an
  action cannot satisfy the corpus.

**Determinism, and order-independence.** Scores round to four decimals. Where
`jitter` is non-zero the draw comes from a stream derived from
`(seed, tick, agent, action, target)` — length-prefixed, FNV-1a mixed, then
mulberry32, the same pair the radiant engine uses — never from one RNG advanced
per decision. A port that shares a stream across the roster reproduces every
`jitter: 0` case and fails
`jitter-on-the-roster-is-per-agent-and-per-candidate`. Ties break on the
`(action, target)` key rather than on Prolog solution order, which a native engine
may enumerate differently.

## Combat case format

`combat/resolution.json` uses the same `{ area, description, cases }` envelope and
pins one **attack resolution** (`resolveAttack`) or one **defensive action**
(`resolveDefense`), both in `src/combat/resolution.ts`:

```jsonc
{
  "area": "combat-resolution",
  "description": "…",
  "cases": [
    {
      "kind": "attack",                 // or "defense" — two doors onto ONE action table
      "name": "ranged-blocked-line-is-a-miss-not-a-new-outcome",
      "note": "…",                      // what this case is FOR, in a sentence
      "input": {
        "attacker": { "id": "knight", "health": 40, "maxHealth": 40, "alive": true,
                      "weapon": { "id": "crossbow", "damage": 14,
                                  "damageType": "piercing", "range": 20 },
                      "stamina": { "current": 60, "max": 60 } },
        "defender": { "id": "bandit", "health": 30, "maxHealth": 30, "alive": true },
        "action":   { "id": "crossbow_shot", "delivery": "projectile",
                      "range": 20, "accuracy": 0.9, "staminaCost": 6 },
        "tuning":   { "baseDamage": 10, "damageVariance": 0, … },  // FULLY resolved
        "separation": 12,               // a SCALAR, in the world's authored distance unit
        "seed": "corpus",               // string hashed to uint32, or a number
        "tick": 4,
        "legality":   { "permitted": true },                     // OPTIONAL: the KB's can_attack/2
        "lineOfFire": { "clear": false, "blockedBy": "pillar" }   // OPTIONAL: the host's probe
      },
      "threatBefore": 40,               // OPTIONAL: accumulated threat/3 before this attack
      "expected": {
        "resolution": { "outcome": "missed", "reason": "line_blocked",
                        // `breakdown` is present only when the attack connected:
                        // base → variance → critical → type → block → armour
                        "damage": 0, "staminaCost": 6, "staminaSpent": 6, … },
        "facts": { "retract": [ … ], "assert": [ … ] },   // SerializedFacts, in apply order
        "threat": 76                                      // OPTIONAL, when damage moved it
      }
    }
  ]
}
```

Field semantics (a conforming engine MUST reproduce these):

- **`input`** — everything. No defaults table, no world file, no KB: a harness in
  any language reads one object and produces one answer. The two things core
  cannot know arrive as inputs exactly as they do at runtime — `legality` is the
  rules layer's `can_attack/2` answer and `lineOfFire` is the host's
  `ITrajectoryProbe` reading. `separation` is a **scalar** in the world's authored
  distance unit (the unit `item_range/2` uses); core performs no vector math and
  assumes no handedness, up-axis or unit scale.
- **The gate order is the contract**, not an implementation detail: legality →
  state → stamina → reach → line of fire (`projectile` rows only) → accuracy →
  dodge → damage. A port that dodges before checking reach answers differently for
  an out-of-range attack.
- **`breakdown`** — base → variance → critical → type → block → armour, every
  stage. A port that agrees on the total by getting two stages wrong in opposite
  directions fails here.
- **`facts`** — what the rules layer is told, in the 110 predicate vocabulary
  (`src/combat/combat-facts.ts`). It is as much the contract as the damage was:
  combat outcomes feed reputation, witnessing, faction standing and quest state,
  and every one of those reads facts. An attack that was never made — `refused` or
  `exhausted` — produces an **empty** delta. The two lifecycle facts a death also
  owes (`deceased/3`, `cause_of_death/2`) belong to the decision layer
  (`CombatResolver`), not to the pure resolution, and are deliberately absent here.
- **Coverage** — the corpus carries at least one case each of melee hit, miss,
  ranged, dodge, mitigation, exhaustion and death, plus a **negative** case: an
  attack the rules layer forbade, whose delta is empty. The runner derives that
  coverage from each case's `expected` rather than from its name, so a case cannot
  claim coverage it does not have.

**Determinism.** Every roll comes from a stream derived from
`(seed, tick, attacker, defender, action, phase)` — length-prefixed, FNV-1a mixed,
then mulberry32 — with one stream per phase (`accuracy`, `dodge`, `variance`,
`critical`), never one RNG advanced per attack. Intermediate damage rounds to four
decimals and the final integer is half-up, stated explicitly because `health/3` is
integral and a native engine using banker's rounding would disagree at exactly
`x.5`.

`combat/action-table.json` uses the same envelope for a different function
(`CombatActionTable.loadFromIR`): `actions` is the shared action block
(`systems.actions`), `combat` is combat's COLUMNS on those same rows
(`WorldIR.combat.actions`) — never a second table — and `expected` is the loaded
rows, the `action_range/2` facts the table publishes back into the KB, and the two
shape queries (`projectiles`, `defensive`). The precedence pinned is **combat
column → shared row → unset**, where a `0` on the shared row means unset (`ActionIR`
defaults it to `0`) and a `0` in a column was authored.

## Stealth case format

`stealth/detection.json` uses the same `{ area, description, cases }` envelope and
pins one **detection tick** (`runDetection`, in `src/perception/detection.ts`):

```jsonc
{
  "area": "stealth-detection",
  "description": "…",
  "cases": [
    {
      "name": "the-belief-is-not-refreshed-on-a-tick-nobody-perceived",
      "note": "…",                       // what this case is FOR, in a sentence
      "input": {
        "seed": "corpus",                // string hashed to uint32, or a number
        "tick": 7,
        "playthrough": { "kind": "world", "namespace": "insimul", "localId": "…" },
        "observers": [                   // senses are the SUBSTRATE's vocabulary
          { "agent": {…}, "senses": [{ "channel": "sight", "acuity": 1 }],
            "distraction": 80 }          // OPTIONAL, 0–100, the OBSERVER's parameter
        ],
        "targets": [
          { "id": {…}, "location": {…},  // a location id, NEVER a coordinate
            "coarseLocation": {…},       // what a PARTIAL perception learns instead
            "light": 100, "stance": "standing", "noise": 0, "concealed": false }
        ],
        "readings": [                    // the host's IPerceptionProbe answers
          { "observer": {…}, "target": {…}, "visibility": 1,
            "cover": 0.2, "audibility": 1 }
        ],
        "acts": [ … ],                   // OPTIONAL: acts published into this tick
        "memory": [ … ],                 // what every pair believed last tick
        "tuning": { … }                  // FULLY resolved DetectionTuning
      },
      "expected": {
        "updates": [ { "observer": "…", "target": "…", "awarenessBefore": 60,
                       "awareness": 54, "stateBefore": "searching",
                       "state": "searching", "changed": false, "channels": [],
                       "confidence": 0, "believedLocation": "…:ent:vault",
                       "believedAt": 5, "beliefRefreshed": false } ],
        "memory": [ … ],                 // what the NEXT tick carries in
        "facts": { "retract": [ … ], "assert": [ … ] },   // clause text, in apply order
        "perceptions": [ … ],            // ai/perception.ts's own output, verbatim
        "beliefFacts": [ … ], "perceptFacts": [ … ], "perceivedFacts": [ … ]
      }
    }
  ]
}
```

Field semantics (a conforming engine MUST reproduce these):

- **`input`** — everything. No defaults table, no world file, no KB. The one thing
  core cannot know arrives as an input exactly as it does at runtime: a
  `SensorReading` is what the host's `IPerceptionProbe` answered, and `light`,
  `stance`, `noise` and `concealed` are the host's measurements of the target.
  Core performs no geometry, holds no position and reads no clock.
- **A pair with no reading was not sensed at all**, which is different from sensed
  badly — so it produces **no update**, not an update at awareness zero. Three
  cases are negative in exactly that way, for three different reasons (no reading,
  light below the authored floor, a sense the creature lacks), and the runner
  requires all three.
- **The ladder is graded and the hysteresis is two-sided.** Rising is immediate —
  a level that crosses the top band lands on `alerted` without passing through the
  rungs between — while falling holds the current rung until the level is the
  authored `hysteresis` margin below the band that reached it. Both directions are
  pinned; an implementation that compares against the bare threshold passes the
  rising cases and fails the holding one.
- **`unaware` is never asserted.** It is the absence of a `detection_state/3`
  fact, so a tick that moved neither the level nor the rung writes **nothing**.
- **`believedLocation` is not the target's location.** It is refreshed only on a
  tick that observer perceived that target, and one case has the target genuinely
  moved so the belief is not merely old but wrong. An implementation that reads the
  target's true location on the observer's behalf pins the wrong room here and has
  no stealth mechanic at all.
- **The perception pass is the substrate's, verbatim.** Detection runs no second
  sensing model, so `perceptions` / `beliefFacts` / `perceptFacts` /
  `perceivedFacts` are `src/ai/perception.ts`'s output unchanged — including the
  asymmetry corrected in `docs/game-ai-substrate.md` §9: an act nobody perceived
  publishes `percept_actor/2` and `percept_channel/2` (it HAPPENED) and no
  `percept/4` (nobody learned WHAT).

**Determinism, and order-independence.** Awareness is integer; confidences round
to four decimals. Every draw comes from a stream derived from `(seed, tick, agent
CURIE, percept id)` — never from call order — so the runner re-runs every case
with the observers, targets, readings, acts and memory all REVERSED and requires a
byte-identical result. One case leaves the authored jitter ON, which is what makes
the streams load-bearing rather than incidental.

`stealth/actions.json` uses the same envelope for a different function
(`StealthActionTable.loadFromIR`): `actions` is the shared action block
(`systems.actions`), `columns` is stealth's COLUMNS on those same rows
(`WorldIR.perception.actions`) — never a second table — and `expected` is the
loaded rows, the four SHARED facts the table publishes back (`action/4`,
`action_category/2`, `action_requires_target/1`, `action_target_type/2`, and
deliberately nothing stealth invented), what performing each row changes, and the
percept each row publishes the act as. The precedence pinned is **stealth column →
shared row → unset**. A row that authored no `presence` yields `null` for its
percept: an act that presents on no sense is one nobody can witness, which is an
authoring and not a degradation.

## Traversal case format

The three files in `traversal/` use the same `{ area, description, cases }` envelope
and pin the three halves of the mechanic where the core/host line is hardest to
hold. **There is no position, no transform, no path, no speed and no frame anywhere
in them**, and the runner asserts that of the pinned data rather than trusting it:
core owns WHERE an actor may go and what it COSTS, and where they are this frame is
the host's entirely.

### `affordances.json` (`area: traversal-affordances`)

```jsonc
{
  "area": "traversal-affordances",
  "cases": [
    {
      "name": "an-almost-empty-meter-refuses-the-swim-and-not-the-walk",
      "note": "…",                       // what this case is FOR, in a sentence
      "input": {
        "actor": "wren",
        "from": "riverside_camp",        // a location ATOM, never a coordinate
        "links": [                       // the authored traversal_link/3 graph, DIRECTED
          { "from": "riverside_camp", "to": "far_bank", "mode": "swim",
            "cost": 6, "requires": ["has_item(rope, 1)"] },
          { "from": "ford_path", "to": "far_bank", "mode": "jump",
            "cost": 3, "geometric": true }
        ],
        "modes": ["walk", "swim"],       // movement_mode(Actor, Mode)
        "blocked": [ { "from": "…", "to": "…" } ],   // traversal_blocked/2, runtime
        "geometry": { "ford_path>far_bank:jump": false },  // the host's ITraversalProbe
        "stamina": { "current": 5, "max": 60 },      // 120's SHARED energy/3 meter
        "tuning": { … }                  // FULLY resolved TraversalTuning
      },
      "best": "far_bank",                // the destination bestAffordance is asked for
      "route": { "to": "ridge", "maxSteps": 32 },    // or null
      "expected": {
        "affordances": [ { "id": "…", "from": "…", "to": "…", "mode": "swim",
                           "action": "swim", "cost": 15, "available": false,
                           "refusal": "stamina", "requires": ["…"],
                           "conditional": true } ],
        "best": { … },                   // or null
        "route": { "from": "…", "to": "…", "steps": [ … ], "cost": 10,
                   "conditional": false },   // or null
        "graphFacts": [ "traversal_link(…).", "traversal_cost(…).",
                        "traversal_requires(…)." ]
      }
    }
  ]
}
```

Field semantics (a conforming engine MUST reproduce these):

- **`input`** — everything. No defaults table, no world file, no KB. The two things
  core cannot know arrive as inputs exactly as they do at runtime: `geometry` is what
  the host's `ITraversalProbe` answered per link id, and `stamina` is what 120's
  shared meter held. A geometric link with **no** `geometry` entry is passable, which
  is the documented fallback a headless world runs on.
- **Refused ways are KEPT, not filtered.** `expected.affordances` is every authored
  link out of `from`, sorted by `(to, mode, id)`. A UI greys the ford out and says
  why, and the runner checks the pinned count against the graph.
- **The refusal order is the contract**, not an implementation detail: `unreachable`
  → `blocked` → `mode` → `impassable` → `stamina` → `requires` → `forbidden`.
  Everything core can settle alone comes first, cheapest and most definite first. The
  last two **never appear in this file**: they are the rules layer's, and a pure
  function may not call a KB — a link carrying an authored `traversal_requires/3`
  goal resolves `available` AND `conditional`, which means "nothing core knows
  refuses it, and something core cannot evaluate might".
- **Cost is per LINK; the published fact is per EDGE.** `traversal_cost/3` takes no
  mode, so `graphFacts` carries the **cheapest resolved** way across each edge while
  the affordance carries what its own link costs — a port that publishes one number
  per link makes core and `can_traverse/3` disagree. Every cost is the authored
  number times the mode multiplier, floored to an integer, never below zero.
- **`route`** is uniform-cost search with a fully-specified tie-break — cost, then
  fewer legs, then the canonically-first destination, mode and link id — so four
  engines agree on which way they went and not merely on whether they got there. The
  cheapest route may be the longest; `maxSteps` is a hang guard and a bound that
  finds nothing returns `null` rather than a truncated route.

**Order-independence.** The runner re-runs every case with the link list, the modes
and the closures REVERSED and requires a byte-identical result (the graph facts are
emitted in authoring order, so they are compared as a set). A same-order re-run
passes under an implementation whose route search depends on authoring order, which
is the trap the tie-break exists to close.

### `vehicles.json` (`area: traversal-vehicles`)

One case is one authored `Vehicle`, its `VehicleState`, an actor, where the **actor**
is, and one of the three verbs. `expected` carries the resolution, the state the verb
produced (`next: null` for a refused verb, so a caller cannot apply a transition core
did not afford), the action atoms the verbs are gated as, the seat count, the
authored `vehicle_mode/2` fact, the facts the prior state asserts, the `{ retract,
assert }` delta **computed by diffing the two states**, and `anothers` — whether the
hull is somebody else's.

- **Colocation is asked of the ATOMS**, never of a distance: a host that knows the
  rider is three metres from the horse resolves that to a location and hands over the
  name. There is no radius in the module and nothing to author one on.
- **The refusal order is again the contract**: `unknown` → `elsewhere` → `full` →
  `not_aboard` → `occupied` → `redundant` → `forbidden`. `unknown` never appears (a
  pure function is handed a vehicle; it belongs to `VehicleRegistry`) and `forbidden`
  never appears (permissibility is `forbids/4`'s). What this file supplies instead is
  `anothers`, the **fact** a theft norm is authored over — and an unowned cart is
  `false`, because core does not invent a prohibition.
- **A vehicle has no speed, handling, fuel or mesh**, and there is no field to author
  one on. Its whole traversal meaning is the mode it lends its driver
  (`docs/mechanic-predicates.md` §12), which is why `grants` is present on `drive` and
  on neither other verb. A vehicle never moves on a verb: it moves when whoever is
  driving it arrives somewhere.

### `fast-travel.json` (`area: traversal-fast-travel`)

One case is a whole journey: the authored graph, the traveller's modes, the closures,
the seed, the journey **ordinal**, and both fully resolved tunings.

- **The route is found first, by the same search a walk uses.** A journey is only
  ever offered along a way the actor could have walked, so a landslide on the only
  pass refuses the fast travel too — two cases pin exactly that with `plan: null`,
  for two different reasons (a closure, and a mode the traveller lacks).
- **`hours`** is the route cost times the world's `hoursPerCost`, floored, clamped up
  to `minimumHours` and down to `ceiling`.
- **`ceiling` is the SMALLER of `maxHours` and `stepHours × maxSteps`**, because the
  two bound different things — how much the world moves, and how many times the
  dependent systems are woken to move it — and cases pin each of them winning. A
  journey longer than the ceiling is truncated and reported `capped`, never refused.
- **`steps` sum to `hours` exactly**, with the last advance carrying the remainder,
  and each carries a `draw` in `[0, 1)` derived from `(seed, actor, from, to, journey
  ordinal, step index)` and rounded to four places — never a shared RNG advanced per
  step. Two cases differ only by the ordinal and must not share a draw, which is why
  the ordinal rides in the save.
- **`plan.cost` is what walking it would have cost, and is not charged.** A journey
  spends TIME; a simulation that passed a day and a half and emptied the meter has
  charged for the trip twice.
- **There is no journey predicate.** What a fast travel does to the world is that the
  CLOCK moved and everything downstream of it ran, so the only deltas are
  `at_location/2` and `location_discovered/1` — both predicates that already existed.
  Discovery is additive and idempotent, so re-finding a place writes nothing.

## Skill case format

The four files in `skills/` use the same `{ area, description, cases }` envelope and
pin the four halves of a mechanic that is deliberately **data over** the other
modules rather than a system inside them. Two properties hold across all of them:
every case is self-contained down to the fully resolved `SkillTuning`, and **no
pinned pure resolution ever carries the refusal `requires` or `forbidden`** — both
are the rules layer's, a pure function may not call a KB, and a corpus that pinned
one would be pinning a guess. `trees.json` carries both, because a view is *handed*
the KB's answers.

### `advancement.json` (`area: skills-advancement`)

```jsonc
{
  "name": "the-bank-is-what-is-unspent",
  "note": "…",                          // what this case is FOR, in a sentence
  "input": {
    "actor": "wren",
    "skill": { "id": "masonry", "category": "craft", "maxLevel": 4,
               "levelXp": [0, 0, 40, 120, 300], "requires": [] },  // null = undeclared
    "level": 1,                          // has_skill(Actor, SkillId, Level); 0 = not learned
    "banked": 40,                        // skill_xp/3 — what is UNSPENT
    "levels": { "masonry": 1 },          // every level held, for the skill_requires/3 check
    "tuning": { … }                      // FULLY resolved SkillTuning
  },
  "expected": {
    "resolution": { … },                 // resolveAdvance, refusal in SKILL_ADVANCE_REFUSALS order
    "curve": [0, 0, 40, 120, 300, 300],  // every level 0..cap+1 PRICED, last entry repeating
    "maxLevel": 4
  }
}
```

### `unlocks.json` (`area: skills-unlocks`)

```jsonc
{
  "input": {
    "actor": "wren",
    "node": { "id": "guild_seal", "tree": "stonework", "parents": ["keystone_sense"],
              "requires": ["reputation_at_least(Actor, masons_guild, 40)"],
              "effects": [ { "kind": "permits", "args": ["seal_a_vault"] } ] },
    "points": 3,                         // skill_points(Actor, TreeId, Points) — per TREE
    "unlocked": false,                   // whether skill_unlocked/2 already holds
    "tuning": { … }
  },
  "expected": {
    "resolution": { … },                 // available AND conditional can both be true
    "requirements": [                    // ONE gate: an authored goal, and a parent desugared
      "reputation_at_least(Actor, masons_guild, 40)",
      "skill_unlocked(Actor, keystone_sense)"
    ],
    "cost": 1
  }
}
```

### `effects.json` (`area: skills-effects`)

```jsonc
{
  "input": {
    "effects": [ { "kind": "modifies", "args": ["damage", 2] },
                 { "kind": "sings",    "args": ["the_masons_round"] } ],  // the kind set is OPEN
    "snapshot": { "id": "heavy_swing", "damage": 7 },   // what the module was already resolving from
    "parameter": "damage"
  },
  "expected": {
    "modifiers": { "damage": 2 },        // summed per parameter, ADDITIVE, never multiplied
    "unlocks": [], "permits": [],        // the atom read-out for a host with no KB
    "modified": { "id": "heavy_swing", "damage": 9 },   // the snapshot, COPIED
    "modifierOf": 2
  }
}
```

### `trees.json` (`area: skills-trees`)

```jsonc
{
  "input": {
    "trees": [ … ], "skills": [ … ], "tuning": { … },
    "actor": { "id": "corvin", "levels": { … }, "xp": { … }, "points": { … },
               "unlocked": ["true_chisel"],
               "unmet": { "chapter_key": ["sworn_to(Actor, masons_guild)"] },  // the KB's
               "forbidden": ["guild_seal"] }                                    // the KB's
  },
  "expected": {
    "view": [ { "id": "stonework", "label": "The Stonework",
                "nodes": [ { "id": "…", "label": "…", "depth": 1, "cost": 2,
                             "taken": false, "available": true, "conditional": true,
                             "refusal": "…", "unlocks": [], "permits": [],
                             "modifies": [ { "param": "damage", "amount": 1 } ] } ],
                "rows": [ ["…"], ["…"] ],      // node ids by depth — DERIVED from the edges
                "edges": [ { "from": "…", "to": "…" } ] } ],
    "funded": ["stonework"],             // skill_tree(TreeId, SkillId) read backwards
    "depths": { "…": 0 }
  }
}
```

A `label` falls back to the node's own id, so a half-authored tree is still
inspectable rather than a row of blank boxes; `rows` and `depth` come from the
authored parent edges and never from an authored `tier`, because a second statement
of the tree's shape can disagree with the first.

## Routine case format

The three files in `routines/` use the same `{ area, description, cases }` envelope
and pin the three claims `125-npc-routines-and-locomotion` made. Two properties hold
across all of them: every case is self-contained down to the fully resolved tuning,
and **there is no clip, no path, no speed and no coordinate anywhere in them** — the
runner asserts that of the pinned data rather than trusting it, because a routine is
where an animation and a navmesh would arrive in core if anything let them.

### `goals.json` (`area: routine-goals`)

```jsonc
{
  "area": "routine-goals",
  "cases": [
    {
      "name": "two-blocks-at-one-priority-break-on-the-block-id",
      "note": "…",                        // what this case is FOR, in a sentence
      "input": {
        "routines": { "routines": [ … ],  // the authored WorldIR.routines section
                      "defaultPriority": 50, "weekLength": 7 },
        "tuning": { "defaultPriority": 50, "weekLength": 7 },   // FULLY resolved
        "routine": "night_watch",         // which routine the NPC follows
        "agent": "npc_smith",             // only ever used to spell the adopted fact
        "clock": { "day": 1, "hour": 7 }  // the HOST's clock. Core holds none.
      },
      "expected": {
        "resolved": { "id": "…", "name": "…", "blocks": [ … ] },  // every default applied
        "weekday": 1,                     // day_number mod weekLength
        "due": ["drill", "stand_down"],   // every block whose time condition holds, best first
        "active": "drill",
        "goal": "train", "priority": 30, "destination": "yard",
        "graphFacts": [ "routine_week_length(7).", "routine_block_window(…)." ],
        "issues": [],                     // everything wrong with the authoring
        "delta": { "retract": [], "assert": ["agent_goal(npc_smith, train, 30)."] }
      }
    }
  ]
}
```

Field semantics (a conforming engine MUST reproduce these):

- **A window WRAPS when `endHour <= startHour`**, so the night watch is one block
  rather than two, and a window whose ends coincide is the whole day. Three cases
  pin it; an implementation that compared `start <= hour < end` finds nothing at two
  in the morning.
- **`due` is sorted by priority descending, ties broken on the block id** — never on
  authoring order, because "which of two overlapping blocks wins" is a decision a
  save file and four engines have to agree on. The runner re-runs every case with
  the block list REVERSED and requires a byte-identical answer.
- **A block with no `routine_block_day/2` fact runs every day**, so a daily block
  emits *no* day facts at all: the absence is the meaning, in the pack and in the
  resolved block alike.
- **`routine_block_priority/2` carries the RESOLVED number**, so a rule reading it
  and core adopting the goal cannot disagree about what a block is worth.
- **A gap is an ANSWER.** Two cases fall at an hour the routine says nothing about:
  `due` is empty, nothing is adopted, and the delta is empty in both directions. An
  implementation that must always have a block is a scheduler.
- **A block with no goal is DROPPED, not defaulted**, and an unsatisfiable authoring
  (one goal pursued in two places, an hour no clock can match, a weekday outside the
  world's week) is REPORTED in `issues` while the routine keeps running. A creator's
  mistake is a report, not a crash.
- **`delta` is one `agent_goal/3` fact and nothing else.** There is no routine
  action, no routine step and no routine dispatch; the runner checks every pinned
  clause against the three predicates the module owns.

### `interruption.json` (`area: routine-interruption`)

One case is a whole lifecycle: an authored world, a roster, and an ordered `steps`
script of `assign` / `tick` / `preempt` / `resume` / `forget`. `expected.steps` gives
the per-NPC outcomes of each tick, the `{ retract, assert }` that step wrote, and the
plan invalidations it caused; `expected.facts` is everything the KB holds at the end
and `expected.state` is the save.

- **Resumption is not replay.** A release adopts whichever block is due **then**, so
  a smith dragged into a fight at half past five takes supper at seven rather than
  going back to the anvil. An implementation that queued the interrupted goal
  reproduces every fact except the last two.
- **A preemption invalidates the PLAN and never the goal.** The pinned interrupts
  carry `ai/planner.ts`'s own reasons (`external`, `step-blocked`, …), and no pinned
  delta ever retracts a goal the routine did not adopt — which is what lets the
  interrupting goal simply *be* the top goal rather than fight for it.
- **Preempting a preempted routine keeps the FIRST reason**, and releasing one
  nobody preempted writes nothing.
- **A tick that changed nothing writes nothing.** Pinned explicitly: a module that
  re-asserted its goal every tick would put every NPC in the world on the save path
  once an hour.
- **The roster order may not matter.** The runner re-runs every case with the roster
  REVERSED; the outcomes, the final facts and the save state must be identical, and
  the per-step delta identical as a set (the writes happen per NPC in the order the
  caller passed).

### `intents.json` (`area: routine-intents`)

One case is one actor, where they are, where core wants them, what the goal is worth,
how many times they have already failed to get there, and the action about to be
dispatched. `expected` is the `MovementIntent` (or `null`), whether it is already
satisfied, the urgency rung, whether this many failures re-plans, and the animation
intent.

- **The intent is four atoms and nothing else** — `actor`, `from`, `destination`,
  `urgency`, `stance` — and the runner deep-equals the key set, because a field on
  the intent is a field a coordinate could arrive on.
- **Urgency comes from the goal's OWN `agent_goal/3` priority**, against an authored
  ladder (`hurriedAt`, `urgentAt`, `idleAt`), tested highest rung first so a world
  that authored `urgentAt` below `hurriedAt` gets a legible answer rather than an
  unreachable rung. A goal that named no priority is `ordinary`, never `idle`.
- **Three ways the intent is `null`, and each is a real answer**: the routine is
  preempted, the block names no place, or nobody has told core where the actor is.
  An actor already AT the destination still gets an intent — being somewhere is a
  state a host may present.
- **The animation intent resolves authored → catalogue → `idle`.** An action a world
  invented animates because the world said what it looks like; an atom outside the
  closed vocabulary is IGNORED rather than passed through, which is pinned with a
  case whose declaration is a clip name that got as far as the export.

## Map case format

The two files in `map/` use the same `{ area, description, cases }` envelope, with
a `note` per case saying what it is for. They are hand-authored as data — nothing
in this corpus is generated — and between them they cover the two halves of the
map layer: what the KB answers, and what an engine draws.

### `resolution.json` (`area: map-resolution`)

Each case carries the WHOLE input: `world` (the country/state/settlement blocks as
the importer writes them, plus the extents `geo/regions.ts` mints from the World
IR) and a `position`. A harness consults `src/geo/region-predicates.ts`, adds
`world`, asks about `position` and diffs the `RegionResolution` against `expected`.

- **Positions are in WORLD units; every fact is in GRID units.** A coordinate
  crosses onto the ×100 integer grid inside the reader, through the one function
  that rounds — so a corpus in world units on both sides would be pinning a
  rounding mode instead of a border.
- **Every case is re-run with `world` REVERSED**, and must produce a
  byte-identical resolution. The twin-states case (two states with identical
  bounds, both containing the point) is where "first solution" and "smallest, then
  atom order" visibly disagree.
- **A conflict is reported BESIDE an answer, never instead of one.** The misplaced
  settlement case yields the chain its documents name *and* names the country the
  ground says it is standing in.
- **Zero is an answer.** The strip between two countries resolves to an empty
  resolution rather than to an error or to the nearest region.

### `surface.json` (`area: map-surface`)

Each case is a whole `MapSurfaceInput` and the whole `MapSurface` it produces.
`buildMapSurface` is pure, so a harness needs no KB, no world file and no defaults
table.

- **Region extents arrive in world units and leave on the grid**; timeline entries
  arrive on the grid already, because that is what `regionTimeline()` returns.
  Both must land in the same units or a time control makes a border jump.
- **A region with no timeline gets one border with `start: null, end: null`.**
  Silence inherits: a world that authored no political history draws identically
  at every time.
- **Nothing is hidden.** A marker in undiscovered land is reported with
  `discovered: false`. The runner also scans both files for the vocabulary of
  rendering — a pinned colour, mesh or projection would mean the contract had
  crossed the core/host line with every test still green.

## Items case format

The four files in `items/` use the same `{ area, description, cases }` envelope and
pin the four decisions the equipment module makes that no rule computes. Two
properties hold across all of them: every case is self-contained down to the fully
resolved tuning, and **no pinned resolution ever carries the refusal `forbidden`** —
permissibility is `forbids/4`'s, a pure function may not call a KB, and a corpus
that pinned one would be pinning a guess. `headless-items-host.test.ts` is where
that rung appears, because that is where a KB exists.

### `equipping.json` (`area: items-equipping`)

```jsonc
{
  "name": "a-cloak-into-a-slot-no-engine-was-compiled-with",
  "note": "…",                          // what this case is FOR, in a sentence
  "input": {
    "actor": "wren",
    "item": { "id": "pilgrims_cloak", "equipSlot": "back", "armor": 1,
              "requires": [], "effects": { … }, … },   // null = the catalogue declares none
    "slots": [ { "id": "back", "name": "Back", "capacity": 1, "order": 3 } ],  // the WORLD's table
    "occupied": 0,                       // how many already occupy that slot
    "held": true, "equipped": false,     // has_item/3, has_equipped/3
    "levels": { "heavy_armour": 2 },     // for the item_requires/3 check
    "stacks": [ { "item": "…", "place": { "kind": "inventory", "holder": "wren" },
                  "quantity": 1 } ],     // the whole ledger, as data
    "catalogue": [ … ], "tuning": { … }  // FULLY resolved ItemTuning
  },
  "expected": {
    "resolution": { … },                 // resolveEquip, refusal in EQUIP_REFUSALS order
    "unmet": [],                         // the item_requires/3 rows not satisfied
    "facts": ["has_equipped(wren, chest, steel_cuirass).",
              "has_item(wren, steel_cuirass, 1)."],    // every stack in the 110 vocabulary
    "worn": ["steel_cuirass"],           // in the world's AUTHORED slot order
    "weight": 41, "encumbered": true, "armor": 7,
    "modifiers": { "defense": 4 }        // keyed by the AUTHORED parameter atom
  }
}
```

An equipped stack says **two** true things (`has_equipped/3` and `has_item/3`),
because `carried_weight/2` sums the latter: if wearing a breastplate retracted it,
thirty units of steel would weigh nothing the moment it went on.

### `pricing.json` (`area: items-pricing`)

```jsonc
{
  "input": {
    "actor": "brannoc",
    "item": { "id": "steel_sword", "value": 100, "sellValue": 50, … },
    "direction": "buy",                  // or "sell" — the mirror, not a second formula
    "quantity": 1,
    "market": {                          // null = the documented no-economy path
      "vendor": { "id": "hilde", "business": "ironmongers", "markupPercent": 20, … },
      "owner": "tomas",                  // business_owner/2
      "stock": 4, "stockNormal": 20,     // container_contains/3 against item_stock_normal/2
      "standing": 100, "faction": "town_watch"          // reputation/3
    },
    "tuning": { … }                      // FULLY resolved EconomyTuning
  },
  "expected": {
    "price": {
      "base": 100,                       // item_value/2 — the AUTHORED value, never moved
      "adjustments": [ { "factor": "markup", "percent": 20, "amount": 20,
                         "subject": "ironmongers" } ],   // in PRICE_FACTORS order
      "unit": 95, "quantity": 1, "total": 95,
      "fallback": false                  // true = no simulation was supplied at all
    }
  }
}
```

Every term is a percentage of the **authored base** rather than of a running total,
so term order cannot make two engines disagree, and every percentage is applied per
unit with the quantity multiplied last. Two cases share an item, a vendor, a
direction and a shelf and disagree about the coin: that pair is the corpus's
sharpest claim, and a port that reads a price off `item_value/2` reproduces one of
them and not the other.

### `transactions.json` (`area: items-transactions`)

```jsonc
{
  "input": {
    "actor": "wren", "item": { … }, "direction": "buy", "quantity": 1,
    "market": { … },                     // null = no economy; `vendorId` then names the trader
    "supply": 4,                         // the shelf on a purchase, the pack on a sale
    "actorGold": 90,                     // gold/2 — ABSENT means nobody read it
    "vendorGold": 300,
    "tuning": { … }
  },
  "expected": {
    "resolution": { … }                  // resolveTransaction, TRANSACTION_REFUSALS order,
                                         // carrying the whole PriceResolution and the
                                         // action atom the gate will be asked about
  }
}
```

Money fails **open** when it was never read and **closed** once it was: inventing an
empty purse would refuse every purchase in a world whose host holds the money. A
refused transaction still reports its price, because a greyed-out button still has
one.

### `placement.json` (`area: items-placement`)

```jsonc
{
  "input": {
    "ir": { "lootDraws": 3, "lootDepth": 2,
            "placements": [ { "id": "barrow_chest_01", "locationId": "barrow_deep",
                              "position": { "x": 2, "y": 0, "z": 8 },
                              "container": { "type": "chest", "locked": true,
                                             "keyItem": "iron_key",
                                             "lootTable": "barrow_hoard" } } ] },
    "lootTables": [ … ],                 // systems.lootTables rows, verbatim
    "catalogue": [ … ], "seed": "barrow-01", "cycle": 0
  },
  "expected": {
    "tuning": { "lootDraws": 3, "lootDepth": 2 },
    "placements": [ … ],                 // resolved, in canonical id order
    "places": { "barrow_chest_01": { "kind": "world", "holder": "barrow_deep" } },
    "containers": ["barrow_chest_01"],
    "loot": { "barrow_chest_01": { "entries": [ { "item": "arrow", "quantity": 4 } ],
                                   "gold": 23 } }
  }
}
```

A placement `id` is the **scene node's `entityId`** and therefore the re-import
diff's match key; the item atom is what core resolves it back to, and the two are
never the same string. One pair of cases is the same barrow with the chest moved
three metres and turned around: same id, same place, same hoard down to the coin —
which is a creator's hand-adjusted placement surviving a regeneration, as data.

## Content-library fixture format

Unlike the `prolog/` and `radiant/` corpora (a `{ area, description, cases }`
envelope of input→expected pairs), each file in `content-library/` **is** a
content library — a whole artifact, exactly as an editor would publish it and an
importer would read it. The schema is `contentLibrarySchema`
(`src/schemas/content-library.schema.ts`, US-CL1); the JSON Schema counterpart
is `schemas/content-library.schema.json`.

```jsonc
{
  "manifest": {
    "contractVersion": "insimul-content-library-v1",  // z.literal — a stale value is REJECTED
    "libraryId": "lib-riverside-starter",             // unique to its publisher
    "name": "Riverside Starter Pack",
    "version": 3,                                     // the library's own monotonic revision
    "generatedAt": "2026-07-22T00:00:00.000Z",
    "provenance": { "source": "insimul-editor", "license": "CC-BY-SA-4.0" }  // both REQUIRED
  },
  "items": [ { "id": "…", "name": "…", "itemType": "…" } ],
  "quests": [ { "id": "…", "title": "…", "questType": "…" } ],
  "characters": [ { "id": "…", "name": "…" } ],
  "towns": [ { "id": "…", "name": "…", "settlementType": "…" } ],
  "narratives": [ { "id": "…", "title": "…" } ],
  "prologFacts": [ "settlement(town_riverside)." ]    // OPTIONAL KB slice
}
```

Field semantics (a conforming importer MUST honour these):

- **All five section headers are REQUIRED.** An empty array is how a library says
  "no content of this kind" — same discipline as the WorldIR section headers — so
  an importer iterates the five kinds without presence checks. Only `prologFacts`
  is optional. `minimal.json` pins exactly this case.
- **Cross-references are library-scoped ids**, never world/db ids: a quest's
  `assignedBy` → a `characters[].id`, its `prerequisiteQuestIds` → `quests[].id`,
  a character's `homeTownId` → `towns[].id`, a town's `mayorId` →
  `characters[].id`. An importer resolves the whole entity graph from the artifact
  alone and remaps to its own ids on import. Ids are unique within each section.
- **Every definition is `.passthrough()`**, so parsing is lossless — fields the
  schema has not tightened yet (a lot's `buildingType`, a business's `ownerId`, an
  objective's shape) reach the importer intact. Only a MISSING required key fails.
  The corpus runner asserts `parse(raw)` deep-equals `raw` to keep this true.
- **`prologFacts`** must use only predicate-schema-registered predicates
  (`getCurrentPredicateSchema()`), validated fact-by-fact via `validatePrologFact`
  — an unregistered predicate would not be world-portable.

`riverside-starter.json` is the full-coverage golden: every kind populated, every
cross-reference resolving, a KB slice attached. Add fixtures here whenever a new
authored shape becomes load-bearing for import.

## Editor fixture format

`editor/` breaks the `{ area, description, cases }` envelope in the same way
`content-library/` does: each file is one capability's whole contract, because
placement and re-import take a *document* as input rather than a list of small
cases. All three carry `area` + `description` + `version`, and every derived
`expected*` value is machine-generated (`npm run editor-goldens`,
`scripts/emit-editor-goldens.ts`) while every INPUT and every hand-written
per-class id list is authored — so the corpus can never degrade into proving that
the code agrees with itself.

### `binding-resolver.json`

```jsonc
{
  "area": "editor-binding",
  "sources": [ { "name": "project", "priority": 100, "entries": [ { "key": "…", "scene": "…" } ] } ],
  "cases": [
    { "name": "…", "query": "building.residential.house",
      "expect": { "source": "project", "key": "building.residential.house",
                  "assetRef": "…" } },          // assetRef OPTIONAL; `expect: null` = unresolved
    { "name": "…", "sources": [ … ], "query": "…", "expect": … }   // per-case source override
  ],
  "unboundCases": [
    { "name": "…", "usedKeys": ["…"],
      "expect": { "requestedCount": 3, "boundCount": 1, "missingKeys": ["…"] } }
  ]
}
```

The default `sources` block and the first nine cases ARE the shared resolver
matrix Unreal and Godot each vendor (`unreal .../Tests/fixtures/resolver-matrix.json`,
`godot .../binding/fixtures/resolver-matrix.json`); Unity had no copy, which is
how the tie-break drifted. Semantics a conforming engine MUST reproduce:

- the chain is a **fallback**, not a merge: the first source with ANY match wins
  outright, even when a lower tier holds a more specific entry;
- within a source, specificity is `(matchedSegments, kind)` with
  `Exact > Descendant > Wildcard`, and a tie keeps the **earlier-declared** entry;
- `prefix.*` matches the base node AND its descendants; a bare `*` matches
  everything with zero matched segments; matching is **root-agnostic**, so a key
  outside the taxonomy still resolves (taxonomy conformance is a separate,
  reported diagnostic — `validateBindingSource`).

### `scene-placement.json`

```jsonc
{
  "area": "editor-scene",
  "sources": [ … the CC0 placeholder tier … ],
  "ir": { "meta": {"seed": …}, "geography": {"terrain": …, "roads": […]},
          "entities": {"buildings": […], "props": […]} },
  "expected": { "manifestVersion": 1, "seed": "…", "nodeCount": 13, "nodes": [ … ] },
  "expectedUnbound": { "requestedCount": …, "boundCount": …, "missingKeys": [] },
  "expectedNonTaxonomyKeys": [],
  "fit": { … },                                      // US-2 of 162 — see below
  "manifestForm": {                                  // §5.1, the serialized shape
    "sourceNames": ["project", "insimul-placeholder"],   // the chain the forked doc belongs to
    "canonicalNodeKeys": ["archetype", "assetRef", … ],  // EXACTLY these, ascending
    "legacyAssetRefKeys": ["scene"],                     // read, never written
    "forkedManifest": { "nodes": [ … ] },                // as Godot/Unity actually wrote it
    "expectedNodes": [ … ],                              // what a conforming reader yields
    "expectedRepairs": [ { "entityId": …, "field": "assetRef" | "bindingSource",
                           "reason": "legacy-key" | "key-conflict" | "case-folded",
                           "found": …, "canonical": … } ],
    "expectedRepairsWithoutSourceNames": [ … ]           // same doc, no tiers declared
  }
}
```

`ir` is the golden World IR all three legs already vendor, and `expected` was
verified node-for-node identical to Unity's committed
`golden-placement-manifest.json`. Contract points: coordinates quantized to
`0.001` with ties **away from zero** (C++ `std::round`, NOT JS `Math.round`);
buildings snapped to a 1.0 grid and scaled by zone role; terrain height sampled
bilinearly with edge clamping; nodes emitted in ascending entityId (ordinal)
order; the asset handle serialized as **`assetRef`** and `bindingSource` carrying
the resolving tier's `name` verbatim.

`manifestForm` is what makes that last clause enforceable rather than merely
stated — it is the fixture the two forked legs (§5.1 of
`packages/core/docs/editor-plugin-core-analysis.md`) would fail today. A
conforming engine MUST:

- **write** a node carrying exactly `canonicalNodeKeys` — no `scene`, no extra
  key, no rename. A shape change is a `manifestVersion` bump, not a dialect;
- **read** a forked document by canonicalizing it: `scene` → `assetRef`
  losslessly, and `assetRef` winning outright when a document carries both;
- **never case-fold a tier name.** A title-cased `bindingSource` is repaired
  only when it case-insensitively matches exactly one *declared* tier
  (`sourceNames`); `Placeholder` against a tier called `insimul-placeholder`
  matches nothing, so it is kept **verbatim** and reported. The re-import diff
  then classes that node `updated` and the scene converges on canon at the next
  import — which is the migration. Guessing would hide it;
- **report** every departure, in document order, as the `expectedRepairs` rows.

`fit` is the fit-and-orientation case (US-2 of
`162-asset-metadata-footprint-and-provenance`). It is a **second, self-contained
pack and settlement** rather than an extension of `ir`, because the golden IR all
three legs vendor carries no lots and no measured assets and must keep placing
byte-for-byte as it always did (`result.fit` is empty for it, and that is
asserted).

```jsonc
"fit": {
  "sources": [ { "name": "packs", "entries": [ { "key": "…",
     "transform": { "convention": {…}, "footprint": { "size": {…} } },   // US-1's typed geometry
     "sockets":   { "entrance": { "kind": "door", "yaw": … } } } ] } ],
  "ir": { "entities": { "buildings": [ { "id": "…", "role": "…", "archetype": "…",
     "lot": { "width": 12, "depth": 16, "frontageYaw": 3.14159… } } ] } },
  "expectedNodes": [ … ],   // the manifest — misfits INCLUDED, aligned rotationY
  "expectedFit": [ { "entityId": …, "archetype": …, "assetRef": …,
                     "outcome": "fits" | "misfit" | "unmeasured" | "unbounded",
                     "issues": ["no-entrance-anchor" | "too-large" | "wrong-aspect"],
                     "required": { "across": …, "away": … },
                     "lot": { "width": …, "depth": … },
                     "rotationY": …, "aligned": true } ]
}
```

Semantics a conforming engine MUST reproduce:

- the comparison happens **in the lot's frame and in metres**: `width` runs across
  the street frontage, `depth` away from it, and an asset declaring Z-up
  centimetres (`building.civic.hall`) is converted before anything is compared;
- the footprint checked is the one **as placed** — the declared extents times the
  asset's own scale fixup times the node's zone scale;
- where the asset carries an entrance anchor and the lot states a `frontageYaw`,
  the node's `rotationY` becomes `frontageYaw − transform.yaw − socket.yaw`, so
  the door faces the street;
- a misfit is **reported, never fixed**: nothing rotates an asset a quarter turn
  to make it fit, shrinks it, or drops the node — every checked building is still
  in `expectedNodes`. `wrong-aspect` means precisely "the swapped extents fit and
  these do not";
- `unmeasured` is neither a pass nor a misfit (an asset nobody measured still
  binds and still places), and `unbounded` is a lot that declared no extents —
  the coordinate-free lots `place_lots_topological` emits;
- a building that declares no `lot` is **not checked and not reported**.

### `reimport.json`

```jsonc
{
  "area": "editor-reimport",
  "oldManifest": { "nodes": [ … ] },     // what the scene already has
  "newManifest": { "nodes": [ … ] },     // what regeneration produced
  "expectedReport": { "reportVersion": 1, "added": […], "updated": […],
                      "unchanged": […], "skipped": […], "deprecated": […] },
  "expectedCanonicalReport": "{\"added\":[…]}",   // byte-compared
  "expectedMutatorCalls": ["update:…", "add:…", "deprecate:…"],

  "ownership": {                         // per-field ownership (161 US-4)
    "baseManifest":   { "nodes": [ … ] },  // what the LAST import wrote
    "editedManifest": { "nodes": [ … ] },  // the scene now, after a hand swap
    "expectedOwnership": [{ "entityId": "…", "fields": ["assetRef"] }],
    "expectedReport": { …, "preserved": [{ "entityId": "…", "fields": […] }] },
    "expectedReportWithoutOwnership": { … },  // the control: the clobber
    "expectedCanonicalReport": "…",
    "expectedMutatorCalls": ["update:…", … ],
    "expectedUpdatedNodes": [ … ]          // the MERGED nodes the mutator got
  }
}
```

`expectedCanonicalReport` is byte-identical to the `golden-diff-report.json`
Unity, Unreal and Godot each commit. `expectedMutatorCalls` is what the goldens
cannot express: the order core drives the host's `SceneMutator` in — updates,
then adds, then deprecations, each ascending — and the fact that `unchanged` and
`skipped` produce **no call at all**, which is how a creator's hand edit survives.

The `ownership` block is the same two manifests seen with a *third*: the base the
last import wrote. Ownership is derived per field as `edited ≠ base`, and the
merge takes the fresh value everywhere else, so a creator's asset swap survives a
regeneration that also moves the node. `expectedReportWithoutOwnership` is the
control — the same call with no base, which is the policy the three legs' goldens
encode and is **deliberately unchanged**. `expectedUpdatedNodes` is the half a
half-adoption fails: a leg that passes the base but still applies the *fresh*
node reports what it preserved and clobbers anyway. See
`docs/reimport-field-ownership.md`.

## Purpose — the cross-engine parity gate

`@insimul/core` is the contract every engine plugin implements. The TypeScript
runner (`src/conformance/__tests__/prolog-corpus.test.ts`) and `libinsimul`'s C,
Rust and wasm harnesses all read these very JSON files and assert the same
`expected` sets — any divergence is a contract violation, caught here rather than
in gameplay. Since tasklist 91 the web runtime IS the wasm leg, so a divergence
between the browser and a native plugin would have to come from the wrapper, not
from the interpreter. Add cases here whenever a Prolog behaviour becomes
load-bearing for save files, quests, or NPC reasoning.
