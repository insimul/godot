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
npm run test:talos-bridge # the insimul-talos-bridge decision half, 67 checks
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
shared corpus) and `addons/insimul_talos/supported-versions.json` + its mirrored
cases (the workspace's published engine-version matrix) are **generated**. Never
hand-edit any of them; regenerate:

```sh
npm run vendor:core        -- --core <packages/core>
npm run vendor:conformance -- --core <packages/core>
npm run vendor:versions    -- --matrix <workspace docs/supported-versions.json>
node tools/verify-mechanics/check-mechanics.mjs --core <packages/core> --write
```

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

## The Talos bridge is a THIRD artifact, and stays one

`addons/insimul_talos/` implements `TALOS_INSIMUL_BRIDGE.md` §7.5: it depends on
both projects and is depended on by neither. Four things that will bite:

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
