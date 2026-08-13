# Working in `@insimul/godot`

Conventions and traps that cost somebody an hour. Not a tour of the repo — the
README is that, `RUNTIME_CORE_ADOPTION.md` is the design record, and
`VERIFICATION.md` is what to run.

## The gates

```sh
npm run check            # ALWAYS. Structural .gd lint + three drift/mirror guards.
npm run test:mechanics   # the seven band-120 mechanic modules, 43 checks
npm run test:corpus      # PARITY: 467 of core's golden cases, executed here
npm run test:radiant     # the first adopted slice, 11 conformance vectors
npm run test:quest-parity
npm run test:conformance
npm run test:activation  # 8 genre bundles, 88 KB witnesses, the sample scenario
npm run test:talos-bridge # the insimul-talos-bridge decision half, 73 checks
npm run test:replay      # the bridge's replay leg vs core's own answers, 20 checks
npm run test:ui          # the default-UI registry/theme/panel gate (needs godot), 637 checks
npm run test:ui-quest-trade  # the shared quest + trade matrices + state-location, 172 checks
npm run test:ui-dialogue-menu-save # the dialogue/menu/save matrices + the Controls, 179 checks
```

Everything under `gdextension/test/run_*.sh` builds with a **plain C/C++
compiler** — no cmake, no scons, no godot-cpp, no Godot binary. Five of them
(`run_radiant_tests.sh`, `run_quest_parity_tests.sh`, `run_mechanic_tests.sh`,
`run_corpus_tests.sh`, `run_activation_tests.sh`) additionally **link libinsimul**
and fail loudly when it is absent rather than skipping. Point them at a build:

```sh
INSIMUL_NATIVE_DIR=<insimul-native checkout>   bash gdextension/test/run_mechanic_tests.sh
INSIMUL_NATIVE_DIST=<dist/<platform>>          bash gdextension/test/run_mechanic_tests.sh
```

The sibling-layout probe only finds `../native` and `../../native`, so a worktree
that is not beside the project checkout MUST pass one of those variables.

**`npm run check` reads `git ls-files`.** A new `.gd` file that is not staged is
not scanned, and the gate prints a green number that means nothing. `git add`
before believing it.

## Three vendored artifacts, one rule

