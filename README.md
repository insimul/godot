# Insimul Godot Plugin

Connect any Godot 4.2+ game to the Insimul AI conversation service. NPCs speak, listen, and lip-sync via streaming text, audio, and viseme data.

## Installation

1. Copy the `addons/insimul/` folder into your project's `res://addons/` directory.
2. Go to **Project → Project Settings → Plugins** and enable **Insimul**.
3. The `InsimulClient` autoload singleton is registered automatically.

## Quick Start

### Configure the client

Select the **InsimulClient** autoload in your scene tree and set these properties in the Inspector:

| Property        | Description                                      |
|-----------------|--------------------------------------------------|
| `server_url`    | Insimul server URL (e.g. `http://localhost:5000`) |
| `api_key`       | API key for authentication (optional)             |
| `world_id`      | World ID to scope conversations                   |
| `language_code` | Default language (e.g. `en`, `fr`, `es`)          |

### Add conversation to an NPC

1. Add an **InsimulNPC** node as a child of your NPC's `CharacterBody3D`.
2. Set the `character_id` property to the Insimul character ID.
3. Connect to the NPC's signals:

```gdscript
@onready var npc := $InsimulNPC

func _ready():
    npc.text_received.connect(_on_text)
    npc.conversation_started.connect(_on_started)
    npc.conversation_ended.connect(_on_ended)

func talk_to_npc():
    npc.start_conversation()
    npc.send_text("Hello!")

func _on_text(text: String, is_final: bool):
    print("NPC says: ", text)
```

### Audio playback (TTS)

Add an **InsimulAudioPlayer** as a child of the NPC and connect it:

```gdscript
@onready var audio_player := $InsimulAudioPlayer
@onready var npc := $InsimulNPC

func _ready():
    npc.audio_chunk_received.connect(func(chunk):
        audio_player.queue_chunk(chunk)
    )
```

### Lip sync

Add an **InsimulLipSync** node and set `target_mesh` to the NPC's `MeshInstance3D` with blend shapes:

```gdscript
@onready var lip_sync := $InsimulLipSync
@onready var npc := $InsimulNPC

func _ready():
    npc.facial_data_received.connect(func(data):
        lip_sync.queue_facial_data(data)
    )
```

### Microphone input

Add an **InsimulMicrophone** node for voice input:

```gdscript
@onready var mic := $InsimulMicrophone
@onready var npc := $InsimulNPC

func _on_push_to_talk_pressed():
    mic.start_recording()

func _on_push_to_talk_released():
    var audio_data := mic.stop_recording()
    npc.send_audio(audio_data)
```

## Components

| Component              | Description                                                |
|------------------------|------------------------------------------------------------|
| `InsimulClient`        | Autoload singleton — manages server connection and session |
| `InsimulNPC`           | Node — attach to any NPC for conversation                  |
| `InsimulAudioPlayer`   | Node — streams TTS audio to AudioStreamPlayer3D            |
| `InsimulLipSync`       | Node — applies viseme data to blend shapes                 |
| `InsimulMicrophone`    | Node — captures microphone audio for voice input           |
| `InsimulHttpClient`    | RefCounted — HTTP/SSE transport (internal)                 |
| `InsimulTypes`         | RefCounted — shared type definitions                       |

## Signals Reference

### InsimulClient
- `text_received(chunk: InsimulTypes.TextChunk)`
- `audio_chunk_received(chunk: InsimulTypes.AudioChunk)`
- `facial_data_received(data: InsimulTypes.FacialData)`
- `action_trigger_received(action: InsimulTypes.ActionTrigger)`
- `conversation_started(session_id: String)`
- `conversation_ended(session_id: String)`
- `error_occurred(message: String)`

### InsimulNPC
- `text_received(text: String, is_final: bool)`
- `audio_chunk_received(chunk: InsimulTypes.AudioChunk)`
- `facial_data_received(data: InsimulTypes.FacialData)`
- `action_trigger_received(action: InsimulTypes.ActionTrigger)`
- `conversation_started()`
- `conversation_ended()`
- `error_occurred(message: String)`

## Supported Versions

- Godot **4.2+**

## License

MIT
