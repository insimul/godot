@tool
extends EditorPlugin
## Insimul editor plugin — registers the runtime autoload and the editor-time
## Binding Editor dock (US-GB3).

const BindingDock := preload("res://addons/insimul/editor/dock/insimul_binding_dock.gd")

var _binding_dock: Control


func _enter_tree() -> void:
	add_autoload_singleton("InsimulClient", "res://addons/insimul/insimul_client.gd")

	# Binding Editor dock — taxonomy tree, bound/unbound status, scene picker,
	# bind-descendants, suggestions, pack import/export (US-GB3).
	_binding_dock = BindingDock.new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _binding_dock)


func _exit_tree() -> void:
	if _binding_dock != null:
		remove_control_from_docks(_binding_dock)
		_binding_dock.queue_free()
		_binding_dock = null

	remove_autoload_singleton("InsimulClient")
