extends CanvasLayer
## Quest Journal UI — split-panel journal with tab filters, quest list,
## detail view, objective tracking, and tracked-quests HUD.
## Toggle with J key; pauses the game while open.

signal quest_tracked(quest_id: String)
signal quest_untracked(quest_id: String)

enum FilterTab { ALL, ACTIVE, COMPLETED, AVAILABLE }

const MAX_TRACKED_QUESTS := 3

const DIFFICULTY_COLORS := {
	"easy": Color(0.2, 0.8, 0.2),
	"medium": Color(1.0, 0.8, 0.0),
	"hard": Color(1.0, 0.4, 0.0),
	"legendary": Color(0.6, 0.2, 0.8),
}
const DEFAULT_DIFFICULTY_COLOR := Color(0.7, 0.7, 0.7)

var _is_open := false
var _current_tab: FilterTab = FilterTab.ALL
var _filtered_quests: Array[Dictionary] = []
var _selected_index := -1
var _tracked_quest_ids: Array[String] = []

# ── Panels ────────────────────────────────────────────────────────────
var _journal_panel: PanelContainer
var _list_panel: VBoxContainer
var _detail_panel: VBoxContainer

# ── Tab buttons ───────────────────────────────────────────────────────
var _tab_all: Button
var _tab_active: Button
var _tab_completed: Button
var _tab_available: Button

# ── Quest list ────────────────────────────────────────────────────────
var _quest_scroll: ScrollContainer
var _quest_list_container: VBoxContainer

# ── Detail elements ───────────────────────────────────────────────────
var _detail_title: RichTextLabel
var _detail_description: RichTextLabel
var _detail_type: Label
var _detail_difficulty: Label
var _detail_location: Label
var _detail_rewards: RichTextLabel
var _objectives_container: VBoxContainer

# ── Action buttons ────────────────────────────────────────────────────
var _track_button: Button
var _accept_button: Button
var _abandon_button: Button

# ── Tracked quests HUD ────────────────────────────────────────────────
var _tracked_hud: RichTextLabel


