extends CanvasLayer
## Dialogue Panel — polished RPG/educational dialogue interface.
## Bottom-of-screen panel with NPC portrait, typewriter text, response buttons,
## and optional language learning mode.

signal dialogue_closed
signal gesture_performed(gesture_id: String)
signal quest_assigned(quest_data: Dictionary)
signal quest_branched(quest_id: String, choice_id: String, target_stage_id: String)
signal action_selected(action_id: String)
signal vocabulary_used(word: String)
signal conversation_turn(keywords: Array)
signal npc_conversation_started(npc_id: String)
signal npc_speech_update(text: String)
signal quest_turned_in(quest_id: String, rewards: Dictionary)
signal fluency_gain(fluency: float, gain: float)
signal conversation_summary(result: Dictionary)
signal dialogue_rating(message_index: int, rating: int)
signal chat_exchange(npc_id: String, player_message: String, npc_response: String)
signal talk_requested
signal npc_conversation_turn(npc_id: String, topic_tag: String)
signal writing_submitted(text: String, word_count: int)
signal listen_and_repeat(result: Dictionary)
signal conversational_action(actions: Array, turn_state: Dictionary)
signal new_word_learned(entry: Dictionary)
signal word_mastered(entry: Dictionary)
signal grammar_demonstrated(feedback: Dictionary)
signal translation_attempt(data: Dictionary)
signal friendship_changed(npc_id: String, relationship_strength: float)

const TYPEWRITER_SPEED := 30.0  # characters per second
const MAX_RESPONSE_BUTTONS := 4

## Stream watchdog window. If AIService never fires response_complete/response_error
## within this window (Gemini safety filter, dropped WS frame, hung TTS chain),
## the UI force-clears the "thinking" state instead of hanging forever.
## Mirrors BabylonChatPanel.ts streamTimeoutMs.
const STREAM_TIMEOUT_SECONDS := 90.0

var _current_character_id := ""
var _current_world_id := ""
var _current_character_gender := ""
var _is_open := false
var _is_typing := false
var _is_recording := false
var _is_listening_mode := false
var _target_language: String = ""
var _ai_provider := "server"
var _playthrough_id := ""
var _typewriter_elapsed := 0.0
var _typewriter_full_text := ""
var _typewriter_visible_chars := 0
var _pending_responses: Array = []
var _language_mode := false
var _gesture_container: HBoxContainer
var _inventory_items: Array = []
var _player_gold := 0

# Streaming response accumulator — collects chunks into a full response
var _full_response := ""

# Conversation turn counter — tracks how many exchanges have occurred
var _conversation_turn_count := 0

# Voice input enabled state — guards microphone features
var _voice_input_enabled := false

# Dialogue action data
var _current_dialogue_actions: Array = []
var _current_player_energy := 0.0

# Quest context state
var _quest_offering_context = null
var _active_quest_from_npc = null
var _quest_guidance_prompt := ""

# Quest bridge for conversation goal evaluation (ConversationQuestBridge reference)
var _quest_bridge = null

# Per-NPC conversation counter for friendship/rapport tracking
var _npc_conversation_counts: Dictionary = {}

# Pronunciation quest gating — only offer Listen & Repeat when active
var _pronunciation_quest_active := false

# Game event bus for emitting quest-tracking events
var _game_event_bus: Node = null

# Appearance provider — returns a natural-language description of the NPC's
# visible outfit/body type/accessories for the given character id. Forwarded
# to the server so the LLM can acknowledge what the player sees on screen.
# Mirrors BabylonGame.setAppearanceProvider().
var _appearance_provider: Callable = Callable()

# Active stream watchdog. Null when no request is in flight.
var _stream_watchdog_token: int = 0

# Raw transcript of player↔NPC turns for assessment grading. Each entry is a
# Dictionary {role: "user"|"assistant"|"system", content: String}. Mirrors
# BabylonChatPanel.getTranscriptForGrading().
var _transcript: Array = []

# Root UI nodes
var _panel: PanelContainer
var _portrait_rect: ColorRect
var _portrait_label: Label
var _npc_name_label: Label
var _dialogue_text: RichTextLabel
var _response_container: VBoxContainer
var _close_button: Button
var _lang_target_label: RichTextLabel
var _lang_translation_label: Label
var _lang_listen_button: Button
var _lang_container: VBoxContainer

