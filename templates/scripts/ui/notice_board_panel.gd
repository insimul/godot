extends CanvasLayer
## Notice Board Panel — displays articles and notices with comprehension questions.
## Supports language learning through reading practice.

var _is_open := false
var _notices: Array = []  # [{title, content, target_language_content, questions, read}]
var _selected_index := -1

var _panel: PanelContainer = null
var _notice_list: VBoxContainer = null
var _content_label: RichTextLabel = null
var _question_container: VBoxContainer = null
var _title_label: Label = null
var _close_button: Button = null
var _toggle_lang_button: Button = null
var _showing_target := false

func _ready() -> void:
	layer = 20
	_build_ui()
	visible = false

func toggle() -> void:
	if _is_open:
		close_panel()
	else:
		open_panel()

func open_panel() -> void:
	_is_open = true
	visible = true
	_refresh()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true

func close_panel() -> void:
	_is_open = false
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().paused = false

func set_notices(notices: Array) -> void:
	_notices = notices.duplicate(true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu") and _is_open:
		close_panel()
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.08
	_panel.anchor_right = 0.92
	_panel.anchor_top = 0.05
	_panel.anchor_bottom = 0.95
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.09, 0.95)
	style.border_color = Color(0.6, 0.5, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	# Title bar
	var title_bar := HBoxContainer.new()
	vbox.add_child(title_bar)
	var title := Label.new()
	title.text = "Notice Board"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
	title_bar.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(sp)
	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.pressed.connect(close_panel)
	title_bar.add_child(_close_button)

	# Split: notice list + content
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(split)

	# Left: notice list
	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size.x = 200
	split.add_child(left_panel)
	var list_title := Label.new()
	list_title.text = "Notices"
	list_title.add_theme_font_size_override("font_size", 16)
	left_panel.add_child(list_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(scroll)
	_notice_list = VBoxContainer.new()
	_notice_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_notice_list)

	# Right: content + questions
	var right_panel := VBoxContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right_panel)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	right_panel.add_child(_title_label)

	# Language toggle
	_toggle_lang_button = Button.new()
	_toggle_lang_button.text = "Show in Target Language"
	_toggle_lang_button.pressed.connect(_toggle_language)
	_toggle_lang_button.visible = false
	right_panel.add_child(_toggle_lang_button)

	_content_label = RichTextLabel.new()
	_content_label.bbcode_enabled = true
	_content_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_label.add_theme_color_override("default_color", Color(0.85, 0.82, 0.75))
	right_panel.add_child(_content_label)

	# Comprehension questions
	var q_title := Label.new()
	q_title.text = "Comprehension Questions"
	q_title.add_theme_font_size_override("font_size", 16)
	q_title.add_theme_color_override("font_color", Color(0.7, 0.6, 0.4))
	right_panel.add_child(q_title)
	_question_container = VBoxContainer.new()
	_question_container.custom_minimum_size.y = 100
	right_panel.add_child(_question_container)

func _refresh() -> void:
	for child in _notice_list.get_children():
		child.queue_free()

	for i in range(_notices.size()):
		var notice: Dictionary = _notices[i]
		var btn := Button.new()
		var is_read: bool = notice.get("read", false)
		var prefix: String = "" if is_read else "[NEW] "
		btn.text = prefix + notice.get("title", "Untitled")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if not is_read:
			btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		var idx := i
		btn.pressed.connect(func(): _select_notice(idx))
		_notice_list.add_child(btn)

	if _notices.is_empty():
		_content_label.text = "[i]No notices posted.[/i]"
		_title_label.text = ""
	elif _selected_index >= 0:
		_display_notice(_selected_index)
	else:
		_content_label.text = "Select a notice to read."
		_title_label.text = ""

func _select_notice(index: int) -> void:
	_selected_index = index
	_showing_target = false
	if index >= 0 and index < _notices.size():
		_notices[index]["read"] = true
	_display_notice(index)
	_refresh()

func _display_notice(index: int) -> void:
	if index < 0 or index >= _notices.size():
		return
	var notice: Dictionary = _notices[index]
	_title_label.text = notice.get("title", "Untitled")

	var has_target: bool = notice.get("target_language_content", "") != ""
	_toggle_lang_button.visible = has_target

	if _showing_target and has_target:
		_content_label.text = notice.get("target_language_content", "")
		_toggle_lang_button.text = "Show Translation"
	else:
		_content_label.text = notice.get("content", "")
		_toggle_lang_button.text = "Show in Target Language"

	# Display questions
	for child in _question_container.get_children():
		child.queue_free()
	var questions: Array = notice.get("questions", [])
	for q in questions:
		var q_label := Label.new()
		q_label.text = "  %s" % q.get("question", "")
		q_label.add_theme_font_size_override("font_size", 14)
		q_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_question_container.add_child(q_label)

		# Answer choices
		var choices: Array = q.get("choices", [])
		for choice in choices:
			var choice_btn := Button.new()
			choice_btn.text = "    %s" % choice.get("text", "")
			choice_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var is_correct: bool = choice.get("correct", false)
			choice_btn.pressed.connect(func():
				if is_correct:
					choice_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
					EventBus.emit_event({"type": "questions_answered", "correct": true})
				else:
					choice_btn.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
			)
			_question_container.add_child(choice_btn)

func _toggle_language() -> void:
	_showing_target = not _showing_target
	if _selected_index >= 0:
		_display_notice(_selected_index)
