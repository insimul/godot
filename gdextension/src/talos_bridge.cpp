// talos_bridge.cpp — see talos_bridge.h for what this artifact is and why the
// decision lives in C++ rather than in the addon's GDScript.
//
// This is a PORT, and it says so: `scripts/engine-versions/check-hello.mjs` in
// the workspace is the reference implementation of the refuse-at-hello contract,
// written so "the three per-engine adapters port a decision procedure instead of
// re-deriving one each" (docs/REFUSE_AT_HELLO.md). A port is only worth as much
// as the evidence that it agrees, so the reference's own 21 cases are mirrored
// into gdextension/test/fixtures/refuse-at-hello/ and replayed here by
// test/test_talos_bridge.cpp. The suite is two-sided by construction — it
// carries an admitted hello and a restored archive — because a decision
// procedure that refused everything would otherwise pass every refusal case.

#include "talos_bridge.h"

#include "canonical_json.h"

#include <algorithm>
#include <cctype>
#include <utility>

namespace insimul {
namespace talos {
namespace {

// The four axes of §7.7, IN THE ORDER A REFUSAL IS DECIDED. The first blocking
// axis is the one named; two adapters refusing the same build must produce the
// same token or Conductor-side attribution stops aggregating.
const char *const AXES[] = { "engine_version", "c_abi", "snapshot_version", "plugin_version" };
const std::size_t AXIS_COUNT = 4;

// Talos freezes its top-level error codes and lets `data.sub_code` grow freely
// (talos:docs/03-engine-bridge.md §2.11), so every Insimul token is a SUB-code.
// NOT_DECLARED is the closest frozen code: the build does not declare a
// combination the matrix supports.
const int NOT_DECLARED = -32003;

JsonValuePtr jnull() {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::Null;
	return v;
}

JsonValuePtr jstr(const std::string &s) {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::String;
	v->string_value = s;
	return v;
}

JsonValuePtr jbool(bool b) {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::Bool;
	v->bool_value = b;
	return v;
}

JsonValuePtr jint(long long n) {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::Number;
	v->number_value = static_cast<double>(n);
	v->raw_number = std::to_string(n);
	return v;
}

JsonValuePtr jobj() {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::Object;
	return v;
}

JsonValuePtr jarr() {
	auto v = std::make_shared<JsonValue>();
	v->type = JsonType::Array;
	return v;
}

void put(const JsonValuePtr &obj, const std::string &key, const JsonValuePtr &value) {
	obj->object_items.push_back({ key, value });
}

// A string member, or null when absent/empty — the distinction the whole design
// rests on: an absent reading is not an empty one.
JsonValuePtr jstr_or_null(const std::string &s) {
	return s.empty() ? jnull() : jstr(s);
}

// A copy of a parsed node, or null. Copies rather than aliases so a returned
// document never shares structure with the contract the bridge was configured
// with.
JsonValuePtr clone_or_null(const JsonValue *node) {
	if (node == nullptr || node->is_null()) {
		return jnull();
	}
	return std::make_shared<JsonValue>(*node);
}

std::string serialize(const JsonValuePtr &value) {
	return canonical_json_stringify(*value);
}

bool is_digit(char c) {
	return c >= '0' && c <= '9';
}

// The engine MINOR, from either a clean version or the prose the matrix
// sometimes carries (">=4.2", "2022.3 (unityRelease 0f1)"). Prose there is
// deliberate — the matrix records what a manifest actually says — so the
// comparison extracts rather than demanding the matrix lie about its sources.
// The twin of `minorOf` in check-hello.mjs.
std::string minor_of(const std::string &value) {
	for (std::size_t i = 0; i < value.size(); ++i) {
		if (!is_digit(value[i])) {
			continue;
		}
		if (i > 0 && is_digit(value[i - 1])) {
			continue;
		}
		std::size_t j = i;
		while (j < value.size() && is_digit(value[j])) {
			++j;
		}
		if (j >= value.size() || value[j] != '.') {
			continue;
		}
		std::size_t k = j + 1;
		while (k < value.size() && is_digit(value[k])) {
			++k;
		}
		if (k == j + 1) {
			continue;
		}
		return value.substr(i, k - i);
	}
	return std::string();
}

// MAJOR.MINOR of a semver, anchored. The c_abi axis is proxied by the
// libinsimul semver because the library carries no compiled-in ABI symbol, so a
// patch bump is not skew and a minor bump is. The twin of `majorMinor`.
std::string major_minor(const std::string &value) {
	std::size_t i = 0;
	while (i < value.size() && is_digit(value[i])) {
		++i;
	}
	if (i == 0 || i >= value.size() || value[i] != '.') {
		return std::string();
	}
	std::size_t j = i + 1;
	while (j < value.size() && is_digit(value[j])) {
		++j;
	}
	if (j == i + 1) {
		return std::string();
	}
	return value.substr(0, j);
}

// `tbp/1.<n>` and nothing else. A different major is not a skewed axis, it is a
// different protocol, and guessing at an unknown envelope is how a misparse
// becomes a finding.
bool is_tbp_1(const std::string &protocol) {
	if (protocol.rfind("tbp/1.", 0) != 0) {
		return false;
	}
	const std::string tail = protocol.substr(6);
	if (tail.empty()) {
		return false;
	}
	for (std::size_t i = 0; i < tail.size(); ++i) {
		if (!is_digit(tail[i])) {
			return false;
		}
	}
	return true;
}

// MAJOR.MINOR shape, the save-format gate's own. A value that is not this shape
// is almost always babylon's per-world `snapshotVersion` COUNTER published on
// the wrong axis, which is a different bug with a different fix.
bool is_save_format_shape(const std::string &value) {
	std::size_t i = 0;
	while (i < value.size() && is_digit(value[i])) {
		++i;
	}
	if (i == 0 || i >= value.size() || value[i] != '.') {
		return false;
	}
	std::size_t j = i + 1;
	while (j < value.size() && is_digit(value[j])) {
		++j;
	}
	return j > i + 1 && j == value.size();
}

// Where each axis's OBSERVED value lives in a hello result. `plugin_version` at
// the top level of a hello is TALOS's addon version, so the Insimul plugin build
// rides the namespaced block and both halves of that jointly-owned axis stay
// legible instead of one overwriting the other.
std::string observed_axis(const JsonValue &result, const std::string &axis) {
	if (axis == "engine_version") {
		return result.get_string("engine_version");
	}
	const JsonValue *caps = result.find("capabilities");
	const JsonValue *insimul = caps == nullptr ? nullptr : caps->find("insimul");
	if (insimul == nullptr) {
		return std::string();
	}
	if (axis == "c_abi") {
		return insimul->get_string("core_version");
	}
	return insimul->get_string(axis);
}

std::string hello_field(const std::string &axis) {
	if (axis == "engine_version") {
		return "result.engine_version";
	}
	if (axis == "c_abi") {
		return "result.capabilities.insimul.core_version";
	}
	return "result.capabilities.insimul." + axis;
}

} // namespace

bool Bridge::configure(const std::string &contract_json, const std::string &matrix_json) {
	configured_ = false;
	contract_.reset();
	matrix_.reset();
	error_.clear();

	const JsonParseResult contract = parse_json(contract_json);
	if (!contract.ok || contract.root == nullptr || !contract.root->is_object()) {
		error_ = "bridge-contract.json is unreadable: " + contract.error;
		return false;
	}
	const JsonParseResult matrix = parse_json(matrix_json);
	if (!matrix.ok || matrix.root == nullptr || !matrix.root->is_object()) {
		error_ = "supported-versions.json is unreadable: " + matrix.error;
		return false;
	}
	// Both files must actually be the files they claim to be. A bridge configured
	// from something else would decide from a default, and §7.8's whole argument
	// is that a silent default is the one failure mode this design exists to
	// remove.
	if (contract.root->get_string("format") != "insimul.talos-bridge.contract/1") {
		error_ = "bridge-contract.json is not an insimul.talos-bridge.contract/1 document";
		return false;
	}
	const JsonValue *refuse = matrix.root->find("refuse_at_hello");
	if (refuse == nullptr || refuse->find("tokens") == nullptr) {
		error_ = "supported-versions.json publishes no refuse_at_hello.tokens vocabulary";
		return false;
	}
	if (matrix.root->find("engines") == nullptr) {
		error_ = "supported-versions.json publishes no engines";
		return false;
	}
	if (contract.root->find("groups") == nullptr || contract.root->find("verbs") == nullptr) {
		error_ = "bridge-contract.json declares no groups or no verbs";
		return false;
	}

	contract_ = contract.root;
	matrix_ = matrix.root;
	configured_ = true;
	return true;
}

std::vector<std::string> Bridge::groups() const {
	std::vector<std::string> out;
	if (!configured_) {
		return out;
	}
	const JsonValue *groups = contract_->find("groups");
	for (std::size_t i = 0; i < groups->object_items.size(); ++i) {
		out.push_back(groups->object_items[i].second->get_string("group"));
	}
	return out;
}

const JsonValue *Bridge::matrix_for(const std::string &override_json, JsonValuePtr &holder) const {
	if (override_json.empty()) {
		return matrix_.get();
	}
	const JsonParseResult parsed = parse_json(override_json);
	if (!parsed.ok || parsed.root == nullptr || !parsed.root->is_object()) {
		return matrix_.get();
	}
	holder = parsed.root;
	return holder.get();
}

const JsonValue *Bridge::engine_row(const JsonValue &matrix, const std::string &engine) const {
	const JsonValue *engines = matrix.find("engines");
	if (engines == nullptr || !engines->is_array()) {
		return nullptr;
	}
	for (std::size_t i = 0; i < engines->array_items.size(); ++i) {
		const JsonValuePtr &row = engines->array_items[i];
		if (row->get_string("engine") == engine) {
			return row.get();
		}
	}
	return nullptr;
}

const JsonValue *Bridge::token_meta(const std::string &token) const {
	const JsonValue *contract_tokens = contract_ == nullptr ? nullptr : contract_->find("tokens");
	if (contract_tokens != nullptr) {
		const JsonValue *found = contract_tokens->find(token);
		if (found != nullptr) {
			return found;
		}
	}
	const JsonValue *refuse = matrix_ == nullptr ? nullptr : matrix_->find("refuse_at_hello");
	const JsonValue *published = refuse == nullptr ? nullptr : refuse->find("tokens");
	return published == nullptr ? nullptr : published->find(token);
}

std::string Bridge::refuse(const std::string &token, const std::string &message,
		const std::vector<std::pair<std::string, JsonValuePtr>> &extra) const {
	const JsonValue *meta = token_meta(token);

	auto data = jobj();
	put(data, "sub_code", jstr(token));
	// `retryable` and `unblock` come from the PUBLISHED token entry rather than
	// from a string beside the throw. §2.11 requires every refusal to carry its
	// unblock recipe, and a recipe that lives with the vocabulary cannot drift
	// away from the token it explains.
	put(data, "retryable", jbool(meta != nullptr && meta->get_bool("retryable", false)));
	if (meta != nullptr) {
		const JsonValue *unblock = meta->find("unblock");
		if (unblock != nullptr && unblock->is_string()) {
			put(data, "unblock", jstr(unblock->string_value));
		}
	} else {
		// Unreachable if the gate is doing its job — which is exactly why it says
		// so in the payload rather than quietly emitting a bare token.
		put(data, "token_unpublished", jbool(true));
	}
	for (std::size_t i = 0; i < extra.size(); ++i) {
		put(data, extra[i].first, extra[i].second);
	}

	auto error = jobj();
	put(error, "code", jint(NOT_DECLARED));
	put(error, "code_name", jstr("NOT_DECLARED"));
	put(error, "message", jstr(message));
	put(error, "data", data);

	auto root = jobj();
	put(root, "ok", jbool(false));
	// `verdict` and `token` at the top level so a decision is directly comparable
	// with the reference implementation's; `error` is the wire envelope.
	put(root, "verdict", jstr(token.rfind("insimul_checkpoint_", 0) == 0 ? "invalidate" : "refuse"));
	put(root, "token", jstr(token));
	put(root, "error", error);
	return serialize(root);
}

std::string Bridge::not_configured() const {
	auto data = jobj();
	put(data, "sub_code", jstr("insimul_bridge_not_configured"));
	put(data, "retryable", jbool(false));
	put(data, "unblock",
			jstr("install addons/insimul_talos in full — bridge-contract.json and "
				 "supported-versions.json ship with the addon"));
	put(data, "configure_error", jstr(error_));

	auto error = jobj();
	put(error, "code", jint(NOT_DECLARED));
	put(error, "code_name", jstr("NOT_DECLARED"));
	put(error, "message", jstr("insimul: the bridge was asked to decide before it was configured"));
	put(error, "data", data);

	auto root = jobj();
	put(root, "ok", jbool(false));
	put(root, "verdict", jstr("refuse"));
	put(root, "token", jstr("insimul_bridge_not_configured"));
	put(root, "error", error);
	return serialize(root);
}

std::string Bridge::capabilities(const Readings &readings) const {
	auto caps = jobj();
	put(caps, "core_version", jstr_or_null(readings.core_version));
	put(caps, "snapshot_version", jstr_or_null(readings.snapshot_version));
	put(caps, "plugin_version", jstr_or_null(readings.plugin_version));
	// Tier 1, and the fidelity beside it. §3.5: a KB snapshot restores the
	// SIMULATION and not the SCENE, and declaring tier 2 on it would import a
	// claim this project has not earned — the Go-Explore ROI numbers are scoped
	// to tier 2 and to thousands of restores an hour.
	put(caps, "checkpoint_tier", jint(1));
	put(caps, "checkpoint_fidelity", jstr("kb_authoritative"));
	put(caps, "kb_query", jbool(true));
	put(caps, "kb_checkpoint", jbool(true));
	put(caps, "kb_ready", jbool(readings.kb_ready));
	// The world half is a READING, so it is null until there is a world to read.
	// §7.5: the adapter never reads the KB at construction, and an empty world id
	// reported as a world is the silent degradation that rule exists to remove.
	put(caps, "world_id", readings.kb_ready ? jstr_or_null(readings.world_id) : jnull());
	put(caps, "seed", readings.kb_ready ? jstr_or_null(readings.seed) : jnull());
	if (readings.kb_ready) {
		auto modules = jarr();
		for (std::size_t i = 0; i < readings.active_modules.size(); ++i) {
			modules->array_items.push_back(jstr(readings.active_modules[i]));
		}
		put(caps, "active_modules", modules);
	} else {
		put(caps, "active_modules", jnull());
	}
	return serialize(caps);
}

std::string Bridge::hello(const Readings &readings) const {
	const JsonParseResult caps = parse_json(capabilities(readings));

	auto capabilities_obj = jobj();
	put(capabilities_obj, "insimul", caps.root);

	auto result = jobj();
	put(result, "protocol", jstr("tbp/1.0"));
	put(result, "engine", jstr(readings.engine));
	put(result, "engine_version", jstr_or_null(readings.engine_version));
	put(result, "capabilities", capabilities_obj);

	auto root = jobj();
	put(root, "jsonrpc", jstr("2.0"));
	put(root, "result", result);
	return serialize(root);
}

std::string Bridge::evaluate_hello(const std::string &hello_json,
		const std::string &matrix_override) const {
	if (!configured_) {
		return not_configured();
	}
	JsonValuePtr holder;
	const JsonValue &matrix = *matrix_for(matrix_override, holder);
	const JsonParseResult parsed = parse_json(hello_json);
	const JsonValue *result = nullptr;
	if (parsed.ok && parsed.root != nullptr && parsed.root->is_object()) {
		const JsonValue *inner = parsed.root->find("result");
		result = inner != nullptr && inner->is_object() ? inner : parsed.root.get();
	}
	if (result == nullptr || !result->is_object()) {
		return refuse("insimul_hello_malformed",
				"insimul: the hello carried no result object; nothing was checked because "
				"nothing was readable",
				{});
	}

	// R1 — protocol.
	const std::string protocol = result->get_string("protocol");
	if (!is_tbp_1(protocol)) {
		return refuse("insimul_tbp_protocol_unknown",
				"insimul: protocol '" + protocol + "' is not a TBP major this adapter implements",
				{ { "observed", jstr_or_null(protocol) }, { "expected", jstr("tbp/1.x") } });
	}

	// R2 — the engine has to be one the matrix speaks about at all.
	const std::string engine = result->get_string("engine");
	const JsonValue *row = engine_row(matrix, engine);
	if (row == nullptr) {
		return refuse("insimul_engine_unknown",
				"insimul: engine '" + engine + "' has no row in the published matrix",
				{ { "observed", jstr_or_null(engine) } });
	}

	// R3 — §7.8's dangerous row made loud. A hello with no `capabilities.insimul`
	// is a Talos run against what LOOKS like an ordinary game while the ground
	// truth sits unread; it is refused rather than degraded into.
	const JsonValue *caps = result->find("capabilities");
	const JsonValue *insimul = caps == nullptr ? nullptr : caps->find("insimul");
	if (insimul == nullptr || !insimul->is_object()) {
		return refuse("insimul_capabilities_absent",
				"insimul: the hello declares no capabilities.insimul — this would run as an "
				"ordinary Talos target with the knowledge base unread",
				{ { "observed", jnull() }, { "expected", jstr("capabilities.insimul (BRIDGE §3.1)") } });
	}

	// R4 — the four axes, in order.
	const JsonValue *axes = row->find("axes");
	for (std::size_t i = 0; i < AXIS_COUNT; ++i) {
		const std::string axis = AXES[i];
		const JsonValue *published = axes == nullptr ? nullptr : axes->find(axis);
		if (published == nullptr || !published->is_object()) {
			return refuse("insimul_" + axis + "_unpublished",
					"insimul: the matrix publishes no " + axis + " axis for " + engine,
					{ { "axis", jstr(axis) } });
		}

		// An axis the matrix has not VERIFIED cannot admit anything, whatever the
		// build reports. `declared` is a manifest floor, `unstated` is a silence,
		// `unverified` is an untested claim, and none of the three is a per-minor
		// artifact that was exercised.
		const std::string status = published->get_string("status");
		if (status != "verified") {
			return refuse("insimul_" + axis + "_" + status,
					"insimul: the " + axis + " axis is published as '" + status +
							"', which is not 'verified'",
					{ { "axis", jstr(axis) },
							{ "status", jstr(status) },
							{ "expected", clone_or_null(published->find("value")) },
							{ "observed", jstr_or_null(observed_axis(*result, axis)) },
							{ "source", clone_or_null(published->find("source")) } });
		}

		const std::string observed = observed_axis(*result, axis);
		if (observed.empty()) {
			return refuse("insimul_" + axis + "_absent",
					"insimul: the hello declares no " + hello_field(axis) +
							"; a partial declaration is not a partial pass",
					{ { "axis", jstr(axis) },
							{ "expected", clone_or_null(published->find("value")) },
							{ "field", jstr(hello_field(axis)) } });
		}

		// The naming collision, checked BEFORE the value comparison so it is
		// reported as itself: babylon's `snapshotVersion` is a per-world monotonic
		// structure counter, not the save FORMAT gate, and reporting "17" vs "3.0"
		// as ordinary skew would send the fixer to the wrong file.
		if (axis == "snapshot_version" && !is_save_format_shape(observed)) {
			return refuse("insimul_snapshot_version_not_save_format",
					"insimul: snapshot_version '" + observed +
							"' is not the MAJOR.MINOR shape of a save format",
					{ { "axis", jstr(axis) },
							{ "observed", jstr(observed) },
							{ "expected", clone_or_null(published->find("value")) } });
		}

		const std::string published_value = published->get_string("value");
		std::string want = published_value;
		std::string got = observed;
		std::string compared_as = "exact";
		if (axis == "engine_version") {
			want = minor_of(published_value);
			got = minor_of(observed);
			compared_as = "engine minor";
		} else if (axis == "c_abi") {
			want = major_minor(published_value);
			got = major_minor(observed);
			compared_as = "semver MAJOR.MINOR";
		}
		if (want.empty() || got.empty() || want != got) {
			return refuse("insimul_" + axis + "_skew",
					"insimul: the build's " + axis + " is '" + observed +
							"'; the cell was verified at '" + published_value + "'",
					{ { "axis", jstr(axis) },
							{ "expected", jstr_or_null(published_value) },
							{ "observed", jstr(observed) },
							{ "compared_as", jstr(compared_as) },
							{ "source", clone_or_null(published->find("source")) } });
		}
	}

	// R5 — the counterparty half of the intersection. Four verified axes is ONE
	// matrix; a supported cell needs both.
	const JsonValue *counterparty = matrix.find("counterparty");
	const JsonValue *claims = counterparty == nullptr ? nullptr : counterparty->find("claims");
	const JsonValue *claim = nullptr;
	if (claims != nullptr && claims->is_array()) {
		for (std::size_t i = 0; i < claims->array_items.size(); ++i) {
			if (claims->array_items[i]->get_string("engine") == engine) {
				claim = claims->array_items[i].get();
				break;
			}
		}
	}
	const std::string engine_minor = minor_of(result->get_string("engine_version"));
	if (claim == nullptr) {
		return refuse("insimul_counterparty_claim_absent",
				"insimul: the counterparty publishes no claim for " + engine +
						", so there is no second matrix to intersect with",
				{ { "observed", jstr_or_null(engine_minor) } });
	}
	if (minor_of(claim->get_string("minor")) != engine_minor) {
		return refuse("insimul_counterparty_minor_disjoint",
				"insimul: both projects verified an artifact and they verified different minors",
				{ { "observed", jstr_or_null(engine_minor) },
						{ "expected", jstr_or_null(minor_of(claim->get_string("minor"))) } });
	}

	// R6 — the backstop. If every axis passes and the published cell still says
	// otherwise, the matrix knows something the axes do not, and the matrix wins.
	const JsonValue *cell = row->find("cell");
	const std::string cell_status = cell == nullptr ? std::string("unpublished") : cell->get_string("status", "unpublished");
	if (cell_status != "supported") {
		return refuse("insimul_cell_" + cell_status,
				"insimul: every axis passed and the published cell is '" + cell_status + "'",
				{ { "why", cell == nullptr ? jnull() : clone_or_null(cell->find("why")) },
						{ "blocking_axes", cell == nullptr ? jnull() : clone_or_null(cell->find("blocking_axes")) } });
	}

	auto observed_axes = jobj();
	for (std::size_t i = 0; i < AXIS_COUNT; ++i) {
		put(observed_axes, AXES[i], jstr_or_null(observed_axis(*result, AXES[i])));
	}
	auto root = jobj();
	put(root, "ok", jbool(true));
	put(root, "verdict", jstr("admit"));
	put(root, "engine", jstr(engine));
	put(root, "minor", jstr_or_null(engine_minor));
	put(root, "axes", observed_axes);
	return serialize(root);
}

std::string Bridge::evaluate_archive(const std::string &archive_json,
		const std::string &matrix_override) const {
	if (!configured_) {
		return not_configured();
	}
	JsonValuePtr holder;
	const JsonValue &matrix = *matrix_for(matrix_override, holder);
	const JsonParseResult parsed = parse_json(archive_json);
	if (!parsed.ok || parsed.root == nullptr || !parsed.root->is_object()) {
		return refuse("insimul_checkpoint_malformed",
				"insimul: the archive entry was unreadable", {});
	}
	const JsonValue &archive = *parsed.root;
	const std::string engine = archive.get_string("engine");
	const JsonValue *row = engine_row(matrix, engine);
	if (row == nullptr) {
		return refuse("insimul_checkpoint_engine_unknown",
				"insimul: the archive names engine '" + engine + "', which has no row in the matrix",
				{ { "observed", jstr_or_null(engine) } });
	}

	const JsonValue *stamped = archive.find("axes");
	if (stamped == nullptr || !stamped->is_object() || stamped->object_items.empty()) {
		return refuse("insimul_checkpoint_unstamped",
				"insimul: the archive entry carries no version stamp, so it cannot be proven "
				"to match anything",
				{});
	}

	const JsonValue *axes = row->find("axes");
	const char *const ARCHIVE_AXES[] = { "snapshot_version", "c_abi" };
	for (std::size_t i = 0; i < 2; ++i) {
		const std::string axis = ARCHIVE_AXES[i];
		const JsonValue *published = axes == nullptr ? nullptr : axes->find(axis);
		const JsonValue *value = published == nullptr ? nullptr : published->find("value");
		const bool has_value = value != nullptr && value->is_string();
		const JsonValue *got = stamped->find(axis);
		const bool has_got = got != nullptr && got->is_string();
		if (!has_value) {
			// Uncheckable is not matching. Godot and Unreal declare no expected C
			// ABI anywhere, so this is a token an adapter really hits.
			return refuse("insimul_checkpoint_axis_uncheckable",
					"insimul: the matrix publishes no " + axis + " value for " + engine +
							" — nothing to compare the archive against",
					{ { "axis", jstr(axis) },
							{ "observed", has_got ? jstr(got->string_value) : jnull() },
							{ "status", published == nullptr ? jstr("unpublished") : jstr_or_null(published->get_string("status")) },
							{ "source", published == nullptr ? jnull() : clone_or_null(published->find("source")) } });
		}
		if (!has_got) {
			return refuse("insimul_checkpoint_" + axis + "_absent",
					"insimul: the archive is stamped, but not on the " + axis +
							" axis; half a stamp is not a stamp",
					{ { "axis", jstr(axis) }, { "expected", jstr(value->string_value) } });
		}
		std::string want = value->string_value;
		std::string have = got->string_value;
		if (axis == "c_abi") {
			want = major_minor(want);
			have = major_minor(have);
		}
		if (want != have) {
			return refuse("insimul_checkpoint_" + axis + "_skew",
					"insimul: the archive was written under " + axis + " '" + got->string_value +
							"'; the matrix publishes '" + value->string_value + "'",
					{ { "axis", jstr(axis) },
							{ "expected", jstr(value->string_value) },
							{ "observed", jstr(got->string_value) } });
		}
	}

	auto root = jobj();
	put(root, "ok", jbool(true));
	put(root, "verdict", jstr("restore"));
	put(root, "id", jstr_or_null(archive.get_string("id")));
	put(root, "engine", jstr(engine));
	return serialize(root);
}

std::string Bridge::checkpoint_stamp(const Readings &readings) const {
	auto axes = jobj();
	put(axes, "engine_version", jstr_or_null(readings.engine_version));
	put(axes, "c_abi", jstr_or_null(readings.core_version));
	put(axes, "snapshot_version", jstr_or_null(readings.snapshot_version));
	put(axes, "plugin_version", jstr_or_null(readings.plugin_version));

	auto root = jobj();
	put(root, "engine", jstr(readings.engine));
	put(root, "tier", jint(1));
	put(root, "fidelity", jstr("kb_authoritative"));
	put(root, "axes", axes);
	return serialize(root);
}

std::string Bridge::verb(const std::string &name, const Readings &readings,
		const std::string &required_module) const {
	if (!configured_) {
		return not_configured();
	}
	const JsonValue *verbs = contract_->find("verbs");
	const JsonValue *row = verbs == nullptr ? nullptr : verbs->find(name);
	if (row == nullptr || !row->is_object()) {
		// Under absent-means-absent semantics a typo is indistinguishable from a
		// decision, so an undeclared verb is refused rather than guessed at.
		return refuse("insimul_verb_unknown",
				"insimul: '" + name + "' is not a verb this bridge's contract declares",
				{ { "observed", jstr(name) } });
	}

	const std::string answered_by = row->get_string("answered_by");
	if (answered_by != "insimul") {
		const std::string token = row->get_string("why_not");
		return refuse(token.empty() ? std::string("insimul_verb_unmapped") : token,
				"insimul: '" + name + "' is not answered from the knowledge base — " +
						row->get_string("mapping"),
				{ { "verb", jstr(name) },
						{ "answered_by", jstr_or_null(answered_by) },
						{ "verdict_in_mapping", jstr_or_null(row->get_string("verdict")) } });
	}

	// A verb with a hook needs a live knowledge base. §7.5: before a world is
	// loaded this is a RETRYABLE refusal and never an empty success — the
	// Conductor must not be able to read "no facts" as a fact.
	const JsonValue *hook = row->find("hook");
	const bool needs_kb = hook != nullptr && hook->is_string() && !hook->string_value.empty();
	if (needs_kb && !readings.kb_ready) {
		return refuse("insimul_kb_uninitialized",
				"insimul: '" + name + "' arrived before a world was loaded; the knowledge base "
				"has not been read and will not be guessed at",
				{ { "verb", jstr(name) }, { "retry_after_ms", jint(250) } });
	}

	if (!required_module.empty()) {
		bool active = false;
		for (std::size_t i = 0; i < readings.active_modules.size(); ++i) {
			if (readings.active_modules[i] == required_module) {
				active = true;
				break;
			}
		}
		if (!active) {
			auto declared = jarr();
			for (std::size_t i = 0; i < readings.active_modules.size(); ++i) {
				declared->array_items.push_back(jstr(readings.active_modules[i]));
			}
			return refuse("insimul_module_inactive",
					"insimul: '" + name + "' needs the '" + required_module +
							"' module, which this world's genre bundle never activated",
					{ { "verb", jstr(name) },
							{ "module", jstr(required_module) },
							{ "active_modules", declared } });
		}
	}

	auto root = jobj();
	put(root, "ok", jbool(true));
	put(root, "verdict", jstr("admit"));
	put(root, "verb", jstr(name));
	put(root, "mapping", jstr_or_null(row->get_string("mapping")));
	put(root, "hook", needs_kb ? jstr(hook->string_value) : jnull());
	return serialize(root);
}

std::string Bridge::query_digest(const std::string &solutions_json, std::size_t cap_bytes) const {
	const JsonParseResult parsed = parse_json(solutions_json);
	if (!parsed.ok || parsed.root == nullptr || !parsed.root->is_array()) {
		auto root = jobj();
		put(root, "ok", jbool(false));
		put(root, "verdict", jstr("refuse"));
		put(root, "token", jstr("insimul_verb_unknown"));
		put(root, "message", jstr("insimul: query_digest was handed something that is not a solution array"));
		return serialize(root);
	}

	// §3.4's correction. Core compares solutions as an UNORDERED multiset by
	// design, so a native engine may enumerate in any order; TBP requires
	// deterministic truncation when the digest cap is hit. Sorting canonically
	// before the cap is what makes a capped Insimul query reproducible across
	// engines — and missing it produces exactly the flavour of intermittent
	// cross-engine disagreement that is hardest to diagnose.
	std::vector<std::pair<std::string, JsonValuePtr> > sorted;
	sorted.reserve(parsed.root->array_items.size());
	for (std::size_t i = 0; i < parsed.root->array_items.size(); ++i) {
		const JsonValuePtr &item = parsed.root->array_items[i];
		sorted.push_back({ serialize(item), item });
	}
	std::sort(sorted.begin(), sorted.end(),
			[](const std::pair<std::string, JsonValuePtr> &a,
					const std::pair<std::string, JsonValuePtr> &b) { return a.first < b.first; });

	auto kept = jarr();
	std::size_t bytes = 2; // the enclosing brackets
	std::size_t taken = 0;
	for (std::size_t i = 0; i < sorted.size(); ++i) {
		const std::size_t addition = sorted[i].first.size() + (taken == 0 ? 0 : 1);
		if (taken > 0 && bytes + addition > cap_bytes) {
			break;
		}
		bytes += addition;
		kept->array_items.push_back(sorted[i].second);
		++taken;
	}

	auto root = jobj();
	put(root, "ok", jbool(true));
	put(root, "solutions", kept);
	put(root, "count", jint(static_cast<long long>(taken)));
	put(root, "total", jint(static_cast<long long>(sorted.size())));
	put(root, "dropped", jint(static_cast<long long>(sorted.size() - taken)));
	put(root, "overflow", jbool(taken < sorted.size()));
	put(root, "bytes", jint(static_cast<long long>(bytes)));
	put(root, "sorted_by", jstr("canonical JSON of each binding set"));
	return serialize(root);
}

std::string Bridge::progress_var(const std::string &name, const std::string &value_json,
		bool targets_template, const Readings &readings) const {
	const std::string gate = verb("set_progress_var", readings);
	const JsonParseResult gated = parse_json(gate);
	if (!gated.ok || gated.root == nullptr || !gated.root->get_bool("ok", false)) {
		return gate;
	}
	if (targets_template) {
		// §3.6's one hard requirement. A write that landed on a world TEMPLATE
		// would corrupt every future playthrough of that world, and it would do so
		// invisibly.
		return refuse("insimul_world_template_write_refused",
				"insimul: set_progress_var('" + name + "') targets a world template; asserted "
				"runtime facts belong to the playthrough, never to the world every future "
				"playthrough is generated from",
				{ { "verb", jstr("set_progress_var") }, { "variable", jstr(name) } });
	}

	const JsonParseResult value = parse_json(value_json);
	auto order = jobj();
	put(order, "kind", jstr("kb_assert"));
	put(order, "variable", jstr(name));
	put(order, "value", value.ok && value.root != nullptr ? value.root : jnull());
	// The fact TEXT is the game's, not the bridge's: a progress var IS a fact, and
	// which predicate carries it is declared by the game's own schema. The bridge
	// says WHAT to record and refuses WHERE it must not go.
	put(order, "target", jstr("playthrough"));

	auto root = jobj();
	put(root, "ok", jbool(true));
	put(root, "verdict", jstr("admit"));
	put(root, "order", order);
	return serialize(root);
}

std::vector<std::string> Bridge::tokens() const {
	// Built the way the code builds them rather than listed beside it, so this can
	// never fall out of step with what `evaluate_hello` can actually emit.
	std::vector<std::string> out;
	out.push_back("insimul_hello_malformed");
	out.push_back("insimul_tbp_protocol_unknown");
	out.push_back("insimul_engine_unknown");
	out.push_back("insimul_capabilities_absent");
	const char *const STATUSES[] = { "unpublished", "unstated", "declared", "unverified" };
	for (std::size_t i = 0; i < AXIS_COUNT; ++i) {
		const std::string axis = AXES[i];
		for (std::size_t s = 0; s < 4; ++s) {
			out.push_back("insimul_" + axis + "_" + STATUSES[s]);
		}
		out.push_back("insimul_" + axis + "_absent");
		out.push_back("insimul_" + axis + "_skew");
	}
	out.push_back("insimul_snapshot_version_not_save_format");
	out.push_back("insimul_counterparty_claim_absent");
	out.push_back("insimul_counterparty_minor_disjoint");
	out.push_back("insimul_cell_unsupported");
	out.push_back("insimul_cell_disjoint");
	out.push_back("insimul_cell_unpublished");
	out.push_back("insimul_checkpoint_malformed");
	out.push_back("insimul_checkpoint_engine_unknown");
	out.push_back("insimul_checkpoint_unstamped");
	out.push_back("insimul_checkpoint_axis_uncheckable");
	out.push_back("insimul_checkpoint_snapshot_version_absent");
	out.push_back("insimul_checkpoint_snapshot_version_skew");
	out.push_back("insimul_checkpoint_c_abi_absent");
	out.push_back("insimul_checkpoint_c_abi_skew");
	out.push_back("insimul_verb_unknown");
	out.push_back("insimul_verb_host_owned");
	out.push_back("insimul_verb_unmapped");
	out.push_back("insimul_kb_uninitialized");
	out.push_back("insimul_world_template_write_refused");
	out.push_back("insimul_module_inactive");
	out.push_back("insimul_bridge_not_configured");
	return out;
}

} // namespace talos
} // namespace insimul
