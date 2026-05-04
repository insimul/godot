extends CanvasLayer
## Skill Tree Panel — 5-tier language skill progression.
## Displays skill nodes in a tree layout with unlock progression.

const TIER_COLORS := [
	Color(0.5, 0.5, 0.5),    # Tier 0 — Locked (gray)
	Color(0.65, 0.5, 0.3),   # Tier 1 — Novice (bronze)
	Color(0.6, 0.6, 0.65),   # Tier 2 — Apprentice (silver)
	Color(0.9, 0.75, 0.2),   # Tier 3 — Journeyman (gold)
	Color(0.3, 0.7, 0.9),    # Tier 4 — Expert (blue)
	Color(0.6, 0.3, 0.9),    # Tier 5 — Master (purple)
]

const TIER_NAMES := ["Locked", "Novice", "Apprentice", "Journeyman", "Expert", "Master"]

## Default skill tree structure — language learning focus
const DEFAULT_SKILLS := [
	# Tier 1 — Basics
	{"id": "greetings", "name": "Greetings", "tier": 1, "category": "speaking", "description": "Basic hello/goodbye phrases", "xp_required": 0},
	{"id": "numbers", "name": "Numbers", "tier": 1, "category": "vocabulary", "description": "Count from 1 to 20", "xp_required": 0},
	{"id": "colors", "name": "Colors", "tier": 1, "category": "vocabulary", "description": "Primary and secondary colors", "xp_required": 0},
	# Tier 2 — Foundation
	{"id": "shopping", "name": "Shopping", "tier": 2, "category": "speaking", "description": "Buy items and ask prices", "xp_required": 100, "requires": ["greetings"]},
	{"id": "directions", "name": "Directions", "tier": 2, "category": "speaking", "description": "Ask for and give directions", "xp_required": 100, "requires": ["greetings"]},
	{"id": "food_vocab", "name": "Food & Drink", "tier": 2, "category": "vocabulary", "description": "Common food and beverage words", "xp_required": 80, "requires": ["numbers"]},
	# Tier 3 — Intermediate
	{"id": "past_tense", "name": "Past Tense", "tier": 3, "category": "grammar", "description": "Express past events", "xp_required": 250, "requires": ["shopping", "directions"]},
	{"id": "opinions", "name": "Opinions", "tier": 3, "category": "speaking", "description": "Express likes, dislikes, and preferences", "xp_required": 250, "requires": ["shopping"]},
	{"id": "reading", "name": "Reading", "tier": 3, "category": "literacy", "description": "Read signs, menus, and notices", "xp_required": 200, "requires": ["food_vocab", "colors"]},
	# Tier 4 — Advanced
	{"id": "storytelling", "name": "Storytelling", "tier": 4, "category": "speaking", "description": "Narrate events and tell stories", "xp_required": 500, "requires": ["past_tense", "opinions"]},
	{"id": "formal_speech", "name": "Formal Speech", "tier": 4, "category": "speaking", "description": "Polite and formal registers", "xp_required": 500, "requires": ["opinions"]},
	# Tier 5 — Mastery
	{"id": "fluency", "name": "Fluency", "tier": 5, "category": "mastery", "description": "Natural conversation flow", "xp_required": 1000, "requires": ["storytelling", "formal_speech"]},
]

var _is_open := false
var _skills: Array = []
var _unlocked: Dictionary = {}  # skill_id → true
var _xp: int = 0
var _panel: PanelContainer = null
var _tree_container: VBoxContainer = null
var _detail_label: RichTextLabel = null
var _xp_label: Label = null

func _ready() -> void:
	layer = 20
	_build_ui()
	visible = false
	_skills = DEFAULT_SKILLS.duplicate(true)
	# Auto-unlock tier 1
	for skill in _skills:
		if skill.get("tier", 1) <= 1:
			_unlocked[skill["id"]] = true

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

func add_xp(amount: int) -> void:
	_xp += amount
	# Check for new unlocks
	for skill in _skills:
		var sid: String = skill["id"]
		if _unlocked.has(sid):
			continue
		if _xp >= skill.get("xp_required", 0) and _prereqs_met(skill):
			_unlocked[sid] = true
			var hud: Node = get_node_or_null("/root/HUD")
			if hud and hud.has_method("show_notification"):
				hud.show_notification("Skill unlocked: %s" % skill["name"], Color(0.6, 0.3, 0.9))

