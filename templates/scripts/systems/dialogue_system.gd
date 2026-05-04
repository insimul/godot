extends Node
## Dialogue System — autoloaded singleton.
## Manages NPC conversations with AI-powered chat.

signal dialogue_started(npc_id: String)
signal dialogue_ended
signal action_selected(action_id: String)

var is_in_dialogue := false
var current_npc_id := ""
var player_energy: float = 100.0

signal audio_requested(npc_id: String, text: String)

var _dialogue_panel = null
var _ai_config: Dictionary = {}
var _dialogue_contexts: Array = []
var _social_actions: Array = []

func _ready() -> void:
	_load_dialogue_data()
	_load_social_actions()
	call_deferred("_setup_ai_service")
	call_deferred("_setup_dialogue_panel")

func _load_dialogue_data() -> void:
	var config_file = FileAccess.open("res://data/ai_config.json", FileAccess.READ)
	if config_file:
		var parsed = JSON.parse_string(config_file.get_as_text())
		if parsed is Dictionary:
			_ai_config = parsed
			print("[Insimul] AI config loaded: mode=%s" % _ai_config.get("apiMode", "insimul"))
	else:
		_ai_config = {"apiMode": "insimul", "insimulEndpoint": "/api/gemini/chat", "geminiModel": "gemini-3.1-flash", "voiceEnabled": true, "defaultVoice": "Kore"}
		print("[Insimul] ai_config.json not found, using defaults")

	var ctx_file = FileAccess.open("res://data/dialogue_contexts.json", FileAccess.READ)
	if ctx_file:
		var parsed = JSON.parse_string(ctx_file.get_as_text())
		if parsed is Array:
			_dialogue_contexts = parsed
			print("[Insimul] Loaded %d dialogue contexts" % _dialogue_contexts.size())
	else:
		print("[Insimul] dialogue_contexts.json not found")

func _setup_ai_service() -> void:
	var ai = get_node_or_null("/root/AIService")
	if ai:
		ai.initialize(_ai_config, _dialogue_contexts)

func _setup_dialogue_panel() -> void:
	var root = get_tree().root
	_dialogue_panel = _find_dialogue_panel(root)
	if _dialogue_panel == null:
		var PanelScript = load("res://scripts/ui/dialogue_panel.gd")
		if PanelScript:
			var panel_node = CanvasLayer.new()
			panel_node.set_script(PanelScript)
			root.add_child(panel_node)
			_dialogue_panel = panel_node
	if _dialogue_panel:
		_dialogue_panel.dialogue_closed.connect(_on_panel_closed)

func _find_dialogue_panel(node: Node):
	if node.has_method("open_dialogue"):
		return node
	for child in node.get_children():
		var result = _find_dialogue_panel(child)
		if result:
			return result
	return null

func start_dialogue(npc_character_id: String) -> void:
	if is_in_dialogue:
		end_dialogue()

	is_in_dialogue = true
	current_npc_id = npc_character_id
	dialogue_started.emit(npc_character_id)

	if _dialogue_panel and _dialogue_panel.has_method("open_dialogue"):
		_dialogue_panel.open_dialogue(npc_character_id)
		var actions := get_available_actions()
		if actions.size() > 0:
			_dialogue_panel.show_responses(actions)

	print("[Insimul] Dialogue started with NPC: %s" % npc_character_id)

func end_dialogue() -> void:
	var npc_id := current_npc_id
	is_in_dialogue = false
	current_npc_id = ""
	dialogue_ended.emit()

	if _dialogue_panel and _dialogue_panel.has_method("close_dialogue"):
		_dialogue_panel.close_dialogue()

	print("[Insimul] Dialogue ended with NPC: %s" % npc_id)

func _on_panel_closed() -> void:
	if is_in_dialogue:
		end_dialogue()

func set_player_energy(energy: float) -> void:
	player_energy = maxf(0.0, energy)

## Returns an array of action dictionaries that the player can currently afford.
func get_available_actions() -> Array:
	if not is_in_dialogue:
		return []

	var available: Array = []
	for action in _social_actions:
		if not action is Dictionary:
			continue
		var energy_cost: float = action.get("energyCost", 0.0)
		if energy_cost <= 0.0 or energy_cost <= player_energy:
			available.append(action)
	return available

## Select an action during dialogue. Checks affordability and emits action_selected.
func select_action(action_id: String) -> void:
	if not is_in_dialogue:
		print("[Insimul] Cannot select action - not in dialogue")
		return

	for action in _social_actions:
		if not action is Dictionary:
			continue
		if action.get("id", "") == action_id:
			var energy_cost: float = action.get("energyCost", 0.0)
			if energy_cost > 0.0 and energy_cost > player_energy:
				print("[Insimul] Not enough energy for action: %s (cost=%.0f, energy=%.0f)" % [action_id, energy_cost, player_energy])
				return
			action_selected.emit(action_id)
			print("[Insimul] Action selected: %s" % action_id)
			return

	print("[Insimul] Action not found: %s" % action_id)

## Show dialogue with romance actions merged alongside base actions.
## Converts romance action dicts into standard social action format and appends them.
## romance_actions: Array of dicts with keys: id, name, requiredStage, sparkGain, description (optional), energyCost (optional)
func show_with_romance_actions(base_actions: Array, romance_actions: Array, energy: float) -> void:
	set_player_energy(energy)

	var combined: Array = base_actions.duplicate()
	for ra in romance_actions:
		if not ra is Dictionary:
			continue
		var desc: String = ra.get("description", "")
		if desc.is_empty():
			desc = "Romance action (requires %s stage)" % ra.get("requiredStage", "unknown")
		combined.append({
			"id": "romance_%s" % ra.get("id", ""),
			"name": "\U0001F495 %s" % ra.get("name", ""),
			"description": desc,
			"actionType": "social",
			"category": "romance",
			"energyCost": ra.get("energyCost", 5.0),
			"sparkGain": ra.get("sparkGain", 0.0),
			"romanceActionId": ra.get("id", ""),
			"tags": ["romance"]
		})
	_social_actions = combined

	print("[Insimul] show_with_romance_actions: added %d romance actions (total=%d)" % [romance_actions.size(), _social_actions.size()])

func _load_social_actions() -> void:
	var actions_file = FileAccess.open("res://data/social_actions.json", FileAccess.READ)
	if actions_file:
		var parsed = JSON.parse_string(actions_file.get_as_text())
		if parsed is Array:
			_social_actions = parsed
			print("[Insimul] Loaded %d social actions" % _social_actions.size())
	else:
		print("[Insimul] social_actions.json not found")
