// insimul_talos_bridge.cpp — marshalling only; see the header.

#include "insimul_talos_bridge.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

insimul::talos::Readings InsimulTalosBridge::to_readings(const Dictionary &readings) {
	insimul::talos::Readings out;
	out.engine = String(readings.get("engine", "godot")).utf8().get_data();
	out.engine_version = String(readings.get("engine_version", "")).utf8().get_data();
	out.plugin_version = String(readings.get("plugin_version", "")).utf8().get_data();
	out.core_version = String(readings.get("core_version", "")).utf8().get_data();
	out.snapshot_version = String(readings.get("snapshot_version", "")).utf8().get_data();
	out.world_id = String(readings.get("world_id", "")).utf8().get_data();
	out.seed = String(readings.get("seed", "")).utf8().get_data();
	out.kb_ready = bool(readings.get("kb_ready", false));
	const Array modules = readings.get("active_modules", Array());
	for (int i = 0; i < modules.size(); i++) {
		out.active_modules.push_back(String(modules[i]).utf8().get_data());
	}
	return out;
}

bool InsimulTalosBridge::configure(const String &contract_json, const String &matrix_json) {
	return bridge_.configure(contract_json.utf8().get_data(), matrix_json.utf8().get_data());
}

bool InsimulTalosBridge::is_configured() const {
	return bridge_.configured();
}

String InsimulTalosBridge::last_error() const {
	return String(bridge_.error().c_str());
}

PackedStringArray InsimulTalosBridge::groups() const {
	PackedStringArray out;
	const std::vector<std::string> names = bridge_.groups();
	for (size_t i = 0; i < names.size(); i++) {
		out.push_back(String(names[i].c_str()));
	}
	return out;
}

String InsimulTalosBridge::capabilities(const Dictionary &readings) const {
	return String(bridge_.capabilities(to_readings(readings)).c_str());
}

String InsimulTalosBridge::hello(const Dictionary &readings) const {
	return String(bridge_.hello(to_readings(readings)).c_str());
}

String InsimulTalosBridge::evaluate_hello(const String &hello_json, const String &matrix_override) const {
	return String(bridge_.evaluate_hello(hello_json.utf8().get_data(),
								   matrix_override.utf8().get_data())
						  .c_str());
}

String InsimulTalosBridge::evaluate_archive(const String &archive_json, const String &matrix_override) const {
	return String(bridge_.evaluate_archive(archive_json.utf8().get_data(),
								   matrix_override.utf8().get_data())
						  .c_str());
}

String InsimulTalosBridge::checkpoint_stamp(const Dictionary &readings) const {
	return String(bridge_.checkpoint_stamp(to_readings(readings)).c_str());
}

String InsimulTalosBridge::verb(const String &name, const Dictionary &readings,
		const String &required_module) const {
	return String(bridge_.verb(name.utf8().get_data(), to_readings(readings),
								   required_module.utf8().get_data())
						  .c_str());
}

String InsimulTalosBridge::query_digest(const String &solutions_json, int cap_bytes) const {
	const size_t cap = cap_bytes > 0 ? static_cast<size_t>(cap_bytes)
									 : insimul::talos::QUERY_DIGEST_CAP_BYTES;
	return String(bridge_.query_digest(solutions_json.utf8().get_data(), cap).c_str());
}

String InsimulTalosBridge::progress_var(const String &name, const String &value_json,
		bool targets_template, const Dictionary &readings) const {
	return String(bridge_.progress_var(name.utf8().get_data(), value_json.utf8().get_data(),
								   targets_template, to_readings(readings))
						  .c_str());
}

void InsimulTalosBridge::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "contract_json", "matrix_json"), &InsimulTalosBridge::configure);
	ClassDB::bind_method(D_METHOD("is_configured"), &InsimulTalosBridge::is_configured);
	ClassDB::bind_method(D_METHOD("last_error"), &InsimulTalosBridge::last_error);
	ClassDB::bind_method(D_METHOD("groups"), &InsimulTalosBridge::groups);
	ClassDB::bind_method(D_METHOD("capabilities", "readings"), &InsimulTalosBridge::capabilities);
	ClassDB::bind_method(D_METHOD("hello", "readings"), &InsimulTalosBridge::hello);
	ClassDB::bind_method(D_METHOD("evaluate_hello", "hello_json", "matrix_override"),
			&InsimulTalosBridge::evaluate_hello, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("evaluate_archive", "archive_json", "matrix_override"),
			&InsimulTalosBridge::evaluate_archive, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("checkpoint_stamp", "readings"), &InsimulTalosBridge::checkpoint_stamp);
	ClassDB::bind_method(D_METHOD("verb", "name", "readings", "required_module"),
			&InsimulTalosBridge::verb, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("query_digest", "solutions_json", "cap_bytes"),
			&InsimulTalosBridge::query_digest, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("progress_var", "name", "value_json", "targets_template", "readings"),
			&InsimulTalosBridge::progress_var);
}
