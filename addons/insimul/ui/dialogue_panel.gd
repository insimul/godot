class_name InsimulDialoguePanel
extends Control
## Dialogue panel — a thin view over InsimulChatModel (US-GU3).
##
## Wires the streaming conversation SDK (AIService autoload: chunk_received /
## response_complete / response_error) into the engine-neutral chat model, which
## owns the transcript / streaming / action / history contract. The panel adds the
## engine-coupled hooks:
##   * TTS — speak the settled NPC line via a TTS provider on response_complete,
##   * insimul_lip_sync — drive the speaker's visemes from the same line,
##   * ACTION triggers — assert each action's Prolog fact into the KB (PrologEngine),
##   * HISTORY — persist model.history() into save.conversations on close.
##
## Model contract + shared cases: packages/core/conformance/ui/chat-cases.json.

signal chat_closed

var _model := InsimulChatModel.new()

## Optional provider that speaks a line: func(text: String, character_id: String).
var _tts: Callable = Callable()
## Optional lip-sync hook: func(character_id: String, text: String).
var _lip_sync: Callable = Callable()
## Optional KB sink for triggered actions: func(fact: String).
var _kb_assert: Callable = Callable()
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
	var ai := get_node_or_null("/root/AIService")
	if ai:
		ai.chunk_received.connect(_on_chunk)
		ai.response_complete.connect(_on_complete)
		ai.response_error.connect(_on_error)


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


func close_chat() -> void:
	visible = false
	chat_closed.emit()


## The transcript projected for save.conversations (recentTurns + totalTurnCount).
func export_history(timestamp: String = "") -> Dictionary:
	return _model.history(timestamp)


func _on_send() -> void:
	if _model.is_streaming():
		return
	var text := _input.text.strip_edges()
	if text.is_empty():
		return
	_input.text = ""
	if not _model.begin_user_turn(text):
		return
	_refresh()
	var ai := get_node_or_null("/root/AIService")
	if ai:
		ai.send_message(_model.character_id, text)


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
	if _messages_box == null:
		return
	for child in _messages_box.get_children():
		child.queue_free()
	for m in _model.message_list():
		var row := Label.new()
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var who := "You" if String(m.get("role", "")) == "player" else _model.character_name
		row.text = "%s: %s" % [who, String(m.get("text", ""))]
		if m.has("error"):
			row.add_theme_color_override("font_color", InsimulUiTokens.color("danger"))
		_messages_box.add_child(row)


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
