# `libinsimulcore` — running `@insimul/core` from a native engine

This directory is the answer to the question the whole unification program hung
on: **how does a C++/C#/GDScript engine run 19,000 lines of TypeScript?**

The answer (RUNTIME_CORE_ADOPTION.md §4.5) is *not a language*. It is a **C ABI**
— `include/insimulcore.h`, five functions, opaque handle, JSON in, JSON out —
shaped exactly like `libinsimul`'s ABI, which Godot, Unity and Unreal already
consume successfully. Behind that ABI runs core's TypeScript inside an embedded
**QuickJS** today, and a Rust port later if it is ever funded, *without any
adapter noticing the difference*.

Zero lines of core are re-implemented here. TypeScript stays the single
semantics authority.

## The stack

```
GDScript                 addons/insimul/runtime/radiant_source.gd
   │  Dictionary → JSON      ← the ONLY place engine types are translated
InsimulCore              gdextension/src/insimul_core.{h,cpp}   [RefCounted]
   │  C ABI                  insimul_core_call(h, "radiant.generate", json)
libinsimulcore           src/insimulcore.c  =  QuickJS + the vendored core bundle
   │  JS → C                 __insimul_prolog_{create,consult,query,destroy}
libinsimul               Trealla, natively linked (../vendor/insimul/insimul.h)
```

Dependencies run one way only: adapters depend on core. Core gains no knowledge
of Godot, and this repository gains no edge into `packages/core` beyond two
vendored artifacts (the bundle here, the corpus in `../../conformance/`).

## Why the Prolog seam is wired to the native engine

Core's `createPrologEngine()` dynamic-imports `WasmPrologEngine`, which
instantiates libinsimul/Trealla compiled to **wasm32**. QuickJS has no
WebAssembly — and even if it did, wrapping a wasm build of an engine this plugin
already links natively would be absurd.

So the bundler resolves core's `../prolog/prolog-engine` import to
`js/host-prolog-engine.js`, an adapter-owned module implementing the same seam
over libinsimul's C ABI. **Core's source is never patched**; only the resolution
of its seam import changes, which is what a seam is for. The contract amendment
that would make this explicit (an injectable engine rather than a resolver
trick) is RUNTIME_CORE_ADOPTION.md §8.

`js/host-prolog-engine.js` therefore has one hard obligation: agree with
`packages/core/src/prolog/wasm-engine.ts` on everything the caller can observe —
`collapseTerm`, the trailing-`.` trim, the 1000-result default. The conformance
corpus is what proves it.

## Layout

| Path | What it is |
|------|------------|
| `include/insimulcore.h` | **The contract.** The one file that must not fork when this moves. |
| `src/insimulcore.c` | The QuickJS host: ABI, promise pump, Prolog bridge. |
| `js/entry.js` | The adopted surface — one entry per callable core method. |
| `js/host-prolog-engine.js` | Core's Prolog seam, implemented over libinsimul. Asserts and retracts **in place** rather than rebuilding the KB the way core's wasm engine does, with core's bookkeeping mirrored so nothing observable differs — see the file header. |
| `js/host-mechanics.js` | The session table and the eight host-interface shims the mechanic rows run through. Glue only: no mechanic is decided here. |
| `js/host-text-codec.js` | `TextEncoder`/`TextDecoder` for QuickJS, which has neither. A polyfill rather than a seam, imported FIRST because core's `identity/kinp.ts` constructs one at module scope. |
| `js/host-crypto.js` | Stand-in for Node's `crypto`, which core's `save-envelope.ts` imports at module scope. It **throws**: nothing on the adopted surface hashes, and a plausible wrong digest is worse than a stop. See `RUNTIME_CORE_ADOPTION.md` §8. |
| `vendor/quickjs/` | QuickJS 2025-04-26, unmodified (see `../THIRD_PARTY.md`). |
| `vendor/core/` | **Generated.** The bundled core + its provenance. Never hand-edit. |

## The method table, and what "adopted" means in it

`js/entry.js` holds every callable method. Two of them are **not** adopted
runtime surface:

