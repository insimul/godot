// register_types.cpp — registers the Insimul classes with Godot's ClassDB and wires
// the GDExtension entry symbol referenced by insimul.gdextension.
//
// Syntax-gated only (needs godot-cpp). Follows the standard godot-cpp 4.x
// GDExtension bootstrap.

#include "register_types.h"

#include "insimul_core.h"
#include "insimul_prolog.h"
#include "insimul_quest_core.h"
#include "insimul_runtime_core.h"
#include "insimul_save_codec.h"
#include "insimul_talos_bridge.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_insimul_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(InsimulCore);
	GDREGISTER_CLASS(InsimulProlog);
	GDREGISTER_CLASS(InsimulQuestCore);
	GDREGISTER_CLASS(InsimulRuntimeCore);
	GDREGISTER_CLASS(InsimulSaveCodec);
	// The decision half of insimul-talos-bridge (addons/insimul_talos/). Inert
	// unless that addon hands it a contract, and nothing in addons/insimul/ ever
	// does — see insimul_talos_bridge.h.
	GDREGISTER_CLASS(InsimulTalosBridge);
}

void uninitialize_insimul_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
// Entry symbol — must match `entry_symbol` in insimul.gdextension.
GDExtensionBool GDE_EXPORT insimul_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(
			p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_insimul_module);
	init_obj.register_terminator(uninitialize_insimul_module);
	init_obj.set_minimum_library_initialization_level(
			MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
