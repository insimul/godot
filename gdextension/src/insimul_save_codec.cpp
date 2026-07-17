// insimul_save_codec.cpp — Godot-facing save codec implementation.
//
// Syntax-gated only (needs godot-cpp). All non-trivial logic is delegated to the
// host-tested core (save_file.cpp); this file only marshals String<->std::string
// and Array<->std::vector<PrologFact>.

#include "insimul_save_codec.h"

#include <godot_cpp/core/class_db.hpp>

#include <string>
#include <vector>

using namespace godot;

namespace {

std::string to_std(const String &s) {
	return std::string(s.utf8().get_data());
}

} // namespace

bool InsimulSaveCodec::load(const String &json) {
	std::string error;
	const bool ok = save_.load(to_std(json), error);
	last_error_ = ok ? String() : String(error.c_str());
	return ok;
}

bool InsimulSaveCodec::new_game(const String &world_snapshot_json, const String &id,
		const String &user_id, const String &world_id, const String &name, int slot_index,
		const String &created_at) {
	insimul::NewGameOptions opts;
	opts.id = to_std(id);
	opts.user_id = to_std(user_id);
	opts.world_id = to_std(world_id);
	opts.name = to_std(name);
	opts.slot_index = slot_index;
	if (!created_at.is_empty()) {
		opts.created_at = to_std(created_at);
	}
	std::string error;
	const bool ok = save_.new_game(to_std(world_snapshot_json), opts, error);
	last_error_ = ok ? String() : String(error.c_str());
	return ok;
}

bool InsimulSaveCodec::is_loaded() const {
	return save_.is_loaded();
}

int InsimulSaveCodec::version() const {
	return save_.version();
}

String InsimulSaveCodec::serialize_canonical() const {
	return String(save_.serialize_canonical().c_str());
}

String InsimulSaveCodec::compute_integrity() const {
	return String(save_.compute_integrity().c_str());
}

String InsimulSaveCodec::build_envelope(const String &insimul_version, const String &exported_at) const {
	return String(save_.build_envelope_json(to_std(insimul_version), to_std(exported_at)).c_str());
}

void InsimulSaveCodec::snapshot_facts(const Array &facts) {
	std::vector<insimul::PrologFact> out;
	for (int i = 0; i < facts.size(); ++i) {
		const Dictionary fact_dict = facts[i];
		insimul::PrologFact fact;
		fact.predicate = to_std(String(fact_dict.get("predicate", String())));
		const Array args = fact_dict.get("args", Array());
		for (int j = 0; j < args.size(); ++j) {
			const Variant arg = args[j];
			switch (arg.get_type()) {
				case Variant::INT:
					fact.args.push_back(insimul::PrologArg::number((double)(int64_t)arg));
					break;
				case Variant::FLOAT:
					fact.args.push_back(insimul::PrologArg::number((double)arg));
					break;
				default:
					fact.args.push_back(insimul::PrologArg::atom(to_std(String(arg))));
					break;
			}
		}
		out.push_back(fact);
	}
	save_.snapshot_facts(out);
}

Array InsimulSaveCodec::restore_facts() const {
	Array out;
	const std::vector<insimul::PrologFact> facts = save_.restore_facts();
	for (const insimul::PrologFact &fact : facts) {
		Dictionary fact_dict;
		fact_dict["predicate"] = String(fact.predicate.c_str());
		Array args;
		for (const insimul::PrologArg &arg : fact.args) {
			if (arg.is_number) {
				args.push_back((double)arg.num);
			} else {
				args.push_back(String(arg.str.c_str()));
			}
		}
		fact_dict["args"] = args;
		out.push_back(fact_dict);
	}
	return out;
}

String InsimulSaveCodec::last_error() const {
	return last_error_;
}

void InsimulSaveCodec::_bind_methods() {
	ClassDB::bind_method(D_METHOD("load", "json"), &InsimulSaveCodec::load);
	ClassDB::bind_method(
			D_METHOD("new_game", "world_snapshot_json", "id", "user_id", "world_id", "name", "slot_index", "created_at"),
			&InsimulSaveCodec::new_game);
	ClassDB::bind_method(D_METHOD("is_loaded"), &InsimulSaveCodec::is_loaded);
	ClassDB::bind_method(D_METHOD("version"), &InsimulSaveCodec::version);
	ClassDB::bind_method(D_METHOD("serialize_canonical"), &InsimulSaveCodec::serialize_canonical);
	ClassDB::bind_method(D_METHOD("compute_integrity"), &InsimulSaveCodec::compute_integrity);
	ClassDB::bind_method(D_METHOD("build_envelope", "insimul_version", "exported_at"),
			&InsimulSaveCodec::build_envelope);
	ClassDB::bind_method(D_METHOD("snapshot_facts", "facts"), &InsimulSaveCodec::snapshot_facts);
	ClassDB::bind_method(D_METHOD("restore_facts"), &InsimulSaveCodec::restore_facts);
	ClassDB::bind_method(D_METHOD("last_error"), &InsimulSaveCodec::last_error);
}
