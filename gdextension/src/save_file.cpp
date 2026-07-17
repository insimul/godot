// save_file.cpp — faithful port of InsimulSaveSystem.cpp (the semantics
// authority is packages/core/src/{save-file,save-envelope,save-file-migrations}.ts).

#include "save_file.h"

#include "canonical_json.h"

#include <utility>

namespace insimul {
namespace {

// ── JSON node factories (mutable building) ──────────────────────────────────

JsonValuePtr make_object() {
	auto node = std::make_shared<JsonValue>();
	node->type = JsonType::Object;
	return node;
}

JsonValuePtr make_array() {
	auto node = std::make_shared<JsonValue>();
	node->type = JsonType::Array;
	return node;
}

JsonValuePtr make_string(const std::string &s) {
	auto node = std::make_shared<JsonValue>();
	node->type = JsonType::String;
	node->string_value = s;
	return node;
}

JsonValuePtr make_null() {
	auto node = std::make_shared<JsonValue>();
	node->type = JsonType::Null;
	return node;
}

JsonValuePtr make_int(long long n) {
	auto node = std::make_shared<JsonValue>();
	node->type = JsonType::Number;
	node->number_value = static_cast<double>(n);
	node->raw_number = std::to_string(n);
	return node;
}

JsonValuePtr make_number(double n) {
	auto node = std::make_shared<JsonValue>();
	node->type = JsonType::Number;
	node->number_value = n;
	return node;
}

// ── Mutable object member access ────────────────────────────────────────────

JsonValue *obj_find(JsonValue &obj, const std::string &key) {
	for (auto &pair : obj.object_items) {
		if (pair.first == key) {
			return pair.second.get();
		}
	}
	return nullptr;
}

void obj_set(JsonValue &obj, const std::string &key, JsonValuePtr value) {
	for (auto &pair : obj.object_items) {
		if (pair.first == key) {
			pair.second = std::move(value);
			return;
		}
	}
	obj.object_items.emplace_back(key, std::move(value));
}

// Ensure `key` exists on `obj`; if absent, insert `fallback` and return it.
JsonValue *obj_ensure(JsonValue &obj, const std::string &key, JsonValuePtr fallback) {
	if (JsonValue *existing = obj_find(obj, key)) {
		return existing;
	}
	JsonValue *raw = fallback.get();
	obj.object_items.emplace_back(key, std::move(fallback));
	return raw;
}

JsonValuePtr make_empty_srs_state() {
	// createEmptySrsState() in packages/core/src/language/spaced-repetition.ts.
	auto node = make_object();
	obj_set(*node, "items", make_object());
	obj_set(*node, "currentSession", make_int(0));
	obj_set(*node, "lastUpdated", make_int(0));
	return node;
}

// migrateLanguageProgress() in packages/core/src/save-file.ts: backfill the
// proficiency fields so every field is present. Augments in place (idempotent).
void migrate_language_progress(JsonValue &state) {
	JsonValue *lp = obj_find(state, "languageProgress");
	if (!lp || !lp->is_object()) {
		JsonValuePtr fresh = make_object();
		obj_set(state, "languageProgress", fresh);
		lp = obj_find(state, "languageProgress");
	}
	obj_ensure(*lp, "vocabulary", make_array());
	obj_ensure(*lp, "grammarPatterns", make_array());
	obj_ensure(*lp, "totalXP", make_int(0));
	obj_ensure(*lp, "level", make_int(1));
	obj_ensure(*lp, "arrivalAssessment", make_null());
	obj_ensure(*lp, "proficiencyHistory", make_array());
	obj_ensure(*lp, "srsState", make_empty_srs_state());
	obj_ensure(*lp, "weakAreaHistory", make_array());
}

// Backfill WorldSnapshot version stamps on saves predating US-001.
void backfill_snapshot_versioning(JsonValue &snapshot) {
	auto ensure_string = [&](const char *key) {
		JsonValue *member = obj_find(snapshot, key);
		if (!member || !member->is_string()) {
			obj_set(snapshot, key, make_string("pre-versioning"));
		}
	};
	ensure_string("insimulVersion");
	ensure_string("engineRevision");
	ensure_string("snapshotCreatedAt");
}

JsonValuePtr build_default_vec3() {
	auto v = make_object();
	obj_set(*v, "x", make_int(0));
	obj_set(*v, "y", make_int(0));
	obj_set(*v, "z", make_int(0));
	return v;
}

JsonValuePtr build_default_current_state() {
	auto state = make_object();

	auto player = make_object();
	obj_set(*player, "position", build_default_vec3());
	obj_set(*player, "rotation", build_default_vec3());
	obj_set(*player, "gold", make_int(0));
	obj_set(*player, "health", make_int(100));
	obj_set(*player, "energy", make_int(100));
	obj_set(*player, "inventory", make_array());
	obj_set(*player, "cefrLevel", make_null());
	obj_set(*player, "effectiveFluency", make_null());
	obj_set(*state, "player", player);

	auto quests = make_object();
	obj_set(*quests, "progress", make_object());
	obj_set(*quests, "dynamicQuests", make_array());
	obj_set(*state, "quests", quests);

	auto npcs = make_object();
	obj_set(*npcs, "relationships", make_object());
	obj_set(*npcs, "romance", make_object());
	obj_set(*npcs, "merchantStates", make_object());
	obj_set(*state, "npcs", npcs);

	obj_set(*state, "characterRelationships", make_object());

	auto reputation = make_object();
	obj_set(*reputation, "settlements", make_object());
	obj_set(*state, "reputation", reputation);

	auto containers = make_object();
	obj_set(*containers, "containers", make_object());
	obj_set(*state, "containers", containers);

	// Full (current-version) languageProgress defaults.
	auto lp = make_object();
	obj_set(*state, "languageProgress", lp);
	migrate_language_progress(*state);

	obj_set(*state, "prologFacts", make_array());
	obj_set(*state, "timeState", make_null());
	obj_set(*state, "interiorState", make_null());
	obj_set(*state, "extensions", make_object());
	return state;
}

} // namespace

// ── Public API ──────────────────────────────────────────────────────────────

bool SaveSystem::load(const std::string &json, std::string &out_error) {
	root_.reset();
	loaded_version_ = 0;

	JsonParseResult parsed = parse_json(json);
	if (!parsed.ok || !parsed.root || !parsed.root->is_object()) {
		out_error = parsed.ok ? "SaveFile root is not a JSON object" : parsed.error;
		return false;
	}

	const JsonValue *version_node = parsed.root->find("version");
	const int file_version = version_node ? static_cast<int>(version_node->as_int(1)) : 1;
	if (file_version < 1) {
		out_error = "SaveFile version " + std::to_string(file_version) + " is below the minimum (1).";
		return false;
	}
	if (file_version > SAVE_FILE_VERSION) {
		out_error = "SaveFile version " + std::to_string(file_version) +
			" was produced by a newer build (max supported " + std::to_string(SAVE_FILE_VERSION) +
			"). Please update the game.";
		return false;
	}

	root_ = parsed.root;
	loaded_version_ = file_version;
	migrate_to_current();
	return true;
}

bool SaveSystem::new_game(
		const std::string &world_snapshot_json, const NewGameOptions &options, std::string &out_error) {
	root_.reset();
	loaded_version_ = 0;

	JsonParseResult parsed = parse_json(world_snapshot_json);
	if (!parsed.ok || !parsed.root || !parsed.root->is_object()) {
		out_error = parsed.ok ? "worldSnapshot root is not a JSON object" : parsed.error;
		return false;
	}

	// Accept either a bare snapshot or a document wrapping it under worldSnapshot.
	JsonValuePtr snapshot = parsed.root;
	if (const JsonValue *wrapped = parsed.root->find("worldSnapshot")) {
		if (wrapped->is_object()) {
			for (const auto &pair : parsed.root->object_items) {
				if (pair.first == "worldSnapshot") {
					snapshot = pair.second;
					break;
				}
			}
		}
	}
	if (!snapshot->find("world")) {
		out_error = "worldSnapshot is missing a world object";
		return false;
	}

	auto save = make_object();
	obj_set(*save, "id", make_string(options.id));
	obj_set(*save, "slotIndex", make_int(options.slot_index));
	obj_set(*save, "userId", make_string(options.user_id));
	obj_set(*save, "worldId", make_string(options.world_id));
	obj_set(*save, "name", make_string(options.name));
	obj_set(*save, "version", make_int(SAVE_FILE_VERSION));
	obj_set(*save, "status", make_string("active"));
	obj_set(*save, "createdAt", make_string(options.created_at));
	obj_set(*save, "lastSavedAt", make_string(options.created_at));
	obj_set(*save, "totalPlaytime", make_int(0));
	obj_set(*save, "saveCount", make_int(0));
	obj_set(*save, "worldSnapshot", snapshot);
	obj_set(*save, "currentState", build_default_current_state());
	obj_set(*save, "conversations", make_array());

	root_ = save;
	loaded_version_ = SAVE_FILE_VERSION;
	return true;
}

void SaveSystem::migrate_to_current() {
	if (!root_) {
		return;
	}
	int version = loaded_version_;

	// v1 -> v2: backfill LanguageProgressState proficiency fields.
	if (version < 2) {
		if (JsonValue *state = obj_find(*root_, "currentState")) {
			if (state->is_object()) {
				migrate_language_progress(*state);
			}
		}
		version = 2;
	}

	// v2 -> v3: backfill WorldSnapshot version stamps.
	if (version < 3) {
		if (JsonValue *snapshot = obj_find(*root_, "worldSnapshot")) {
			if (snapshot->is_object()) {
				backfill_snapshot_versioning(*snapshot);
			}
		}
		version = 3;
	}

	obj_set(*root_, "version", make_int(version));
	loaded_version_ = version;
}

std::string SaveSystem::serialize_canonical() const {
	if (!root_) {
		return "null";
	}
	return canonical_json_stringify(*root_);
}

std::string SaveSystem::compute_integrity() const {
	if (!root_) {
		return canonical_json_integrity(*make_null());
	}
	return canonical_json_integrity(*root_);
}

std::string SaveSystem::world_snapshot_integrity() const {
	if (!root_) {
		return std::string();
	}
	const JsonValue *snapshot = root_->find("worldSnapshot");
	if (!snapshot) {
		return std::string();
	}
	return canonical_json_integrity(*snapshot);
}

std::string SaveSystem::build_envelope_json(
		const std::string &insimul_version, const std::string &exported_at) const {
	auto envelope = make_object();
	obj_set(*envelope, "format", make_string(save_envelope_format()));
	obj_set(*envelope, "exportedAt", make_string(exported_at));
	obj_set(*envelope, "insimulVersion", make_string(insimul_version));
	obj_set(*envelope, "saveFile", root_ ? root_ : make_null());
	obj_set(*envelope, "integrity", make_string(compute_integrity()));
	return canonical_json_stringify(*envelope);
}

void SaveSystem::snapshot_facts(const std::vector<PrologFact> &facts) {
	if (!root_) {
		return;
	}
	JsonValue *state = obj_find(*root_, "currentState");
	if (!state || !state->is_object()) {
		obj_set(*root_, "currentState", make_object());
		state = obj_find(*root_, "currentState");
	}

	auto facts_array = make_array();
	for (const PrologFact &fact : facts) {
		auto fact_node = make_object();
		obj_set(*fact_node, "predicate", make_string(fact.predicate));
		auto args_array = make_array();
		for (const PrologArg &arg : fact.args) {
			args_array->array_items.push_back(arg.is_number ? make_number(arg.num) : make_string(arg.str));
		}
		obj_set(*fact_node, "args", args_array);
		facts_array->array_items.push_back(fact_node);
	}
	obj_set(*state, "prologFacts", facts_array);
}

std::vector<PrologFact> SaveSystem::restore_facts() const {
	std::vector<PrologFact> out;
	if (!root_) {
		return out;
	}
	const JsonValue *state = root_->find("currentState");
	if (!state) {
		return out;
	}
	const JsonValue *facts_array = state->find("prologFacts");
	if (!facts_array || !facts_array->is_array()) {
		return out;
	}
	for (const JsonValuePtr &item : facts_array->array_items) {
		if (!item || !item->is_object()) {
			continue;
		}
		PrologFact fact;
		fact.predicate = item->get_string("predicate");
		if (const JsonValue *args = item->find("args")) {
			for (const JsonValuePtr &arg_node : args->array_items) {
				if (!arg_node) {
					continue;
				}
				if (arg_node->is_number()) {
					fact.args.push_back(PrologArg::number(arg_node->number_value));
				} else {
					fact.args.push_back(PrologArg::atom(arg_node->as_string()));
				}
			}
		}
		out.push_back(std::move(fact));
	}
	return out;
}

} // namespace insimul
