extends Node
## AI Service — autoloaded singleton for NPC chat with SSE streaming.
## Supports two modes: "insimul" (API server) and "gemini" (direct Gemini API).

signal chunk_received(npc_id: String, text: String)
signal response_complete(npc_id: String, full_text: String)
signal response_error(npc_id: String, error: String)

var config: Dictionary = {}
var contexts: Dictionary = {}  # characterId -> context dict
var histories: Dictionary = {}  # characterId -> Array of {role, text}

var _http: HTTPClient = HTTPClient.new()
var _active_npc_id := ""
var _active_buffer := ""
var _active_full_text := ""
var _is_requesting := false

func initialize(ai_config: Dictionary, dialogue_contexts: Array) -> void:
	config = ai_config
	contexts.clear()
	histories.clear()
	for ctx in dialogue_contexts:
		contexts[ctx.get("characterId", "")] = ctx
	print("[InsimulAI] Initialized with %d dialogue contexts, mode: %s" % [contexts.size(), config.get("apiMode", "insimul")])

func get_context(character_id: String) -> Dictionary:
	return contexts.get(character_id, {})

func clear_history(character_id: String) -> void:
	histories.erase(character_id)

## Current appearance description to attach to the next Insimul API request,
## populated by send_message(). The AIService call is fire-and-forget so we
## cache it on the instance rather than plumbing it through every helper.
var _pending_appearance_description: String = ""

## Send a chat message. `appearance_description` is an optional natural-language
## summary of the NPC's visible outfit/body type/accessories — forwarded to the
## server and injected into the system prompt so the LLM can acknowledge what
## the player actually sees. Mirrors BabylonChatPanel.ts sendMessageViaGrpc
## gameContext.appearanceDescription.
func send_message(character_id: String, user_message: String, appearance_description: String = "") -> void:
	if _is_requesting:
		response_error.emit(character_id, "Already processing a request")
		return

	var ctx = contexts.get(character_id)
	if ctx == null or ctx.is_empty():
		response_error.emit(character_id, "No dialogue context for: " + character_id)
		return

	if not histories.has(character_id):
		histories[character_id] = []

	histories[character_id].append({"role": "user", "text": user_message})
	_active_npc_id = character_id
	_active_buffer = ""
	_active_full_text = ""
	_is_requesting = true
	_pending_appearance_description = appearance_description

	var mode = config.get("apiMode", "insimul")
	if mode == "gemini":
		_send_gemini_direct(ctx, character_id)
	else:
		_send_insimul_api(ctx, character_id)

func _send_insimul_api(ctx: Dictionary, character_id: String) -> void:
	var history = histories.get(character_id, [])
	var body = {
		"characterId": character_id,
		"text": history[-1]["text"],
		"systemPrompt": ctx.get("systemPrompt", ""),
		"stream": true,
		"history": history.slice(0, -1),
	}
	if _pending_appearance_description != "":
		body["appearanceDescription"] = _pending_appearance_description
	_pending_appearance_description = ""

	var url = config.get("insimulEndpoint", "/api/gemini/chat")
	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_insimul_response.bind(character_id, request))
	request.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))

func _send_gemini_direct(ctx: Dictionary, character_id: String) -> void:
	var api_key = config.get("geminiApiKeyPlaceholder", "")
	var model = config.get("geminiModel", "gemini-3.1-flash")
	var url = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s" % [model, api_key]

	var history = histories.get(character_id, [])
	var contents = []
	for msg in history:
		var role = "model" if msg["role"] == "model" else "user"
		contents.append({"role": role, "parts": [{"text": msg["text"]}]})

	var body = {
		"system_instruction": {"parts": [{"text": ctx.get("systemPrompt", "")}]},
		"contents": contents,
		"generationConfig": {"temperature": 0.8, "maxOutputTokens": 2048},
	}

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_gemini_response.bind(character_id, request))
	request.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))

func _on_insimul_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, character_id: String, request: HTTPRequest) -> void:
	request.queue_free()
	_is_requesting = false

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		response_error.emit(character_id, "HTTP error: %d" % response_code)
		return

	var text = body.get_string_from_utf8()
	# Parse SSE lines
	var full_text = ""
	for line in text.split("\n"):
		line = line.strip_edges()
		if line.begins_with("data: "):
			var payload = line.substr(6)
			if payload == "[DONE]":
				continue
			var parsed = JSON.parse_string(payload)
			if parsed is Dictionary:
				var chunk = parsed.get("text", parsed.get("chunk", ""))
				if chunk != "":
					full_text += chunk
					chunk_received.emit(character_id, chunk)

	if full_text == "":
		# Non-streaming fallback
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			full_text = parsed.get("response", parsed.get("text", ""))
			if full_text != "":
				chunk_received.emit(character_id, full_text)

	histories[character_id].append({"role": "model", "text": full_text})
	response_complete.emit(character_id, full_text)

func _on_gemini_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, character_id: String, request: HTTPRequest) -> void:
	request.queue_free()
	_is_requesting = false

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		response_error.emit(character_id, "Gemini HTTP error: %d" % response_code)
		return

	var text = body.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	var full_text = ""

	if parsed is Dictionary and parsed.has("candidates"):
		var candidates = parsed["candidates"]
		if candidates is Array and candidates.size() > 0:
			var content = candidates[0].get("content", {})
			var parts = content.get("parts", [])
			for part in parts:
				full_text += part.get("text", "")

	if full_text != "":
		chunk_received.emit(character_id, full_text)
		histories[character_id].append({"role": "model", "text": full_text})
	else:
		response_error.emit(character_id, "Empty response from Gemini")
		return

	response_complete.emit(character_id, full_text)
