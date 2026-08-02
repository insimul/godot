// insimul_core.cpp — Godot-facing wrapper implementation.
//
// Syntax-gated only (needs godot-cpp). The C ABI it wraps IS exercised here, by
// test/run_radiant_tests.sh, which drives the identical calls from a plain C++
// harness — so the only thing untested in this file is the String <-> const char*
// plumbing, which is mechanical.

#include "insimul_core.h"

#include "../corebridge/include/insimulcore.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

InsimulCore::InsimulCore() {
	core_ = insimul_core_create();
	if (!core_) {
		// A missing/broken bundle is a build defect, and a silent one would look
		// exactly like "core generated nothing". Say it once, loudly, at
		// construction rather than per call.
		last_error_ = String("insimulcore: core runtime failed to start (see stderr)");
		UtilityFunctions::push_error(last_error_);
	}
}

InsimulCore::~InsimulCore() {
	if (core_) {
		insimul_core_destroy(core_);
		core_ = nullptr;
	}
}

String InsimulCore::call_json(const String &method, const String &args_json) {
	if (!core_) {
		return String();
	}
	last_error_ = String();
	const CharString args = args_json.utf8();
	const char *result = insimul_core_call(
			core_, method.utf8().get_data(), args.length() > 0 ? args.get_data() : nullptr);
	if (!result) {
		last_error_ = String(insimul_core_last_error(core_));
		return String();
	}
	return String(result);
}

String InsimulCore::get_version() const {
	return String(insimul_core_version());
}

String InsimulCore::last_error() const {
	if (!core_) {
		return last_error_;
	}
	const String abi_error = String(insimul_core_last_error(core_));
	return abi_error.is_empty() ? last_error_ : abi_error;
}

void InsimulCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_available"), &InsimulCore::is_available);
	ClassDB::bind_method(D_METHOD("call_json", "method", "args_json"), &InsimulCore::call_json);
	ClassDB::bind_method(D_METHOD("get_version"), &InsimulCore::get_version);
	ClassDB::bind_method(D_METHOD("last_error"), &InsimulCore::last_error);
}
