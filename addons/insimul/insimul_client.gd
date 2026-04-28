extends Node
## InsimulClient — Autoloaded singleton managing the Insimul conversation service.
##
## Supports two modes:
##   - Server: HTTP/SSE to Insimul server (default)
##   - Local: Local LLM via GDLlama or Ollama HTTP
##
## Provider settings match the JS SDK and Unreal/Unity plugins.

# ── Signals ──────────────────────────────────────────────────────────────────

signal text_received(chunk: InsimulTypes.TextChunk)
signal audio_chunk_received(chunk: InsimulTypes.AudioChunk)
signal facial_data_received(data: InsimulTypes.FacialData)
signal action_trigger_received(action: InsimulTypes.ActionTrigger)
signal conversation_started(session_id: String)
signal conversation_ended(session_id: String)
signal error_occurred(message: String)

# ── Provider Selection ───────────────────────────────────────────────────────

@export_enum("Server", "Local") var chat_provider: int = InsimulTypes.ChatProvider.SERVER
@export_enum("Server", "Local", "None") var tts_provider: int = InsimulTypes.TTSProvider.SERVER
@export_enum("Server", "Local", "None") var stt_provider: int = InsimulTypes.STTProvider.NONE

# ── Server Settings ──────────────────────────────────────────────────────────

@export var server_url: String = "http://localhost:8080"
@export var api_key: String = ""
@export var world_id: String = "default-world"
@export var language_code: String = "en"

# ── Local LLM Settings ──────────────────────────────────────────────────────

@export var local_llm_server_url: String = "http://localhost:11434/api/generate"
@export var local_llm_model: String = "mistral"
@export_file("*.json") var world_data_path: String = "res://insimul_data/world_export.json"
@export_range(32, 2048) var max_tokens: int = 256
@export_range(0.0, 2.0) var temperature: float = 0.7

# ── State ────────────────────────────────────────────────────────────────────

var _http_client: InsimulHttpClient = null
var _local_provider: InsimulLocalProvider = null
var _session_id: String = ""
var _state: int = InsimulTypes.ConversationState.UNSPECIFIED
var _session_counter: int = 0


func _ready() -> void:
	if chat_provider == InsimulTypes.ChatProvider.LOCAL:
		_setup_local_provider()
	else:
		_setup_server_client()

	print("[Insimul] Client initialized — Chat: %s, TTS: %s, STT: %s" % [
		"Local" if chat_provider == InsimulTypes.ChatProvider.LOCAL else "Server",
		["Server", "Local", "None"][tts_provider],
		["Server", "Local", "None"][stt_provider],
	])


## Whether we're using local LLM mode.
var is_offline_mode: bool:
	get: return chat_provider == InsimulTypes.ChatProvider.LOCAL


# ── Public API ───────────────────────────────────────────────────────────────

func start_conversation(character_id: String, session_id: String = "") -> String:
	if _session_id != "":
		await end_conversation()
	if session_id == "":
		_session_counter += 1
		session_id = "godot_%s_%d" % [_generate_id(), _session_counter]
	_session_id = session_id
	_state = InsimulTypes.ConversationState.STARTED
	conversation_started.emit(_session_id)
	return _session_id


func send_text(text: String, character_id: String, override_language: String = "") -> void:
	if _session_id == "":
		error_occurred.emit("No active conversation. Call start_conversation() first.")
		return
	_state = InsimulTypes.ConversationState.ACTIVE
	var lang := override_language if override_language != "" else language_code

	if is_offline_mode and _local_provider != null:
		_local_provider.send_text(_session_id, character_id, text, lang)
	elif _http_client != null:
		_http_client.send_text(_session_id, character_id, world_id, text, lang)


func send_audio(audio_data: PackedByteArray, character_id: String,
		override_language: String = "") -> void:
	if _session_id == "":
		error_occurred.emit("No active conversation. Call start_conversation() first.")
		return
	_state = InsimulTypes.ConversationState.ACTIVE
	var lang := override_language if override_language != "" else language_code

	if is_offline_mode:
		error_occurred.emit("Audio input requires server mode or local STT")
		return

	if _http_client != null:
		_http_client.send_audio(_session_id, character_id, world_id, audio_data, lang)


func end_conversation() -> void:
	if _session_id == "":
		return

	if is_offline_mode and _local_provider != null:
		_local_provider.end_session(_session_id)
	elif _http_client != null:
		_http_client.end_session(_session_id)

	var old_session := _session_id
	_session_id = ""
	_state = InsimulTypes.ConversationState.ENDED
	conversation_ended.emit(old_session)


func get_session_id() -> String:
	return _session_id


func get_conversation_state() -> int:
	return _state


func health_check(callback: Callable) -> void:
	if is_offline_mode:
		var response := InsimulTypes.HealthCheckResponse.new()
		response.healthy = _local_provider != null and _local_provider.is_ready()
		response.version = "local"
		callback.call(response)
		return
	if _http_client != null:
		_http_client.health_check(callback)


# ── Setup ────────────────────────────────────────────────────────────────────

func _setup_server_client() -> void:
	_http_client = InsimulHttpClient.new(server_url, api_key)
	_http_client.setup(self)
	_http_client.text_chunk_received.connect(_on_text_chunk)
	_http_client.audio_chunk_received.connect(_on_audio_chunk)
	_http_client.facial_data_received.connect(_on_facial_data)
	_http_client.action_trigger_received.connect(_on_action_trigger)
	_http_client.error_received.connect(_on_error)
	_http_client.stream_completed.connect(_on_stream_completed)


func _setup_local_provider() -> void:
	_local_provider = InsimulLocalProvider.new()
	add_child(_local_provider)
	_local_provider.initialize(local_llm_server_url, local_llm_model, max_tokens, temperature)
	_local_provider.load_world_data(world_data_path)
	_local_provider.text_chunk_received.connect(_on_text_chunk)
	_local_provider.error_received.connect(_on_error)
	_local_provider.stream_completed.connect(_on_stream_completed)


# ── Internal ─────────────────────────────────────────────────────────────────

func _generate_id() -> String:
	var chars := "abcdefghijklmnopqrstuvwxyz0123456789"
	var id := ""
	for i in range(12):
		id += chars[randi() % chars.length()]
	return id


func _on_text_chunk(chunk: InsimulTypes.TextChunk) -> void:
	text_received.emit(chunk)

func _on_audio_chunk(chunk: InsimulTypes.AudioChunk) -> void:
	audio_chunk_received.emit(chunk)

func _on_facial_data(data: InsimulTypes.FacialData) -> void:
	facial_data_received.emit(data)

func _on_action_trigger(action: InsimulTypes.ActionTrigger) -> void:
	action_trigger_received.emit(action)

func _on_error(message: String) -> void:
	error_occurred.emit(message)

func _on_stream_completed() -> void:
	pass
