# Walkthrough: an AI character, end to end

This is a worked example of the plugin's **conversation** side — the part that lets an NPC
speak, be heard, and move its mouth in time with its own voice. It's the fastest way to build
intuition for the nodes, because a single line of dialogue flows through all of them at once:
text streams in, audio streams in beside it, viseme (mouth-shape) data drives the face, and the
microphone lets the player talk back.

Everything here lives in the `addons/insimul/` addon and is pure GDScript — no native build
required. You do need something for the NPC to talk *to*: either an Insimul server (set
`server_url` on the `InsimulClient` autoload) or a local LLM (see [Talking to a local LLM
instead of a server](#talking-to-a-local-llm-instead-of-a-server) at the end).

## The cast of nodes

| Node | Base | What it does |
| --- | --- | --- |
| `InsimulClient` | autoload (`Node`) | One connection + session for the whole game. Configured once in the Inspector. |
| `InsimulNPC` | `Node` | Attach one per NPC. Owns that character's conversation and re-emits its events. |
| `InsimulAudioPlayer` | `Node` | Queues streamed TTS audio chunks into an `AudioStreamPlayer3D`. |
| `InsimulLipSync` | `Node` | Applies viseme data to a mesh's blend shapes so the mouth matches the audio. |
| `InsimulMicrophone` | `Node` | Captures microphone audio for voice input. |

The pattern throughout is **signals, not polling**: you connect to a node's signals in `_ready()`
and react as data arrives. Nothing blocks the frame.

## Step 1 — Configure the client (once)

`InsimulClient` is registered as an autoload the moment you enable the plugin. Select it and set
these in the Inspector:

| Property | Meaning |
| --- | --- |
| `server_url` | Where the Insimul server answers (default `http://localhost:8080`). |
| `api_key` | Auth token, if your server requires one. |
| `world_id` | Which world the conversation is scoped to (default `default-world`). |
| `language_code` | Default language, e.g. `en`, `fr`, `es`. |

The provider dropdowns (`chat_provider`, `tts_provider`, `stt_provider`) pick where each stream
comes from — `Server`, `Local`, or `None`. Leave them on their defaults to start.

## Step 2 — Give an NPC a voice

Add an `InsimulNPC` as a child of your character (e.g. under its `CharacterBody3D`), set its
`character_id` to a character the world knows about, and connect to its signals:

```gdscript
@onready var npc := $InsimulNPC

func _ready() -> void:
    npc.text_received.connect(_on_text)
    npc.conversation_started.connect(_on_started)
    npc.conversation_ended.connect(_on_ended)

func talk_to_npc() -> void:
    npc.start_conversation()
    npc.send_text("Hello!")

func _on_text(text: String, is_final: bool) -> void:
    # `is_final` is false for each streamed fragment and true for the last one.
    print("NPC says: ", text)
```

That is a complete, working conversation. Everything below is enrichment.

## Step 3 — Hear it (streaming TTS audio)

The server streams the spoken audio in chunks alongside the text. Feed each chunk to an
`InsimulAudioPlayer` and it plays them back in order through a 3D audio source:

```gdscript
@onready var audio_player := $InsimulAudioPlayer
@onready var npc := $InsimulNPC

func _ready() -> void:
    npc.audio_chunk_received.connect(func(chunk):
        audio_player.queue_chunk(chunk)
    )
```

## Step 4 — See it (lip sync)

Alongside the audio comes **viseme** data — the sequence of mouth shapes that matches the speech.
An `InsimulLipSync` node maps those onto the blend shapes of a `MeshInstance3D` so the face moves
with the voice. Set its `target_mesh` to the head mesh, then:

```gdscript
@onready var lip_sync := $InsimulLipSync
@onready var npc := $InsimulNPC

func _ready() -> void:
    npc.facial_data_received.connect(func(data):
        lip_sync.queue_facial_data(data)
    )
```

## Step 5 — Talk back (microphone input)

To let the player answer out loud, capture audio with `InsimulMicrophone` and send it to the NPC
(the server transcribes it). A push-to-talk button is the simplest driver:

```gdscript
@onready var mic := $InsimulMicrophone
@onready var npc := $InsimulNPC

func _on_push_to_talk_pressed() -> void:
    mic.start_recording()

func _on_push_to_talk_released() -> void:
    var audio_data := mic.stop_recording()
    npc.send_audio(audio_data)
```

## That's the whole loop

**Configure → talk → hear → see → answer.** Five nodes, all driven by signals. The reference
below lists every signal each emits, so you can bind exactly what your scene needs.

## Talking to a local LLM instead of a server

The client can run entirely off a local, Ollama-style endpoint instead of an Insimul server — set
`chat_provider` to `Local` and point `local_llm_server_url` at it (default
`http://localhost:11434/api/generate`, model `mistral`). This is handled by
`insimul_local_provider.gd`; the node surface above is identical whichever provider you choose.

## Signals reference

### `InsimulClient`
- `text_received(chunk: InsimulTypes.TextChunk)`
- `audio_chunk_received(chunk: InsimulTypes.AudioChunk)`
- `facial_data_received(data: InsimulTypes.FacialData)`
- `action_trigger_received(action: InsimulTypes.ActionTrigger)`
- `conversation_started(session_id: String)`
- `conversation_ended(session_id: String)`
- `error_occurred(message: String)`

### `InsimulNPC`
- `text_received(text: String, is_final: bool)`
- `audio_chunk_received(chunk: InsimulTypes.AudioChunk)`
- `facial_data_received(data: InsimulTypes.FacialData)`
- `action_trigger_received(action: InsimulTypes.ActionTrigger)`
- `conversation_started()`
- `conversation_ended()`
- `error_occurred(message: String)`

`action_trigger_received` carries an in-world action the character decided to take (open a door,
hand over an item, and so on) — your game decides what to do with it.