`gdextension/corebridge/vendor/core/` (the bundled core), `conformance/` (the
shared corpus), `addons/insimul_talos/supported-versions.json` + its mirrored
cases (the workspace's published engine-version matrix) and
`gdextension/test/fixtures/replay/` + `addons/insimul_talos/input-vocabulary.json`
(core's own answers about the portable input-trace artifact) are **generated**. Never
hand-edit any of them; regenerate:

```sh
npm run vendor:core        -- --core <packages/core>
npm run vendor:conformance -- --core <packages/core>
npm run vendor:replay      -- --core <packages/core>
npm run vendor:versions    -- --matrix <workspace docs/supported-versions.json>
node tools/verify-mechanics/check-mechanics.mjs --core <packages/core> --write
```

A FOURTH generated artifact joined them: `gdextension/test/fixtures/replay/` plus
`addons/insimul_talos/input-vocabulary.json`, both minted by
`tools/vendor-replay-fixtures.mjs` from core's `src/replay/` and
`action-matrix.ts`. The vocabulary is not test data — it ships, because the
replay leg refuses a trace whose `signal` names an Insimul action id and cannot
do that without core's list.

The matrix comes from the workspace parent, not from core, so it moves on its
own schedule; `--check` verifies the mirror's own hashes and `--matrix` is the
only real drift check. Re-vendoring it also re-mirrors
`scripts/engine-versions/fixtures/` into
`gdextension/test/fixtures/refuse-at-hello/`, which is what holds this repo's
C++ port of the refuse-at-hello decision to the reference implementation's own
answers.

`packages/core` lives in the **babylon** checkout (`babylon/packages/core`), not
in a top-level `packages/`. All three tools also take `--check` (or run with no
`--core` at all), which verifies the checked-in artifact's own hashes; adding
`--core` is what actually diffs against core and is the only real drift check.

**That checkout is shared and it moves under you.** Another agent's run can merge
into it mid-story — it did during 147/US-2, between vendoring and the drift
check, which reported one drifted file that was not this repo's doing. Re-vendor
**all three** artifacts from one commit and re-run `--core` at the end; a corpus
at one core sha with a bundle at another is real drift, and the guards will say
so on the next run rather than this one.

Case counts are floored, per area, by hand (`CASE_FLOORS` in
`tools/vendor-conformance.mjs`). `prologCases` cannot catch a shrink on its own:
it is written *from* the corpus on every re-vendor, so an upstream corpus that
lost cases re-vendors to a smaller number and the guard agrees with it.

## Adopting more of core

One row in `gdextension/corebridge/js/entry.js`, one host implementation, one
gate. Never a port — `UNIFICATION_ROADMAP` decision 1 is closed. Three things
that will bite:

1. **QuickJS is not Node and not a browser.** No `WebAssembly`, no `crypto`, no
   `TextEncoder`. The bundle fails to evaluate at LOAD, not at the call site, so
   a missing global shows up as `insimul_core_create() failed`. Adapter-owned
   modules under `corebridge/js/` supply what is missing (`host-prolog-engine.js`
   is a seam, `host-text-codec.js` is a polyfill, `host-crypto.js` deliberately
   throws).
2. **Host interfaces are callbacks and the C ABI has none.** The shape that
   resolves it is *readings in, orders out* — `corebridge/js/host-mechanics.js`
   plus `addons/insimul/runtime/mechanics/insimul_mechanic_session.gd`. Do not
   add a callback entry point to `insimulcore.h`.
3. **A session's KB must carry the packs its module's gates read.** Core's
   `checkAction` throws when `forbidden_by/4` raises, and Trealla raises for an
   undefined procedure. Facts alone are not enough.
4. **A vendored corpus is not adopted until something RUNS it.** Adding a corpus
   directory to `conformance/` means adding a runner in
   `corebridge/js/host-corpus.js` keyed by the file's own `area` string, or a
   NOT_MIRRORED entry in `tools/vendor-conformance.mjs` saying why not.
   `check-mechanics.mjs`'s sixth check fails on either omission — in **both**
   directions, plus a total accounting of every directory under `conformance/`.
   The corpus case crosses the ABI whole (`conformance.run` takes `{area, case}`
   and returns the entire `expected` shape), so the C++ harness compares rather
   than interprets and adding an area never touches it.
5. **The active module set is DATA, and the two readers may not spell it.**
   `insimul_module_activation.gd` and `insimul_mechanic_activator.gd` are grepped
   by `check-mechanics.mjs`'s seventh check for every module id, pack area and
   genre id in `conformance/modules/genre-activation.json` — **comments
   included**. Writing `# e.g. the combat module` in either file fails the gate,
   and that is deliberate: a comment listing the modules rots exactly like code.
   Everything those two files know arrives from `modules.activate`.
6. **A genre can activate a module this repo does not adopt** (`agentAi`, `map`
   under `rpg`). Activation has two halves: the pack half works for every pack in
   the build, the session half needs a bridge row. Say which in
   `check-mechanics.mjs`'s `NOT_ADOPTED` — an activated module in neither that
   list nor `BAND_120` fails the gate.

## GDScript in this repo

- The SDK is `addons/insimul/` (shipped plugin); `templates/` is the EXPORTED
  GAME and is in no compiled assembly, so nothing in it is type-checked by any
  gate here. Engine-specific code (raycasts, `NavigationAgent3D`) belongs there;
  contracts and fallbacks belong in the addon.
- A file added to `templates/scripts/` must also be added to
  `templates/TEMPLATE_MANIFEST.json`, or the export pipeline will not copy it.
  The regenerator lives in the platform repo, so add the entry by hand and keep
  the list sorted by path.
- Target is Godot **4.2+** (`gdextension/insimul.gdextension`). `Dictionary.get_or_add`
  (4.4) and friends are out.
- One `class_name` per file; use inner `class Foo extends Bar:` for the rest.
- Tabs, typed locals (`var x := ...`), `##` doc comments.

## The default UI is DATA, and the GDScript gates need an import pass

`addons/insimul/ui/` is the shipped default-UI. Six things that will bite:

1. **The panel set lives in `panels.json`, not in the registry.** Panel key ->
   scene, plus the band-111 modules a panel needs before it is offered at all.
   `tools/verify-ui/check-ui.mjs` greps `insimul_ui_registry.gd` for every panel
   key and every module id in the activation table and fails on a hit — the same
   discipline as `check-mechanics.mjs`'s seventh check, and for the same reason.
   It strips comments first, unlike that one: there is no comment here LISTING
   the panels, and a doc comment showing one call is the rule being documented.
2. **Nothing under `ui/` may name `InsimulCore`.** The default UI has to load in
   a project with no native build — otherwise a missing GDExtension takes the
   menus down with it, and the headless gate could not stage the UI alone.
   `bind_activation()` is duck-typed (`module_ids()` + `genre()`) for exactly
   this reason.
3. **A `godot -s` gate that skipped the import pass ran NOTHING and said so with
   an exit code of 0.** Godot registers the addon's global `class_name`s only
   after the project has been scanned, so a throwaway project that goes straight
   to `-s` fails to parse every script — and `godot -s` still exits 0.
   `run_ui_registry_headless.sh` and `run_quest_trade_headless.sh` therefore run
   `--import` first, check that `.godot/global_script_class_cache.cfg` appeared,
   and grep the log for parse errors afterwards. Both were green and empty —
   the registry gate for three stories, the quest/trade gate for its whole life
   (it pointed at `../core/conformance/ui`, a path outside this repo, and was in
   no npm script). The first real execution failed 18 of 172 checks, all of them
   the harness's own comparison: `JSON.parse()` hands back every number as a
   FLOAT, so a corpus `4` never equalled a model's `int` 4.
4. **A panel added to the tree during `_initialize()` never gets `_ready()`.** The
   SceneTree's `root` is not itself in the tree yet, so `add_child` defers. A
   "does this panel build itself?" check written there passes vacuously; the
   node-level legs run from `_process()` instead. That is what catches a panel
   reaching for a theme token that does not exist (`FONT_SIZE["subtitle"]` was one
   until US-2 — it resolved, instantiated, and errored only when shown).
5. **`panels.json` has two TIERS and the gate holds them apart.** An entry with a
   `pending_corpus` string is a panel shipped before the shared corpus documents
   the key; everything else must equal `registry-cases.json -> panel_keys`
   exactly, both ways. The tier is a waiting room: check-ui fails a
   `pending_corpus` key the corpus already has, so a re-vendor forces the entry to
   move. An ahead-of-corpus panel gating on nothing needs a `gate_note` saying
   which module would back it and why it is the wrong answer. Same idiom as
   `NOT_ADOPTED` in `check-mechanics.mjs`.
6. **A composite panel (`children` in the manifest) is a SECOND resolver**, so it
   lives under the same "spells no panel key" rule as the registry — check-ui
   finds its script through the scene and greps it. `InsimulHud.mount()` takes the
   key it was resolved under rather than spelling `hud`. check-ui's check 9
   widens that to ANY ui/ file calling `children()` / `tab_panel()` /
   `tab_panels()`, which is how the rule reached `pause_menu.gd` without the gate
   being told about it.
7. **The ESC menu has TWO gates and they are different vocabularies.** A tab is
   offered when the pause-menu module bundle enables it (`proficiency`,
   `assessment`, … — `pause-menu-cases.json`); its BODY is a shipped panel, so it
   also meets the band-111 gate (`skill`, `map`, …). The tab -> panel map is
   manifest data (`pauseMenuTabs`), and **every shipped tab must be in exactly one
   of `pauseMenuTabs` and `pauseMenuTabNotes`** — a tab in neither renders a blank
   pane, which is the failure the registry's diagnostics exist to prevent. Same
   accounting idiom as the ahead-of-corpus tier.
8. **A `SceneTree` test script has no `get_tree()`.** It IS the tree: write
   `paused`, not `get_tree().paused`. The parse error only surfaces when something
   LOADS the script — which is exactly what the wrapper's `SCRIPT ERROR` grep is
   for, and it caught this one.

## The Talos bridge is a THIRD artifact, and stays one

`addons/insimul_talos/` implements `TALOS_INSIMUL_BRIDGE.md` §7.5: it depends on
both projects and is depended on by neither. Seven things that will bite:

1. **`addons/insimul/` may never mention it.** `check-bridge.mjs` greps for
   `insimul_talos` / `InsimulTalos` across the shipped plugin and fails on a hit.
   The bridge is QA-only; a mention there is Insimul acquiring a QA dependency.
2. **No Talos symbol in the bridge either.** Talos's Godot contract is duck-typed
   — groups plus method and signal NAMES — so `talos_save`, `talos_event` and the
   rest are contract, while `TalosBridge`, `res://addons/talos/…` and friends are
   a compile-time dependency the design exists to avoid. The gate matches those
   on a word boundary, because this artifact's own class is `InsimulTalosBridge`.
3. **The six group names live in `bridge-contract.json`, and `talos.game.yaml`
   quotes them.** The gate compares the two IN BOTH DIRECTIONS, and the adapter
   reads its groups from the contract rather than spelling them. A group the
   manifest does not declare is an adapter the Bridge never finds — it fails
   after the run starts, not at install.
4. **The decision half is C++ and that is deliberate.** §7.5 pictured one
   GDScript file; there is no Godot binary in these gates, so a decision
   procedure written in GDScript could not be executed by anything that gates a
   merge. `gdextension/src/talos_bridge.*` keeps ONE implementation and makes it
   testable under a plain compiler; the addon stays buildless GDScript plus data.
   It is registered in the existing extension rather than a second one, so the
   per-Godot-minor artifact matrix does not grow a third row.
5. **The §7.5 rule is a CODE PATH, and the gate reads it as one.**
   `check-bridge.mjs` builds the adapter's call graph and fails if anything
   reachable from `_init`/`_ready` names `_kb`, `_world_id`, `_state_goals`,
   `_progress` or `_replay_world` — and if any state answer touches the KB before
   it reaches `_gate()`. It strips comments first, deliberately: this is the
   opposite of `check-mechanics.mjs`'s seventh check, which greps comments ON
   PURPOSE. A comment listing the active module set rots like code; a comment
   describing a rule is the rule being documented, and forbidding the file to
   explain itself would be perverse.
6. **A half-present install must still be FOUND.** `_ready()` joins the groups
   BEFORE it configures, and the gate enforces that order. An adapter that
   refused to join because its install was broken would be invisible, and a Talos
   Bridge that finds no adapter degrades to generic scene queries — §7.8's first
   silent failure. The failure MODES live in a table compiled into
   `talos_bridge.cpp` (not read from the contract, because the contract is one of
   the things that can be missing) and the gate holds that table and the
   contract's `stage: "install"` tokens to each other in both directions.
7. **The replay leg is a PORT of core's `src/replay/`, and it must stay pinned.**
   The bundle cannot help: `host-crypto.js` makes `createHash` throw on purpose,
   and core's replay module hashes. `gdextension/src/talos_replay.cpp` therefore
   computes the content address with this repo's own `sha256.cpp` +
   `canonical_json.cpp` — the pair already byte-pinned to `save-envelope.ts` —
   and `tools/vendor-replay-fixtures.mjs` mints the evidence by running core's
   REAL module under Node. A change to core's replay module means re-vendoring,
   not re-deriving. Note `entropy` hashes UTF-16 code units, not bytes: a leg
   that counted bytes would agree for every ASCII seed and diverge only for the
   worlds nobody tests.
