// insimul_talos_bridge.cpp — marshalling only; see the header.

#include "insimul_talos_bridge.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cstdint>
#include <string>

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

bool InsimulTalosBridge::configure(const String &contract_json, const String &matrix_json,
		const String &vocabulary_json) {
	const bool decided = bridge_.configure(contract_json.utf8().get_data(), matrix_json.utf8().get_data());
	// The replay leg is configured in the same breath and reported in the same
	// answer: an install that can decide but cannot read a trace is half-present,
	// and §7.8's whole argument is that half-present must be loud.
	const bool replayable = replay_.configure(vocabulary_json.utf8().get_data());
	return decided && replayable;
}

bool InsimulTalosBridge::is_configured() const {
	// Both halves, because an install that can decide but cannot read a trace is
	// half-present and must say so at install time rather than at replay time.
	return bridge_.configured() && replay_.configured();
}

String InsimulTalosBridge::last_error() const {
	if (!bridge_.error().empty()) {
		return String(bridge_.error().c_str());
	}
	return String(replay_.error().c_str());
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

String InsimulTalosBridge::diagnose_install(const Dictionary &readings) const {
	insimul::talos::InstallReadings out;
	out.extension_registered = bool(readings.get("extension_registered", true));
	out.contract_json = String(readings.get("contract_json", "")).utf8().get_data();
	out.matrix_json = String(readings.get("matrix_json", "")).utf8().get_data();
	out.vocabulary_json = String(readings.get("vocabulary_json", "")).utf8().get_data();
	return String(insimul::talos::Bridge::diagnose_install(out).c_str());
}

String InsimulTalosBridge::open_trace(const String &trace_json, const String &world_json) const {
	return String(replay_.open_trace(trace_json.utf8().get_data(), world_json.utf8().get_data()).c_str());
}

String InsimulTalosBridge::plan_replay(const String &trace_json, const String &world_json,
		const String &options_json) const {
	return String(replay_.plan(trace_json.utf8().get_data(), world_json.utf8().get_data(),
							 options_json.utf8().get_data())
						  .c_str());
}

String InsimulTalosBridge::seal_outcome(const String &args_json) const {
	return String(replay_.seal_outcome(args_json.utf8().get_data()).c_str());
}

String InsimulTalosBridge::read_outcome(const String &outcome_json) const {
	return String(replay_.read_outcome(outcome_json.utf8().get_data()).c_str());
}

String InsimulTalosBridge::verify_outcome(const String &recorded_json, const String &trace_id) const {
	return String(replay_.verify_outcome(recorded_json.utf8().get_data(), trace_id.utf8().get_data()).c_str());
}

String InsimulTalosBridge::compare_outcomes(const String &recorded_json, const String &replayed_json) const {
	return String(replay_.compare(recorded_json.utf8().get_data(), replayed_json.utf8().get_data()).c_str());
}

String InsimulTalosBridge::world_content_digest(const String &world_json) const {
	return String(insimul::talos::Replay::world_content_digest(world_json.utf8().get_data()).c_str());
}

String InsimulTalosBridge::kb_digest(const String &facts_json) const {
	return String(insimul::talos::Replay::kb_digest(facts_json.utf8().get_data()).c_str());
}

int InsimulTalosBridge::replay_entropy(const String &seed, int tick) const {
	const std::string key = seed.utf8().get_data();
	// A `uint32` reaching GDScript as an int: Godot's is 64-bit, so the value
	// survives whole and a world seeding its PRNG from it lands where core did.
	const uint32_t drawn = tick < 0 ? insimul::talos::Replay::entropy(key)
									: insimul::talos::Replay::entropy(key, tick);
	return static_cast<int>(drawn);
}

void InsimulTalosBridge::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "contract_json", "matrix_json", "vocabulary_json"),
			&InsimulTalosBridge::configure, DEFVAL(String()));
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
	ClassDB::bind_method(D_METHOD("diagnose_install", "readings"), &InsimulTalosBridge::diagnose_install);
	ClassDB::bind_method(D_METHOD("open_trace", "trace_json", "world_json"), &InsimulTalosBridge::open_trace);
	ClassDB::bind_method(D_METHOD("plan_replay", "trace_json", "world_json", "options_json"),
			&InsimulTalosBridge::plan_replay, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("seal_outcome", "args_json"), &InsimulTalosBridge::seal_outcome);
	ClassDB::bind_method(D_METHOD("read_outcome", "outcome_json"), &InsimulTalosBridge::read_outcome);
	ClassDB::bind_method(D_METHOD("verify_outcome", "recorded_json", "trace_id"),
			&InsimulTalosBridge::verify_outcome);
	ClassDB::bind_method(D_METHOD("compare_outcomes", "recorded_json", "replayed_json"),
			&InsimulTalosBridge::compare_outcomes);
	ClassDB::bind_method(D_METHOD("world_content_digest", "world_json"),
			&InsimulTalosBridge::world_content_digest);
	ClassDB::bind_method(D_METHOD("kb_digest", "facts_json"), &InsimulTalosBridge::kb_digest);
	ClassDB::bind_method(D_METHOD("replay_entropy", "seed", "tick"),
			&InsimulTalosBridge::replay_entropy, DEFVAL(-1));
}
