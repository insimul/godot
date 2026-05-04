extends Node
## NPC Greeting System — interaction prompts and contextual greetings.
## Matches shared/game-engine/rendering/NPCGreetingSystem.ts, NPCInteractionPrompt.ts.

signal interaction_started(npc_id: String)

@export var detection_radius := 4.0
@export var greeting_cooldown := 30.0

var _prompt_label: Label = null
var _nearby_npc: Node3D = null
var _greeting_timers: Dictionary = {}  # npc_id -> seconds since last greeting

func _ready() -> void:
	_create_prompt_ui()

func _create_prompt_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)

	_prompt_label = Label.new()
	_prompt_label.text = "[E] Talk"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.anchors_preset = Control.PRESET_CENTER_BOTTOM
	_prompt_label.anchor_top = 0.85
	_prompt_label.anchor_bottom = 0.9
	_prompt_label.anchor_left = 0.4
	_prompt_label.anchor_right = 0.6
	_prompt_label.visible = false
	canvas.add_child(_prompt_label)

func register_npc(npc: CharacterBody3D) -> void:
	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = detection_radius
	col.shape = sphere
	area.add_child(col)
	area.monitoring = true
	area.collision_layer = 0
	area.collision_mask = 1  # Player layer
	npc.add_child(area)

	area.body_entered.connect(func(body): _on_player_entered(body, npc))
	area.body_exited.connect(func(body): _on_player_exited(body, npc))

	# Name label above NPC head
	var name_label := Label3D.new()
	name_label.text = npc.get("character_id") if npc.get("character_id") else npc.name
	name_label.position.y = 2.2
	name_label.font_size = 18
	name_label.outline_size = 4
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.modulate = Color(1, 1, 1, 0.9)
	npc.add_child(name_label)

	# Role label
	var role: String = npc.get("role") if npc.get("role") else ""
	if role != "":
		var role_label := Label3D.new()
		role_label.text = role.capitalize()
		role_label.position.y = 2.0
		role_label.font_size = 14
		role_label.outline_size = 3
		role_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		role_label.modulate = Color(0.8, 0.8, 0.6, 0.8)
		npc.add_child(role_label)

func _on_player_entered(body: Node3D, npc: CharacterBody3D) -> void:
	if not body.is_in_group("player"):
		return
	_nearby_npc = npc
	_prompt_label.visible = true
	_show_greeting(npc)

func _on_player_exited(body: Node3D, npc: CharacterBody3D) -> void:
	if not body.is_in_group("player"):
		return
	if _nearby_npc == npc:
		_nearby_npc = null
		_prompt_label.visible = false

func _show_greeting(npc: CharacterBody3D) -> void:
	var npc_id: String = npc.get("character_id") if npc.get("character_id") else npc.name
	var last_greet: float = _greeting_timers.get(npc_id, 0.0)
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - last_greet < greeting_cooldown:
		return
	_greeting_timers[npc_id] = now

	# Speech bubble with contextual greeting
	var greeting := _generate_greeting(npc)
	var bubble := Label3D.new()
	bubble.text = greeting
	bubble.position.y = 2.5
	bubble.font_size = 16
	bubble.outline_size = 4
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.modulate = Color(1, 1, 0.9, 1)
	npc.add_child(bubble)

	# Remove after 4 seconds
	get_tree().create_timer(4.0).timeout.connect(func(): bubble.queue_free())

func _generate_greeting(npc: CharacterBody3D) -> String:
	var hour: float = GameClock.current_hour
	var time_greeting := "Hello"
	if hour < 6:
		time_greeting = "*yawns*"
	elif hour < 12:
		time_greeting = "Good morning"
	elif hour < 18:
		time_greeting = "Good afternoon"
	else:
		time_greeting = "Good evening"
	return time_greeting + "!"

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _nearby_npc:
		var npc_id: String = _nearby_npc.get("character_id") if _nearby_npc.get("character_id") else _nearby_npc.name
		interaction_started.emit(npc_id)
		if _nearby_npc.has_method("start_dialogue"):
			var players := get_tree().get_nodes_in_group("player")
			if players.size() > 0:
				_nearby_npc.start_dialogue(players[0])
