# Insimul for Godot

> Drop-in AI characters — and an optional shared game runtime — for Godot 4.2+.

This is a Godot plugin that gives your game living, AI-driven characters: NPCs that hold real
conversations, speak with streamed voice, lip-sync to that voice, and listen to the player's
microphone. It's for Godot developers who want believable, reactive characters without building
the dialogue, speech, and world-logic stack themselves.

It is the Godot component of **Insimul**, a hybrid-AI platform for building fictional worlds and
games whose canonical state lives in a logic (Prolog) knowledge base — but **you don't need to
know the platform to use this plugin.** The conversation features work against a server or a local
LLM out of the box, and the deeper world/quest/save runtime is there when you want it.

## What you get

- **AI conversations for NPCs** — streaming text, text-to-speech audio, viseme (mouth-shape) data
  for lip-sync, and microphone voice input, all delivered through Godot nodes and signals.
- **Bring your own brain** — talk to an Insimul server, or point the plugin at a local,
  Ollama-style LLM endpoint. Same nodes either way.
- **A real logic engine in Godot** — `InsimulProlog`, a native GDExtension wrapping a genuine
  Prolog runtime (true unification and backtracking), for games whose world state is expressed as
  facts and rules rather than scattered flags.
- **A portable game runtime** — load worlds, save and restore them with an integrity-checked
  codec, run a quest system, import shared content packs, and generate deterministic *radiant*
  quests — all sharing one cross-engine core so behaviour matches the other Insimul engines.
- **Editor tooling** — in-editor docks for browsing/importing worlds, running world generators,
  testing conversations, and binding scene nodes to world entities.

The conversation side is pure GDScript and needs no build step. The runtime side is native and
needs the GDExtension compiled — but it degrades gracefully when the binary is absent.

## The problem it solves

Convincing game characters usually mean stitching together a dialogue system, an LLM integration,
a TTS pipeline, facial animation, speech-to-text, *and* a world-state model that all of them can
reason over. This plugin packages that whole stack behind a handful of Godot nodes, and keeps the
"what the character knows and can do" part in a logic engine instead of ad-hoc script state — so a
character's behaviour follows from the world's facts, not from booleans you have to keep in sync.

## How it works

The plugin has three layers, and most projects only touch the first:

1. **The addon (GDScript)** — `addons/insimul/`. Nodes you drop into scenes (`InsimulNPC`,
   `InsimulAudioPlayer`, `InsimulLipSync`, `InsimulMicrophone`) plus the `InsimulClient` autoload
   that owns the connection. This is all you need for AI conversations.
2. **The native core (C++ GDExtension)** — `gdextension/`. Exposes the Prolog engine and the save,
   quest, and world cores to Godot. Behind a small C ABI (`libinsimulcore`) it runs the *shared*
   Insimul runtime core, so the game logic is written once and reused by every engine rather than
   re-implemented per platform.
3. **The game-template tree** — `templates/`. A full Godot project the Insimul platform copies and
   customizes when a creator exports a world for Godot. Relevant to platform/export work, not to
   using the addon in your own project.

A few terms, unpacked: **Prolog** is a logic language of facts and rules with a query engine;
**GDExtension** is Godot's native (C++) plugin mechanism; a **viseme** is the mouth shape for a
speech sound; **radiant quests** are procedurally generated side-quests (here, deterministically —
same inputs always yield the same quests).

## Getting started

1. Copy the `addons/insimul/` folder into your project's `res://addons/` directory.
2. In **Project → Project Settings → Plugins**, enable **Insimul**. The `InsimulClient` autoload
   registers automatically.
3. Select the **InsimulClient** autoload and set `server_url` (default `http://localhost:8080`),
   and `api_key` / `world_id` / `language_code` as needed.

Then give a character a voice — add an `InsimulNPC` node under it, set its `character_id`, and
connect its signals:

```gdscript
@onready var npc := $InsimulNPC

func _ready() -> void:
    npc.text_received.connect(_on_text)

func talk_to_npc() -> void:
    npc.start_conversation()
    npc.send_text("Hello!")

func _on_text(text: String, is_final: bool) -> void:
    print("NPC says: ", text)
```

That's a complete conversation. To add streamed voice, lip-sync, and microphone input — and to
see the full signal reference — follow the walkthrough below.

