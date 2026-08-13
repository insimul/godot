# Changelog — Insimul Godot Plugin

All notable changes to the Godot plugin are documented here. This package is
independently versioned; its version is the `godot` entry in the repo-root
`VERSIONS.json` (the single source of truth, enforced by
`npm run engines:manifests`) and must match both `addons/insimul/plugin.cfg` and
the top-level `asset-lib.json` metadata.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Modules are activated from the genre bundle, not from a list in the plugin.**
  `InsimulModuleActivation` reads the genre out of the World IR's
  `meta.genreConfig.id` and resolves it through core's own table; nothing in it
  or in `InsimulMechanicActivator` spells a module, a rule pack or a genre, and
  `check-mechanics.mjs`'s **seventh check** greps both files for every name in
  `conformance/modules/genre-activation.json` and fails on a hit. Adding a module
  to a bundle upstream changes what a game activates with no engine code change.
  See `RUNTIME_CORE_ADOPTION.md` §13.
- **`npm run test:activation`** (`gdextension/test/run_activation_tests.sh`) —
  **30 checks**. `modules.table` is deep-compared to the vendored table; all
  **8 genre bundles** are resolved through `modules.activate`, by genre id and
  through a World IR, and compared to the committed set (24 module activations);
  core's three answers are kept apart (known genre / unknown genre / nothing
  declared); and for all **8 genres × 11 packs** the pack's signature predicate is
  witnessed in a REAL Trealla KB — present exactly when its module is active.
  That last one is the only check that can fail on a plugin which resolves
  activation correctly and then consults everything anyway.
- **`modules.activate`, `modules.table` and `prolog.packs`** — three bridge rows.
  The first two return core's `ActiveModuleSet` and its committed table verbatim;
  the third returns the rule-pack TEXT for a set of areas in core's consult order,
  which closes the gap Unity had to vendor eleven `.pl` files to fill.
- **`conformance/modules/genre-activation.json` is vendored and EXECUTED.** It
  left `NOT_MIRRORED` in the same commit that added its runner, which is the rule
  this repo now works by. `tools/vendor-conformance.mjs` grew `TABLE_FLOORS` (8
  genre bundles, 24 activations) because a case-count floor cannot guard a table
  with no `cases` array.
- **A playable sample scene, whose steps are a file.**
  `templates/scripts/mechanics/mechanic_courtyard_demo.gd` builds a dark
  courtyard — a guard, a wanderer, a lantern, a crate — and runs perception and
  combat end to end: the engine measures (raycast, light probe), core decides
  (detection, suspicion, damage), the engine executes the orders. The steps are
  `templates/project/insimul/scenarios/dark-courtyard.json`, so the activation
  gate replays the same 6 steps through the same rows with no Godot binary.
  `templates/scripts/mechanics/godot_mechanic_binder.gd` is the reusable half:
  it activates on `_ready()` and asks the game for each module's create arguments
  through a `creating_module` signal.
- **The band-120 corpora are vendored AND executed — 467 cases, 0 divergences.**
  `npm run test:corpus` (`gdextension/test/run_corpus_tests.sh`) runs core's own
  golden vectors in this engine, on the natively linked Trealla, in two halves:
  **255 Prolog cases** across 21 files, each one consulted and *queried* (the
  vocabulary — `can_attack/2`, `routine_due/2`, `detects/2`), and **212 decision
  cases** across 18 areas, each resolved by core's own `resolveAttack`,
  `runDetection`, `findRoute`, `resolvePrice`, `resolveAdvance` … (the damage
  number, the suspicion rung, the route, the price — the things no rule computes
  and no Prolog corpus can pin). Result: `254 AGREE, 1 AMEND, 0 DIVERGE, 0 ERROR`
  and `212 AGREE, 0 DIVERGE, 0 ERROR`. See `RUNTIME_CORE_ADOPTION.md` §12.
- **The vendored corpus grew from 10 files / 76 cases to 63 files.** Every
  band-120 corpus for the seven adopted modules is now mirrored — the eight
  `prolog/mechanic-*` packs plus `scaffold`, `agent-ai`, `geo-map`, and the six
  decision directories `combat/`, `stealth/`, `traversal/`, `skills/`, `items/`,
  `routines/`. What is *not* mirrored is now six explicit NOT_MIRRORED entries in
  `tools/vendor-conformance.mjs`, each with a reason, each PRINTED with a count on
  every vendoring run.
- **`prolog.run`, `conformance.run` and `conformance.areas`** — three bridge rows
  that let a gate execute a corpus case through the same bundle a shipped game
  loads. `conformance.run` takes the case whole and returns the whole `expected`
  shape, so the C++ harness compares rather than interprets and adding an area is
  one function in `gdextension/corebridge/js/host-corpus.js`.
