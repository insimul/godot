# The runtime: worlds, saves, and quests

The conversation nodes ([conversation-walkthrough.md](conversation-walkthrough.md)) work with
nothing but GDScript. This page is about the *other* half of the plugin — the **portable
runtime** that loads a world, tracks its state in a real logic engine, saves and restores it, and
generates quests. This half is native: it needs the GDExtension to be built (see
[`../gdextension/README.md`](../gdextension/README.md)), and it degrades gracefully when the
binary is absent — the runtime classes report the failure through `last_error()` rather than
crashing.

## The one idea to hold onto: the world state is Prolog

Insimul games keep their canonical state in a **Prolog knowledge base**. Prolog is a logic
language: facts (`has(player, sword).`) and rules (`can_enter(X, Room) :- has_key(X, Room).`),
with a query engine that does real unification and backtracking to answer questions. Instead of
scattering booleans and inventory arrays across scripts, the world *is* a set of Prolog clauses,
and gameplay asks it questions.

This plugin exposes that engine to Godot as **`InsimulProlog`**, a C++ GDExtension class wrapping
`libinsimul` (a natively linked Prolog runtime). Its full method surface — `consult`, `query`,
`assert_fact`, `retract_fact`, `snapshot`, `restore` — and how Prolog terms decode into Godot
`Variant`s is documented in [`../gdextension/README.md`](../gdextension/README.md). A taste:

```gdscript
var kb := ClassDB.instantiate("InsimulProlog")
kb.consult("parent(tom, bob).")
for sol in kb.query("parent(tom, X)"):
    print(sol["X"])   # -> bob
```

## The runtime classes

These GDScript classes (in `addons/insimul/runtime/`) compose the native cores into the systems a
game actually uses. All are `RefCounted` — you create and hold them; they are not scene nodes.

| Class | What it does |
| --- | --- |
| `InsimulWorldSource` | Loads a world — from a save file's embedded snapshot or a bare world document — into the generated DTO classes, gating on the save-format version so incompatible data is rejected before any accessor runs. |
| `InsimulSaveSystem` | Reads and writes save files through the native, canonical, integrity-stamped save codec (migrating older formats up). |
| `InsimulQuestSystem` | Tracks quests and objectives against the knowledge base, emitting `quest_completed` / `objective_completed`. |
| `InsimulRadiantSource` | Generates *radiant* quests (see below). |
| `InsimulContentLibrary` | Imports a shared, engine-neutral content pack (items, characters, towns, quests, narratives) into native Godot entities — the artifact a creator authors once and imports into every engine. |
| `InsimulRuntime` | The startup orchestrator that ties the others into one boot/resume/save loop. |

### The full loop, in one class

`InsimulRuntime` is the "just start the game" entry point. It runs the sequence
**world source → save slot → knowledge base → systems init**:

- **Boot** — prefer an existing, integrity-checked save slot; if there is none, or it is corrupt,
  start a new game from the world snapshot. A bad slot never bricks startup.
- **Rehydrate** — from the (migrated) save file, load the world, restore the knowledge base from
  the saved Prolog facts, and hydrate every quest's Prolog content.
- **Commit + save** — snapshot the live knowledge base back into the save file and write a
  canonical, integrity-stamped envelope. A state-only commit never mutates the immutable world
  snapshot, so its integrity hash stays stable across save/reload.

## Radiant quests: deterministic generation

*Radiant* quests are the procedurally generated, "there's always something new to do" kind. In
Insimul they are **deterministic**: the same world, seed, and in-game time always produce
byte-identical quests. `InsimulRadiantSource` doesn't re-implement that generator — it calls the
**shared Insimul runtime core**'s own generator across the native bridge, so Godot, the other
engines, and the web build all emit the same quests from the same inputs.

```gdscript
var radiant := InsimulRadiantSource.new()
var quests := radiant.generate(world_facts, radiant.base_templates().split("\n"), "my-seed", world_time)
for quest in quests:
    prolog.consult(quest["questContent"])
    for fact in quest["factsToRetract"]:
        prolog.retract_fact(fact)
    for fact in quest["factsToAssert"]:
        prolog.assert_fact(fact)
```

Two usage notes:

- **`generate()` is a decision-rate call.** Tick it when the director should offer new work —
  never from `_process`.
- **Opting out.** Set `source = InsimulRadiantSource.SOURCE_NONE` for the pre-adoption behaviour
  (no generation).

## Why "the same on every engine" is a testable claim, not a hope

The runtime shares one semantics authority — the Insimul runtime core — behind a small C ABI, so
the logic lives in exactly one place and every engine binds to it rather than re-deriving it. That
parity is *pinned*: a vendored cross-engine test corpus (`conformance/`) is replayed through both
this repo's native cores and the shared core, and the build fails if they disagree. How the bridge
runs the shared core, and why the boundary is a C ABI rather than a shared language, is in
[`../gdextension/corebridge/README.md`](../gdextension/corebridge/README.md); the parity gates
themselves are in [`../VERIFICATION.md`](../VERIFICATION.md).
