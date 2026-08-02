# Third-party dependencies — Insimul GDExtension

## godot-cpp (pin)

The extension is built against **godot-cpp**, the official C++ bindings for
GDExtension.

| Field       | Value                                              |
|-------------|----------------------------------------------------|
| Repository  | https://github.com/godotengine/godot-cpp           |
| Pin (tag)   | `godot-4.2-stable`                                 |
| License     | MIT                                                |
| Vendoring   | git submodule at `packages/godot/gdextension/godot-cpp` |

`compatibility_minimum = 4.2` in `insimul.gdextension` matches this pin (Godot
4.2+ per the plugin README). Bump both together when moving to a newer godot-cpp.

Add it with:

```sh
cd packages/godot/gdextension
git submodule add https://github.com/godotengine/godot-cpp godot-cpp
git -C godot-cpp checkout godot-4.2-stable
```

> The submodule is **not** vendored in this repo yet — the Ralph harness has no
> `scons`/`godot`/`godot-cpp` toolchain, so the C++ that depends on godot-cpp is
> syntax-gated, not compiled here. See `README.md` → *Structural fallback*.

## libinsimul (native Prolog core)

The `InsimulProlog` class links **libinsimul**, the shared native Prolog core
(Trealla-backed) produced by the `libinsimul-bootstrap` PRD (`insimul-native/`).

| Field       | Value                                                        |
|-------------|--------------------------------------------------------------|
| Source      | `insimul-native/` (`native/`) — its own submodule            |
| Pin         | commit `a9287b579c2f998f78ef94c5f19bc3290dc397a2`, libinsimul 0.1.0, Trealla v2.106.1 |
| Consumption | `insimul-native/dist/<platform>/` per `docs/consuming.md`    |
| Header      | `vendor/insimul/insimul.h` — a **verbatim copy** of the shipping header |
| License     | see `insimul-native/THIRD_PARTY.md` (Trealla: MIT)           |

`vendor/insimul/insimul.h` used to be a hand-written *contract copy* written
before the library existed, and tasklist 100 US-2 — the first story to actually
LINK libinsimul rather than syntax-gate against it — found it wrong on three
counts, including the return-code polarity of every mutating call. It is now a
verbatim copy of the shipping header. Re-copy it when the ABI moves; never edit
it in place.

## QuickJS (embedded JS engine for libinsimulcore)

`corebridge/` embeds **QuickJS** to run `@insimul/core`'s TypeScript behind a C
ABI — see `corebridge/README.md` and `RUNTIME_CORE_ADOPTION.md` §4.5.

| Field       | Value                                                         |
|-------------|---------------------------------------------------------------|
| Upstream    | https://bellard.org/quickjs/ (Fabrice Bellard, Charlie Gordon) |
| Pin         | `2025-04-26` (`corebridge/vendor/quickjs/VERSION`)            |
| License     | MIT (`corebridge/vendor/quickjs/LICENSE`)                     |
| Vendoring   | source drop, **unmodified**, in `corebridge/vendor/quickjs/`  |

Vendored rather than submoduled for the same reason libinsimul vendors Trealla:
it is a small, dependency-free C source set, and a plugin that a game developer
unzips into `addons/` cannot ask them to init submodules. Only the engine core
is taken — `quickjs-libc` is deliberately excluded, so the embedded runtime has
no filesystem, process or network access at all.

Bump by replacing the files and the `VERSION` stamp together, then re-running
`npm run test:radiant`.

## `@insimul/core` bundle (generated)

`corebridge/vendor/core/` holds `@insimul/core`, bundled to a single script and
embedded as a C array. It is a **generated build artifact**, not third-party
code and not hand-written: regenerate it with `npm run vendor:core -- --core
<path-to-packages/core>`. Provenance (source commit, module list, hash) is in
`corebridge/vendor/core/VENDORED.json`; `npm run check` fails if the artifacts
drift from each other.

| Field       | Value                                                    |
|-------------|----------------------------------------------------------|
| Source      | `@insimul/core` (`packages/core`), Apache-2.0            |
| Generator   | `tools/vendor-core-bundle.mjs` (esbuild)                 |
| Provenance  | `corebridge/vendor/core/VENDORED.json`                   |
