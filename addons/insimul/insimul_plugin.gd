@tool
extends EditorPlugin
## Insimul editor plugin — registers autoload and custom nodes.


func _enter_tree() -> void:
	add_autoload_singleton("InsimulClient", "res://addons/insimul/insimul_client.gd")


func _exit_tree() -> void:
	remove_autoload_singleton("InsimulClient")
