@tool
extends EditorPlugin
## Installs `insimul-talos-bridge` — the third artifact of
## TALOS_INSIMUL_BRIDGE.md §7.5 — as an autoload beside the game.
##
## THIS IS NOT AN INSIMUL PLUGIN AND NOT A TALOS PLUGIN. §7.5 rejected both
## shapes: an adapter inside the Insimul plugin would put QA code in every
## shipped game and tie Insimul's release cadence to TBP's, and an adapter inside
## the Talos plugin is structurally impossible on two of the three engines. The
## artifact that is left depends on both and is depended on by neither, and on
## Godot it can be exactly this: one autoload, one node script, and data.
##
## An autoload rather than a scene node because the Bridge finds the game's
## participation by GROUP membership, and a node that is not in the tree is in no
## group. Autoload ORDER is deliberately not relied on — §7.3's first Godot
## collision is that registration order is whichever addon was enabled first, and
## the fix is not to sequence it but to forbid the read that made it matter
## (§7.5). See insimul_talos_adapter.gd.
##
## QA-ONLY. Release export presets should exclude this addon and the Talos one.
## The adapter is inert without Talos — there is no Talos symbol in it to
## resolve — and Talos's own autoload is dormant without its launch switch, but
## posture should be explicit rather than inherited (§7.8's last row).

const AUTOLOAD_NAME := "InsimulTalos"
const AUTOLOAD_PATH := "res://addons/insimul_talos/insimul_talos_adapter.gd"


func _enter_tree() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
