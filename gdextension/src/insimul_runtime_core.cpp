// insimul_runtime_core.cpp — Godot-facing bootstrap orchestrator implementation.
//
// Syntax-gated only (needs godot-cpp). All non-trivial logic is delegated to the
// host-tested core (bootstrap.cpp / RuntimeContext); this file only marshals
// String<->std::string and Array/Dictionary<->the core structs.

#include "insimul_runtime_core.h"

#include <godot_cpp/core/class_db.hpp>

#include <string>
#include <vector>

using namespace godot;

namespace {

std::string to_std(const String &s) {
	return std::string(s.utf8().get_data());
}

insimul::NewGameOptions options_from_dict(const Dictionary &d) {
	insimul::NewGameOptions o;
	o.id = to_std(String(d.get("id", String())));
	o.user_id = to_std(String(d.get("user_id", String())));
	o.world_id = to_std(String(d.get("world_id", String())));
	o.name = to_std(String(d.get("name", String())));
	o.slot_index = (int)(int64_t)d.get("slot_index", 0);
	if (d.has("created_at")) {
		o.created_at = to_std(String(d.get("created_at", String())));
	}
	return o;
}

// Dictionary{predicate, args:Array[String|int|float]} -> insimul::PrologFact.
insimul::PrologFact fact_from_dict(const Dictionary &fact_dict) {
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
	return fact;
}

// insimul::PrologFact -> Dictionary{predicate, args}.
Dictionary fact_to_dict(const insimul::PrologFact &fact) {
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
	return fact_dict;
}

} // namespace

Dictionary InsimulRuntimeCore::boot(const String &existing_save_json,
		const String &fallback_world_snapshot_json, const Dictionary &options) {
	const insimul::BootResult result = ctx_.boot(to_std(existing_save_json),
			to_std(fallback_world_snapshot_json), options_from_dict(options));
	last_error_ = result.error;
	Dictionary out;
	out["ok"] = result.ok;
	out["resumed_save"] = result.resumed_save;
	out["error"] = String(result.error.c_str());
	return out;
}

bool InsimulRuntimeCore::start_new_game(const String &world_snapshot_json, const Dictionary &options) {
	last_error_.clear();
	return ctx_.start_new_game(to_std(world_snapshot_json), options_from_dict(options), last_error_);
}

bool InsimulRuntimeCore::load_from_save(const String &save_json) {
	last_error_.clear();
	return ctx_.load_from_save(to_std(save_json), last_error_);
}

Dictionary InsimulRuntimeCore::entity_counts() const {
	Dictionary out;
	out["countries"] = ctx_.country_count();
	out["settlements"] = ctx_.settlement_count();
	out["characters"] = ctx_.character_count();
	out["lots"] = ctx_.lot_count();
	out["quests"] = ctx_.quest_count();
	out["rules"] = ctx_.rule_count();
	out["actions"] = ctx_.action_count();
	out["grammars"] = ctx_.grammar_count();
	return out;
}

Array InsimulRuntimeCore::kb_facts() const {
	Array out;
	for (const insimul::PrologFact &f : ctx_.kb().facts()) {
		out.push_back(fact_to_dict(f));
	}
	return out;
}

void InsimulRuntimeCore::set_kb(const Array &facts) {
	std::vector<insimul::PrologFact> loaded;
	for (int i = 0; i < facts.size(); ++i) {
		loaded.push_back(fact_from_dict(facts[i]));
	}
	ctx_.kb().load(loaded);
}

void InsimulRuntimeCore::assert_fact(const String &predicate, const Array &args) {
	Dictionary d;
	d["predicate"] = predicate;
	d["args"] = args;
	ctx_.kb().assert_fact(fact_from_dict(d));
}

Array InsimulRuntimeCore::run_radiant_tick(int max_offering, int ticks) {
	Array out;
	for (const insimul::PrologFact &f : ctx_.run_radiant_tick(max_offering, ticks)) {
		out.push_back(fact_to_dict(f));
	}
	return out;
}

Array InsimulRuntimeCore::evaluate_all_quests() {
	Array out;
	for (const insimul::QuestTransition &t : ctx_.evaluate_all_quests()) {
		Dictionary d;
		d["quest_id"] = String(t.quest_id.c_str());
		d["completed"] = t.completed;
		Array satisfied;
		for (const std::string &id : t.satisfied_objective_ids) {
			satisfied.push_back(String(id.c_str()));
		}
		d["satisfied_objective_ids"] = satisfied;
		out.push_back(d);
	}
	return out;
}

String InsimulRuntimeCore::build_envelope(const String &insimul_version, const String &exported_at) const {
	return String(ctx_.build_envelope_json(to_std(insimul_version), to_std(exported_at)).c_str());
}

void InsimulRuntimeCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("boot", "existing_save_json", "fallback_world_snapshot_json", "options"),
			&InsimulRuntimeCore::boot);
	ClassDB::bind_method(D_METHOD("start_new_game", "world_snapshot_json", "options"),
			&InsimulRuntimeCore::start_new_game);
	ClassDB::bind_method(D_METHOD("load_from_save", "save_json"), &InsimulRuntimeCore::load_from_save);
	ClassDB::bind_method(D_METHOD("is_loaded"), &InsimulRuntimeCore::is_loaded);
	ClassDB::bind_method(D_METHOD("last_error"), &InsimulRuntimeCore::last_error);
	ClassDB::bind_method(D_METHOD("entity_counts"), &InsimulRuntimeCore::entity_counts);
	ClassDB::bind_method(D_METHOD("world_id"), &InsimulRuntimeCore::world_id);
	ClassDB::bind_method(D_METHOD("spawn_character_id", "index"), &InsimulRuntimeCore::spawn_character_id);
	ClassDB::bind_method(D_METHOD("kb_facts"), &InsimulRuntimeCore::kb_facts);
	ClassDB::bind_method(D_METHOD("set_kb", "facts"), &InsimulRuntimeCore::set_kb);
	ClassDB::bind_method(D_METHOD("assert_fact", "predicate", "args"), &InsimulRuntimeCore::assert_fact);
	ClassDB::bind_method(D_METHOD("run_radiant_tick", "max_offering", "ticks"),
			&InsimulRuntimeCore::run_radiant_tick);
	ClassDB::bind_method(D_METHOD("evaluate_all_quests"), &InsimulRuntimeCore::evaluate_all_quests);
	ClassDB::bind_method(D_METHOD("commit_to_save"), &InsimulRuntimeCore::commit_to_save);
	ClassDB::bind_method(D_METHOD("serialize_canonical"), &InsimulRuntimeCore::serialize_canonical);
	ClassDB::bind_method(D_METHOD("compute_integrity"), &InsimulRuntimeCore::compute_integrity);
	ClassDB::bind_method(D_METHOD("build_envelope", "insimul_version", "exported_at"),
			&InsimulRuntimeCore::build_envelope);
	ClassDB::bind_method(D_METHOD("world_snapshot_integrity"), &InsimulRuntimeCore::world_snapshot_integrity);
}