- **The band-120 mechanic modules — combat, stamina, perception, traversal,
  skill, equipment and routine — are reachable and implemented.** Seven of core's
  decision layers now run behind **27 new rows** in
  `gdextension/corebridge/js/entry.js` (`combat.attack`, `stamina.spend`,
  `perception.observe`, `traversal.traverse`, `skill.unlock`, `equipment.equip`,
  `routine.tick`, …), and all **eight** host interfaces they declare are
  implemented in GDScript. Adopting a mechanic is a row plus a host
  implementation; not one line of core is re-implemented here.
  See `RUNTIME_CORE_ADOPTION.md` §11.
- **`InsimulMechanicSession`** (`addons/insimul/runtime/mechanics/`) — the host
  side of *readings in, orders out*: a game gathers what core would have asked it
  (a raycast, a navmesh path, an entity's base stats) before the call, and every
  call core would have made to a host interface comes back as an order this class
  carries out. That is what lets eight callback interfaces cross a C ABI that has
  no callbacks.
- **`InsimulMechanicHosts`** — all eight interfaces as base classes, each with
  the fallback core documents for a MISSING host implemented once (a shot with no
  probe is clear, a geometric link with no answer is passable, an ordered
  movement with no locomotion host has arrived).
- **`InsimulMechanicSurface`** — per-module reachability asked of the BUILD
  (`core.methods` + `mechanic.modules`), so a boot log says which mechanics are
  live instead of leaving a creator to infer it.
- **`InsimulActorRegistry`** — actor atom → `Node3D`, place atom → position. Core
  names `nessa` and `forge_gate`; a raycast needs a body.
- **Godot host implementations** in `templates/scripts/mechanics/`:
  `godot_geometry_probes.gd` (`PhysicsDirectSpaceState3D.intersect_ray` +
  `NavigationServer3D.map_get_path` for the three probes),
  `godot_locomotion_host.gd` (`NavigationAgent3D` driving a `CharacterBody3D`),
  `godot_combat_host.gd` (`ICombatSystem` + `ICombatStatSink` over one roster),
  `godot_survival_host.gd` (forwards onto the template's own `survival_system.gd`
  so the meter the player sees is the meter core charges) and
  `godot_skill_modifier_sink.gd`.
- **`npm run test:mechanics`** — 43 checks driving all seven modules end to end
  through libinsimulcore on the natively linked libinsimul: the rows are
  reachable, readings reach core, orders reach the host, the host **cannot**
  decide, sessions are isolated and disposed, and the Prolog seam's new
  assert/retract path works.
- **`tools/verify-mechanics/check-mechanics.mjs`** in `npm run check` — six
  mirrors between core's module manifest, the GDScript hosts, the bridge rows and
  the vendored corpus, with `--core` re-derivation and six negative controls that
  prove no check is vacuous.

### Changed

- **The marshalling gate now covers 255 cases across 21 files** (was 76 / 10);
  its floor moved with it. It still *decodes* pinned solutions rather than
  running them — the two gates are complementary and `RUNTIME_CORE_ADOPTION.md`
  §12.1 is the table that says why neither is enough alone.
- **`npm run check` gained per-area case floors and a corpus-coverage check.**
  `vendor-conformance.mjs` now carries 19 hand-written `CASE_FLOORS` (465 cases
  pinned as a minimum) that a re-vendor cannot lower, and `check-mechanics.mjs`
  gained a sixth check — with its own negative control — asserting that every
  module's declared corpus is vendored, that everything vendored has a runner,
  and that every directory under `conformance/` is accounted for by a named gate
  or an explicit "nothing here runs it".
- **The Prolog seam grew `assertFact`, `retractFact` and `queryOnce`** (the only
  `PrologEngine` members the mechanic layers reach that it lacked), and
  `__insimul_prolog_{assert,retract}` were added to the C host to back them.
  They mutate the KB **in place** rather than rebuilding it the way core's wasm
  engine does — the same Trealla, so nothing a caller can observe differs, with
  core's de-duplication and retract bookkeeping mirrored exactly.
  `RUNTIME_CORE_ADOPTION.md` §11.3.
- The vendored core bundle now carries the seven decision layers (54 KB → 353 KB,
  42 core modules), and ships a `TextEncoder`/`TextDecoder` polyfill: core's
  `identity/kinp.ts` constructs one at module scope and QuickJS has neither, so
  the whole bundle failed to evaluate without it.

- **`@insimul/core` adoption, first slice — radiant quest generation.**
  `InsimulRadiantSource` (`addons/insimul/runtime/radiant_source.gd`) generates
  radiant quests by calling core's own deterministic, Prolog-driven generator
  instead of re-implementing it. Same seed + world + time ⇒ byte-identical
  quests on every engine, pinned by the shared corpus `conformance/radiant/*.json`
  (`npm run test:radiant`, 11 cases). Set `source = SOURCE_NONE` for
  pre-adoption behaviour.
- **`libinsimulcore` (`gdextension/corebridge/`)** — the C ABI all four runtimes
  will bind (`insimulcore.h`: opaque handle, JSON in, JSON out), with core's
  TypeScript running behind it in an embedded QuickJS and its Prolog seam wired
  to the natively linked libinsimul rather than a wasm copy. `InsimulCore`
  exposes it to GDScript. See `gdextension/corebridge/README.md` and
  `RUNTIME_CORE_ADOPTION.md` §4.
- `npm run test:radiant` (the adoption gate) and `npm run vendor:core` (re-vendor
  the core bundle); `npm run check` now also guards the vendored bundle against
  drift.
- **`npm run test:quest-parity`** — the two-implementation diff. Runs
  `conformance/quests/{hydration,radiant}-cases.json` through both this repo's
  hand-ported C++ quest core and `@insimul/core`, and classifies every case
  **AGREE / FIX / SHAPE / REGRESSION** against the committed corpus. Result:
  **7 AGREE, 0 regressions** — the hand-port and core agree byte-for-byte on
  every shared vector. `--source cpp` runs the hand-port alone (no libinsimul).
  See `RUNTIME_CORE_ADOPTION.md` §10.3.
- **`npm run vendor:conformance`** — re-vendor and drift-guard the shared
  conformance corpus, mirroring `vendor:core`'s two modes. `npm run check` now
  runs `--check`; pass `--core <packages/core>` for a byte-for-byte diff against
  the source tree.
- `run_radiant_tests.sh --source none` now **classifies** the pre-adoption leg
  (4 AGREE, 7 GAIN, 0 REGRESSION) and fails if that leg ever produces a quest of
  its own, or if the GAIN count reaches zero.
- `asset-lib.json` — Godot Asset Library submission metadata, version-locked to
  `plugin.cfg` and `VERSIONS.json` by `npm run engines:manifests`.
- Asset Library release dry-run (`scripts/release/build-assetlib-zip.mjs`): stages
  `addons/insimul/**` (no `templates/` tree) and builds + validates a
  `dist/insimul-godot-<version>.zip`.

### Fixed

- **`InsimulProlog.consult()`, `assert_fact()`, `retract_fact()` and `restore()`
  returned the inverse of what happened.** The vendored libinsimul header was a
  hand-written contract copy predating the library, and it documented "1 on
  success" where libinsimul returns **0**. Found by the first code to actually
  link the library; the header is now a verbatim copy of the shipping one.
- `run_save_tests.sh`, `run_quest_tests.sh` and `run_bootstrap_tests.sh` resolve
  the vendored conformance corpus first, like `run_conformance.sh` already did.
  They hardcoded a monorepo sibling path and so failed in a standalone checkout —
  58, 33 and 42 checks now run green instead of reporting 20, 6 and 21 path
  failures.
- **The vendored conformance corpus had silently rotted to 54% of the source and
  nothing was checking.** `conformance/prolog/` carried **41 of core's 76 cases**
  — the whole KINP `identity` / `equivalence` / `worlds` pack was missing and
  `gameplay.json` was a pre-KINP snapshot — while `VENDORED.md` described the
  directory as a mirror. Re-vendored to byte-identity (34 files,
  `packages/core` @ `443cce78`), so `npm run test:conformance` now runs
  **76 cases / 97 solutions** instead of 41. `predicate-schema-hash.json` and
  `content-library/` are mirrored too.
- `conformance/content/library.json` no longer claims to mirror a core file that
  does not exist; it is declared local, and core's actual content-library golden
  (`conformance/content-library/`) now sits beside it. The two shapes are not
  interchangeable — see `conformance/content/README.md`.
- **Two gates that could not fail.** `run_conformance.sh` returned success on an
  empty corpus directory; it now asserts a file and case floor. The quest-parity
  classifier asserts all five of its verdicts are reachable before it reports
  agreement.

### Documented

- **One divergence, classified as SHAPE rather than amended away.** This gate
  applies libinsimul's *two*-substitution amendment to
  `assert-retract.json::asserta-prepends` where core's TS runner applies one:
  the natively linked Trealla reports a failing `:- dynamic(log/1).` directive as
  a failed **consult**, where core's wasm wrapper only fails at the query. Same
  answer, different stage. Every case runs unamended first, so a stale amendment
  fails the gate. `RUNTIME_CORE_ADOPTION.md` §12.3.
- **`conformance/ui/*.json` is executed by nothing on this tier**, and now says
  so in code rather than by omission — the one `CORPUS_RUN_ELSEWHERE` entry whose
  value is "nothing runs it". Closing it needs a GDScript runner, not a C++ one.

## [1.0.0]

### Added
- Initial addon (`addons/insimul/`): `InsimulClient` autoload, `InsimulNPC`,
  streaming text/audio, lip sync, microphone capture, and world-export loading.
