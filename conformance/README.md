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
  "expectedNonTaxonomyKeys": []
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

### `reimport.json`

```jsonc
{
  "area": "editor-reimport",
  "oldManifest": { "nodes": [ … ] },     // what the scene already has
  "newManifest": { "nodes": [ … ] },     // what regeneration produced
  "expectedReport": { "reportVersion": 1, "added": […], "updated": […],
                      "unchanged": […], "skipped": […], "deprecated": […] },
  "expectedCanonicalReport": "{\"added\":[…]}",   // byte-compared
  "expectedMutatorCalls": ["update:…", "add:…", "deprecate:…"]
}
```

`expectedCanonicalReport` is byte-identical to the `golden-diff-report.json`
Unity, Unreal and Godot each commit. `expectedMutatorCalls` is what the goldens
cannot express: the order core drives the host's `SceneMutator` in — updates,
then adds, then deprecations, each ascending — and the fact that `unchanged` and
`skipped` produce **no call at all**, which is how a creator's hand edit survives.

## Purpose — the cross-engine parity gate

`@insimul/core` is the contract every engine plugin implements. The TypeScript
runner (`src/conformance/__tests__/prolog-corpus.test.ts`) and `libinsimul`'s C,
Rust and wasm harnesses all read these very JSON files and assert the same
`expected` sets — any divergence is a contract violation, caught here rather than
in gameplay. Since tasklist 91 the web runtime IS the wasm leg, so a divergence
between the browser and a native plugin would have to come from the wrapper, not
from the interpreter. Add cases here whenever a Prolog behaviour becomes
load-bearing for save files, quests, or NPC reasoning.
