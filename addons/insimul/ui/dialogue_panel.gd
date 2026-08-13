class_name InsimulDialoguePanel
extends Control
## Dialogue panel — a thin view over InsimulChatModel (US-3).
##
## Wires the streaming conversation SDK into the engine-neutral chat model, which
## owns the transcript / streaming / action / history contract. The panel adds the
## engine-coupled hooks the model cannot have:
##   * TTS — speak the settled NPC line on response_complete,
##   * insimul_lip_sync — drive the speaker's visemes from the same line,
##   * ACTION triggers — assert each action's Prolog fact into the KB,
##   * HISTORY — project the transcript into `save.conversations` on close.
##
## ## The service is DUCK-TYPED
##
## [method bind_conversation_service] takes anything with the three streaming
## signals (`chunk_received(npc_id, text)`, `response_complete(npc_id, full_text)`,
## `response_error(npc_id, error)`) and a `send_message(character_id, text)` — the
## shape of the template's `AIService` autoload, which is where the real streaming
## SDK lives. It is duck-typed rather than typed for the same reason
## [method InsimulUiRegistry.bind_activation] is: the shipped default UI must
## compile in a project with no game code in it at all, and the panel must still
## work when a creator swaps the provider. With no explicit bind, `_ready()` picks
## up the `/root/AIService` autoload if the game has one.
##
## ## History lands in the save, and nowhere else
##
## The panel keeps no transcript store of its own: [method bind_save] points it at
## the live save Dictionary and [method persist_history] writes the model's
## projection into `save.conversations` as this character's ConversationSummary —
## UPDATING the existing entry rather than appending a second one. That is the same
## data-first invariant the quest and trade panels run under, applied to the one
## piece of UI state that does not live in `currentState`.
##
## Model contract + shared cases: conformance/ui/chat-cases.json.

signal chat_closed
## Emitted whenever the transcript reaches the save (a close, or an explicit flush).
signal history_persisted(character_id: String)

## The autoload a game's streaming SDK conventionally registers itself as.
const SERVICE_AUTOLOAD := "/root/AIService"

var _model := InsimulChatModel.new()

## The streaming conversation service, duck-typed — see the class doc.
var _service: Object = null
## Optional provider that speaks a line: func(text: String, character_id: String).
var _tts: Callable = Callable()
## Optional lip-sync hook: func(character_id: String, text: String).
var _lip_sync: Callable = Callable()
## Optional KB sink for triggered actions: func(fact: String).
var _kb_assert: Callable = Callable()
## The live save Dictionary this conversation's history belongs in.
var _save: Dictionary = {}
## How many actions have already been forwarded to the KB (diff cursor).
var _actions_applied := 0

var _header: Label = null
var _messages_box: VBoxContainer = null
var _input: LineEdit = null
var _send: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = InsimulUiTokens.build_theme()
	_build_ui()
	_send.pressed.connect(_on_send)
	_input.text_submitted.connect(func(_t): _on_send())
	if _service == null:
		bind_conversation_service(get_node_or_null(SERVICE_AUTOLOAD))


## Bind the streaming conversation SDK. Anything answering `send_message` and
## carrying the three streaming signals will do; a null (or wrong-shaped) service
## unbinds and leaves the panel a transcript viewer. Returns whether it took.
func bind_conversation_service(service: Object) -> bool:
	if _service != null:
		_disconnect_service(_service)
	_service = null
	if service == null or not service.has_method("send_message"):
		return false
	_service = service
	_connect_signal(service, "chunk_received", _on_chunk)
	_connect_signal(service, "response_complete", _on_complete)
	_connect_signal(service, "response_error", _on_error)
	return true


func has_conversation_service() -> bool:
	return _service != null


## Point the panel at the live save Dictionary its history belongs in.
func bind_save(save: Dictionary) -> void:
	_save = save


## Open the panel for a character, seeding the greeting from the AI context.
func open_chat(character_id: String, character_name: String = "", greeting: String = "") -> void:
	_model = InsimulChatModel.new(character_id, character_name)
	_actions_applied = 0
	if greeting != "":
		_model.greeting(greeting)
	visible = true
	if _header:
		_header.text = _model.character_name
	_refresh()
	if _input:
		_input.grab_focus()


## Register the TTS provider: func(text: String, character_id: String).
func set_tts_provider(provider: Callable) -> void:
	_tts = provider


## Register the insimul_lip_sync hook: func(character_id: String, text: String).
func set_lip_sync_hook(hook: Callable) -> void:
	_lip_sync = hook


## Register the KB fact sink for triggered actions: func(fact: String).
func set_kb_assert(sink: Callable) -> void:
	_kb_assert = sink


func model() -> InsimulChatModel:
	return _model


## Close the conversation, persisting the transcript into the bound save first.
func close_chat(timestamp: String = "") -> void:
	persist_history(timestamp)
	visible = false
	chat_closed.emit()


## The transcript projected for save.conversations (recentTurns + totalTurnCount).
func export_history(timestamp: String = "") -> Dictionary:
	return _model.history(timestamp)


