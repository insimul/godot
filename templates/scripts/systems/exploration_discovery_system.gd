extends Node
## Exploration Discovery System — tracks visited areas and awards discoveries.
## Matches shared/game-engine/rendering/ExplorationDiscoverySystem.ts.

signal area_discovered(area_id: String, area_name: String)
signal lore_collected(lore_id: String, title: String)
signal discovery_bonus(xp: int, item_id: String)

var _discovered_areas: Array[String] = []
var _collected_lore: Array[Dictionary] = []
var _notification_panel: PanelContainer = null
var _notification_label: Label = null
var _notification_anim: AnimationPlayer = null

func _ready() -> void:
	_build_notification_ui()

func register_discovery_zone(area_id: String, area_name: String, position: Vector3, radius: float) -> void:
	var area := Area3D.new()
	area.name = "DiscoveryZone_%s" % area_id
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	col.shape = sphere
	area.add_child(col)
	area.monitoring = true
	area.collision_layer = 0
	area.collision_mask = 1

	area.body_entered.connect(func(body):
		if body.is_in_group("player") and area_id not in _discovered_areas:
			_on_area_discovered(area_id, area_name)
	)

	add_child(area)
	area.global_position = position

func is_discovered(area_id: String) -> bool:
	return area_id in _discovered_areas

func get_discovered_count() -> int:
	return _discovered_areas.size()

func collect_lore(lore_id: String, title: String, text: String) -> void:
	for entry in _collected_lore:
		if entry.get("id") == lore_id:
			return  # Already collected
	_collected_lore.append({"id": lore_id, "title": title, "text": text})
	lore_collected.emit(lore_id, title)
	_show_notification("Lore collected: %s" % title)

func get_all_lore() -> Array[Dictionary]:
	return _collected_lore

func _on_area_discovered(area_id: String, area_name: String) -> void:
	_discovered_areas.append(area_id)

	# Award XP bonus
	var xp_reward := 50
	area_discovered.emit(area_id, area_name)
	discovery_bonus.emit(xp_reward, "")

	_show_notification("Discovered: %s" % area_name)
	print("[Exploration] Discovered %s (total: %d)" % [area_name, _discovered_areas.size()])

func _build_notification_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 8
	add_child(canvas)

	_notification_panel = PanelContainer.new()
	_notification_panel.anchors_preset = Control.PRESET_TOP_RIGHT
	_notification_panel.anchor_left = 0.6
	_notification_panel.anchor_right = 0.98
	_notification_panel.anchor_top = 0.02
	_notification_panel.anchor_bottom = 0.08
	_notification_panel.visible = false
	canvas.add_child(_notification_panel)

	_notification_label = Label.new()
	_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notification_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notification_panel.add_child(_notification_label)

	_notification_anim = AnimationPlayer.new()
	_notification_panel.add_child(_notification_anim)

	# Create slide-in animation
	var anim_lib := AnimationLibrary.new()
	var anim := Animation.new()
	anim.length = 3.0
	var track_idx := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track_idx, ".:visible")
	anim.track_insert_key(track_idx, 0.0, true)
	anim.track_insert_key(track_idx, 2.5, true)
	anim.track_insert_key(track_idx, 3.0, false)
	anim_lib.add_animation("show", anim)
	_notification_anim.add_animation_library("", anim_lib)

func _show_notification(text: String) -> void:
	if _notification_label:
		_notification_label.text = text
		_notification_panel.visible = true
		_notification_anim.play("show")

func save_data() -> Dictionary:
	return {"discovered": _discovered_areas, "lore": _collected_lore}

func load_data(data: Dictionary) -> void:
	_discovered_areas.assign(data.get("discovered", []))
	_collected_lore.assign(data.get("lore", []))
