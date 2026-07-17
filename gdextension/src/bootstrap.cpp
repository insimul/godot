// bootstrap.cpp — RuntimeContext implementation. See bootstrap.h. Ported from the
// Unreal twin InsimulBootstrap.cpp (US-XC4); drives the same full loop over the
// Godot save + quest cores and the shared golden fixtures.

#include "bootstrap.h"

#include <algorithm>

namespace insimul {

bool RuntimeContext::start_new_game(const std::string &world_snapshot_json,
		const NewGameOptions &options, std::string &out_error) {
	loaded_ = false;
	if (!save_sys_.new_game(world_snapshot_json, options, out_error)) {
		return false;
	}
	return rehydrate(out_error);
}

bool RuntimeContext::load_from_save(const std::string &save_json, std::string &out_error) {
	loaded_ = false;
	if (!save_sys_.load(save_json, out_error)) {
		return false;
	}
	return rehydrate(out_error);
}

BootResult RuntimeContext::boot(const std::string &existing_save_json,
		const std::string &fallback_world_snapshot_json, const NewGameOptions &options) {
	BootResult result;

	// Prefer resuming a present, valid save slot.
	if (!existing_save_json.empty()) {
		std::string load_error;
		if (load_from_save(existing_save_json, load_error)) {
			result.ok = true;
			result.resumed_save = true;
			return result;
		}
		// A corrupt/incompatible slot must not brick startup — fall through to a
		// new game rather than aborting the boot.
	}

	std::string new_game_error;
	if (start_new_game(fallback_world_snapshot_json, options, new_game_error)) {
		result.ok = true;
		result.resumed_save = false;
		return result;
	}

	result.ok = false;
	result.error = new_game_error;
	return result;
}

bool RuntimeContext::rehydrate(std::string &out_error) {
	(void)out_error; // no failure path once the save is loaded/created

	// Restore the KB from currentState.prologFacts (empty on a fresh new game).
	kb_.load(save_sys_.restore_facts());

	// Systems init: hydrate every world quest's Prolog content. The quest's
	// `content` is the single source of truth (see quest-hydrator.ts); a quest with
	// empty content hydrates to a no-op shell keyed by its worldSnapshot id.
	hydrated_quests_.clear();
	const JsonValue *snapshot = world_snapshot();
	if (snapshot != nullptr) {
		const JsonValue *quests = snapshot->find("quests");
		if (quests != nullptr && quests->is_array()) {
			for (const JsonValuePtr &q : quests->array_items) {
				if (q == nullptr || !q->is_object()) {
					continue;
				}
				const std::string id = q->get_string("id");
				const std::string status = q->get_string("status");
				const std::string content = q->get_string("content");
				HydratedQuest h = content.empty()
						? HydratedQuest{}
						: QuestSystem::hydrate_from_content(content, status);
				if (h.id.empty()) {
					h.id = id; // fall back to the world-source id when content carries none
				}
				hydrated_quests_.push_back(std::move(h));
			}
		}
	}

	loaded_ = true;
	return true;
}

void RuntimeContext::commit_to_save() {
	save_sys_.snapshot_facts(kb_.facts());
}

std::vector<QuestTransition> RuntimeContext::evaluate_all_quests() {
	std::vector<QuestTransition> transitions;
	transitions.reserve(hydrated_quests_.size());
	for (HydratedQuest &q : hydrated_quests_) {
		if (q.objectives.empty()) {
			continue; // nothing query-driven to evaluate (e.g. no-op content)
		}
		transitions.push_back(QuestSystem::evaluate_quest(q, kb_));
	}
	return transitions;
}

std::vector<PrologFact> RuntimeContext::run_radiant_tick(int max_offering, int ticks) {
	std::vector<RadiantQuest> radiants;
	const JsonValue *snapshot = world_snapshot();
	if (snapshot != nullptr) {
		const JsonValue *quests = snapshot->find("quests");
		if (quests != nullptr && quests->is_array()) {
			for (const JsonValuePtr &q : quests->array_items) {
				if (q == nullptr || !q->is_object()) {
					continue;
				}
				const std::string content = q->get_string("content");
				// Cheap pre-filter: only quests whose content mentions the tag at all.
				if (content.find("radiant") == std::string::npos) {
					continue;
				}
				const std::string status = q->get_string("status");
				const HydratedQuest h = QuestSystem::hydrate_from_content(content, status);
				const bool is_radiant =
						std::find(h.tags.begin(), h.tags.end(), "radiant") != h.tags.end();
				if (!is_radiant) {
					continue;
				}
				RadiantQuest rq;
				rq.id = h.id.empty() ? q->get_string("id") : h.id;
				rq.tags = h.tags;
				rq.status = h.has_status ? h.status : status;
				radiants.push_back(std::move(rq));
			}
		}
	}

	const std::vector<PrologFact> offered = QuestSystem::radiant_tick(radiants, max_offering, ticks);
	for (const PrologFact &f : offered) {
		kb_.assert_fact(f);
	}
	return offered;
}

const JsonValue *RuntimeContext::world_snapshot() const {
	const JsonValue *save = save_sys_.save_file();
	if (save == nullptr) {
		return nullptr;
	}
	return save->find("worldSnapshot");
}

int RuntimeContext::world_array_size(const std::string &key) const {
	const JsonValue *snapshot = world_snapshot();
	if (snapshot == nullptr) {
		return 0;
	}
	const JsonValue *arr = snapshot->find(key);
	if (arr == nullptr || !arr->is_array()) {
		return 0;
	}
	return static_cast<int>(arr->array_items.size());
}

std::string RuntimeContext::world_id() const {
	const JsonValue *snapshot = world_snapshot();
	if (snapshot == nullptr) {
		return std::string();
	}
	const JsonValue *world = snapshot->find("world");
	if (world == nullptr || !world->is_object()) {
		return std::string();
	}
	return world->get_string("id");
}

std::string RuntimeContext::spawn_character_id(int index) const {
	const JsonValue *snapshot = world_snapshot();
	if (snapshot == nullptr || index < 0) {
		return std::string();
	}
	const JsonValue *chars = snapshot->find("characters");
	if (chars == nullptr || !chars->is_array() ||
			static_cast<std::size_t>(index) >= chars->array_items.size()) {
		return std::string();
	}
	const JsonValuePtr &c = chars->array_items[static_cast<std::size_t>(index)];
	if (c == nullptr || !c->is_object()) {
		return std::string();
	}
	return c->get_string("id");
}

std::string RuntimeContext::world_snapshot_integrity() const {
	// One implementation, host-tested here and reused by the save codec.
	return save_sys_.world_snapshot_integrity();
}

} // namespace insimul