## Write this character's ConversationSummary into the bound save's
## `conversations` array, updating the existing entry rather than appending a
## second one. A no-op with no save bound or nothing settled to persist.
func persist_history(timestamp: String = "") -> bool:
	if _save.is_empty() or _model.character_id == "":
		return false
	var projection := _model.history(timestamp)
	if (projection.get("recentTurns", []) as Array).is_empty():
		return false
	if not (_save.get("conversations", null) is Array):
		_save["conversations"] = []
	var conversations: Array = _save["conversations"]
	var summary := _summary(projection)
	for i in conversations.size():
		var entry: Variant = conversations[i]
		if entry is Dictionary and String((entry as Dictionary).get("npcCharacterId", "")) == _model.character_id:
			(entry as Dictionary).merge(summary, true)
			history_persisted.emit(_model.character_id)
			return true
	conversations.append(summary)
	history_persisted.emit(_model.character_id)
	return true


## The ConversationSummary shape the save schema carries. The fields this panel has
## no reading for stay at their schema defaults rather than being invented: topics
## and vocabulary are the language modules' answers, not the transcript's.
func _summary(projection: Dictionary) -> Dictionary:
	return {
		"npcCharacterId": _model.character_id,
		"npcCharacterName": _model.character_name,
		"compressedHistory": null,
		"recentTurns": projection.get("recentTurns", []),
		"totalTurnCount": int(projection.get("totalTurnCount", 0)),
	}


## Send a player line: opens a turn and hands it to the streaming service. This is
## the whole send path — the Send button and the input's submit both come through
## here, and so does a host pushing a line from somewhere else (a voice transcript,
## a scripted beat). Returns false while a turn is already in flight.
func send_line(text: String) -> bool:
	if _model.is_streaming():
		return false
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return false
	if not _model.begin_user_turn(trimmed):
		return false
	_refresh()
	if _service != null:
		_service.call("send_message", _model.character_id, trimmed)
	return true


func _on_send() -> void:
	var text := _input.text
	if send_line(text):
		_input.text = ""


func _on_chunk(npc_id: String, text: String) -> void:
	if npc_id != _model.character_id:
		return
	_model.append_chunk(text)
	_apply_pending_actions()
	_refresh()


func _on_complete(npc_id: String, full_text: String) -> void:
	if npc_id != _model.character_id:
		return
	_model.complete_turn(full_text if full_text != "" else null)
	_apply_pending_actions()
	_refresh()
	# Engine-coupled hooks fed from the settled NPC line.
	var line := _model.last_npc_text()
	if line != "":
		if _tts.is_valid():
			_tts.call(line, _model.character_id)
		if _lip_sync.is_valid():
			_lip_sync.call(_model.character_id, line)
	if _input:
		_input.grab_focus()


func _on_error(npc_id: String, error: String) -> void:
	if npc_id != _model.character_id:
		return
	_model.fail_turn(error)
	_refresh()


## An NPC action the panel should record + assert into the KB (called by the SDK's
## action channel). `fact` is the Prolog fact to assert.
func on_action(name: String, args: Array = [], fact: String = "") -> void:
	_model.trigger_action({"name": name, "args": args, "factToAssert": fact})
	_apply_pending_actions()


func _apply_pending_actions() -> void:
	var actions := _model.action_list()
	while _actions_applied < actions.size():
		var a: Dictionary = actions[_actions_applied]
		var fact := String(a.get("factToAssert", ""))
		if fact != "" and _kb_assert.is_valid():
			_kb_assert.call(fact)
		_actions_applied += 1


func _refresh() -> void:
	# The input is locked for the length of a turn: the model rejects a second
	# begin while one is streaming, and a send box that silently swallows a line is
	# worse than one that will not take it.
	var streaming := _model.is_streaming()
	if _input:
		_input.editable = not streaming
	if _send:
		_send.disabled = streaming
	if _messages_box == null:
		return
	for child in _messages_box.get_children():
		_messages_box.remove_child(child)
		child.queue_free()
	for m in _model.message_list():
		var row := Label.new()
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var who := "You" if String(m.get("role", "")) == "player" else _model.character_name
		row.text = "%s: %s" % [who, String(m.get("text", ""))]
		if m.has("error"):
			row.add_theme_color_override("font_color", InsimulUiTokens.color("danger"))
		_messages_box.add_child(row)


func _connect_signal(service: Object, signal_name: String, handler: Callable) -> void:
	if service.has_signal(signal_name) and not service.is_connected(signal_name, handler):
		service.connect(signal_name, handler)


func _disconnect_service(service: Object) -> void:
	for pair in [["chunk_received", _on_chunk], ["response_complete", _on_complete],
			["response_error", _on_error]]:
		var signal_name := String(pair[0])
		var handler: Callable = pair[1]
		if service.has_signal(signal_name) and service.is_connected(signal_name, handler):
			service.disconnect(signal_name, handler)


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["sm"]))
	add_child(box)

	_header = Label.new()
	_header.add_theme_font_size_override("font_size", int(InsimulUiTokens.FONT_SIZE["title"]))
	box.add_child(_header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_messages_box = VBoxContainer.new()
	_messages_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_messages_box)

	var input_row := HBoxContainer.new()
	box.add_child(input_row)
	_input = LineEdit.new()
	_input.placeholder_text = "Type a message…"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row.add_child(_input)
	_send = Button.new()
	_send.text = "Send"
	input_row.add_child(_send)
