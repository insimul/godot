# Insimul GDExtension — native Prolog for Godot 4

A GDExtension (C++ against [godot-cpp](https://github.com/godotengine/godot-cpp))
that exposes **`InsimulProlog`**, a `RefCounted` class wrapping
[libinsimul](../../../../docs/PLATFORM_SPLIT_AND_ENGINE_PLUGINS.md) — the shared
native Prolog core (real unification/backtracking/rules) — replacing the fake
substring-matching `templates/scripts/systems/prolog_engine.gd`.

This is the Godot leg of the three native-Prolog engine plugins (Unity: P/Invoke,
Unreal: ThirdParty module, Godot: GDExtension). Plan: §3.1, §4.1.

## `InsimulProlog` surface

| Method                        | Returns            | Notes                                        |
|-------------------------------|--------------------|----------------------------------------------|
| `consult(source: String)`     | `bool`             | Load Prolog program text (clauses/directives)|
| `assert_fact(fact: String)`   | `bool`             | Assert one fact/clause                       |
| `retract_fact(fact: String)`  | `bool`             | Retract the first match                      |
| `query(goal: String)`         | `Array[Dictionary]`| One Dictionary per solution (see below)      |
| `snapshot()`                  | `String`           | Canonical Prolog text of the dynamic-fact set|
| `restore(image: String)`      | `bool`             | Replace the dynamic-fact set                 |
| `last_error()`                | `String`           | Reason for the most recent failure           |

### Query result shape

`query(goal)` returns `Array[Dictionary]`, one entry per solution:

- `[]` — the goal **failed** (no solutions).
- `[{}]` — the goal **succeeded** with no variable bindings.
- `[{ "X": <value>, ... }, ...]` — one Dictionary per solution, each mapping a
  query variable name to its bound term.

Terms decode from libinsimul's JSON binding format to Godot `Variant`:

| Prolog term        | libinsimul JSON                       | Godot Variant                        |
|--------------------|---------------------------------------|--------------------------------------|
| atom               | `"bob"`                               | `String`                             |
| integer            | `5`                                   | `int`                                |
| float              | `3.5`                                 | `float`                              |
| list `[a,b]`       | `["a","b"]`                           | `Array`                              |
| compound `f(a,b)`  | `{"functor":"f","args":["a","b"]}`    | `Dictionary` `{functor, args}`       |

```gdscript
var kb := ClassDB.instantiate("InsimulProlog")
kb.consult("parent(tom, bob).")
for sol in kb.query("parent(tom, X)"):
    print(sol["X"])   # -> bob
```

## Layout

```
gdextension/
  insimul.gdextension       # descriptor: entry_symbol + per-platform lib paths
  SConstruct                # godot-cpp build (needs ./godot-cpp submodule)
  src/
    prolog_value.{h,cpp}    # dependency-free marshalling core (HOST-TESTABLE)
    insimul_prolog.{h,cpp}  # RefCounted wrapper (godot-cpp; syntax-gated)
    register_types.{h,cpp}  # GDExtension entry / ClassDB registration
  vendor/insimul/insimul.h  # libinsimul C ABI — contract copy (see THIRD_PARTY.md)
  test/
    test_marshalling.cpp    # host unit tests for the marshalling core
    run_host_tests.sh       # clang++ build+run — the US-GP1 gate
  smoke/test_smoke.gd       # headless end-to-end (godot --headless -s)
```

## Building & testing

### Host marshalling tests (runs here, no godot toolchain)

The binding-JSON → `PrologValue` decode in `src/prolog_value.*` is deliberately
free of godot-cpp and libinsimul, so it compiles and runs under a plain C++
toolchain:

```sh
bash packages/godot/gdextension/test/run_host_tests.sh
```

This is the machine-verified gate. Only the thin `PrologValue → Variant` adapter
in `insimul_prolog.cpp` (a mechanical 1:1 of the tested kinds) is outside it.

### Full GDExtension build (needs the toolchain)

```sh
cd packages/godot/gdextension
git submodule add https://github.com/godotengine/godot-cpp godot-cpp   # pin: THIRD_PARTY.md
git -C godot-cpp checkout godot-4.2-stable
# point at a libinsimul dist built by insimul-native (docs/consuming.md):
export INSIMUL_NATIVE_DIST=/path/to/insimul-native/dist/macos
scons target=template_debug
```

### Headless smoke (when `godot` is on PATH)

```sh
godot --headless -s packages/godot/gdextension/smoke/test_smoke.gd
```

## Structural fallback (Ralph harness)

The harness has **no `scons`, no `godot`, no `godot-cpp`, and libinsimul is not
yet built** (it is produced by the `libinsimul-bootstrap` PRD, a dependency of
this one). Consequently:

- **What runs here:** `test/run_host_tests.sh` — the marshalling core built with
  `clang++` and executed. Green on this machine.
- **What is syntax-gated only:** `insimul_prolog.*`, `register_types.*`,
  `SConstruct`, `insimul.gdextension` — they encode the real godot-cpp/libinsimul
  contract but require the toolchain to compile/link. Human-verify per
  `THIRD_PARTY.md` once godot-cpp and an `insimul-native/dist` are available (a
  Godot binary makes `smoke/test_smoke.gd` a real end-to-end check).

`autoMerge` is off for this PRD precisely so a human reviews the toolchain wiring
before merge.
