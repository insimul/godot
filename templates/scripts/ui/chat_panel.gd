extends PanelContainer
## Chat Panel — NPC conversation UI with streaming text display.
##
## Parity with the Babylon implementation (see NPCAppearanceDescription.ts):
##  * `set_appearance_provider(Callable)` — optional callback that returns a
##    natural-language description of the NPC's current visible appearance;
##    the chat panel invokes it on each send and passes the result to
##    `AIService.send_message(..., appearance_description)`.
##  * 30-second stream watchdog — if no `response_complete` / `response_error`
##    signal arrives within the timeout, treat it as an error so the UI can
##    clear its streaming state instead of hanging indefinitely.

signal chat_closed

const STREAM_TIMEOUT_SECONDS := 90.0

var _current_character_id := ""
var _is_streaming := false
var _streaming_label: RichTextLabel = null

## Optional provider that returns a natural-language appearance description
## for a given character_id. Signature: func(character_id: String) -> String.
var _appearance_provider: Callable = Callable()

## Active watchdog timer for the in-flight stream. Cleared on completion/error.
var _stream_watchdog: SceneTreeTimer = null

var header_label: Label = null
var scroll_container: ScrollContainer = null
var message_container: VBoxContainer = null
var input_field: LineEdit = null
var send_button: Button = null
var close_button: Button = null

func _ready() -> void:
	visible = false
	_build_ui()
	send_button.pressed.connect(_on_send_pressed)
	close_button.pressed.connect(close_chat)
	input_field.text_submitted.connect(func(_t): _on_send_pressed())

	# Connect to AI service signals
	if Engine.has_singleton("AIService") or has_node("/root/AIService"):
		var ai = get_node_or_null("/root/AIService")
		if ai:
			ai.chunk_received.connect(_on_chunk_received)
			ai.response_complete.connect(_on_response_complete)
			ai.response_error.connect(_on_response_error)

func open_chat(character_id: String) -> void:
	_current_character_id = character_id
	_clear_messages()
	visible = true
	input_field.text = ""
	input_field.grab_focus()

	# Show greeting
	var ai = get_node_or_null("/root/AIService")
	if ai:
		var ctx = ai.get_context(character_id)
		if not ctx.is_empty():
			header_label.text = ctx.get("characterName", character_id)
			var greeting = ctx.get("greeting", "")
			if greeting != "":
				_add_npc_message(greeting)
		else:
			header_label.text = character_id

func close_chat() -> void:
	visible = false
	_current_character_id = ""
	_is_streaming = false
	_cancel_stream_watchdog()
	chat_closed.emit()

## Register a provider that returns the NPC's visible-appearance description.
## The string is attached to the outgoing AI request as gameContext.appearanceDescription.
func set_appearance_provider(provider: Callable) -> void:
	_appearance_provider = provider

func _resolve_appearance(character_id: String) -> String:
	if not _appearance_provider.is_valid():
		return ""
	var result = _appearance_provider.call(character_id)
	if typeof(result) == TYPE_STRING:
		return result
	return ""

func _start_stream_watchdog() -> void:
	_cancel_stream_watchdog()
	_stream_watchdog = get_tree().create_timer(STREAM_TIMEOUT_SECONDS)
	_stream_watchdog.timeout.connect(_on_stream_watchdog_fired)

func _cancel_stream_watchdog() -> void:
	# SceneTreeTimers can't be stopped directly; we just drop the reference so
	# the handler checks identity before firing.
	_stream_watchdog = null

func _on_stream_watchdog_fired() -> void:
	# Guard: this timer may have been superseded by a newer send. Only act if
	# we're still streaming and no replacement watchdog was started.
	if not _is_streaming:
		return
	_stream_watchdog = null
	_is_streaming = false
	if _streaming_label:
		_streaming_label.text = "[Error: connection timed out]"
	_streaming_label = null
	push_error("[ChatPanel] Stream watchdog fired after %.1fs — no done event." % STREAM_TIMEOUT_SECONDS)

func _on_send_pressed() -> void:
	if _is_streaming:
		return
	var text = input_field.text.strip_edges()
	if text.is_empty():
		return

	input_field.text = ""
	_add_user_message(text)

	# Start streaming
	_is_streaming = true
	_streaming_label = _create_message_bubble(false)
	_streaming_label.text = ""

	var ai = get_node_or_null("/root/AIService")
	if ai:
		var appearance := _resolve_appearance(_current_character_id)
		_start_stream_watchdog()
		ai.send_message(_current_character_id, text, appearance)

func _on_chunk_received(npc_id: String, text: String) -> void:
	if npc_id != _current_character_id:
		return
	if _streaming_label:
		_streaming_label.text += text
		_scroll_to_bottom()

func _on_response_complete(npc_id: String, _full_text: String) -> void:
	if npc_id != _current_character_id:
		return
	_cancel_stream_watchdog()
	_is_streaming = false
	_streaming_label = null
	input_field.grab_focus()

func _on_response_error(npc_id: String, error: String) -> void:
	if npc_id != _current_character_id:
		return
	_cancel_stream_watchdog()
	_is_streaming = false
	if _streaming_label:
		_streaming_label.text = "[Error: %s]" % error
	_streaming_label = null
	push_error("[ChatPanel] AI error: %s" % error)

func _add_user_message(text: String) -> void:
	var label = _create_message_bubble(true)
	label.text = text
	_scroll_to_bottom()

func _add_npc_message(text: String) -> void:
	var label = _create_message_bubble(false)
	label.text = text
	_scroll_to_bottom()

func _create_message_bubble(is_user: bool) -> RichTextLabel:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	if is_user:
		style.bg_color = Color(0.2, 0.4, 0.8, 0.9)
	else:
		style.bg_color = Color(0.25, 0.25, 0.3, 0.9)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.custom_minimum_size = Vector2(0, 20)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(label)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10 if is_user else 0)
	margin.add_theme_constant_override("margin_right", 0 if is_user else 10)
	margin.add_child(panel)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	message_container.add_child(margin)
	return label

func _clear_messages() -> void:
	for child in message_container.get_children():
		child.queue_free()

func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)

func _build_ui() -> void:
	# Build UI programmatically if scene nodes don't exist
	if header_label != null:
		return

	custom_minimum_size = Vector2(350, 500)
	anchors_preset = Control.PRESET_BOTTOM_RIGHT
	anchor_left = 0.6
	anchor_top = 0.05
	anchor_right = 0.98
	anchor_bottom = 0.95

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	bg_style.set_corner_radius_all(8)
	bg_style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", bg_style)

	var vbox = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	# Header
	var header_hbox = HBoxContainer.new()
	vbox.add_child(header_hbox)

	header_label = Label.new()
	header_label.unique_name_in_owner = true
	header_label.text = "NPC"
	header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(header_label)

	close_button = Button.new()
	close_button.unique_name_in_owner = true
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(30, 30)
	header_hbox.add_child(close_button)

	# Scroll area
	scroll_container = ScrollContainer.new()
	scroll_container.unique_name_in_owner = true
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll_container)

	message_container = VBoxContainer.new()
	message_container.unique_name_in_owner = true
	message_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(message_container)

	# Input area
	var input_hbox = HBoxContainer.new()
	vbox.add_child(input_hbox)

	input_field = LineEdit.new()
	input_field.unique_name_in_owner = true
	input_field.placeholder_text = "Type a message..."
	input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_hbox.add_child(input_field)

	send_button = Button.new()
	send_button.unique_name_in_owner = true
	send_button.text = "Send"
	send_button.custom_minimum_size = Vector2(60, 0)
	input_hbox.add_child(send_button)
