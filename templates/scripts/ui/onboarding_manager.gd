extends Node
## Onboarding Manager — step-by-step tutorial system.
## Matches shared/game-engine/rendering/OnboardingLauncher.ts, logic/OnboardingManager.ts.

signal tutorial_step_completed(step_id: String)
signal tutorial_completed

const TUTORIAL_STEPS := [
	{"id": "movement", "text": "Use WASD to move around.", "action": "move_forward"},
	{"id": "camera", "text": "Move the mouse to look around.", "action": ""},
	{"id": "interact", "text": "Press E to interact with objects and NPCs.", "action": "interact"},
	{"id": "inventory", "text": "Press Tab to open your inventory.", "action": "inventory"},
	{"id": "journal", "text": "Press J to open the quest journal.", "action": "journal"},
	{"id": "combat", "text": "Click to attack enemies.", "action": "attack"},
]

var _current_step := 0
var _is_active := false
var _overlay: CanvasLayer = null
var _instruction_label: Label = null
var _arrow: TextureRect = null

func _ready() -> void:
	_build_ui()

func start_tutorial() -> void:
	_is_active = true
	_current_step = 0
	_show_step()

func skip_tutorial() -> void:
	_is_active = false
	_overlay.visible = false
	tutorial_completed.emit()

func _show_step() -> void:
	if _current_step >= TUTORIAL_STEPS.size():
		_is_active = false
		_overlay.visible = false
		tutorial_completed.emit()
		return

	var step: Dictionary = TUTORIAL_STEPS[_current_step]
	_instruction_label.text = step.get("text", "")
	_overlay.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if not _is_active:
		return

	var step: Dictionary = TUTORIAL_STEPS[_current_step]
	var action: String = step.get("action", "")

	if action == "":
		# Mouse movement step — any mouse motion completes it
		if event is InputEventMouseMotion:
			_complete_current_step()
	elif event.is_action_pressed(action):
		_complete_current_step()

func _complete_current_step() -> void:
	var step: Dictionary = TUTORIAL_STEPS[_current_step]
	tutorial_step_completed.emit(step.get("id", ""))
	_current_step += 1
	_show_step()

func _build_ui() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 50
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.visible = false
	add_child(_overlay)

	# Semi-transparent overlay
	var bg := ColorRect.new()
	bg.anchors_preset = Control.PRESET_FULL_RECT
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0, 0, 0, 0.3)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(bg)

	# Instruction panel
	var panel := PanelContainer.new()
	panel.anchors_preset = Control.PRESET_CENTER_BOTTOM
	panel.anchor_left = 0.3
	panel.anchor_right = 0.7
	panel.anchor_top = 0.8
	panel.anchor_bottom = 0.95
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(panel)

	_instruction_label = Label.new()
	_instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_instruction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_instruction_label)

	# Skip button
	var skip_btn := Button.new()
	skip_btn.text = "Skip Tutorial"
	skip_btn.anchors_preset = Control.PRESET_TOP_RIGHT
	skip_btn.anchor_left = 0.85
	skip_btn.anchor_right = 0.98
	skip_btn.anchor_top = 0.02
	skip_btn.anchor_bottom = 0.06
	skip_btn.pressed.connect(skip_tutorial)
	_overlay.add_child(skip_btn)