func _ready() -> void:
	layer = 100
	_build_ui()
	visible = false

func _process(delta: float) -> void:
	if not _is_typing:
		return
	_typewriter_elapsed += delta
	var target_chars := int(_typewriter_elapsed * TYPEWRITER_SPEED)
	if target_chars > _typewriter_full_text.length():
		target_chars = _typewriter_full_text.length()
	if target_chars != _typewriter_visible_chars:
		_typewriter_visible_chars = target_chars
		_dialogue_text.text = _typewriter_full_text.substr(0, _typewriter_visible_chars)
		if _typewriter_visible_chars >= _typewriter_full_text.length():
			_finish_typing()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close_dialogue()
			get_viewport().set_input_as_handled()

func perform_gesture(gesture_id: String) -> void:
	gesture_performed.emit(gesture_id)

func open_dialogue(character_id: String, world_id: String = "", gender: String = "") -> void:
	_current_character_id = character_id
	_current_world_id = world_id
	_current_character_gender = gender
	_is_open = true
	visible = true
	_clear_responses()
	_dialogue_text.text = ""
	_full_response = ""
	_conversation_turn_count = 0
	_quest_offering_context = null
	_active_quest_from_npc = null
	_quest_guidance_prompt = ""
	if _gesture_container:
		_gesture_container.visible = true

	# Track per-NPC conversation count for friendship/rapport objectives
	var npc_count: int = _npc_conversation_counts.get(character_id, 0) + 1
	_npc_conversation_counts[character_id] = npc_count
	var new_strength: float = minf(float(npc_count) / 5.0, 1.0)
	friendship_changed.emit(character_id, new_strength)
	# Also emit through game event bus if available
	if _game_event_bus and _game_event_bus.has_method("emit_event"):
		_game_event_bus.emit_event({
			"type": "friendship_changed",
			"npcId": character_id,
			"relationshipStrength": new_strength,
		})

	# Load NPC context from AIService
	var ai := get_node_or_null("/root/AIService")
	if ai:
		var ctx: Dictionary = ai.get_context(character_id)
		if not ctx.is_empty():
			var npc_name: String = ctx.get("characterName", character_id)
			_npc_name_label.text = npc_name
			_set_portrait(npc_name)
			var greeting: String = ctx.get("greeting", "")
			if greeting != "":
				_start_typewriter(greeting)
		else:
			_npc_name_label.text = character_id
			_set_portrait(character_id)
	else:
		_npc_name_label.text = character_id
		_set_portrait(character_id)

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func close_dialogue() -> void:
	_is_open = false
	_is_typing = false
	_current_character_id = ""
	visible = false
	_clear_responses()
	if _gesture_container:
		_gesture_container.visible = false
	dialogue_closed.emit()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func show_npc_text(text: String) -> void:
	_clear_responses()
	_start_typewriter(text)

func show_responses(responses: Array) -> void:
	_pending_responses = responses
	if not _is_typing:
		_display_responses()

func show_language_content(target_text: String, translation: String) -> void:
	_language_mode = true
	_lang_container.visible = true
	_lang_target_label.text = "[b]%s[/b]" % target_text
	_lang_translation_label.text = translation

func hide_language_content() -> void:
	_language_mode = false
	_lang_container.visible = false

func is_open() -> bool:
	return _is_open

func is_recording() -> bool:
	return _is_recording

func is_listening_mode() -> bool:
	return _is_listening_mode

## Set the AI provider for dialogue (e.g. "server", "local").
func set_ai_provider(provider: String) -> void:
	_ai_provider = provider

func get_ai_provider() -> String:
	return _ai_provider

## Set the playthrough ID for conversation context.
func set_playthrough_id(id: String) -> void:
	_playthrough_id = id

## Set the target language for language-learning dialogue.
func set_target_language(lang: String) -> void:
	_target_language = lang

## Called after world data finishes loading. Re-sets character on the AI service
## so the system prompt is rebuilt with language context that may not have been
## available at initial open_dialogue() time.
func on_world_data_loaded() -> void:
	if _current_character_id == "":
		return
	var ai := get_node_or_null("/root/AIService")
	if ai and ai.has_method("set_character"):
		ai.set_character(_current_character_id, _current_world_id, _current_character_gender)

## Set player inventory context for NPC dialogue awareness.
func set_player_inventory_context(items: Array, gold: int) -> void:
	_inventory_items = items
	_player_gold = gold

