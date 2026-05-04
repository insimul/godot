extends CanvasLayer
## Vocabulary Panel — displays learned words with mastery levels and category filters.
## Tracks vocabulary progress for the language learning system.

const MASTERY_COLORS := {
	0: Color(0.5, 0.5, 0.5),    # Unknown — gray
	1: Color(0.8, 0.3, 0.3),    # Seen — red
	2: Color(0.9, 0.6, 0.2),    # Familiar — orange
	3: Color(0.9, 0.85, 0.2),   # Practiced — yellow
	4: Color(0.4, 0.8, 0.3),    # Learned — green
	5: Color(0.3, 0.6, 0.9),    # Mastered — blue
}

const MASTERY_LABELS := {
	0: "Unknown", 1: "Seen", 2: "Familiar",
	3: "Practiced", 4: "Learned", 5: "Mastered",
}

const CATEGORIES := ["All", "Nouns", "Verbs", "Adjectives", "Phrases", "Numbers", "Food", "Greetings"]

var _is_open := false
var _vocabulary: Array = []  # [{word, translation, category, mastery, times_used}]
var _active_category := "All"

var _panel: PanelContainer = null
var _word_list: VBoxContainer = null
var _detail_label: RichTextLabel = null
var _stats_label: Label = null
var _category_tabs: HBoxContainer = null

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
	_load_vocabulary()
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

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu") and _is_open:
		close_panel()
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.1
	_panel.anchor_right = 0.9
	_panel.anchor_top = 0.05
	_panel.anchor_bottom = 0.95
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	style.border_color = Color(0.3, 0.5, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	# Title
	var title_bar := HBoxContainer.new()
	vbox.add_child(title_bar)
	var title := Label.new()
	title.text = "Vocabulary"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.3, 0.6, 0.9))
	title_bar.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(spacer)
	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 14)
	title_bar.add_child(_stats_label)
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(spacer2)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(close_panel)
	title_bar.add_child(close_btn)

	# Category filter tabs
	_category_tabs = HBoxContainer.new()
	_category_tabs.add_theme_constant_override("separation", 4)
	vbox.add_child(_category_tabs)
	for cat in CATEGORIES:
		var btn := Button.new()
		btn.text = cat
		btn.toggle_mode = true
		btn.button_pressed = (cat == "All")
		var cat_name := cat
		btn.pressed.connect(func(): _set_category(cat_name))
		_category_tabs.add_child(btn)

	# Split: word list + detail
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(split)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)
	_word_list = VBoxContainer.new()
	_word_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_word_list)

	_detail_label = RichTextLabel.new()
	_detail_label.bbcode_enabled = true
	_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_label.custom_minimum_size.x = 250
	split.add_child(_detail_label)

func _load_vocabulary() -> void:
	# Load from QuestSystem tracked vocabulary or DataLoader
	_vocabulary.clear()
	var quest_vocab: Array = QuestSystem.get_tracked_vocabulary() if QuestSystem.has_method("get_tracked_vocabulary") else []
	for v in quest_vocab:
		_vocabulary.append(v)
	# Also load from inventory language_learning_data
	var items: Array = InventorySystem.get_all_items()
	for item in items:
		var lld: Dictionary = item.get("language_learning_data", {})
		if not lld.is_empty():
			_vocabulary.append({
				"word": lld.get("target_word", ""),
				"translation": item.get("name", ""),
				"category": lld.get("category", "Nouns"),
				"mastery": lld.get("mastery", 1),
				"times_used": lld.get("times_used", 0),
			})

func _set_category(cat: String) -> void:
	_active_category = cat
	for btn in _category_tabs.get_children():
		if btn is Button:
			btn.button_pressed = (btn.text == cat)
	_refresh()

func _refresh() -> void:
	for child in _word_list.get_children():
		child.queue_free()

	var filtered: Array = _vocabulary.filter(func(v: Dictionary) -> bool:
		return _active_category == "All" or v.get("category", "") == _active_category
	)

	# Stats
	var total: int = _vocabulary.size()
	var mastered: int = _vocabulary.filter(func(v: Dictionary) -> bool: return v.get("mastery", 0) >= 4).size()
	_stats_label.text = "%d words learned | %d mastered" % [total, mastered]

	for v in filtered:
		var mastery: int = clampi(v.get("mastery", 0), 0, 5)
		var color: Color = MASTERY_COLORS[mastery]
		var btn := Button.new()
		btn.text = "%s — %s" % [v.get("word", "?"), v.get("translation", "?")]
		btn.add_theme_color_override("font_color", color)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var word_data := v
		btn.pressed.connect(func(): _show_detail(word_data))
		_word_list.add_child(btn)

	if filtered.is_empty():
		_detail_label.text = "[i]No vocabulary in this category yet.[/i]"
	else:
		_detail_label.text = "Select a word to see details."

func _show_detail(v: Dictionary) -> void:
	var mastery: int = clampi(v.get("mastery", 0), 0, 5)
	var color: Color = MASTERY_COLORS[mastery]
	var color_hex := "#%s" % color.to_html(false)
	_detail_label.text = "[b][font_size=20]%s[/font_size][/b]\n\n" % v.get("word", "?")
	_detail_label.text += "[b]Translation:[/b] %s\n" % v.get("translation", "?")
	_detail_label.text += "[b]Category:[/b] %s\n" % v.get("category", "?")
	_detail_label.text += "[b]Mastery:[/b] [color=%s]%s[/color]\n" % [color_hex, MASTERY_LABELS[mastery]]
	_detail_label.text += "[b]Times Used:[/b] %d\n" % v.get("times_used", 0)
