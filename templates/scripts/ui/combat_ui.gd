extends CanvasLayer
## Combat UI — floating damage numbers, enemy health bars, and combat log.
## Listens to EventBus combat events and displays feedback.

const DAMAGE_FLOAT_DURATION := 1.2
const DAMAGE_FLOAT_RISE := 60.0
const LOG_MAX_ENTRIES := 8
const LOG_FADE_TIME := 5.0

var _damage_numbers: Array[Dictionary] = []  # [{label, timer, velocity}]
var _combat_log_entries: Array[Dictionary] = []  # [{text, timer}]
var _enemy_bars: Dictionary = {}  # entity_id → {bar, label, timer}

var _log_container: VBoxContainer = null
var _bar_container: Control = null

func _ready() -> void:
	layer = 15
	_build_ui()
	EventBus.connect_event("combat_action", _on_combat_action)
	EventBus.connect_event("enemy_defeated", _on_enemy_defeated)

func _process(delta: float) -> void:
	_update_damage_numbers(delta)
	_update_combat_log(delta)
	_update_enemy_bars(delta)

# ─────────────────────────────────────────────
# UI construction
# ─────────────────────────────────────────────

func _build_ui() -> void:
	# Combat log (bottom-left)
	var log_anchor := Control.new()
	log_anchor.anchor_left = 0.02
	log_anchor.anchor_right = 0.35
	log_anchor.anchor_top = 0.6
	log_anchor.anchor_bottom = 0.95
	log_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(log_anchor)

	_log_container = VBoxContainer.new()
	_log_container.anchor_right = 1.0
	_log_container.anchor_bottom = 1.0
	_log_container.alignment = BoxContainer.ALIGNMENT_END
	_log_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_anchor.add_child(_log_container)

	# Container for enemy health bars (centered top area)
	_bar_container = Control.new()
	_bar_container.anchor_left = 0.3
	_bar_container.anchor_right = 0.7
	_bar_container.anchor_top = 0.02
	_bar_container.anchor_bottom = 0.15
	_bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_container)

# ─────────────────────────────────────────────
# Floating damage numbers
# ─────────────────────────────────────────────

func show_damage(amount: int, pos: Vector2, is_critical: bool = false, is_heal: bool = false) -> void:
	var label := Label.new()
	label.text = str(amount) if not is_heal else "+%d" % amount
	label.add_theme_font_size_override("font_size", 28 if is_critical else 22)

	if is_heal:
		label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	elif is_critical:
		label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
		label.text += "!"
	else:
		label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))

	label.position = pos
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

	_damage_numbers.append({
		"label": label,
		"timer": 0.0,
		"velocity": Vector2(randf_range(-20, 20), -DAMAGE_FLOAT_RISE),
	})

func _update_damage_numbers(delta: float) -> void:
	var to_remove: Array[int] = []
	for i in range(_damage_numbers.size()):
		var entry: Dictionary = _damage_numbers[i]
		entry["timer"] += delta
		var label: Label = entry["label"]
		var vel: Vector2 = entry["velocity"]

		label.position += vel * delta
		entry["velocity"] = Vector2(vel.x, vel.y + 40.0 * delta)  # gravity

		# Fade out
		var t: float = entry["timer"] / DAMAGE_FLOAT_DURATION
		if t >= 1.0:
			to_remove.append(i)
			label.queue_free()
		else:
			label.modulate.a = 1.0 - t

	for i in range(to_remove.size() - 1, -1, -1):
		_damage_numbers.remove_at(to_remove[i])

# ─────────────────────────────────────────────
# Combat log
# ─────────────────────────────────────────────

func add_log_entry(text: String, color: Color = Color.WHITE) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_container.add_child(label)

	_combat_log_entries.append({"label": label, "timer": 0.0})

	# Trim old entries
	while _combat_log_entries.size() > LOG_MAX_ENTRIES:
		var old: Dictionary = _combat_log_entries[0]
		if is_instance_valid(old["label"]):
			old["label"].queue_free()
		_combat_log_entries.remove_at(0)