## Set the quest bridge for conversation goal evaluation.
## Mirrors BabylonChatPanel.setQuestBridge() — used to evaluate quest objectives
## from conversation metadata responses via the InsimulClient SDK.
func set_quest_bridge(bridge) -> void:
	_quest_bridge = bridge

## Set the pronunciation quest active flag.
## When true, Listen & Repeat will be offered during conversations.
## Called by the game when the active quest changes.
func set_pronunciation_quest_active(active: bool) -> void:
	_pronunciation_quest_active = active

## Set the game event bus for emitting quest-tracking events (grammar, translation, friendship).
func set_game_event_bus(bus: Node) -> void:
	_game_event_bus = bus

## Register a provider that returns a natural-language description of the
## given NPC's visible appearance. The description is forwarded to the server
## and injected into the system prompt so the NPC can acknowledge what the
## player actually sees on screen. Mirrors BabylonGame.setAppearanceProvider().
func set_appearance_provider(provider: Callable) -> void:
	_appearance_provider = provider

## Resolve the appearance description for the current NPC. Returns "" on any
## error (missing provider, invalid callable, exception inside the callable)
## so callers can safely concatenate the result.
func _resolve_appearance_description() -> String:
	if not _appearance_provider.is_valid() or _current_character_id == "":
		return ""
	var desc: Variant = _appearance_provider.call(_current_character_id)
	if typeof(desc) == TYPE_STRING:
		return desc
	return ""

## Send a free-text player message to the AI service with hardening:
##   - Forwards appearance description so the LLM can acknowledge visible outfit.
##   - Arms a 30s watchdog so the UI never sticks on "thinking" if the server
##     forgets to send response_complete/response_error.
##   - Captures any terminal error through ErrorReporter for Sentry routing.
##
## The caller is responsible for wiring AIService signals (chunk_received,
## response_complete, response_error) to the dialogue panel UI. This method
## just sends the request and races it against the watchdog.
func send_player_message(text: String) -> void:
	if _current_character_id == "":
		return
	_transcript.append({"role": "user", "content": text})
	var ai := get_node_or_null("/root/AIService")
	if ai == null:
		_report_chat_error("AIService not available", "provider", text, 0)
		return

	var appearance := _resolve_appearance_description()
	if ai.has_method("send_message"):
		# Prefer the appearance-aware overload when available; fall back gracefully.
		var method_info := _lookup_method_arg_count(ai, "send_message")
		if method_info >= 3:
			ai.send_message(_current_character_id, text, appearance)
		else:
			ai.send_message(_current_character_id, text)

	_start_stream_watchdog(text)

## Start a 30s watchdog. Uses a monotonically-increasing token so late
## response_complete/response_error signals can't resurrect a cancelled watchdog.
func _start_stream_watchdog(player_message: String) -> void:
	_stream_watchdog_token += 1
	var token := _stream_watchdog_token
	_watchdog_await(token, player_message)

func _watchdog_await(token: int, player_message: String) -> void:
	await get_tree().create_timer(STREAM_TIMEOUT_SECONDS).timeout
	if token != _stream_watchdog_token:
		return  # A newer request started (or the current one completed) — stand down.
	_is_typing = false
	_full_response = ""
	var accumulated_len := _dialogue_text.text.length() if _dialogue_text else 0
	_report_chat_error(
		"Stream timeout: no done event in %ds" % int(STREAM_TIMEOUT_SECONDS),
		"timeout",
		player_message,
		accumulated_len
	)
	# Surface a user-facing message so the player isn't left staring at an empty bubble.
	var reporter := get_node_or_null("/root/ErrorReporter")
	var display_msg := "Sorry, the connection timed out. Please try again."
	if reporter and reporter.has_method("display_message_for_stage"):
		display_msg = reporter.display_message_for_stage("timeout")
	_start_typewriter(display_msg)

## Clear the watchdog — call from response_complete/response_error signal handlers.
## After this returns, any pending watchdog timer will no-op when it fires.
func clear_stream_watchdog() -> void:
	_stream_watchdog_token += 1

