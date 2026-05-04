extends CanvasLayer
## HUD manager — shows health, energy, gold, survival bars, compass, time, and notifications.

@onready var health_bar: ProgressBar = $HealthBar if has_node("HealthBar") else null
@onready var health_label: Label = $HealthLabel if has_node("HealthLabel") else null
@onready var gold_label: Label = $GoldLabel if has_node("GoldLabel") else null

var _player: CharacterBody3D
var _survival_system: Node = null
var _survival_bars: Dictionary = {}  # need_id -> {bar: ProgressBar, label: Label, container: HBoxContainer}
var _survival_container: VBoxContainer = null

## Compass & time
var _compass_label: Label = null
var _time_label: Label = null

## Notification ticker
var _notification_container: VBoxContainer = null
var _notifications: Array[Dictionary] = []  # [{label, timer}]
const NOTIFICATION_DURATION := 5.0
const NOTIFICATION_MAX := 5

const COMPASS_DIRECTIONS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

const NEED_ICONS: Dictionary = {
	"hunger": "Hunger",
	"thirst": "Thirst",
	"temperature": "Temp",
	"stamina": "Stamina",
	"sleep": "Rest",
}

const NEED_COLORS: Dictionary = {
	"hunger": Color(0.85, 0.55, 0.2),
	"thirst": Color(0.3, 0.6, 0.9),
	"temperature": Color(0.9, 0.4, 0.3),
	"stamina": Color(0.9, 0.85, 0.2),
	"sleep": Color(0.5, 0.4, 0.8),
}

func _ready() -> void:
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_survival_system = get_node_or_null("/root/SurvivalSystem")
	if _survival_system:
		_setup_survival_bars()
		if _survival_system.has_signal("need_warning"):
			_survival_system.need_warning.connect(_on_need_warning)
		if _survival_system.has_signal("need_critical"):
			_survival_system.need_critical.connect(_on_need_critical)
		if _survival_system.has_signal("need_restored"):
			_survival_system.need_restored.connect(_on_need_restored)
	_setup_compass()
	_setup_time_display()
	_setup_notifications()
	# Subscribe to events for notifications
	EventBus.connect_event("quest_accepted", func(e: Dictionary): show_notification("Quest accepted: %s" % e.get("quest_title", ""), Color(0.3, 0.8, 1.0)))
	EventBus.connect_event("quest_completed", func(e: Dictionary): show_notification("Quest completed!", Color(0.3, 1.0, 0.3)))
	EventBus.connect_event("item_collected", func(e: Dictionary): show_notification("Collected: %s" % e.get("item_name", ""), Color(0.9, 0.8, 0.5)))
	EventBus.connect_event("level_up", func(e: Dictionary): show_notification("Level Up!", Color(1.0, 0.85, 0.0)))
	EventBus.connect_event("achievement_unlocked", func(e: Dictionary): show_notification("Achievement: %s" % e.get("achievement_name", ""), Color(1.0, 0.8, 0.2)))

func _setup_survival_bars() -> void:
	_survival_container = VBoxContainer.new()
	_survival_container.name = "SurvivalBars"
	_survival_container.anchor_left = 0.0
	_survival_container.anchor_top = 0.0
	_survival_container.offset_left = 10.0
	_survival_container.offset_top = 60.0
	_survival_container.add_theme_constant_override("separation", 4)
	add_child(_survival_container)

	var all_needs: Array = _survival_system.get_all_needs()
	for need in all_needs:
		var nid: String = need.get("id", "")
		_add_survival_bar(nid, need.get("max_value", 100.0), need.get("value", 100.0))

func _add_survival_bar(need_id: String, max_val: float, current_val: float) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var label: Label = Label.new()
	label.text = NEED_ICONS.get(need_id, need_id)
	label.custom_minimum_size = Vector2(60, 0)
	label.add_theme_font_size_override("font_size", 12)
	row.add_child(label)

	var bar: ProgressBar = ProgressBar.new()
	bar.max_value = max_val
	bar.value = current_val
	bar.custom_minimum_size = Vector2(120, 16)
	bar.show_percentage = false
	var style := StyleBoxFlat.new()
	style.bg_color = NEED_COLORS.get(need_id, Color(0.5, 0.5, 0.5))
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("fill", style)
	row.add_child(bar)

	_survival_container.add_child(row)
	_survival_bars[need_id] = {"bar": bar, "label": label, "container": row}

func _process(delta: float) -> void:
	if _player == null:
		return
	if health_bar and _player.has_method("get"):
		health_bar.max_value = _player.get("max_health") if _player.get("max_health") else 100.0
		health_bar.value = _player.get("health") if _player.get("health") else 100.0
	if health_label and _player.get("health") != null:
		health_label.text = "%d / %d" % [ceili(_player.health), ceili(_player.max_health)]
	if gold_label and _player.get("gold") != null:
		gold_label.text = str(_player.gold)

	_update_survival_bars()
	_update_compass()
	_update_time()
	_update_notifications(delta)

