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
| Source      | `insimul-native/` (plan §3.1) — becomes its own submodule    |
| Consumption | `insimul-native/dist/<platform>/` per `docs/consuming.md`    |
| Header      | `vendor/insimul/insimul.h` here is a **contract copy** of the ABI |
| License     | see `insimul-native/THIRD_PARTY.md` (Trealla: MIT)           |

Until libinsimul-bootstrap lands, `vendor/insimul/insimul.h` stands in for the
real dist header so the wrapper is syntax-gated against the exact ABI. Replace it
with the shipped header (and drop the libs under `bin/`) when consuming a build.
