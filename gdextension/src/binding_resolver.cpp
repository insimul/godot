// binding_resolver.cpp — implementation of the Asset Binding Layer resolution
// core (US-GB1). std-only; see binding_resolver.h for the contract.

#include "binding_resolver.h"

#include "canonical_json.h"

#include <algorithm>

namespace insimul {

namespace {

// Count dot-separated segments in a non-empty key ("a.b.c" -> 3, "a" -> 1).
int segment_count(const std::string &key) {
	if (key.empty()) {
		return 0;
	}
	int n = 1;
	for (char c : key) {
		if (c == '.') {
			n++;
		}
	}
	return n;
}

JsonValuePtr make_string(const std::string &s) {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::String;
	v->string_value = s;
	return v;
}

JsonValuePtr make_int(long long n) {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::Number;
	v->raw_number = std::to_string(n);
	v->number_value = static_cast<double>(n);
	return v;
}

} // namespace

int MatchScore::compare(const MatchScore &a, const MatchScore &b) {
	if (a.matched_segments != b.matched_segments) {
		return a.matched_segments < b.matched_segments ? -1 : 1;
	}
	int ak = static_cast<int>(a.kind);
	int bk = static_cast<int>(b.kind);
	if (ak != bk) {
		return ak < bk ? -1 : 1;
	}
	return 0;
}

MatchScore match_archetype(const std::string &entry_key, const std::string &query) {
	MatchScore score;
	if (entry_key.empty() || query.empty()) {
		return score;
	}
	// Match-all wildcard.
	if (entry_key == "*") {
		score.kind = MatchKind::Wildcard;
		score.matched_segments = 0;
		return score;
	}
	// Prefix wildcard: "prefix.*" matches the prefix itself and any descendant.
	if (entry_key.size() >= 2 && entry_key.compare(entry_key.size() - 2, 2, ".*") == 0) {
		std::string prefix = entry_key.substr(0, entry_key.size() - 2);
		if (prefix.empty()) {
			return score;
		}
		if (query == prefix ||
				(query.size() > prefix.size() &&
						query.compare(0, prefix.size(), prefix) == 0 &&
						query[prefix.size()] == '.')) {
			score.kind = MatchKind::Wildcard;
			score.matched_segments = segment_count(prefix);
		}
		return score;
	}
	// Exact.
	if (query == entry_key) {
		score.kind = MatchKind::Exact;
		score.matched_segments = segment_count(entry_key);
		return score;
	}
	// Descendant: query starts with entry_key + '.'.
	if (query.size() > entry_key.size() &&
			query.compare(0, entry_key.size(), entry_key) == 0 &&
			query[entry_key.size()] == '.') {
		score.kind = MatchKind::Descendant;
		score.matched_segments = segment_count(entry_key);
	}
	return score;
}

void BindingResolver::add_source(BindingSource source) {
	sources_.push_back(std::move(source));
}

void BindingResolver::sort_sources_by_priority() {
	std::stable_sort(sources_.begin(), sources_.end(),
			[](const BindingSource &a, const BindingSource &b) {
				return a.priority > b.priority;
			});
}

ResolveResult BindingResolver::resolve(const std::string &query) const {
	// Fallback chain: the first source (in current order) with any match wins;
	// within it the most specific entry is chosen. Call
	// sort_sources_by_priority() first to make that project -> packs ->
	// placeholder.
	for (const auto &source : sources_) {
		const BindingEntry *best = nullptr;
		MatchScore best_score;
		for (const auto &entry : source.entries) {
			MatchScore s = match_archetype(entry.key, query);
			if (!s.matched()) {
				continue;
			}
			if (best == nullptr || MatchScore::compare(s, best_score) > 0) {
				best = &entry;
				best_score = s;
			}
			// Ties keep the earlier declared entry (stable): compare() == 0 does
			// not replace.
		}
		if (best != nullptr) {
			ResolveResult r;
			r.resolved = true;
			r.source_name = source.name;
			r.key = best->key;
			r.entry = best;
			return r;
		}
	}
	return ResolveResult{};
}

bool parse_binding_source(const JsonValue &obj, BindingSource &out, std::string &error) {
	if (!obj.is_object()) {
		error = "binding source is not an object";
		return false;
	}
	out = BindingSource{};
	out.name = obj.get_string("name");
	out.priority = obj.get_int("priority", 0);

	const JsonValue *entries = obj.find("entries");
	if (entries == nullptr || !entries->is_array()) {
		error = "binding source '" + out.name + "' has no entries array";
		return false;
	}
	for (const auto &item : entries->array_items) {
		if (item == nullptr || !item->is_object()) {
			error = "binding entry is not an object";
			return false;
		}
		BindingEntry entry;
		entry.key = item->get_string("key");
		if (entry.key.empty()) {
			error = "binding entry missing 'key'";
			return false;
		}
		entry.scene = item->get_string("scene");
		entry.mesh = item->get_string("mesh");
		const JsonValue *t = item->find("transform");
		if (t != nullptr && !t->is_null()) {
			// Copy the shared_ptr node (passthrough).
			entry.transform = std::make_shared<JsonValue>(*t);
		}
		const JsonValue *s = item->find("sockets");
		if (s != nullptr && !s->is_null()) {
			entry.sockets = std::make_shared<JsonValue>(*s);
		}
		out.entries.push_back(std::move(entry));
	}
	return true;
}

bool parse_resolver_matrix_sources(const JsonValue &sources_arr,
		BindingResolver &out, std::string &error) {
	if (!sources_arr.is_array()) {
		error = "matrix 'sources' is not an array";
		return false;
	}
	for (const auto &item : sources_arr.array_items) {
		BindingSource source;
		if (item == nullptr || !parse_binding_source(*item, source, error)) {
			return false;
		}
		out.add_source(std::move(source));
	}
	return true;
}

std::string serialize_pack_sorted(const BindingSource &source) {
	// Build a fresh JSON tree so canonical_json_stringify (which sorts object
	// keys) yields byte-deterministic output. Entries are pre-sorted by key so
	// the entries ARRAY (which canonical_json leaves in order) is deterministic.
	auto root = std::make_shared<JsonValue>();
	root->type = JsonType::Object;
	root->object_items.push_back({"format", make_string("insimul-binding-pack")});
	root->object_items.push_back({"version", make_int(1)});
	root->object_items.push_back({"name", make_string(source.name)});
	root->object_items.push_back({"priority", make_int(source.priority)});

	std::vector<const BindingEntry *> sorted;
	sorted.reserve(source.entries.size());
	for (const auto &e : source.entries) {
		sorted.push_back(&e);
	}
	std::stable_sort(sorted.begin(), sorted.end(),
			[](const BindingEntry *a, const BindingEntry *b) {
				return a->key < b->key;
			});

	auto entries = std::make_shared<JsonValue>();
	entries->type = JsonType::Array;
	for (const BindingEntry *e : sorted) {
		auto obj = std::make_shared<JsonValue>();
		obj->type = JsonType::Object;
		obj->object_items.push_back({"key", make_string(e->key)});
		if (!e->scene.empty()) {
			obj->object_items.push_back({"scene", make_string(e->scene)});
		}
		if (!e->mesh.empty()) {
			obj->object_items.push_back({"mesh", make_string(e->mesh)});
		}
		if (e->transform != nullptr) {
			obj->object_items.push_back({"transform", e->transform});
		}
		if (e->sockets != nullptr) {
			obj->object_items.push_back({"sockets", e->sockets});
		}
		entries->array_items.push_back(obj);
	}
	root->object_items.push_back({"entries", entries});

	return canonical_json_stringify(*root);
}

} // namespace insimul