| method | status |
|---|---|
| `radiant.generate`, `radiant.baseTemplates` | **adopted** — `InsimulRadiantSource` calls these at runtime. |
| `combat.*`, `stamina.*`, `perception.*`, `traversal.*`, `skill.*`, `equipment.*`, `routine.*` | **adopted** — the seven band-120 mechanic modules (27 rows), driven by `InsimulMechanicSession`. Each module is opened once (`<module>.create` → a handle), called many times, and released with `mechanic.dispose`, because a decision layer is stateful and a bridge call is not. |
| `mechanic.modules`, `mechanic.sessions`, `mechanic.dispose` | the session table and its introspection. |
| `quest.hydrate`, `quest.radiantTick` | **comparison only.** Nothing in the runtime calls them; they exist so `run_quest_parity_tests.sh` can diff core against this repo's hand-ported `gdextension/src/quest_system.cpp` over the same vectors. Quest hydration is still served by the C++ port. See `RUNTIME_CORE_ADOPTION.md` §10.3. |
| `core.methods` | introspection, so a gate can assert the surface. |

### Readings in, orders out

Every host interface core declares is a **callback**, and this ABI has none — no
function pointer crosses `insimul_core_call`, deliberately. So the mechanic rows
invert the direction: the engine gathers what core would have ASKED it (a
raycast, a navmesh path, an entity's base stats) before the call and passes it in
as an argument, and everything core would have TOLD the host comes back in the
result as `orders` for the engine to drain. `js/host-mechanics.js` is the
adapter's half; `addons/insimul/runtime/mechanics/insimul_mechanic_session.gd` is
the engine's. Neither contains a damage number, a cost or a suspicion level —
those are all core's, and `gdextension/test/run_mechanic_tests.sh` proves it by
firing the same shot with opposite host readings.

Keeping that distinction visible matters: a method reachable across the ABI is
not the same as a capability this plugin has adopted, and the gate asserts the
surface by name precisely so the two do not blur.

## Adopting more of core

1. Add a method to the table in `js/entry.js`.
2. Re-vendor the bundle from a checkout that has `packages/core`:
   ```sh
   npm run vendor:core -- --core ../babylon/packages/core
   ```
3. Add corpus coverage for the new method and extend the gate.

The bundle is a **checked-in build artifact**, not a build step, because this
repository is standalone by design — it cannot run a bundler against a package
it does not contain. It carries a recorded source commit and a hash, and
`npm run check` fails if the artifacts disagree with each other. Pass `--core`
to `--check` as well to additionally re-bundle and diff against core itself,
which is the real drift check:

```sh
node tools/vendor-core-bundle.mjs --check --core ../babylon/packages/core
```

## Building and testing

The gate builds the whole thing under a plain C/C++ toolchain — no cmake, no
scons, no godot-cpp, no Godot binary — and runs the shared radiant corpus:

```sh
npm run test:radiant                       # 11 cases, source=core
bash gdextension/test/run_radiant_tests.sh --source none   # 4 AGREE, 7 GAIN, 0 REGRESSION
npm run test:quest-parity                  # hand-ported C++ vs core: 7 AGREE, 0 REGRESSION
npm run test:mechanics                     # the seven mechanic modules: 43 checks
```

It **links libinsimul** (core's radiant algorithm is Prolog-driven), so it needs
the library and says so loudly when it is missing rather than skipping. Point it
at one with `INSIMUL_NATIVE_DIR` or `INSIMUL_NATIVE_DIST`.

In a real Godot build, `../SConstruct` compiles this directory into the
extension automatically.

## Where this should end up

In `native/` beside libinsimul, built and packaged by the same CMake, so all
three engines link **one** artifact instead of three. It lives here for now only
because tasklist 100's worktree is this repository. Moving it should be a file
move plus a CMake target — and the corollary from RUNTIME_CORE_ADOPTION.md §4.5
stands either way:

> **Do not invent a second mechanism.** If Unity needs core, it P/Invokes
> `libinsimulcore`. If Unreal needs core, it links `libinsimulcore`. The bridge
> is built once, not three times.

## Limits worth knowing

- **Nothing per-frame crosses this boundary.** Every call is a JSON round trip.
  Core is the decision layer; rendering, input and physics stay engine-side.
- **`insimul_core_call` is synchronous**, driving the JS job queue until the
  promise settles. Every promise in the adopted surface is resolved by JS or by
  a synchronous C call. A method that awaits real I/O would need a pump driven
  from the host's frame loop — the ABI would not change.
- **One handle, one thread**, exactly like an `insimul_kb`.
- **A `keepalive` KB is held open** for the handle's lifetime, working around a
  libinsimul defect where creating a KB after the live count reaches zero yields
  a handle that crashes on use (RUNTIME_CORE_ADOPTION.md §6.7). Delete it when
  libinsimul is fixed.
