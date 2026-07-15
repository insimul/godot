// register_types.h — GDExtension entry points (godot-cpp init/terminate).
#ifndef INSIMUL_GODOT_REGISTER_TYPES_H
#define INSIMUL_GODOT_REGISTER_TYPES_H

#include <godot_cpp/core/class_db.hpp>

void initialize_insimul_module(godot::ModuleInitializationLevel p_level);
void uninitialize_insimul_module(godot::ModuleInitializationLevel p_level);

#endif // INSIMUL_GODOT_REGISTER_TYPES_H
