extends Node
## Quest Completion Manager — detects completions, awards rewards, shows notifications.
## Matches shared/game-engine/rendering/QuestCompletionManager.ts, QuestNotificationSystem.ts.

signal quest_completed(quest_id: String)
signal quest_updated(quest_id: String, objective_id: String)
signal quest_started(quest_id: String)
signal reward_granted(quest_id: String, rewards: Dictionary)

var _notification_canvas: CanvasLayer = null
var _notification_container: VBoxContainer = null

func _ready() -> void:
	_build_notification_ui()
	# Connect to quest system if available
	var quest_sys := get_node_or_null("/root/QuestSystem")
	if quest_sys:
		if quest_sys.has_signal("objective_completed"):
			quest_sys.objective_completed.connect(_on_objective_completed)

func check_quest_completion(quest_id: String) -> bool:
	var quest_sys := get_node_or_null("/root/QuestSystem")
	if not quest_sys or not quest_sys.has_method("get_quest"):
		return false

	var quest: Dictionary = quest_sys.get_quest(quest_id)
	if quest.is_empty():
		return false

	var objectives: Array = quest.get("objectives", [])
	for obj in objectives:
		if not obj.get("completed", false):
			return false

	# All objectives complete
	_complete_quest(quest_id, quest)
	return true

func _complete_quest(quest_id: String, quest: Dictionary) -> void:
	# Award rewards
	var rewards: Dictionary = quest.get("rewards", {})
	var xp: int = rewards.get("xp", 0)
	var gold: int = rewards.get("gold", 0)
	var items: Array = rewards.get("items", [])

	if gold > 0:
		InventorySystem.set_gold(InventorySystem.gold + gold)
	for item in items:
		InventorySystem.add_item(item)

	# Update reputation
	var rep_mgr := get_node_or_null("/root/ReputationManager")
	var settlement_id: String = quest.get("settlementId", "")
	var npc_id: String = quest.get("giverNpcId", "")
	if rep_mgr and rep_mgr.has_method("on_quest_completed"):
		rep_mgr.on_quest_completed(npc_id, settlement_id)

	_show_notification("Quest Complete: %s" % quest.get("title", quest_id))
	quest_completed.emit(quest_id)
	reward_granted.emit(quest_id, rewards)

func _on_objective_completed(quest_id: String, objective_id: String) -> void:
	_show_notification("Objective Complete: %s" % objective_id)
	quest_updated.emit(quest_id, objective_id)
	check_quest_completion(quest_id)

func register_hotspot(quest_id: String, position: Vector3, radius: float) -> void:
	var area := Area3D.new()
	area.name = "QuestHotspot_%s" % quest_id
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	col.shape = sphere
	area.add_child(col)
	area.monitoring = true
	area.collision_layer = 0
	area.collision_mask = 1

	area.body_entered.connect(func(body):
		if body.is_in_group("player"):
			var quest_sys := get_node_or_null("/root/QuestSystem")
			if quest_sys and quest_sys.has_method("complete_objective_by_location"):
				quest_sys.complete_objective_by_location(quest_id, position)
	)
	add_child(area)
	area.global_position = position

func _build_notification_ui() -> void:
	_notification_canvas = CanvasLayer.new()
	_notification_canvas.layer = 9
	add_child(_notification_canvas)

	_notification_container = VBoxContainer.new()
	_notification_container.anchors_preset = Control.PRESET_TOP_LEFT
	_notification_container.anchor_left = 0.02
	_notification_container.anchor_right = 0.4
	_notification_container.anchor_top = 0.15
	_notification_container.anchor_bottom = 0.5
	_notification_canvas.add_child(_notification_container)

func _show_notification(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = Color(1, 1, 0.8, 1)
	_notification_container.add_child(label)

	# Fade and remove after 4 seconds
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)