func _ready() -> void:
	_build_ui()
	_journal_panel.visible = false
	QuestSystem.quest_accepted.connect(_on_quest_accepted)
	QuestSystem.quest_completed.connect(_on_quest_completed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_J:
			toggle_journal()
			get_viewport().set_input_as_handled()


# ═══════════════════════════════════════════════
# Public API
# ═══════════════════════════════════════════════

func toggle_journal() -> void:
	if _is_open:
		close_journal()
	else:
		open_journal()


func open_journal() -> void:
	_is_open = true
	_journal_panel.visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	refresh_quest_list()


func close_journal() -> void:
	_is_open = false
	_journal_panel.visible = false
	_detail_panel.visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_clear_selection()


func is_open() -> bool:
	return _is_open


# ═══════════════════════════════════════════════
# Filter tabs
# ═══════════════════════════════════════════════

func set_filter_tab(tab: FilterTab) -> void:
	_current_tab = tab
	_update_tab_styles()
	_clear_selection()
	refresh_quest_list()


func _apply_filters() -> Array[Dictionary]:
	match _current_tab:
		FilterTab.ACTIVE:
			return QuestSystem.get_active_quests()
		FilterTab.COMPLETED:
			return QuestSystem.get_completed_quests()
		FilterTab.AVAILABLE:
			return QuestSystem.get_available_quests()
		_:
			return QuestSystem.get_all_quests()


# ═══════════════════════════════════════════════
# Quest list
# ═══════════════════════════════════════════════

func refresh_quest_list() -> void:
	for child in _quest_list_container.get_children():
		child.queue_free()

	_filtered_quests = _apply_filters()

	for i in range(_filtered_quests.size()):
		var quest: Dictionary = _filtered_quests[i]
		var entry := _create_quest_entry(quest, i)
		_quest_list_container.add_child(entry)


func _create_quest_entry(quest: Dictionary, index: int) -> Button:
	var btn := Button.new()
	var quest_id: String = quest.get("id", "")
	var title: String = quest.get("title", "?")

	var prefix := ""
	if quest_id in _tracked_quest_ids:
		prefix = "► "
	if QuestSystem.is_quest_completed(quest_id):
		prefix = "✓ "

	btn.text = prefix + title

	# Difficulty color indicator
	var difficulty: String = quest.get("difficulty", "").to_lower()
	var diff_color: Color = DIFFICULTY_COLORS.get(difficulty, DEFAULT_DIFFICULTY_COLOR)
	btn.add_theme_color_override("font_color", diff_color)

	# Selection highlight
	if index == _selected_index:
		btn.add_theme_color_override("font_color", Color.YELLOW)

	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(_on_quest_entry_pressed.bind(index))
	return btn


func _on_quest_entry_pressed(index: int) -> void:
	select_quest(index)


# ═══════════════════════════════════════════════
# Selection
# ═══════════════════════════════════════════════

func select_quest(index: int) -> void:
	if index < 0 or index >= _filtered_quests.size():
		_clear_selection()
		return
	_selected_index = index
	_show_detail_panel(_filtered_quests[index])
	refresh_quest_list()


func _clear_selection() -> void:
	_selected_index = -1
	_detail_panel.visible = false


func has_selection() -> bool:
	return _selected_index >= 0 and _selected_index < _filtered_quests.size()


func get_selected_quest() -> Dictionary:
	if not has_selection():
		return {}
	return _filtered_quests[_selected_index]


# ═══════════════════════════════════════════════
# Detail panel
# ═══════════════════════════════════════════════

func _show_detail_panel(quest: Dictionary) -> void:
	_detail_panel.visible = true

	_detail_title.text = "[b]%s[/b]" % quest.get("title", "")
	_detail_description.text = quest.get("description", "")
	_detail_type.text = "Type: %s" % quest.get("questType", "unknown")
	_detail_difficulty.text = "Difficulty: %s" % quest.get("difficulty", "normal")

	var loc_name: String = quest.get("locationName", "")
	_detail_location.text = "Location: %s" % loc_name if not loc_name.is_empty() else ""
	_detail_location.visible = not loc_name.is_empty()

	_detail_rewards.text = _format_rewards(quest)

	_refresh_objectives(quest)
	_update_detail_buttons(quest)


func _format_rewards(quest: Dictionary) -> String:
	var parts: Array[String] = []
	var xp: int = quest.get("experienceReward", 0)
	if xp > 0:
		parts.append("%d XP" % xp)
	var item_rewards: Array = quest.get("itemRewards", [])
	if item_rewards.size() > 0:
		parts.append("%d item(s)" % item_rewards.size())
	var skill_rewards: Array = quest.get("skillRewards", [])
	if skill_rewards.size() > 0:
		parts.append("%d skill(s)" % skill_rewards.size())
	if parts.is_empty():
		return "No rewards"
	return "Rewards: " + ", ".join(parts)


func _refresh_objectives(quest: Dictionary) -> void:
	for child in _objectives_container.get_children():
		child.queue_free()

	var quest_id: String = quest.get("id", "")
	var objs: Array[Dictionary] = QuestSystem.get_objectives_for_quest(quest_id)

	for obj in objs:
		var lbl := RichTextLabel.new()
		lbl.bbcode_enabled = true
		lbl.fit_content = true
		lbl.custom_minimum_size = Vector2(0, 24)

		var completed: bool = obj.get("completed", false)
		var current: int = obj.get("current_count", 0)
		var target: int = obj.get("required_count", 1)
		var desc: String = obj.get("description", "")
		var optional: bool = obj.get("optional", false)

		var status: String
		if completed:
			status = "✓"
		elif target > 1:
			status = "%d/%d" % [current, target]
		else:
			status = "○"

		var opt_text := " [i](optional)[/i]" if optional else ""
		lbl.text = "[%s] %s%s" % [status, desc, opt_text]
		_objectives_container.add_child(lbl)


func _update_detail_buttons(quest: Dictionary) -> void:
	var quest_id: String = quest.get("id", "")
	var is_active: bool = QuestSystem.is_quest_active(quest_id)
	var is_completed: bool = QuestSystem.is_quest_completed(quest_id)

	_track_button.visible = is_active
	_accept_button.visible = not is_active and not is_completed
	_abandon_button.visible = is_active

	if is_active:
		var is_tracked: bool = quest_id in _tracked_quest_ids
		_track_button.text = "Untrack" if is_tracked else "Track"


# ═══════════════════════════════════════════════
# Action buttons
# ═══════════════════════════════════════════════

func toggle_track_selected() -> void:
	var quest := get_selected_quest()
	if quest.is_empty():
		return
	var quest_id: String = quest.get("id", "")

	if quest_id in _tracked_quest_ids:
		_tracked_quest_ids.erase(quest_id)
		quest_untracked.emit(quest_id)
	else:
		if _tracked_quest_ids.size() >= MAX_TRACKED_QUESTS:
			var removed: String = _tracked_quest_ids.pop_front()
			quest_untracked.emit(removed)
		_tracked_quest_ids.append(quest_id)
		quest_tracked.emit(quest_id)

	_update_detail_buttons(quest)
	refresh_quest_list()
	_update_tracked_hud()


func accept_selected() -> void:
	var quest := get_selected_quest()
	if quest.is_empty():
		return
	QuestSystem.accept_quest(quest.get("id", ""))
	refresh_quest_list()
	if has_selection():
		_show_detail_panel(_filtered_quests[_selected_index])


func abandon_selected() -> void:
	var quest := get_selected_quest()
	if quest.is_empty():
		return
	var quest_id: String = quest.get("id", "")
	_tracked_quest_ids.erase(quest_id)
	refresh_quest_list()
	if has_selection():
		_show_detail_panel(_filtered_quests[_selected_index])
	_update_tracked_hud()


func get_tracked_quest_ids() -> Array[String]:
	return _tracked_quest_ids.duplicate()


# ═══════════════════════════════════════════════
# Tracked quests HUD
# ═══════════════════════════════════════════════

func _update_tracked_hud() -> void:
	if _tracked_hud == null:
		return

	if _tracked_quest_ids.is_empty():
		_tracked_hud.text = ""
		return

	var text := ""
	for quest_id in _tracked_quest_ids:
		var quest: Dictionary = QuestSystem.get_quest(quest_id)
		if quest.is_empty():
			continue
		text += "[b]%s[/b]\n" % quest.get("title", "?")
		var objs: Array = QuestSystem.get_objectives_for_quest(quest_id)
		for obj in objs:
			if obj.get("completed", false):
				continue
			var desc: String = obj.get("description", "")
			var current: int = obj.get("current_count", 0)
			var target: int = obj.get("required_count", 1)
			var progress := " (%d/%d)" % [current, target] if target > 1 else ""
			text += "  • %s%s\n" % [desc, progress]
	_tracked_hud.text = text


func _process(_delta: float) -> void:
	_update_tracked_hud()


# ═══════════════════════════════════════════════
# Event handlers
# ═══════════════════════════════════════════════

func _on_quest_accepted(_quest_id: String) -> void:
	if _is_open:
		refresh_quest_list()


func _on_quest_completed(quest_id: String) -> void:
	_tracked_quest_ids.erase(quest_id)
	if _is_open:
		refresh_quest_list()
	_update_tracked_hud()


# ═══════════════════════════════════════════════
# UI construction (built in code — no .tscn needed)
# ═══════════════════════════════════════════════

func _build_ui() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# ── Journal panel (centered overlay) ──────────────────────────────
	_journal_panel = PanelContainer.new()
	_journal_panel.anchor_left = 0.1
	_journal_panel.anchor_top = 0.05
	_journal_panel.anchor_right = 0.9
	_journal_panel.anchor_bottom = 0.95
	add_child(_journal_panel)

	var root_vbox := VBoxContainer.new()
	_journal_panel.add_child(root_vbox)

	# ── Title ─────────────────────────────────────────────────────────
	var title_label := Label.new()
	title_label.text = "Quest Journal"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	root_vbox.add_child(title_label)

	# ── Tab bar ───────────────────────────────────────────────────────
	var tab_bar := HBoxContainer.new()
	tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(tab_bar)

	_tab_all = _make_tab_button("All", FilterTab.ALL)
	_tab_active = _make_tab_button("Active", FilterTab.ACTIVE)
	_tab_completed = _make_tab_button("Completed", FilterTab.COMPLETED)
	_tab_available = _make_tab_button("Available", FilterTab.AVAILABLE)
	tab_bar.add_child(_tab_all)
	tab_bar.add_child(_tab_active)
	tab_bar.add_child(_tab_completed)
	tab_bar.add_child(_tab_available)

	# ── Split panel (list left, detail right) ─────────────────────────
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(split)

	# Left: quest list
	_list_panel = VBoxContainer.new()
	_list_panel.custom_minimum_size = Vector2(250, 0)
	split.add_child(_list_panel)

	_quest_scroll = ScrollContainer.new()
	_quest_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_panel.add_child(_quest_scroll)

	_quest_list_container = VBoxContainer.new()
	_quest_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_scroll.add_child(_quest_list_container)

	# Right: detail panel
	_detail_panel = VBoxContainer.new()
	_detail_panel.custom_minimum_size = Vector2(350, 0)
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_panel.visible = false
	split.add_child(_detail_panel)

	_detail_title = RichTextLabel.new()
	_detail_title.bbcode_enabled = true
	_detail_title.fit_content = true
	_detail_title.custom_minimum_size = Vector2(0, 32)
	_detail_panel.add_child(_detail_title)

	_detail_description = RichTextLabel.new()
	_detail_description.bbcode_enabled = true
	_detail_description.fit_content = true
	_detail_description.custom_minimum_size = Vector2(0, 48)
	_detail_panel.add_child(_detail_description)

	_detail_type = Label.new()
	_detail_panel.add_child(_detail_type)

	_detail_difficulty = Label.new()
	_detail_panel.add_child(_detail_difficulty)

	_detail_location = Label.new()
	_detail_panel.add_child(_detail_location)

	_detail_rewards = RichTextLabel.new()
	_detail_rewards.bbcode_enabled = true
	_detail_rewards.fit_content = true
	_detail_rewards.custom_minimum_size = Vector2(0, 24)
	_detail_panel.add_child(_detail_rewards)

	# Objectives section
	var obj_label := Label.new()
	obj_label.text = "Objectives"
	obj_label.add_theme_font_size_override("font_size", 18)
	_detail_panel.add_child(obj_label)

	var obj_scroll := ScrollContainer.new()
	obj_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_panel.add_child(obj_scroll)

	_objectives_container = VBoxContainer.new()
	_objectives_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	obj_scroll.add_child(_objectives_container)

	# Action buttons
	var btn_bar := HBoxContainer.new()
	btn_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_detail_panel.add_child(btn_bar)

	_track_button = Button.new()
	_track_button.text = "Track"
	_track_button.pressed.connect(toggle_track_selected)
	btn_bar.add_child(_track_button)

	_accept_button = Button.new()
	_accept_button.text = "Accept"
	_accept_button.pressed.connect(accept_selected)
	btn_bar.add_child(_accept_button)

	_abandon_button = Button.new()
	_abandon_button.text = "Abandon"
	_abandon_button.pressed.connect(abandon_selected)
	btn_bar.add_child(_abandon_button)

	# ── Tracked quests HUD (top-right corner, always visible) ────────
	_tracked_hud = RichTextLabel.new()
	_tracked_hud.bbcode_enabled = true
	_tracked_hud.fit_content = true
	_tracked_hud.anchor_left = 0.7
	_tracked_hud.anchor_top = 0.02
	_tracked_hud.anchor_right = 0.98
	_tracked_hud.anchor_bottom = 0.3
	_tracked_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tracked_hud)

	_update_tab_styles()


func _make_tab_button(label: String, tab: FilterTab) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.pressed.connect(set_filter_tab.bind(tab))
	return btn


func _update_tab_styles() -> void:
	for btn: Button in [_tab_all, _tab_active, _tab_completed, _tab_available]:
		if btn == null:
			continue
		btn.add_theme_color_override("font_color", Color.WHITE)

	var active_btn: Button
	match _current_tab:
		FilterTab.ALL: active_btn = _tab_all
		FilterTab.ACTIVE: active_btn = _tab_active
		FilterTab.COMPLETED: active_btn = _tab_completed
		FilterTab.AVAILABLE: active_btn = _tab_available
	if active_btn:
		active_btn.add_theme_color_override("font_color", Color.YELLOW)