## Route a chat error through the Sentry-compatible reporter (autoload), falling
## back to push_error if ErrorReporter isn't installed. Mirrors BabylonChatPanel.ts
## Sentry.captureException calls.
func _report_chat_error(err_message: String, stage: String, player_message: String, accumulated_len: int) -> void:
	var reporter := get_node_or_null("/root/ErrorReporter")
	if reporter and reporter.has_method("capture_exception"):
		reporter.capture_exception(
			err_message,
			stage,
			_current_character_id,
			_current_world_id,
			player_message,
			accumulated_len
		)
	else:
		push_error("[DialoguePanel] chat-panel %s | %s | characterId=%s worldId=%s" % [
			stage, err_message, _current_character_id, _current_world_id
		])

## Detect how many arguments a method accepts. Returns the max argument count
## across overloads (Godot doesn't overload, so this is usually one entry).
## Defaults to 2 if introspection fails so the legacy (character_id, text) call
## is preferred over failing outright.
func _lookup_method_arg_count(obj: Object, method_name: String) -> int:
	if obj == null:
		return 0
	for m in obj.get_method_list():
		if m.get("name", "") == method_name:
			var args: Array = m.get("args", [])
			return args.size()
	return 2

## Request metadata via InsimulClient SDK instead of HTTP POST to /api/conversation/metadata.
## Processes goal evaluations through the quest bridge when available.
## Emits grammar_demonstrated and translation_attempt signals/events through game event bus.
func _request_metadata_via_sdk(player_message: String, npc_response: String) -> void:
	if _target_language == "":
		return
	var ai := get_node_or_null("/root/AIService")
	if not ai:
		return

	# Include active quest objectives for conversation goal evaluation
	var active_objectives = null
	if _quest_bridge and _quest_bridge.has_method("get_objectives_for_evaluation"):
		active_objectives = _quest_bridge.get_objectives_for_evaluation(_current_character_id)

	if ai.has_method("request_metadata"):
		ai.request_metadata(
			player_message,
			npc_response,
			_target_language,
			active_objectives,
			func(metadata: Dictionary) -> void:
				if metadata.is_empty():
					return
				# Process conversation goal evaluations — complete quest objectives
				var goal_evals = metadata.get("goalEvaluations", [])
				if goal_evals.size() > 0 and _quest_bridge and _quest_bridge.has_method("process_evaluations"):
					_quest_bridge.process_evaluations(goal_evals, _current_character_id, player_message)

				# Emit grammar_demonstrated for quest objective tracking
				var grammar = metadata.get("grammarFeedback", {})
				if not grammar.is_empty():
					var feedback_data := { "status": grammar.get("status", ""), "corrections": grammar.get("corrections", []) }
					grammar_demonstrated.emit(feedback_data)
					if _game_event_bus and _game_event_bus.has_method("emit_event") and grammar.get("status", "") == "correct":
						_game_event_bus.emit_event({
							"type": "grammar_demonstrated",
							"patternCount": 1,
						})

				# Emit translation_attempt for each vocab hint (target-language word used)
				var vocab_hints: Array = metadata.get("vocabHints", [])
				for hint in vocab_hints:
					var word: String = hint.get("word", hint.get("term", ""))
					var attempt_data := { "isCorrect": true, "word": word }
					translation_attempt.emit(attempt_data)
					if _game_event_bus and _game_event_bus.has_method("emit_event"):
						_game_event_bus.emit_event({
							"type": "translation_attempt",
							"isCorrect": true,
							"word": word,
						})
		)

## Add a system message to the dialogue panel.
func add_system_message(text: String) -> void:
	_clear_responses()
	_dialogue_text.text = "[color=#aaaacc][i]%s[/i][/color]" % text

## Add an NPC message externally.
func add_npc_message(text: String) -> void:
	_transcript.append({"role": "assistant", "content": text})
	_start_typewriter(text)

## Return the conversation transcript in the shape the server-side grader
## (POST /api/assessments/score-conversation) expects. Used by the assessment
## flow to grade the conversation phase per-turn. System turns carry NPC role
## context; only user/assistant turns produce task results downstream.
## Mirrors BabylonChatPanel.getTranscriptForGrading().
func get_transcript_for_grading() -> Array:
	return _transcript.duplicate(true)

## Enter listening mode for voice-based conversation.
func enter_listening_mode() -> void:
	_is_listening_mode = true

## Exit listening mode.
func exit_listening_mode() -> void:
	_is_listening_mode = false

## Start push-to-talk voice recording.
func start_push_to_talk() -> void:
	_is_recording = true

## Stop push-to-talk voice recording.
func stop_push_to_talk() -> void:
	_is_recording = false

