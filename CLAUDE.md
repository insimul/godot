# Working in `@insimul/godot`

Conventions and traps that cost somebody an hour. Not a tour of the repo — the
README is that, `RUNTIME_CORE_ADOPTION.md` is the design record, and
`VERIFICATION.md` is what to run.

## The gates

```sh
npm run check            # ALWAYS. Structural .gd lint + three drift/mirror guards.
npm run test:mechanics   # the seven band-120 mechanic modules, 43 checks
npm run test:radiant     # the first adopted slice, 11 conformance vectors
npm run test:quest-parity
npm run test:conformance
```

Everything under `gdextension/test/run_*.sh` builds with a **plain C/C++
compiler** — no cmake, no scons, no godot-cpp, no Godot binary. Three of them
(`run_radiant_tests.sh`, `run_quest_parity_tests.sh`, `run_mechanic_tests.sh`)
additionally **link libinsimul** and fail loudly when it is absent rather than
skipping. Point them at a build:

```sh
INSIMUL_NATIVE_DIR=<insimul-native checkout>   bash gdextension/test/run_mechanic_tests.sh
INSIMUL_NATIVE_DIST=<dist/<platform>>          bash gdextension/test/run_mechanic_tests.sh
```

The sibling-layout probe only finds `../native` and `../../native`, so a worktree
that is not beside the project checkout MUST pass one of those variables.

**`npm run check` reads `git ls-files`.** A new `.gd` file that is not staged is
not scanned, and the gate prints a green number that means nothing. `git add`
before believing it.

## Two vendored artifacts, one rule

`gdextension/corebridge/vendor/core/` (the bundled core) and `conformance/` (the
shared corpus) are **generated**. Never hand-edit either; regenerate:

```sh
npm run vendor:core        -- --core <packages/core>
npm run vendor:conformance -- --core <packages/core>
node tools/verify-mechanics/check-mechanics.mjs --core <packages/core> --write
```

`packages/core` lives in the **babylon** checkout (`babylon/packages/core`), not
in a top-level `packages/`. All three tools also take `--check` (or run with no
`--core` at all), which verifies the checked-in artifact's own hashes; adding
`--core` is what actually diffs against core and is the only real drift check.

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
