@tool
class_name InsimulBindingDock
extends Control
## Binding Editor dock — UI (US-GB3).
##
## The @tool Control the EditorPlugin docks into the editor (see
## insimul_plugin.gd add_control_to_dock). It is a THIN view over the logic layer
## (InsimulBindingDockModel): the model owns taxonomy-tree construction,
## bound/unbound status, suggestion ranking and pack import/export; this file only
## wires Godot Controls (Tree, buttons, dialogs) to those calls. Per the story's
## "logic layer tested; UI structurally checked" split, the model is exercised
## headless (binding_dock_test.gd) and this file is covered by the GDScript
## structural lint — the editor UI needs a running Godot editor to exercise, which
## the human end-to-end pass (VERIFICATION.md) does.

const BOUND_COLOR := Color(0.55, 0.85, 0.55)
const UNBOUND_COLOR := Color(0.9, 0.6, 0.55)

var model: InsimulBindingDockModel

## The taxonomy archetype keys the world uses (fed in by the owner / scene-gen IR).
var archetypes: Array = []

var _tree: Tree
var _scene_dialog: EditorFileDialog
var _pack_dialog: EditorFileDialog
var _status: Label
var _selected_archetype: String = ""
var _pack_saving := false


func _init() -> void:
	model = InsimulBindingDockModel.new()
	name = "Insimul Bindings"


func _ready() -> void:
	_build_ui()
	refresh()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var toolbar := HBoxContainer.new()
	root.add_child(toolbar)

	var bind_btn := Button.new()
	bind_btn.text = "Bind Scene…"
	bind_btn.pressed.connect(_on_bind_pressed)
	toolbar.add_child(bind_btn)

	var descend_btn := Button.new()
	descend_btn.text = "Bind Descendants…"
	descend_btn.pressed.connect(_on_bind_descendants_pressed)
	toolbar.add_child(descend_btn)

	var unbind_btn := Button.new()
	unbind_btn.text = "Unbind"
	unbind_btn.pressed.connect(_on_unbind_pressed)
	toolbar.add_child(unbind_btn)

	var import_btn := Button.new()
	import_btn.text = "Import Pack…"
	import_btn.pressed.connect(_on_import_pressed)
	toolbar.add_child(import_btn)

	var export_btn := Button.new()
	export_btn.text = "Export Pack…"
	export_btn.pressed.connect(_on_export_pressed)
	toolbar.add_child(export_btn)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.columns = 2
	_tree.set_column_title(0, "Archetype")
	_tree.set_column_title(1, "Binding")
	_tree.column_titles_visible = true
	_tree.item_selected.connect(_on_tree_item_selected)
	root.add_child(_tree)

	_status = Label.new()
	root.add_child(_status)

	_scene_dialog = EditorFileDialog.new()
	_scene_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_scene_dialog.add_filter("*.tscn", "PackedScene")
	_scene_dialog.add_filter("*.scn", "PackedScene")
	_scene_dialog.file_selected.connect(_on_scene_chosen)
	add_child(_scene_dialog)

	_pack_dialog = EditorFileDialog.new()
	_pack_dialog.add_filter("*.json", "Binding pack")
	_pack_dialog.file_selected.connect(_on_pack_file_selected)
	add_child(_pack_dialog)


## Rebuild the taxonomy tree from the model. Bound leaves are green, unbound red.
func refresh() -> void:
	if _tree == null:
		return
	_tree.clear()
	var root_item := _tree.create_item()
	root_item.set_text(0, "world")
	var data := model.build_taxonomy_tree(archetypes)
	_add_children(root_item, data)
	_update_status()


func _add_children(parent_item: TreeItem, node: Dictionary) -> void:
	var children: Dictionary = node.get("children", {})
	var keys := children.keys()
	keys.sort()
	for seg in keys:
		var child: Dictionary = children[seg]
		var item := _tree.create_item(parent_item)
		item.set_text(0, String(child.get("segment", "")))
		item.set_metadata(0, String(child.get("path", "")))
		var bound := bool(child.get("bound", false))
		var scene := String(child.get("scene", ""))
		item.set_text(1, scene if not scene.is_empty() else ("(bound)" if bound else "(unbound)"))
		item.set_custom_color(1, BOUND_COLOR if bound else UNBOUND_COLOR)
		_add_children(item, child)


func _update_status() -> void:
	var bound := model.bound_keys(archetypes).size()
	var total := archetypes.size()
	_status.text = "%d / %d archetypes bound" % [bound, total]


func _on_tree_item_selected() -> void:
	var item := _tree.get_selected()
	_selected_archetype = String(item.get_metadata(0)) if item != null else ""


func _on_bind_pressed() -> void:
	if _selected_archetype.is_empty():
		return
	_scene_dialog.popup_centered_ratio(0.6)


func _on_bind_descendants_pressed() -> void:
	# Same picker; binding a non-leaf key already covers descendants via the
	# resolver's descendant match, so this reuses the bind flow on the selected key.
	_on_bind_pressed()


func _on_scene_chosen(path: String) -> void:
	if _selected_archetype.is_empty():
		return
	model.bind(_selected_archetype, path)
	refresh()


func _on_unbind_pressed() -> void:
	if _selected_archetype.is_empty():
		return
	model.unbind(_selected_archetype)
	refresh()


func _on_import_pressed() -> void:
	_pack_saving = false
	_pack_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_pack_dialog.popup_centered_ratio(0.6)


func _on_export_pressed() -> void:
	_pack_saving = true
	_pack_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_pack_dialog.popup_centered_ratio(0.6)


func _on_pack_file_selected(path: String) -> void:
	if _pack_saving:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(model.export_pack_json())
			f.close()
	else:
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			model.import_pack_json(f.get_as_text())
			f.close()
			refresh()