## Set eavesdrop mode (observe NPC conversations without participating).
func set_eavesdrop_mode(enabled: bool) -> void:
	pass

## Set quest topics for contextual dialogue.
func set_quest_topics(topics: Array) -> void:
	pass

## Set dialogue actions available to the player.
## Renders action buttons with energy cost display. Actions exceeding
## the player's current energy are shown as disabled.
func set_dialogue_actions(actions: Array, player_energy: float) -> void:
	_current_dialogue_actions = actions
	_current_player_energy = player_energy
	_rebuild_action_buttons()

## Update dialogue actions with current player energy (re-evaluates availability).
func update_dialogue_actions(player_energy: float) -> void:
	_current_player_energy = player_energy
	_rebuild_action_buttons()

## Set quest offering context for NPC dialogue.
## When set, the NPC will offer the quest during conversation.
func set_quest_offering_context(context) -> void:
	_quest_offering_context = context

## Set active quest context from this NPC.
## Used when the player has an in-progress quest assigned by this NPC.
func set_active_quest_from_npc(context) -> void:
	_active_quest_from_npc = context

## Set quest guidance prompt for directed conversation.
## This prompt is appended to the NPC system prompt to guide dialogue.
func set_quest_guidance_prompt(prompt) -> void:
	_quest_guidance_prompt = str(prompt) if prompt else ""

## Trigger quest guidance greeting from NPC.
func trigger_quest_guidance_greeting() -> void:
	if _quest_guidance_prompt != "":
		_start_typewriter(_quest_guidance_prompt)

## Callback for streaming response chunks from the AI service.
## Each chunk is appended to the accumulator and displayed incrementally.
func on_response_chunk(chunk: String) -> void:
	_full_response += chunk
	_dialogue_text.text = _full_response

## Start a typewriter effect at a custom speed (characters per second).
func start_typewriter_effect(text: String, chars_per_second: float = 30.0) -> void:
	_typewriter_full_text = text
	_typewriter_visible_chars = 0
	_typewriter_elapsed = 0.0
	_dialogue_text.text = ""
	_is_typing = true
	_clear_responses()

## Enable or disable voice input (microphone) features.
## When disabled, push-to-talk and auto-listen are unavailable.
func set_voice_input_enabled(enabled: bool) -> void:
	_voice_input_enabled = enabled

## Whether voice input is enabled.
func is_voice_input_enabled() -> bool:
	return _voice_input_enabled

## Get the current conversation turn count.
func get_conversation_turn_count() -> int:
	return _conversation_turn_count

## Clean up resources.
func dispose() -> void:
	close_dialogue()

# ─── Typewriter ───────────────────────────────────────

func _start_typewriter(text: String) -> void:
	_typewriter_full_text = text
	_typewriter_visible_chars = 0
	_typewriter_elapsed = 0.0
	_dialogue_text.text = ""
	_is_typing = true
	_clear_responses()

func _finish_typing() -> void:
	_is_typing = false
	_dialogue_text.text = _typewriter_full_text
	if _pending_responses.size() > 0:
		_display_responses()

func _skip_typewriter() -> void:
	if _is_typing:
		_is_typing = false
		_dialogue_text.text = _typewriter_full_text
		_typewriter_visible_chars = _typewriter_full_text.length()
		if _pending_responses.size() > 0:
			_display_responses()

# ─── Responses ────────────────────────────────────────

