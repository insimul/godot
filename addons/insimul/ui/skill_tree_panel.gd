class_name InsimulSkillTreePanel
extends Control
## Skill-tree Control — a thin view over InsimulSkillTreeModel (US-GU2).
##
## Draws the node set tier by tier and spends points through the model, which owns
## prerequisites, cost and eligibility. Module-gated on `skill`: a world that does
## not activate the Skills module never resolves this panel (panels.json).

signal skill_unlocked(skill_id: String)

var _model := InsimulSkillTreeModel.new()
var _points_label: Label = null
var _tiers: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = InsimulUiTokens.build_theme()
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["md"]))
	add_child(box)

	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", int(InsimulUiTokens.FONT_SIZE["title"]))
	box.add_child(_points_label)

	_tiers = VBoxContainer.new()
	_tiers.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["sm"]))
	box.add_child(_tiers)


## Bind the skill set ({ id, name, tier?, requires?, cost? }) and the spendable
## points. Share the model with a progression system via [method set_model].
func set_skills(nodes: Array, points: int = 0) -> void:
	_model.set_nodes(nodes)
	_model.set_points(points)
	_refresh()


func set_model(model: InsimulSkillTreeModel) -> void:
	_model = model
	_refresh()


func model() -> InsimulSkillTreeModel:
	return _model


func unlock(id: String) -> bool:
	var ok := _model.unlock(id)
	if ok:
		skill_unlocked.emit(id)
		_refresh()
	return ok


func refresh() -> void:
	_refresh()


func _refresh() -> void:
	if _tiers == null:
		return
	_points_label.text = "Skill points: %d" % _model.points()
	for child in _tiers.get_children():
		child.queue_free()
	for tier in _model.tiers():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(InsimulUiTokens.SPACING["sm"]))
		var tier_label := Label.new()
		tier_label.text = "Tier %d" % int(tier)
		tier_label.add_theme_color_override("font_color", InsimulUiTokens.color("text_secondary"))
		row.add_child(tier_label)
		for node in _model.nodes_in_tier(int(tier)):
			row.add_child(_node_button(String(node.get("id", ""))))
		_tiers.add_child(row)


func _node_button(id: String) -> Button:
	var view := _model.node_view(id)
	var button := Button.new()
	button.text = String(view.get("name", id))
	button.disabled = not bool(view.get("available", false))
	if bool(view.get("unlocked", false)):
		button.add_theme_color_override("font_color", InsimulUiTokens.color("success"))
	elif not (view.get("missing", []) as Array).is_empty():
		button.tooltip_text = "Requires: %s" % ", ".join(PackedStringArray(view.get("missing", [])))
	button.pressed.connect(unlock.bind(id))
	return button
