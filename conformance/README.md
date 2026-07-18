# @insimul/core conformance corpus

Language-neutral, data-only fixtures that pin the **engine-agnostic contract**
carved out of `shared/` into `@insimul/core`. Everything here is JSON (plus the
golden save files) so a native harness — the future `libinsimul` C/C++ Prolog
runtime for the Unreal/Unity/Godot plugins — can consume the **same** cases as the
TypeScript `tau-prolog` engine and prove semantic parity. **Write cases as data,
never as code.**

## Layout

- `saves/` — three golden save-file fixtures (`v1-minimal.json`,
  `v2-typical.json`, `v2-with-extensions.json`), copied read-only from
  `insimul-platform/shared/__tests__/fixtures/saves/`. They are runtime-format
  artifacts (the transport shape validated by the US-CE4 zod schemas). A migration
  test (`src/conformance/__tests__/saves-migration.test.ts`) asserts
  `migrateSaveFile` lifts `v1-minimal` to the current `SAVE_FILE_VERSION`.
- `prolog/*.json` — the golden Prolog query corpus (this file's main subject).
- `radiant/*.json` — the radiant quest-generation corpus (see "Radiant case
  format" below). Pins `generateRadiantQuests` — the contract the future native
  `insimul_radiant_tick()` must match.
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
  predicates (`member/2`, `length/2`, `nth0/3`, …) require the
  `:- use_module(library(lists)).` directive in `kb`.
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
conforming engine need not enumerate solutions in the same order as `tau-prolog`,
only produce the same set. Do not rely on solution order in a case.

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

## Purpose — the cross-engine parity gate

`@insimul/core` is the contract every engine plugin implements. Today one engine
(`tau-prolog`, TypeScript) runs this corpus via
`src/conformance/__tests__/prolog-corpus.test.ts`. When `libinsimul` (native
Prolog) lands, its C test harness reads these very JSON files and asserts the same
`expected` sets — any divergence is a contract violation, caught here rather than
in gameplay. Add cases here whenever a Prolog behaviour becomes load-bearing for
save files, quests, or NPC reasoning.