func _display_responses() -> void:
	_clear_responses()
	var count := mini(_pending_responses.size(), MAX_RESPONSE_BUTTONS)
	for i in range(count):
		var action: Dictionary = _pending_responses[i]
		var btn := Button.new()
		var btn_name: String = action.get("name", action.get("id", "Option %d" % (i + 1)))
		var energy_cost: float = action.get("energyCost", 0.0)
		if energy_cost > 0.0:
			btn.text = "%s (%d energy)" % [btn_name, int(energy_cost)]
		else:
			btn.text = btn_name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 36)

		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = Color(0.2, 0.25, 0.35, 0.9)
		btn_style.set_corner_radius_all(4)
		btn_style.set_content_margin_all(6)
		btn.add_theme_stylebox_override("normal", btn_style)

		var hover_style := StyleBoxFlat.new()
		hover_style.bg_color = Color(0.3, 0.35, 0.5, 0.95)
		hover_style.set_corner_radius_all(4)
		hover_style.set_content_margin_all(6)
		btn.add_theme_stylebox_override("hover", hover_style)

		var action_id: String = action.get("id", "")
		btn.pressed.connect(_on_response_pressed.bind(action_id))
		_response_container.add_child(btn)

	# Always add a goodbye/close button
	var goodbye := Button.new()
	goodbye.text = "Goodbye"
	goodbye.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goodbye.custom_minimum_size = Vector2(0, 36)

	var goodbye_style := StyleBoxFlat.new()
	goodbye_style.bg_color = Color(0.4, 0.2, 0.2, 0.9)
	goodbye_style.set_corner_radius_all(4)
	goodbye_style.set_content_margin_all(6)
	goodbye.add_theme_stylebox_override("normal", goodbye_style)

	var goodbye_hover := StyleBoxFlat.new()
	goodbye_hover.bg_color = Color(0.5, 0.3, 0.3, 0.95)
	goodbye_hover.set_corner_radius_all(4)
	goodbye_hover.set_content_margin_all(6)
	goodbye.add_theme_stylebox_override("hover", goodbye_hover)

	goodbye.pressed.connect(close_dialogue)
	_response_container.add_child(goodbye)

func _on_response_pressed(action_id: String) -> void:
	if _is_typing:
		_skip_typewriter()
		return
	# Increment conversation turn count on each player response
	_conversation_turn_count += 1
	var ds := get_node_or_null("/root/DialogueSystem")
	if ds and ds.has_method("select_action"):
		ds.select_action(action_id)

func _clear_responses() -> void:
	for child in _response_container.get_children():
		child.queue_free()

# ─── Dialogue Action Buttons ─────────────────────────

## Rebuild dialogue action buttons based on current actions and player energy.
## Actions with energy cost exceeding player energy are displayed as disabled.
func _rebuild_action_buttons() -> void:
	_clear_responses()
	var count := mini(_current_dialogue_actions.size(), MAX_RESPONSE_BUTTONS)
	for i in range(count):
		var action: Dictionary = _current_dialogue_actions[i]
		var btn := Button.new()
		var btn_name: String = action.get("name", action.get("id", "Action %d" % (i + 1)))
		var energy_cost: float = action.get("energyCost", 0.0)
		var can_afford: bool = _current_player_energy >= energy_cost

		if energy_cost > 0.0:
			btn.text = "%s (%d energy)" % [btn_name, int(energy_cost)]
		else:
			btn.text = btn_name

		btn.disabled = not can_afford or not action.get("isAvailable", true)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 36)

		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = Color(0.2, 0.3, 0.5, 0.9) if can_afford else Color(0.3, 0.3, 0.3, 0.6)
		btn_style.set_corner_radius_all(4)
		btn_style.set_content_margin_all(6)
		btn.add_theme_stylebox_override("normal", btn_style)

		var hover_style := StyleBoxFlat.new()
		hover_style.bg_color = Color(0.3, 0.4, 0.6, 0.95) if can_afford else Color(0.3, 0.3, 0.3, 0.6)
		hover_style.set_corner_radius_all(4)
		hover_style.set_content_margin_all(6)
		btn.add_theme_stylebox_override("hover", hover_style)

		var action_id: String = action.get("id", "")
		btn.pressed.connect(_on_response_pressed.bind(action_id))
		_response_container.add_child(btn)

# ─── Portrait ─────────────────────────────────────────

func _set_portrait(npc_name: String) -> void:
	var initial := npc_name.substr(0, 1).to_upper() if npc_name.length() > 0 else "?"
	_portrait_label.text = initial
	# Derive color from name hash for consistent NPC colors
	var h := npc_name.hash()
	var hue := absf(float(h % 360)) / 360.0
	_portrait_rect.color = Color.from_hsv(hue, 0.4, 0.5)

# ─── Language learning ────────────────────────────────

## Only offer Listen & Repeat when the player has an active pronunciation quest.
func _on_listen_pressed() -> void:
	if not _pronunciation_quest_active:
		return
	var ds := get_node_or_null("/root/DialogueSystem")
	if ds and ds.has_signal("audio_requested"):
		ds.emit_signal("audio_requested", _current_character_id, _typewriter_full_text)

# ─── Build UI ─────────────────────────────────────────

