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
