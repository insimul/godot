// insimul_quest_core.cpp — Godot-facing quest core implementation.
//
// Syntax-gated only (needs godot-cpp). All non-trivial logic is delegated to the
// host-tested core (quest_system.cpp); this file only marshals String<->std::string
// and Array/Dictionary<->the core structs.

#include "insimul_quest_core.h"

#include <godot_cpp/core/class_db.hpp>

#include <string>
#include <vector>

using namespace godot;

namespace {

std::string to_std(const String &s) {
	return std::string(s.utf8().get_data());
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

String InsimulQuestCore::hydrate_canonical(const String &content, const String &status) const {
	return String(insimul::QuestSystem::hydrate_canonical(to_std(content), to_std(status)).c_str());
}

Array InsimulQuestCore::radiant_tick(const Array &quests, int max_offering, int ticks) const {
	std::vector<insimul::RadiantQuest> in;
	for (int i = 0; i < quests.size(); ++i) {
		const Dictionary q = quests[i];
		insimul::RadiantQuest rq;
		rq.id = to_std(String(q.get("id", String())));
		rq.status = to_std(String(q.get("status", String())));
		const Array tags = q.get("tags", Array());
		for (int j = 0; j < tags.size(); ++j) {
			rq.tags.push_back(to_std(String(tags[j])));
		}
		in.push_back(rq);
	}

	Array out;
	for (const insimul::PrologFact &f : insimul::QuestSystem::radiant_tick(in, max_offering, ticks)) {
		out.push_back(fact_to_dict(f));
	}
	return out;
}

Dictionary InsimulQuestCore::evaluate_quest(const String &content, const String &status, const Array &facts) const {
	insimul::HydratedQuest quest = insimul::QuestSystem::hydrate_from_content(to_std(content), to_std(status));

	insimul::QuestKB kb;
	std::vector<insimul::PrologFact> loaded;
	for (int i = 0; i < facts.size(); ++i) {
		loaded.push_back(fact_from_dict(facts[i]));
	}
	kb.load(loaded);

	const insimul::QuestTransition transition = insimul::QuestSystem::evaluate_quest(quest, kb);

	Dictionary result;
	result["quest_id"] = String(transition.quest_id.c_str());
	result["completed"] = transition.completed;
	result["status"] = String(quest.status.c_str());
	Array satisfied;
	for (const std::string &id : transition.satisfied_objective_ids) {
		satisfied.push_back(String(id.c_str()));
	}
	result["satisfied_objective_ids"] = satisfied;
	Array out_facts;
	for (const insimul::PrologFact &f : kb.facts()) {
		out_facts.push_back(fact_to_dict(f));
	}
	result["facts"] = out_facts;
	return result;
}

void InsimulQuestCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("hydrate_canonical", "content", "status"),
			&InsimulQuestCore::hydrate_canonical);
	ClassDB::bind_method(D_METHOD("radiant_tick", "quests", "max_offering", "ticks"),
			&InsimulQuestCore::radiant_tick);
	ClassDB::bind_method(D_METHOD("evaluate_quest", "content", "status", "facts"),
			&InsimulQuestCore::evaluate_quest);
}