> The runtime features (Prolog, saves, quests) additionally require the GDExtension to be built;
> see [`gdextension/README.md`](gdextension/README.md) for the toolchain and build steps.

## Learn by example

- **[Conversation walkthrough](docs/conversation-walkthrough.md)** — one AI character end to end:
  configure, talk, hear (TTS), see (lip-sync), and answer (microphone), plus the complete signal
  reference and how to run against a local LLM.
- **[The runtime: worlds, saves, and quests](docs/runtime-and-worlds.md)** — the native side: the
  Prolog world state, the save/quest/world classes, the one-call boot loop, and deterministic
  radiant quest generation.

## Components

| Component | Kind | What it does |
| --- | --- | --- |
| `InsimulClient` | autoload | Manages the server connection and session for the whole game. |
| `InsimulNPC` | node | Attach to any NPC to give it a conversation. |
| `InsimulAudioPlayer` | node | Streams TTS audio into an `AudioStreamPlayer3D`. |
| `InsimulLipSync` | node | Applies viseme data to a mesh's blend shapes. |
| `InsimulMicrophone` | node | Captures microphone audio for voice input. |
| `InsimulHttpClient` | `RefCounted` | HTTP/SSE transport (internal). |
| `InsimulTypes` | `RefCounted` | Shared conversation-event type definitions. |
| `InsimulProlog` | GDExtension | Native Prolog engine (query/assert/retract/snapshot). |
| `InsimulRuntime` / `InsimulSaveSystem` / `InsimulQuestSystem` / `InsimulWorldSource` / `InsimulContentLibrary` / `InsimulRadiantSource` | `RefCounted` | The portable runtime — see [the runtime doc](docs/runtime-and-worlds.md). |

## Repository layout

| Path | Contents |
| --- | --- |
| [`addons/insimul/`](addons/insimul/) | The drop-in Godot addon: conversation nodes, the runtime classes, editor docks, and generated DTOs. |
| [`gdextension/`](gdextension/) | The native C++ core — `InsimulProlog` and the save/quest/world cores — plus `corebridge/`, which runs the shared runtime core behind a C ABI. |
| [`templates/`](templates/) | The game-template tree the Insimul platform copies into exported Godot games. |
| [`conformance/`](conformance/) | Vendored cross-engine test corpus that pins runtime parity. |
| [`tools/`](tools/) · [`scripts/`](scripts/) | Verification, vendoring (drift guards), and release tooling. |
| `docs/` | The walkthroughs and contributor guides linked from this README. |

## Going deeper

Each of these top-level documents covers one concern in depth; open the one that matches what
you're doing.

| Document | When to read it |
| --- | --- |
| [`docs/conversation-walkthrough.md`](docs/conversation-walkthrough.md) | You're wiring up AI dialogue and want the full node/signal picture. |
| [`docs/runtime-and-worlds.md`](docs/runtime-and-worlds.md) | You're using the native runtime — worlds, saves, quests, radiant generation. |
| [`docs/export-pipeline.md`](docs/export-pipeline.md) | You're a contributor: the game-template export flow, how the generated types are produced, and how a release is staged. |
| [`gdextension/README.md`](gdextension/README.md) | You need the native Prolog API surface and how to build the GDExtension. |
| [`gdextension/corebridge/README.md`](gdextension/corebridge/README.md) | You want to know how a native engine runs the shared runtime core, and why the boundary is a C ABI. |
| [`MIGRATION.md`](MIGRATION.md) | You care about the switch from the old fake substring "Prolog" stub to the real native engine, and the portable runtime. |
| [`RUNTIME_CORE_ADOPTION.md`](RUNTIME_CORE_ADOPTION.md) | The plan for adopting the shared runtime core — what this engine keeps vs. adopts, and the cross-engine language-boundary decision. |
| [`VERIFICATION.md`](VERIFICATION.md) | Every quality gate here — the ones that run on any machine, and the human checklists that need a `godot` binary. |
| [`conformance/VENDORED.md`](conformance/VENDORED.md) | Where the vendored parity corpus comes from and the drift guard that keeps it honest. |
| [`CHANGELOG.md`](CHANGELOG.md) | What changed, release by release. |

## Supported versions

- Godot **4.2+**

## License

MIT — see [`LICENSE`](LICENSE).
