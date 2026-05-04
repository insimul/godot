extends CanvasLayer
## Game Intro Sequence — narrative intro and cutscenes.
## Matches shared/game-engine/rendering/GameIntroSequence.ts, NarrativeCutscenePanel.ts.

signal intro_completed
signal cutscene_completed(cutscene_id: String)

var _background: TextureRect = null
var _text_label: RichTextLabel = null
var _portrait: TextureRect = null
var _continue_btn: Button = null
var _narration_queue: Array[Dictionary] = []
var _current_index := 0

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()

func play_intro(narrative_data: Array) -> void:
	_narration_queue = narrative_data
	_current_index = 0
	visible = true
	get_tree().paused = true
	_show_current_page()

func play_cutscene(cutscene_id: String, pages: Array) -> void:
	_narration_queue = pages
	_current_index = 0
	visible = true
	get_tree().paused = true
	_show_current_page()
	# Store cutscene ID for completion signal
	set_meta("cutscene_id", cutscene_id)

func _show_current_page() -> void:
	if _current_index >= _narration_queue.size():
		_finish()
		return

	var page: Dictionary = _narration_queue[_current_index]
	_text_label.text = ""
	var text: String = page.get("text", "")
	# Animate text using Tween
	var tween := create_tween()
	tween.tween_method(func(ratio: float):
		var chars := int(text.length() * ratio)
		_text_label.text = "[center]" + text.substr(0, chars) + "[/center]"
	, 0.0, 1.0, max(1.0, text.length() * 0.03))

func _on_continue() -> void:
	_current_index += 1
	_show_current_page()

func _finish() -> void:
	visible = false
	get_tree().paused = false
	if has_meta("cutscene_id"):
		cutscene_completed.emit(get_meta("cutscene_id"))
		remove_meta("cutscene_id")
	else:
		intro_completed.emit()

func _build_ui() -> void:
	visible = false

	# Full-screen background
	_background = TextureRect.new()
	_background.anchors_preset = Control.PRESET_FULL_RECT
	_background.anchor_right = 1.0
	_background.anchor_bottom = 1.0
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	var bg_panel := PanelContainer.new()
	bg_panel.anchors_preset = Control.PRESET_FULL_RECT
	bg_panel.anchor_right = 1.0
	bg_panel.anchor_bottom = 1.0
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(bg_panel)

	var vbox := VBoxContainer.new()
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	bg_panel.add_child(vbox)

	# Portrait area
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(200, 200)
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_portrait)

	# Text area
	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_text_label)

	# Continue button
	_continue_btn = Button.new()
	_continue_btn.text = "Continue"
	_continue_btn.custom_minimum_size = Vector2(200, 50)
	_continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue_btn.pressed.connect(_on_continue)
	vbox.add_child(_continue_btn)
