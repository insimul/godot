class_name InsimulNPC
extends Node
## InsimulNPC — Attach as a child of CharacterBody3D to enable AI conversation.
##
## Manages the conversation lifecycle for a single NPC, forwarding events
## from the InsimulClient autoload to local signals for easy per-NPC handling.

# ── Signals ──────────────────────────────────────────────────────────────────

## Emitted for each streaming text token from this NPC.
signal text_received(text: String, is_final: bool)
## Emitted for each TTS audio chunk from this NPC.
signal audio_chunk_received(chunk: InsimulTypes.AudioChunk)
## Emitted when viseme/facial data arrives for this NPC's lip sync.
signal facial_data_received(data: InsimulTypes.FacialData)
## Emitted when the server triggers a game action for this NPC.
signal action_trigger_received(action: InsimulTypes.ActionTrigger)
## Emitted when conversation starts.
signal conversation_started()
## Emitted when conversation ends.
signal conversation_ended()
## Emitted on error.
signal error_occurred(message: String)

# ── Export Variables (Inspector) ──────────────────────────────────────────────

## The Insimul character ID this NPC maps to.
@export var character_id: String = ""
## Optional language override for this NPC's conversations.
@export var language_code: String = ""

# ── State ────────────────────────────────────────────────────────────────────

var _session_id: String = ""
var _is_conversing: bool = false
var _client: Node = null  # InsimulClient autoload


func _ready() -> void:
	# Connect to the InsimulClient autoload
	_client = Engine.get_singleton("InsimulClient") if Engine.has_singleton("InsimulClient") else get_node_or_null("/root/InsimulClient")
	if _client == null:
		push_warning("InsimulNPC: InsimulClient autoload not found. Ensure the Insimul plugin is enabled.")
		return
	_client.text_received.connect(_on_text_received)
	_client.audio_chunk_received.connect(_on_audio_chunk_received)
	_client.facial_data_received.connect(_on_facial_data_received)
	_client.action_trigger_received.connect(_on_action_trigger_received)
	_client.conversation_ended.connect(_on_conversation_ended)
	_client.error_occurred.connect(_on_error)


func _exit_tree() -> void:
	if _is_conversing:
		end_conversation()


# ── Public API ───────────────────────────────────────────────────────────────

## Start a conversation with this NPC. Returns the session ID.
func start_conversation(session_id: String = "") -> String:
	if _client == null:
		push_error("InsimulNPC: No InsimulClient available.")
		return ""
	if character_id == "":
		push_error("InsimulNPC: character_id is not set.")
		return ""
	_session_id = _client.start_conversation(character_id, session_id)
	_is_conversing = true
	conversation_started.emit()
	return _session_id


## Send text to this NPC.
func send_text(text: String) -> void:
	if not _is_conversing or _client == null:
		push_warning("InsimulNPC: No active conversation.")
		return
	_client.send_text(text, character_id, language_code)


## Send recorded audio to this NPC.
func send_audio(audio_data: PackedByteArray) -> void:
	if not _is_conversing or _client == null:
		push_warning("InsimulNPC: No active conversation.")
		return
	_client.send_audio(audio_data, character_id, language_code)


## End the conversation with this NPC.
func end_conversation() -> void:
	if not _is_conversing or _client == null:
		return
	_client.end_conversation()
	_is_conversing = false
	_session_id = ""
	conversation_ended.emit()


## Whether this NPC is currently in a conversation.
func is_conversing() -> bool:
	return _is_conversing


## Get the current session ID (empty if not conversing).
func get_session_id() -> String:
	return _session_id


# ── Internal ─────────────────────────────────────────────────────────────────

func _on_text_received(chunk: InsimulTypes.TextChunk) -> void:
	if not _is_conversing:
		return
	text_received.emit(chunk.text, chunk.is_final)


func _on_audio_chunk_received(chunk: InsimulTypes.AudioChunk) -> void:
	if not _is_conversing:
		return
	audio_chunk_received.emit(chunk)


func _on_facial_data_received(data: InsimulTypes.FacialData) -> void:
	if not _is_conversing:
		return
	facial_data_received.emit(data)


func _on_action_trigger_received(action: InsimulTypes.ActionTrigger) -> void:
	if not _is_conversing:
		return
	action_trigger_received.emit(action)


func _on_conversation_ended(session_id: String) -> void:
	if session_id == _session_id:
		_is_conversing = false
		_session_id = ""
		conversation_ended.emit()


func _on_error(message: String) -> void:
	if _is_conversing:
		error_occurred.emit(message)
