class_name InsimulLocalProvider
extends Node
## Local LLM provider for offline NPC conversations.
##
## Supports two backends:
##   1. GDLlama (preferred) — runs llama.cpp in-process via GDExtension.
##      No external server needed. Assign a GDLlama node to gdllama_node.
##   2. HTTP fallback — calls an external Ollama/llama.cpp server via HTTP.
##      Used when GDLlama is not installed or no node assigned.
##
## Uses exported world data for character system prompts.

# ── Signals (same interface as InsimulHttpClient) ────────────────────────────

signal text_chunk_received(chunk: InsimulTypes.TextChunk)
signal error_received(message: String)
signal stream_completed()

# ── Configuration ────────────────────────────────────────────────────────────

## GDLlama node for in-process inference (optional — assign in Inspector).
## If null, falls back to HTTP. Install GDLlama from the Asset Library.
@export var gdllama_node: Node = null

## URL of external LLM server (used when GDLlama is not available).
var llm_server_url: String = "http://localhost:11434/api/generate"
## Model name for Ollama.
var llm_model: String = "mistral"
## Max response tokens.
var max_tokens: int = 256
## LLM temperature.
var temperature: float = 0.7

# ── State ────────────────────────────────────────────────────────────────────

var _world_data: InsimulTypes.ExportedWorld = null
var _histories: Dictionary = {}  # session_id -> Array of {role, text}
var _is_ready: bool = false
var _use_gdllama: bool = false
var _http_request: HTTPRequest = null


func initialize(server_url: String, model: String, tokens: int, temp: float) -> void:
	llm_server_url = server_url
	llm_model = model
	max_tokens = tokens
	temperature = temp
	_detect_gdllama()


func load_world_data(path: String) -> bool:
	_world_data = InsimulWorldExport.load_from_file(path)
	_is_ready = _world_data != null
	return _is_ready


func is_ready() -> bool:
	return _is_ready


# ── Messaging ────────────────────────────────────────────────────────────────

func send_text(session_id: String, character_id: String, text: String,
		_language_code: String = "en") -> void:
	if not _is_ready:
		error_received.emit("World data not loaded")
		return

	# Get or create history
	if not _histories.has(session_id):
		_histories[session_id] = []
	_histories[session_id].append({"role": "user", "text": text})

	if _use_gdllama and gdllama_node != null:
		_send_via_gdllama(session_id, character_id, text)
	else:
		_send_via_http(session_id, character_id)


func end_session(session_id: String) -> void:
	_histories.erase(session_id)


func get_greeting(character_id: String) -> String:
	if _world_data == null:
		return ""
	var ctx := _world_data.find_dialogue_context(character_id)
	return ctx.greeting if ctx != null else ""


# ── GDLlama Detection ───────────────────────────────────────────────────────

func _detect_gdllama() -> void:
	if gdllama_node != null:
		# Check if it has the expected methods
		if gdllama_node.has_method("generate_text") or gdllama_node.has_method("run_generate"):
			_use_gdllama = true
			print("[InsimulLocal] Using GDLlama for in-process LLM inference")
			return

	# Try to find a GDLlama node in the scene tree
	var tree := get_tree()
	if tree != null:
		for node in tree.root.get_children():
			if node.get_class() == "GDLlama" or (node.has_method("generate_text")):
				gdllama_node = node
				_use_gdllama = true
				print("[InsimulLocal] Found GDLlama node: %s" % node.name)
				return

	_use_gdllama = false
	print("[InsimulLocal] GDLlama not found — using HTTP fallback to %s" % llm_server_url)


# ── GDLlama Path ─────────────────────────────────────────────────────────────