func _update_survival_bars() -> void:
	if _survival_system == null:
		return
	for need_id in _survival_bars:
		var entry: Dictionary = _survival_bars[need_id]
		var bar: ProgressBar = entry.get("bar")
		if bar:
			bar.value = _survival_system.get_need_value(need_id)

func _on_need_warning(need_id: String, _value: float) -> void:
	_flash_bar(need_id, Color.YELLOW)

func _on_need_critical(need_id: String, _value: float) -> void:
	_flash_bar(need_id, Color.RED)

func _on_need_restored(need_id: String, _value: float) -> void:
	_reset_bar_color(need_id)

func _flash_bar(need_id: String, color: Color) -> void:
	if not _survival_bars.has(need_id):
		return
	var entry: Dictionary = _survival_bars[need_id]
	var bar: ProgressBar = entry.get("bar")
	if bar:
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.corner_radius_top_left = 3
		style.corner_radius_top_right = 3
		style.corner_radius_bottom_left = 3
		style.corner_radius_bottom_right = 3
		bar.add_theme_stylebox_override("fill", style)

func _reset_bar_color(need_id: String) -> void:
	if not _survival_bars.has(need_id):
		return
	var entry: Dictionary = _survival_bars[need_id]
	var bar: ProgressBar = entry.get("bar")
	if bar:
		var style := StyleBoxFlat.new()
		style.bg_color = NEED_COLORS.get(need_id, Color(0.5, 0.5, 0.5))
		style.corner_radius_top_left = 3
		style.corner_radius_top_right = 3
		style.corner_radius_bottom_left = 3
		style.corner_radius_bottom_right = 3
		bar.add_theme_stylebox_override("fill", style)

# ─────────────────────────────────────────────
# Compass
# ─────────────────────────────────────────────

func _setup_compass() -> void:
	_compass_label = Label.new()
	_compass_label.anchor_left = 0.45
	_compass_label.anchor_right = 0.55
	_compass_label.anchor_top = 0.01
	_compass_label.anchor_bottom = 0.05
	_compass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compass_label.add_theme_font_size_override("font_size", 18)
	_compass_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	_compass_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_compass_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_compass_label)

func _update_compass() -> void:
	if _compass_label == null or _player == null:
		return
	var yaw: float = _player.rotation.y
	# Normalize to 0-360
	var degrees: float = fmod(rad_to_deg(-yaw) + 360.0, 360.0)
	var idx: int = int(round(degrees / 45.0)) % 8
	var dir: String = COMPASS_DIRECTIONS[idx]
	_compass_label.text = "%s  %d\u00B0" % [dir, int(degrees)]

# ─────────────────────────────────────────────
# Time display
# ─────────────────────────────────────────────

func _setup_time_display() -> void:
	_time_label = Label.new()
	_time_label.anchor_left = 0.88
	_time_label.anchor_right = 0.99
	_time_label.anchor_top = 0.01
	_time_label.anchor_bottom = 0.05
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.add_theme_font_size_override("font_size", 16)
	_time_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
	_time_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_time_label)

func _update_time() -> void:
	if _time_label == null:
		return
	var hour: int = int(GameClock.current_hour)
	var minute: int = int((GameClock.current_hour - float(hour)) * 60.0)
	var period: String = "AM" if hour < 12 else "PM"
	var display_hour: int = hour % 12
	if display_hour == 0:
		display_hour = 12
	_time_label.text = "Day %d  %d:%02d %s" % [GameClock.day, display_hour, minute, period]

# ─────────────────────────────────────────────
# Notification ticker
# ─────────────────────────────────────────────

func _setup_notifications() -> void:
	_notification_container = VBoxContainer.new()
	_notification_container.anchor_left = 0.6
	_notification_container.anchor_right = 0.98
	_notification_container.anchor_top = 0.06
	_notification_container.anchor_bottom = 0.25
	_notification_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	_notification_container.add_theme_constant_override("separation", 2)
	_notification_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_notification_container)

func show_notification(text: String, color: Color = Color.WHITE) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notification_container.add_child(label)
	_notifications.append({"label": label, "timer": 0.0})

	# Trim oldest
	while _notifications.size() > NOTIFICATION_MAX:
		var old: Dictionary = _notifications[0]
		if is_instance_valid(old["label"]):
			old["label"].queue_free()
		_notifications.remove_at(0)

func _update_notifications(delta: float) -> void:
	var to_remove: Array[int] = []
	for i in range(_notifications.size()):
		var entry: Dictionary = _notifications[i]
		entry["timer"] += delta
		if entry["timer"] > NOTIFICATION_DURATION:
			var fade: float = (entry["timer"] - NOTIFICATION_DURATION) / 1.0
			if fade >= 1.0:
				to_remove.append(i)
				if is_instance_valid(entry["label"]):
					entry["label"].queue_free()
			elif is_instance_valid(entry["label"]):
				entry["label"].modulate.a = 1.0 - fade

	for i in range(to_remove.size() - 1, -1, -1):
		_notifications.remove_at(to_remove[i])