func _prereqs_met(skill: Dictionary) -> bool:
	var requires: Array = skill.get("requires", [])
	for req in requires:
		if not _unlocked.has(req):
			return false
	return true

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
	style.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	style.border_color = Color(0.5, 0.3, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	var title_bar := HBoxContainer.new()
	vbox.add_child(title_bar)
	var title := Label.new()
	title.text = "Skill Tree"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.6, 0.3, 0.9))
	title_bar.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(sp)
	_xp_label = Label.new()
	_xp_label.add_theme_font_size_override("font_size", 16)
	title_bar.add_child(_xp_label)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(sp2)
	var close := Button.new()
	close.text = "X"
	close.pressed.connect(close_panel)
	title_bar.add_child(close)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(split)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)
	_tree_container = VBoxContainer.new()
	_tree_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_tree_container)

	_detail_label = RichTextLabel.new()
	_detail_label.bbcode_enabled = true
	_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_label.custom_minimum_size.x = 250
	split.add_child(_detail_label)

func _refresh() -> void:
	_xp_label.text = "XP: %d" % _xp
	for child in _tree_container.get_children():
		child.queue_free()

	# Group by tier
	for tier in range(1, 6):
		var tier_label := Label.new()
		tier_label.text = "— %s (Tier %d) —" % [TIER_NAMES[tier], tier]
		tier_label.add_theme_font_size_override("font_size", 16)
		tier_label.add_theme_color_override("font_color", TIER_COLORS[tier])
		tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tree_container.add_child(tier_label)

		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		_tree_container.add_child(row)

		var tier_skills: Array = _skills.filter(func(s: Dictionary) -> bool: return s.get("tier", 0) == tier)
		for skill in tier_skills:
			var is_unlocked: bool = _unlocked.has(skill["id"])
			var can_unlock: bool = not is_unlocked and _xp >= skill.get("xp_required", 0) and _prereqs_met(skill)

			var btn := Button.new()
			btn.text = skill["name"]
			btn.custom_minimum_size = Vector2(110, 40)

			var btn_style := StyleBoxFlat.new()
			if is_unlocked:
				btn_style.bg_color = TIER_COLORS[tier] * 0.4
				btn_style.border_color = TIER_COLORS[tier]
			elif can_unlock:
				btn_style.bg_color = Color(0.2, 0.2, 0.15)
				btn_style.border_color = Color(0.8, 0.7, 0.3)
			else:
				btn_style.bg_color = Color(0.12, 0.12, 0.14)
				btn_style.border_color = Color(0.3, 0.3, 0.3)
			btn_style.set_border_width_all(2)
			btn_style.set_corner_radius_all(4)
			btn.add_theme_stylebox_override("normal", btn_style)

			var skill_data := skill
			btn.pressed.connect(func(): _show_skill_detail(skill_data))
			row.add_child(btn)

	_detail_label.text = "Select a skill to view details."

func _show_skill_detail(skill: Dictionary) -> void:
	var is_unlocked: bool = _unlocked.has(skill["id"])
	var tier: int = skill.get("tier", 1)
	var color: Color = TIER_COLORS[tier]
	var hex := "#%s" % color.to_html(false)
	var status: String = "[color=#55cc55]UNLOCKED[/color]" if is_unlocked else "[color=#cc5555]LOCKED[/color]"

	_detail_label.text = "[b][font_size=20]%s[/font_size][/b]\n%s\n\n" % [skill["name"], status]
	_detail_label.text += "[b]Tier:[/b] [color=%s]%s[/color]\n" % [hex, TIER_NAMES[tier]]
	_detail_label.text += "[b]Category:[/b] %s\n" % skill.get("category", "")
	_detail_label.text += "[b]Description:[/b] %s\n" % skill.get("description", "")
	_detail_label.text += "[b]XP Required:[/b] %d\n" % skill.get("xp_required", 0)
	var requires: Array = skill.get("requires", [])
	if not requires.is_empty():
		_detail_label.text += "[b]Requires:[/b] %s\n" % ", ".join(requires)