func _build_ui() -> void:
	# Main panel — anchored to bottom of screen
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.anchor_top = 0.65
	_panel.anchor_bottom = 1.0
	_panel.anchor_left = 0.05
	_panel.anchor_right = 0.95
	_panel.offset_top = 0
	_panel.offset_bottom = -10
	_panel.offset_left = 0
	_panel.offset_right = 0

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(12)
	panel_style.border_color = Color(0.3, 0.3, 0.4, 0.6)
	panel_style.set_border_width_all(2)
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var main_hbox := HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 12)
	_panel.add_child(main_hbox)

	# ── Left column: portrait + name ──
	var left_vbox := VBoxContainer.new()
	left_vbox.custom_minimum_size = Vector2(120, 0)
	left_vbox.add_theme_constant_override("separation", 6)
	main_hbox.add_child(left_vbox)

	# Portrait placeholder
	_portrait_rect = ColorRect.new()
	_portrait_rect.custom_minimum_size = Vector2(80, 80)
	_portrait_rect.color = Color(0.3, 0.3, 0.5)
	_portrait_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left_vbox.add_child(_portrait_rect)

	# Initial letter on portrait
	_portrait_label = Label.new()
	_portrait_label.text = "?"
	_portrait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_portrait_label.add_theme_font_size_override("font_size", 36)
	_portrait_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_portrait_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_rect.add_child(_portrait_label)

	# NPC name
	_npc_name_label = Label.new()
	_npc_name_label.text = "NPC"
	_npc_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_npc_name_label.add_theme_font_size_override("font_size", 16)
	_npc_name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	left_vbox.add_child(_npc_name_label)

	# Close button under portrait
	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.custom_minimum_size = Vector2(30, 30)
	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close_button.pressed.connect(close_dialogue)
	left_vbox.add_child(_close_button)

	# ── Center column: dialogue text + language ──
	var center_vbox := VBoxContainer.new()
	center_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_vbox.add_theme_constant_override("separation", 6)
	main_hbox.add_child(center_vbox)

	_dialogue_text = RichTextLabel.new()
	_dialogue_text.bbcode_enabled = true
	_dialogue_text.fit_content = false
	_dialogue_text.scroll_active = true
	_dialogue_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialogue_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialogue_text.add_theme_font_size_override("normal_font_size", 16)
	_dialogue_text.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	center_vbox.add_child(_dialogue_text)

	# Language learning sub-panel (hidden by default)
	_lang_container = VBoxContainer.new()
	_lang_container.visible = false
	_lang_container.add_theme_constant_override("separation", 2)
	center_vbox.add_child(_lang_container)

	_lang_target_label = RichTextLabel.new()
	_lang_target_label.bbcode_enabled = true
	_lang_target_label.fit_content = true
	_lang_target_label.scroll_active = false
	_lang_target_label.add_theme_font_size_override("normal_font_size", 20)
	_lang_target_label.add_theme_color_override("default_color", Color(1.0, 0.95, 0.7))
	_lang_container.add_child(_lang_target_label)

	_lang_translation_label = Label.new()
	_lang_translation_label.text = ""
	_lang_translation_label.add_theme_font_size_override("font_size", 13)
	_lang_translation_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_lang_container.add_child(_lang_translation_label)

	var lang_btn_row := HBoxContainer.new()
	_lang_container.add_child(lang_btn_row)

	_lang_listen_button = Button.new()
	_lang_listen_button.text = "Listen"
	_lang_listen_button.custom_minimum_size = Vector2(80, 30)
	_lang_listen_button.pressed.connect(_on_listen_pressed)
	lang_btn_row.add_child(_lang_listen_button)

	# ── Right column: response buttons ──
	_response_container = VBoxContainer.new()
	_response_container.custom_minimum_size = Vector2(200, 0)
	_response_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_response_container.add_theme_constant_override("separation", 6)
	main_hbox.add_child(_response_container)

	# ── Gesture panel (non-verbal actions during conversation) ──
	_gesture_container = HBoxContainer.new()
	_gesture_container.visible = false
	_gesture_container.add_theme_constant_override("separation", 4)
	_gesture_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_vbox.add_child(_gesture_container)

	for gesture_id in ["wave", "nod", "bow", "shrug"]:
		var btn := Button.new()
		btn.text = gesture_id.capitalize()
		btn.custom_minimum_size = Vector2(60, 28)
		btn.pressed.connect(perform_gesture.bind(gesture_id))
		_gesture_container.add_child(btn)