func _update_combat_log(delta: float) -> void:
	var to_remove: Array[int] = []
	for i in range(_combat_log_entries.size()):
		var entry: Dictionary = _combat_log_entries[i]
		entry["timer"] += delta
		if entry["timer"] > LOG_FADE_TIME:
			var fade_t: float = (entry["timer"] - LOG_FADE_TIME) / 2.0
			if fade_t >= 1.0:
				to_remove.append(i)
				if is_instance_valid(entry["label"]):
					entry["label"].queue_free()
			elif is_instance_valid(entry["label"]):
				entry["label"].modulate.a = 1.0 - fade_t

	for i in range(to_remove.size() - 1, -1, -1):
		_combat_log_entries.remove_at(to_remove[i])

# ─────────────────────────────────────────────
# Enemy health bars
# ─────────────────────────────────────────────

func show_enemy_bar(entity_id: String, entity_name: String, health: float, max_health: float) -> void:
	if _enemy_bars.has(entity_id):
		_update_bar(entity_id, health, max_health)
		return

	var container := VBoxContainer.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_label := Label.new()
	name_label.text = entity_name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(name_label)

	var bar := ProgressBar.new()
	bar.max_value = max_health
	bar.value = health
	bar.custom_minimum_size = Vector2(200, 16)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.7, 0.15, 0.15)
	bar_style.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", bar_style)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.15, 0.12, 0.10)
	bar_bg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bar_bg)

	container.add_child(bar)
	_bar_container.add_child(container)

	_enemy_bars[entity_id] = {
		"container": container,
		"bar": bar,
		"name_label": name_label,
		"timer": 0.0,
	}

func _update_bar(entity_id: String, health: float, max_health: float) -> void:
	if not _enemy_bars.has(entity_id):
		return
	var entry: Dictionary = _enemy_bars[entity_id]
	entry["bar"].max_value = max_health
	entry["bar"].value = health
	entry["timer"] = 0.0

func remove_enemy_bar(entity_id: String) -> void:
	if _enemy_bars.has(entity_id):
		var entry: Dictionary = _enemy_bars[entity_id]
		if is_instance_valid(entry["container"]):
			entry["container"].queue_free()
		_enemy_bars.erase(entity_id)

func _update_enemy_bars(delta: float) -> void:
	var to_remove: Array[String] = []
	for entity_id in _enemy_bars:
		var entry: Dictionary = _enemy_bars[entity_id]
		entry["timer"] += delta
		# Auto-hide after 8 seconds of no updates
		if entry["timer"] > 8.0:
			to_remove.append(entity_id)

	for entity_id in to_remove:
		remove_enemy_bar(entity_id)

# ─────────────────────────────────────────────
# Event handlers
# ─────────────────────────────────────────────

func _on_combat_action(event: Dictionary) -> void:
	var action_type: String = event.get("action_type", "attack")
	var damage: int = event.get("damage", 0)
	var target_name: String = event.get("target_name", "enemy")
	var is_critical: bool = event.get("is_critical", false)

	# Show floating number at screen center (approximate)
	var viewport_size := get_viewport().get_visible_rect().size
	var pos := Vector2(
		viewport_size.x / 2.0 + randf_range(-50, 50),
		viewport_size.y / 3.0
	)
	show_damage(damage, pos, is_critical)

	# Log entry
	var log_text: String
	if is_critical:
		log_text = "CRITICAL! %s takes %d damage!" % [target_name, damage]
		add_log_entry(log_text, Color(1.0, 0.85, 0.0))
	else:
		log_text = "%s takes %d damage" % [target_name, damage]
		add_log_entry(log_text, Color(0.9, 0.6, 0.5))

	# Update enemy health bar if target info available
	var target_id: String = event.get("target_id", "")
	if target_id != "":
		var health: float = event.get("target_health", 0.0)
		var max_health: float = event.get("target_max_health", 100.0)
		show_enemy_bar(target_id, target_name, health, max_health)

func _on_enemy_defeated(event: Dictionary) -> void:
	var entity_name: String = event.get("enemy_type", "Enemy")
	add_log_entry("%s defeated!" % entity_name, Color(0.3, 0.9, 0.3))
	var entity_id: String = event.get("entity_id", "")
	if entity_id != "":
		remove_enemy_bar(entity_id)