func _send_via_gdllama(session_id: String, character_id: String, text: String) -> void:
	var prompt := _build_prompt(character_id, session_id)

	# GDLlama API: generate_text(prompt) or run_generate(prompt, callback)
	# The exact API depends on GDLlama version — try both patterns
	if gdllama_node.has_method("generate_text"):
		# Synchronous/async pattern
		var result: String = await gdllama_node.generate_text(prompt)
		_handle_llm_response(session_id, character_id, result)

	elif gdllama_node.has_method("run_generate"):
		# Signal-based pattern (GDLlama emits generate_text_finished)
		if gdllama_node.has_signal("generate_text_finished"):
			gdllama_node.generate_text_finished.connect(
				func(result: String):
					_handle_llm_response(session_id, character_id, result),
				CONNECT_ONE_SHOT
			)
		gdllama_node.run_generate(prompt)

	else:
		error_received.emit("GDLlama node does not have expected methods")
		stream_completed.emit()


func _handle_llm_response(session_id: String, character_id: String, result: String) -> void:
	result = result.strip_edges()

	if result.is_empty():
		error_received.emit("LLM returned empty response")
		stream_completed.emit()
		return

	# Store in history
	if _histories.has(session_id):
		_histories[session_id].append({"role": "assistant", "text": result})

	# Emit as text chunk
	var chunk := InsimulTypes.TextChunk.new()
	chunk.text = result
	chunk.is_final = true
	text_chunk_received.emit(chunk)
	stream_completed.emit()

	print("[InsimulLocal] LLM response for %s: %s" % [character_id, result.substr(0, 100)])


# ── HTTP Fallback Path ───────────────────────────────────────────────────────

func _send_via_http(session_id: String, character_id: String) -> void:
	if _http_request == null:
		_http_request = HTTPRequest.new()
		_http_request.use_threads = true
		add_child(_http_request)

	var prompt := _build_prompt(character_id, session_id)
	var body: String

	# Detect Ollama vs llama.cpp from URL
	if llm_server_url.contains("/api/generate") or llm_server_url.contains("/api/chat"):
		body = JSON.stringify({
			"model": llm_model,
			"prompt": prompt,
			"stream": false,
			"options": {
				"temperature": temperature,
				"num_predict": max_tokens,
				"top_k": 40,
				"top_p": 0.5,
				"repeat_penalty": 1.18,
				"stop": ["Player:", "</s>", "\nPlayer"],
			}
		})
	else:
		body = JSON.stringify({
			"prompt": prompt,
			"n_predict": max_tokens,
			"temperature": temperature,
			"top_k": 40,
			"top_p": 0.5,
			"repeat_penalty": 1.18,
			"repeat_last_n": 256,
			"cache_prompt": true,
			"stream": false,
			"stop": ["Player:", "</s>", "\nPlayer"],
		})

	_http_request.request_completed.connect(
		func(_result: int, code: int, _headers: PackedStringArray, response_body: PackedByteArray):
			if code != 200:
				error_received.emit("LLM server returned %d" % code)
				stream_completed.emit()
				return

			var response_text := response_body.get_string_from_utf8()
			var json = JSON.parse_string(response_text)
			var generated := ""

			if json is Dictionary:
				# Ollama: {"response": "..."}
				if json.has("response"):
					generated = json["response"]
				# llama.cpp: {"content": "..."}
				elif json.has("content"):
					generated = json["content"]

			_handle_llm_response(session_id, character_id, generated),
		CONNECT_ONE_SHOT
	)

	var headers := PackedStringArray(["Content-Type: application/json"])
	_http_request.request(llm_server_url, headers, HTTPClient.METHOD_POST, body)


# ── Prompt Building ──────────────────────────────────────────────────────────

func _build_prompt(character_id: String, session_id: String) -> String:
	var prompt := ""

	# System prompt from dialogue context
	var ctx := _world_data.find_dialogue_context(character_id) if _world_data != null else null
	if ctx != null:
		prompt = ctx.system_prompt + "\n\n"
	else:
		prompt = "You are an NPC in a game world. Respond in character.\n\n"

	# Conversation history
	if _histories.has(session_id):
		var npc_name: String = ctx.character_name if ctx != null else "NPC"
		for entry in _histories[session_id]:
			if entry["role"] == "user":
				prompt += "Player: %s\n" % entry["text"]
			else:
				prompt += "%s: %s\n" % [npc_name, entry["text"]]

	# NPC turn marker
	var speaker_name: String = ctx.character_name if ctx != null else "NPC"
	prompt += "%s:" % speaker_name
	return prompt
