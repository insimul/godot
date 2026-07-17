@tool
class_name InsimulConversationTesterDock
extends Control
## In-editor NPC Conversation Tester dock — UI (US-GE3).
##
## The @tool Control the EditorPlugin docks into the editor. A THIN view over the
## logic layer: InsimulConversationReducer owns the transcript state machine +
## character picker, and InsimulConversationController owns the teardown-safe stream
## lifecycle; this file wires Godot Controls (an OptionButton picker, a LineEdit +
## Send, a transcript RichTextLabel) to those calls and dispatches operations through
## InsimulEditorSession. Per the "logic layer tested; UI structurally checked" split,
## the reducer + controller are exercised headless (conversation_test.gd) and this
## file is covered by the structural lint + the human two-turn pass (VERIFICATION.md).
##
## Editor-restart safety: the controller is disposed in _exit_tree, so leaving the
## editor (or reloading the dock) never lets a late SSE frame touch a freed node.
##
## Streaming vs recorded (PIE-style fallback): the dock attempts a live stream via
## streamConversation; if the editor-process streaming misbehaves it calls
## controller.stream_failed() and fills the turn from a recorded reasoning trace,
## mirroring the other engines' PIE-fallback decision.

var session: InsimulEditorSession
var world_id: String = ""

var _characters: Array = []
var _character_id: String = ""
var _controller: InsimulConversationController = null

var _picker: OptionButton
var _input: LineEdit
var _send_btn: Button
var _transcript: RichTextLabel


func _init(editor_session: InsimulEditorSession = null) -> void:
	session = editor_session
	name = "Insimul Conversation"


func _ready() -> void:
	_build_ui()


func _exit_tree() -> void:
	# Tear down the stream controller so no late frame survives the dock.
	if _controller != null:
		_controller.dispose()
		_controller = null


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var toolbar := HBoxContainer.new()
	root.add_child(toolbar)

	_picker = OptionButton.new()
	_picker.item_selected.connect(_on_character_selected)
	toolbar.add_child(_picker)

	_transcript = RichTextLabel.new()
	_transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_transcript)

	var send_row := HBoxContainer.new()
	root.add_child(send_row)

	_input = LineEdit.new()
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.placeholder_text = "Say something…"
	_input.text_submitted.connect(func(_t): send())
	send_row.add_child(_input)

	_send_btn = Button.new()
	_send_btn.text = "Send"
	_send_btn.pressed.connect(send)
	send_row.add_child(_send_btn)


## Populate the character picker from imported world data (a parsed Dictionary).
func load_characters(world_data) -> void:
	_characters = InsimulConversationReducer.extract_characters(world_data)
	if _picker == null:
		return
	_picker.clear()
	for c in _characters:
		_picker.add_item(String(c.get("name", "")))
	if not _characters.is_empty():
		_character_id = String(_characters[0].get("id", ""))


func _on_character_selected(index: int) -> void:
	if index >= 0 and index < _characters.size():
		_character_id = String(_characters[index].get("id", ""))
		# A new character starts a fresh transcript.
		if _controller != null:
			_controller.dispose()
		_controller = null
		if _transcript != null:
			_transcript.clear()


## Send the player's line and begin streaming the character response.
func send() -> void:
	if session == null or _character_id == "" or _input == null:
		return
	var text := _input.text
	if text.strip_edges() == "":
		return
	_input.clear()
	if _controller == null:
		_controller = InsimulConversationController.new(_on_state_update, _character_id)
	_controller.send_player(text)

	var body := JSON.stringify({
		"characterId": _character_id, "worldId": world_id, "text": text,
	})
	session.call_operation("streamConversation", body, func(res: Dictionary):
		# The controller may have been torn down while the request was in flight.
		if _controller == null or _controller.is_disposed():
			return
		var code := int(res.get("code", 0))
		if code < 200 or code >= 300:
			# Editor-process streaming misbehaved -> PIE-style recorded fallback.
			_controller.stream_failed()
			return
		# Feed each SSE data frame from the response body through the controller.
		for line in String(res.get("body", "")).split("\n"):
			var trimmed := line.strip_edges()
			if trimmed.begins_with("data:"):
				_controller.feed_raw(trimmed.substr(5))
	)


func _on_state_update(state: Dictionary) -> void:
	_render(state)


func _render(state: Dictionary) -> void:
	if _transcript == null:
		return
	_transcript.clear()
	for turn in state.get("turns", []):
		var who := "You" if String(turn.get("role", "")) == "player" else "NPC"
		_transcript.add_text("%s: %s\n" % [who, String(turn.get("text", ""))])
	if InsimulConversationReducer.is_recorded_fallback(state):
		_transcript.add_text("[recorded reasoning fallback]\n")


## End the conversation session on the server.
func end_conversation() -> void:
	if session == null:
		return
	session.call_operation("endConversation", JSON.stringify({"characterId": _character_id}), func(_res): pass)
	if _controller != null:
		_controller.end()
