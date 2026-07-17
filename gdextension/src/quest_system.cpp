// quest_system.cpp — QuestSystem implementation. See quest_system.h. Ported from
// packages/core/src/prolog/quest-hydrator.ts (the semantics authority) and the
// Unreal twin InsimulQuestSystem.cpp, validated against the golden quest/radiant
// corpus under packages/core/conformance/quests.

#include "quest_system.h"

#include "canonical_json.h"

#include <algorithm>
#include <cctype>
#include <regex>
#include <string>
#include <vector>

namespace insimul {

namespace {

// ── small string helpers ──────────────────────────────────────────────────

std::string trim(const std::string &s) {
	std::size_t b = 0, e = s.size();
	while (b < e && std::isspace(static_cast<unsigned char>(s[b]))) ++b;
	while (e > b && std::isspace(static_cast<unsigned char>(s[e - 1]))) --e;
	return s.substr(b, e - b);
}

bool is_all_digits(const std::string &s) {
	if (s.empty()) return false;
	for (char c : s) if (!std::isdigit(static_cast<unsigned char>(c))) return false;
	return true;
}

// Leading-integer parse, like JS parseInt (0 if no leading digits).
long long parse_int_prefix(const std::string &s) {
	std::size_t i = 0;
	while (i < s.size() && std::isspace(static_cast<unsigned char>(s[i]))) ++i;
	bool neg = false;
	if (i < s.size() && (s[i] == '+' || s[i] == '-')) { neg = s[i] == '-'; ++i; }
	long long v = 0; bool any = false;
	while (i < s.size() && std::isdigit(static_cast<unsigned char>(s[i]))) {
		v = v * 10 + (s[i] - '0'); ++i; any = true;
	}
	if (!any) return 0;
	return neg ? -v : v;
}

std::string capitalize(const std::string &s) {
	if (s.empty()) return s;
	std::string r = s;
	r[0] = static_cast<char>(std::toupper(static_cast<unsigned char>(r[0])));
	return r;
}

// Unescape Prolog string escapes: \' -> ' and \\ -> \ (matches TS unescape).
std::string unescape(const std::string &s) {
	std::string r;
	r.reserve(s.size());
	for (std::size_t i = 0; i < s.size(); ++i) {
		if (s[i] == '\\' && i + 1 < s.size() && (s[i + 1] == '\'' || s[i + 1] == '\\')) {
			r += s[i + 1]; ++i;
		} else {
			r += s[i];
		}
	}
	return r;
}

std::string replace_all(std::string s, const std::string &from, const std::string &to) {
	if (from.empty()) return s;
	std::size_t pos = 0;
	while ((pos = s.find(from, pos)) != std::string::npos) {
		s.replace(pos, from.size(), to);
		pos += to.size();
	}
	return s;
}

// ── JSON node builders (for the projection) ────────────────────────────────

JsonValuePtr make_string_node(const std::string &s) {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::String;
	v->string_value = s;
	return v;
}

JsonValuePtr make_number_node(double n) {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::Number;
	v->number_value = n;
	// Emit an integral lexeme for whole numbers so raw_number never disagrees
	// with the ECMAScript ToString the canonical serializer produces.
	if (n == static_cast<double>(static_cast<long long>(n))) {
		v->raw_number = std::to_string(static_cast<long long>(n));
	}
	return v;
}

void add_member(JsonValue &obj, const std::string &key, JsonValuePtr val) {
	obj.object_items.emplace_back(key, std::move(val));
}

JsonValuePtr make_string_array(const std::vector<std::string> &items) {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::Array;
	for (const auto &s : items) v->array_items.push_back(make_string_node(s));
	return v;
}

// ── goalToDescription (mirrors quest-hydrator.ts) ──────────────────────────

std::string label_for(const std::string &functor) {
	static const std::vector<std::pair<std::string, std::string>> labels = {
		{"visit_location", "Visit"}, {"discover_location", "Discover"},
		{"talk_to", "Talk to"}, {"collect", "Collect"}, {"defeat", "Defeat"},
		{"deliver", "Deliver to"}, {"use_item", "Use"}, {"craft_item", "Craft"},
		{"escort", "Escort"}, {"solve_puzzle", "Solve"},
		{"gain_reputation", "Gain reputation with"}, {"reach_level", "Reach level"},
		{"give_gift", "Give a gift to"}, {"equip_item", "Equip"}, {"drop_item", "Drop"},
		{"accept_quest", "Accept quest"}, {"read_text", "Read"}, {"find_text", "Find texts"},
		{"photograph", "Photograph"},
	};
	for (const auto &p : labels) if (p.first == functor) return p.second;
	return capitalize(replace_all(functor, "_", " "));
}

std::string goal_to_description(const std::string &functor, const std::vector<std::string> &args) {
	const std::string label = label_for(functor);
	if (args.empty()) return label;
	const std::string main_arg = (args[0] == "any") ? std::string() : (" " + args[0]);
	if (args.size() > 1 && is_all_digits(args[1])) {
		const long long count = parse_int_prefix(args[1]);
		if (count > 1) {
			const std::string n = std::to_string(count);
			if (functor == "collect") return "Collect " + n + " " + args[0];
			if (functor == "defeat") return "Defeat " + n + " " + args[0];
			if (functor == "craft_item") return "Craft " + n + " " + args[0];
			if (functor == "gain_reputation") return "Gain " + n + " reputation with " + args[0];
			if (functor == "photograph") return "Photograph " + n + " " + args[0];
			return label + main_arg + " (" + n + ")";
		}
	}
	return trim(label + main_arg);
}

std::string format_count_description(const std::string &tmpl, long long count) {
	std::string r = replace_all(tmpl, "{n}", std::to_string(count));
	if (count == 1) {
		r = replace_all(r, "(s)", "");
		r = replace_all(r, "(ies)", "y");
	} else {
		r = replace_all(r, "(s)", "s");
		r = replace_all(r, "(ies)", "ies");
	}
	return r;
}

// Lookup tables mirroring parseObjectiveGoal.
const std::vector<std::pair<std::string, std::string>> &two_arg_goals() {
	static const std::vector<std::pair<std::string, std::string>> m = {
		{"collect", "collect_item"}, {"defeat", "defeat_enemies"}, {"craft_item", "craft_item"},
		{"gain_reputation", "gain_reputation"}, {"reach_level", "reach_level"},
		{"photograph", "photograph_subject"}, {"physical_action", "physical_action"},
		{"practice_grammar", "grammar_pattern"},
	};
	return m;
}
const std::vector<std::pair<std::string, std::string>> &single_arg_goals() {
	static const std::vector<std::pair<std::string, std::string>> m = {
		{"visit_location", "visit_location"}, {"discover_location", "discover_location"},
		{"talk_to", "talk_to_npc"}, {"solve_puzzle", "solve_puzzle"}, {"use_item", "use_item"},
		{"equip_item", "equip_item"}, {"drop_item", "drop_item"}, {"give_gift", "give_gift"},
		{"read_text", "read_text"}, {"accept_quest", "accept_quest"}, {"escort", "escort_npc"},
	};
	return m;
}
const std::vector<std::pair<std::string, std::string>> &count_goals() {
	static const std::vector<std::pair<std::string, std::string>> m = {
		{"conversation_turns", "Complete {n} conversation turn(s)"},
		{"examine_object", "Examine {n} object(s)"}, {"read_sign", "Read {n} sign(s)"},
		{"write_response", "Write {n} response(s)"}, {"listen_and_repeat", "Listen and repeat {n} phrase(s)"},
		{"pronunciation_check", "Complete {n} pronunciation check(s)"}, {"identify_object", "Identify {n} object(s)"},
		{"order_food", "Order {n} food item(s)"}, {"haggle_price", "Haggle {n} price(s)"},
		{"buy_item", "Buy {n} item(s)"}, {"sell_item", "Sell {n} item(s)"},
		{"ask_for_directions", "Ask for directions {n} time(s)"}, {"comprehension_quiz", "Answer {n} quiz question(s) correctly"},
		{"translation_challenge", "Complete {n} translation(s) correctly"}, {"follow_directions", "Follow {n} direction(s)"},
		{"listening_comprehension", "Answer {n} listening question(s) correctly"}, {"collect_vocabulary", "Collect {n} vocabulary word(s)"},
		{"collect_clue", "Collect {n} clue(s)"}, {"vocabulary_activities", "Complete {n} vocabulary activit(ies)"},
		{"conversation_activities", "Complete {n} conversation activit(ies)"}, {"grammar_activities", "Demonstrate {n} grammar pattern(s)"},
		{"sustained_conversation", "Sustain a conversation for {n} turn(s)"}, {"master_words", "Master {n} vocabulary word(s)"},
		{"learn_new_words", "Learn {n} new word(s)"}, {"find_vocabulary_items", "Find {n} vocabulary item(s)"},
		{"find_text", "Find {n} text(s)"}, {"combat_action", "Perform {n} combat action(s)"},
		{"observe_activity", "Observe {n} activit(ies)"}, {"build_friendship", "Build friendship (reach {n} strength)"},
		{"learn_words_count", "Learn {n} vocabulary word(s)"}, {"survive", "Survive for {n} second(s)"},
		{"visit_location", "Visit {n} location(s)"},
	};
	return m;
}
bool lookup_map(const std::vector<std::pair<std::string, std::string>> &m,
		const std::string &key, std::string &out) {
	for (const auto &p : m) if (p.first == key) { out = p.second; return true; }
	return false;
}

// Parse a Prolog goal-term's argument list (mirrors parseObjectiveGoal's loop).
std::vector<std::string> parse_goal_args(const std::string &args_str) {
	std::vector<std::string> args;
	std::size_t i = 0;
	const std::size_t n = args_str.size();
	while (i < n) {
		const char c = args_str[i];
		if (c == ' ' || c == ',') { ++i; continue; }
		if (c == '\'') {
			std::string val;
			++i; // skip opening quote
			while (i < n) {
				if (args_str[i] == '\\' && i + 1 < n) { val += args_str[i + 1]; i += 2; }
				else if (args_str[i] == '\'') { ++i; break; }
				else { val += args_str[i]; ++i; }
			}
			args.push_back(val);
		} else if (c == '[') {
			const std::size_t end = args_str.find(']', i);
			if (end == std::string::npos) { args.push_back(args_str.substr(i)); break; }
			args.push_back(args_str.substr(i, end - i + 1));
			i = end + 1;
		} else {
			std::string val;
			while (i < n && args_str[i] != ',' && args_str[i] != ')') { val += args_str[i]; ++i; }
			args.push_back(trim(val));
		}
	}
	return args;
}

// Map a goal term to a structured objective. Returns false for unparseable.
bool parse_objective_goal(const std::string &goal_in, HydratedObjective &out) {
	const std::string goal = trim(goal_in);
	std::smatch m;
	static const std::regex functor_re("^(\\w+)\\(");
	if (!std::regex_search(goal, m, functor_re)) {
		if (goal == "introduce_self") {
			out.type = "introduce_self"; out.description = "Introduce yourself"; out.required_count = 1; return true;
		}
		if (goal == "complete_assessment") {
			out.type = "complete_assessment"; out.description = "Complete the assessment"; out.required_count = 1; return true;
		}
		return false;
	}
	const std::string functor = m[1].str();
	// args_str = goal.slice(functor.length + 1, -1)
	const std::string args_str = trim(goal.substr(functor.size() + 1, goal.size() - functor.size() - 2));
	const std::vector<std::string> args = parse_goal_args(args_str);

	std::string mapped;

	// Two-arg goals: functor(target, count)
	if (lookup_map(two_arg_goals(), functor, mapped) && args.size() >= 2) {
		const long long count = parse_int_prefix(args[1]) ? parse_int_prefix(args[1]) : 1;
		out.type = mapped;
		out.description = goal_to_description(functor, args);
		out.has_target = true; out.target = args[0];
		out.required_count = static_cast<double>(count);
		return true;
	}

	// Single-quoted-arg goals: functor('target')
	if (lookup_map(single_arg_goals(), functor, mapped) && args.size() >= 1) {
		const std::string target = args[0];
		const long long count = args.size() >= 2 ? (parse_int_prefix(args[1]) ? parse_int_prefix(args[1]) : 1) : 1;
		std::string desc = goal_to_description(functor, args);
		if (functor == "talk_to" && count > 1) {
			desc = "Talk to " + target + " (at least " + std::to_string(count) + " turns)";
		}
		out.type = mapped;
		out.description = desc;
		out.has_target = true; out.target = target;
		out.required_count = static_cast<double>(count);
		if (functor == "talk_to") { out.has_npc_id = true; out.npc_id = target; }
		return true;
	}

	// Deliver: deliver(item, npc)
	if (functor == "deliver" && args.size() >= 2) {
		out.type = "deliver_item";
		out.description = "Deliver " + args[0] + " to " + args[1];
		out.has_target = true; out.target = args[1];
		out.required_count = 1;
		return true;
	}

	// Count-only goals: functor(count[, extra])
	if (lookup_map(count_goals(), functor, mapped) && args.size() >= 1) {
		static const std::regex num_re("^\\d+(\\.\\d+)?$");
		if (std::regex_match(args[0], num_re)) {
			const long long count = parse_int_prefix(args[0]);
			out.type = functor;
			out.description = format_count_description(mapped, count);
			out.required_count = static_cast<double>(count);
			return true;
		}
	}

	// objective('description text')
	if (functor == "objective" && args.size() >= 1) {
		out.type = "objective";
		out.description = capitalize(args[0]);
		out.required_count = 1;
		return true;
	}

	// Fallback — human-readable description from the raw goal.
	std::string desc = goal;
	desc = replace_all(desc, "_", " ");
	desc.erase(std::remove(desc.begin(), desc.end(), '\''), desc.end());
	static const std::regex paren_re("\\(.*\\)");
	desc = std::regex_replace(desc, paren_re, "");
	out.type = functor.empty() ? "custom" : functor;
	out.description = capitalize(trim(desc));
	out.required_count = 1;
	return true;
}

// ── scalar fact parsers ────────────────────────────────────────────────────

bool parse_string_fact(const std::string &content, const std::string &predicate, std::string &out) {
	const std::regex re(predicate + "\\(\\s*\\w+\\s*,\\s*'((?:[^'\\\\]|\\\\.)*)'\\s*\\)");
	std::smatch m;
	if (std::regex_search(content, m, re)) { out = unescape(m[1].str()); return true; }
	return false;
}

bool parse_atom_fact(const std::string &content, const std::string &predicate, std::string &out) {
	const std::regex re(predicate + "\\(\\s*\\w+\\s*,\\s*(\\w+)\\s*\\)");
	std::smatch m;
	if (std::regex_search(content, m, re)) { out = m[1].str(); return true; }
	return false;
}

std::vector<std::string> parse_all_atom_facts(const std::string &content, const std::string &predicate) {
	std::vector<std::string> out;
	const std::regex re(predicate + "\\(\\s*\\w+\\s*,\\s*(\\w+)\\s*\\)");
	for (auto it = std::sregex_iterator(content.begin(), content.end(), re);
			it != std::sregex_iterator(); ++it) {
		out.push_back((*it)[1].str());
	}
	return out;
}

} // namespace

// ── HydratedQuest::to_projection ───────────────────────────────────────────

JsonValuePtr HydratedQuest::to_projection() const {
	auto obj = std::make_shared<JsonValue>();
	obj->type = JsonType::Object;
	if (has_title) add_member(*obj, "title", make_string_node(title));
	if (has_quest_type) add_member(*obj, "questType", make_string_node(quest_type));
	if (has_difficulty) add_member(*obj, "difficulty", make_string_node(difficulty));
	if (has_status) add_member(*obj, "status", make_string_node(status));
	if (has_target_language) add_member(*obj, "targetLanguage", make_string_node(target_language));
	if (has_assigned_to) add_member(*obj, "assignedTo", make_string_node(assigned_to));
	if (has_assigned_by) add_member(*obj, "assignedBy", make_string_node(assigned_by));
	if (has_experience) add_member(*obj, "experienceReward", make_number_node(experience_reward));
	if (!tags.empty()) add_member(*obj, "tags", make_string_array(tags));
	if (!prerequisite_quest_ids.empty())
		add_member(*obj, "prerequisiteQuestIds", make_string_array(prerequisite_quest_ids));
	if (has_completion) {
		auto cc = std::make_shared<JsonValue>();
		cc->type = JsonType::Object;
		add_member(*cc, "type", make_string_node(completion_type));
		if (has_completion_description) add_member(*cc, "description", make_string_node(completion_description));
		if (has_completion_turns) add_member(*cc, "requiredTurns", make_number_node(completion_turns));
		add_member(*obj, "completionCriteria", cc);
	}
	if (!objectives.empty()) {
		auto arr = std::make_shared<JsonValue>();
		arr->type = JsonType::Array;
		for (const auto &o : objectives) {
			auto e = std::make_shared<JsonValue>();
			e->type = JsonType::Object;
			add_member(*e, "id", make_string_node(o.id));
			add_member(*e, "type", make_string_node(o.type));
			add_member(*e, "description", make_string_node(o.description));
			add_member(*e, "requiredCount", make_number_node(o.required_count));
			if (o.has_target) add_member(*e, "target", make_string_node(o.target));
			if (o.has_npc_id) add_member(*e, "npcId", make_string_node(o.npc_id));
			arr->array_items.push_back(e);
		}
		add_member(*obj, "objectives", arr);
	}
	return obj;
}

// ── hydrate_from_content ───────────────────────────────────────────────────

HydratedQuest QuestSystem::hydrate_from_content(const std::string &content,
		const std::string &input_status) {
	HydratedQuest q;

	// Quest id (head atom of the first quest/N term).
	{
		static const std::regex id_re("quest\\(\\s*(\\w+)");
		std::smatch m;
		if (std::regex_search(content, m, id_re)) q.id = m[1].str();
	}

	// quest/5 main fact: quest(id, 'title', type, difficulty, status)
	std::string main_status;
	bool has_main = false;
	{
		static const std::regex quest_re(
			"quest\\(\\s*\\w+\\s*,\\s*'((?:[^'\\\\]|\\\\.)*)'\\s*,\\s*(\\w+)\\s*,\\s*(\\w+)\\s*,\\s*(\\w+)\\s*\\)");
		std::smatch m;
		if (std::regex_search(content, m, quest_re)) {
			has_main = true;
			q.has_title = true; q.title = unescape(m[1].str());
			q.has_quest_type = true; q.quest_type = m[2].str();
			q.has_difficulty = true; q.difficulty = m[3].str();
			main_status = m[4].str();
		}
	}

	// Prerequisites (excludes 'none').
	std::vector<std::string> prereqs;
	{
		static const std::regex prereq_re("quest_prerequisite\\(\\s*\\w+\\s*,\\s*(\\w+)\\s*\\)");
		for (auto it = std::sregex_iterator(content.begin(), content.end(), prereq_re);
				it != std::sregex_iterator(); ++it) {
			const std::string p = (*it)[1].str();
			if (p != "none") prereqs.push_back(p);
		}
	}

	// Status resolution (mirrors the hydrator's availability rule).
	if (has_main) {
		if (input_status.empty()) {
			q.has_status = true; q.status = main_status;
		} else if (input_status == "unavailable" && main_status == "available") {
			q.has_status = true;
			q.status = prereqs.empty() ? "available" : input_status;
		} else {
			q.has_status = true; q.status = input_status;
		}
	} else if (!input_status.empty()) {
		q.has_status = true; q.status = input_status;
	}

	// Objectives: quest_objective(id, Index, Goal).
	{
		static const std::regex obj_re("quest_objective\\(\\s*\\w+\\s*,\\s*(\\d+)\\s*,\\s*(.*)\\)\\s*\\.");
		for (auto it = std::sregex_iterator(content.begin(), content.end(), obj_re);
				it != std::sregex_iterator(); ++it) {
			const std::smatch &m = *it;
			const long long index = parse_int_prefix(m[1].str());
			HydratedObjective o;
			if (parse_objective_goal(trim(m[2].str()), o)) {
				o.id = "obj_" + std::to_string(index);
				q.objectives.push_back(o);
			}
		}
	}

	// Scalars.
	std::string s;
	if (parse_string_fact(content, "quest_assigned_to", s)) { q.has_assigned_to = true; q.assigned_to = s; }
	if (parse_string_fact(content, "quest_assigned_by", s)) { q.has_assigned_by = true; q.assigned_by = s; }
	if (parse_atom_fact(content, "quest_language", s)) { q.has_target_language = true; q.target_language = s; }

	// Rewards: quest_reward(id, key, N) — experience is promoted to a scalar.
	{
		static const std::regex reward_re("quest_reward\\(\\s*\\w+\\s*,\\s*(\\w+)\\s*,\\s*(\\d+(?:\\.\\d+)?)\\s*\\)");
		for (auto it = std::sregex_iterator(content.begin(), content.end(), reward_re);
				it != std::sregex_iterator(); ++it) {
			if ((*it)[1].str() == "experience") {
				q.has_experience = true;
				q.experience_reward = std::stod((*it)[2].str());
			}
		}
	}

	// Tags.
	q.tags = parse_all_atom_facts(content, "quest_tag");

	// Prerequisites projection (only when real prereqs present).
	if (!prereqs.empty()) q.prerequisite_quest_ids = prereqs;

	// Completion criteria: quest_completion(id, Goal).
	{
		static const std::regex comp_re("quest_completion\\(\\s*\\w+\\s*,\\s*(.*?)\\)\\s*\\.");
		std::smatch m;
		if (std::regex_search(content, m, comp_re)) {
			const std::string goal = trim(m[1].str());
			static const std::regex conv_re("^conversation_turns\\(\\s*(\\d+)\\s*\\)$");
			std::smatch cm;
			if (goal == "all_objectives_complete") {
				q.has_completion = true; q.completion_type = "all_objectives";
				q.has_completion_description = true; q.completion_description = "Complete all objectives";
			} else if (std::regex_match(goal, cm, conv_re)) {
				q.has_completion = true; q.completion_type = "conversation_turns";
				q.has_completion_turns = true; q.completion_turns = static_cast<double>(parse_int_prefix(cm[1].str()));
			} else {
				// vocabulary_* and unknown goals default to all-objectives (as TS does).
				q.has_completion = true; q.completion_type = "all_objectives";
				q.has_completion_description = true; q.completion_description = "Complete all objectives";
			}
		}
	}

	return q;
}

std::string QuestSystem::hydrate_canonical(const std::string &content,
		const std::string &input_status) {
	const HydratedQuest q = hydrate_from_content(content, input_status);
	return canonical_json_stringify(*q.to_projection());
}

// ── QuestKB ────────────────────────────────────────────────────────────────

void QuestKB::assert_fact(const PrologFact &fact) {
	for (const auto &f : facts_) if (f == fact) return;
	facts_.push_back(fact);
}

bool QuestKB::has(const std::string &predicate, const std::vector<PrologArg> &args) const {
	for (const auto &f : facts_) {
		if (f.predicate == predicate && f.args == args) return true;
	}
	return false;
}

// ── Query-driven completion + fact-asserting transitions ───────────────────

bool QuestSystem::is_objective_satisfied(const HydratedQuest &quest, std::size_t index,
		const QuestKB &kb) {
	if (index >= quest.objectives.size()) return false;
	const HydratedObjective &o = quest.objectives[index];

	// Explicit satisfaction fact.
	if (kb.has("objective_satisfied", {PrologArg::atom(quest.id), PrologArg::atom(o.id)}))
		return true;

	// Type-specific trigger facts (player is the acting subject).
	if (o.has_target) {
		const std::vector<PrologArg> player_target = {
			PrologArg::atom("player"), PrologArg::atom(o.target)};
		if (o.type == "talk_to_npc" && kb.has("talked_to", player_target)) return true;
		if (o.type == "visit_location" && kb.has("visited", player_target)) return true;
		if (o.type == "deliver_item" && kb.has("delivered", player_target)) return true;
	}
	return false;
}

QuestTransition QuestSystem::evaluate_quest(HydratedQuest &quest, QuestKB &kb) {
	QuestTransition result;
	result.quest_id = quest.id;

	bool all_satisfied = !quest.objectives.empty();
	for (std::size_t i = 0; i < quest.objectives.size(); ++i) {
		if (is_objective_satisfied(quest, i, kb)) {
			const HydratedObjective &o = quest.objectives[i];
			PrologFact done;
			done.predicate = "quest_objective_complete";
			done.args = {PrologArg::atom(quest.id), PrologArg::atom(o.id)};
			kb.assert_fact(done);
			result.satisfied_objective_ids.push_back(o.id);
		} else {
			all_satisfied = false;
		}
	}

	// Completion criterion: all-objectives (the default). conversation_turns is a
	// runtime-metered criterion, not auto-satisfied by objective facts here.
	const bool all_objectives_criterion =
		!quest.has_completion || quest.completion_type == "all_objectives";
	if (all_satisfied && all_objectives_criterion) {
		PrologFact complete;
		complete.predicate = "quest_complete";
		complete.args = {PrologArg::atom(quest.id)};
		kb.assert_fact(complete);
		quest.has_status = true;
		quest.status = "completed";
		result.completed = true;
	}
	return result;
}

// ── Radiant tick ───────────────────────────────────────────────────────────

std::vector<PrologFact> QuestSystem::radiant_tick(const std::vector<RadiantQuest> &quests,
		int max_offering, int ticks) {
	std::vector<PrologFact> facts;
	std::vector<std::string> offered;
	auto was_offered = [&offered](const std::string &id) {
		return std::find(offered.begin(), offered.end(), id) != offered.end();
	};
	for (int t = 0; t < ticks; ++t) {
		std::vector<std::string> candidates;
		for (const auto &q : quests) {
			const bool radiant = std::find(q.tags.begin(), q.tags.end(), "radiant") != q.tags.end();
			if (radiant && q.status == "available" && !was_offered(q.id)) {
				candidates.push_back(q.id);
			}
		}
		std::sort(candidates.begin(), candidates.end());
		const int limit = max_offering > 0 ? max_offering : 0;
		for (int i = 0; i < static_cast<int>(candidates.size()) && i < limit; ++i) {
			offered.push_back(candidates[i]);
			PrologFact f;
			f.predicate = "quest_offered";
			f.args = {PrologArg::atom(candidates[i]), PrologArg::number(static_cast<double>(t))};
			facts.push_back(f);
		}
	}
	return facts;
}

std::string QuestSystem::canonical_fact_string(const PrologFact &fact) {
	std::string s = fact.predicate + "(";
	for (std::size_t i = 0; i < fact.args.size(); ++i) {
		if (i > 0) s += ",";
		const PrologArg &a = fact.args[i];
		if (a.is_number) {
			s += canonical_number(a.num, std::string());
		} else {
			s += a.str;
		}
	}
	s += ")";
	return s;
}

std::string QuestSystem::canonical_fact_list(const std::vector<PrologFact> &facts) {
	std::vector<std::string> lines;
	lines.reserve(facts.size());
	for (const auto &f : facts) lines.push_back(canonical_fact_string(f));
	std::sort(lines.begin(), lines.end());
	std::string out;
	for (std::size_t i = 0; i < lines.size(); ++i) {
		if (i > 0) out += "\n";
		out += lines[i];
	}
	return out;
}

} // namespace insimul
