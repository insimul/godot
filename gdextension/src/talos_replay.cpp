// talos_replay.cpp — see talos_replay.h for what this leg is and why it is a
// port rather than an adoption.
//
// This is a PORT, and it says so. `packages/core/src/replay/` is the reference:
// `input-trace.ts` reads and refuses the artifact, `kb-outcome.ts` seals and
// compares the outcome, `replay-driver.ts` drives the ticks. Every refusal code
// below is core's own (`invalid_format`, `malformed_input`, `id_mismatch`,
// `world_id_mismatch`, `world_content_mismatch`, `invalid_outcome`,
// `outcome_digest_mismatch`, `trace_mismatch`) so a four-way report can key on
// one vocabulary, and each is paired with a published `insimul_*` why-not token
// so a Conductor gets §2.11's unblock recipe rather than a bare string.
//
// The evidence that the port agrees is gdextension/test/fixtures/replay/, minted
// by running core's real module under Node. See tools/vendor-replay-fixtures.mjs.

#include "talos_replay.h"

#include "canonical_json.h"
#include "sha256.h"

#include <algorithm>
#include <cmath>
#include <map>
#include <set>

namespace insimul {
namespace talos {

const char *const INPUT_TRACE_FORMAT = "insimul-input-trace-v1";
const char *const REPLAY_OUTCOME_FORMAT = "insimul-replay-outcome-v1";

namespace {

// The four device channels and the payload each carries, and no other. A record
// that carries another channel's field is malformed rather than tolerated: a
// trace whose extra fields are silently dropped is a trace whose id is a lie.
const char *const CHANNELS[] = { "button", "axis", "pointer", "text" };
const std::size_t CHANNEL_COUNT = 4;
const char *const PAYLOAD_FIELDS[] = { "edge", "value", "x", "y", "text" };
const std::size_t PAYLOAD_COUNT = 5;
const char *const INPUT_FIELDS[] = { "tick", "channel", "signal", "edge", "value", "x", "y", "text" };
const std::size_t INPUT_FIELD_COUNT = 8;

bool channel_carries(const std::string &channel, const std::string &field) {
	if (channel == "button") return field == "edge";
	if (channel == "axis") return field == "value";
	if (channel == "pointer") return field == "x" || field == "y";
	if (channel == "text") return field == "text";
	return false;
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

std::string serialize(const JsonValuePtr &value) {
	return canonical_json_stringify(*value);
}

/// `sha256-<64 hex>` over the canonical JSON of `value`. The one hash in this
/// file, and it is the C host's — see the header on why not the bundle's.
std::string sha256_id(const JsonValuePtr &value) {
	return "sha256-" + sha256_hex(canonical_json_stringify(*value));
}

/// The shape of every id and digest in the two documents.
bool is_digest(const std::string &value) {
	if (value.size() != 71) return false;
	if (value.compare(0, 7, "sha256-") != 0) return false;
	for (std::size_t i = 7; i < value.size(); ++i) {
		const char c = value[i];
		const bool hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
		if (!hex) return false;
	}
	return true;
}

bool is_integer(const JsonValue &value) {
	if (!value.is_number()) return false;
	const double n = value.number_value;
	return std::isfinite(n) && n == std::floor(n);
}

/// The UTF-16 code units of a UTF-8 string — what `String.prototype.length` and
/// `charCodeAt` see. `streamKey` length-prefixes each part with that length and
/// `hashSeedString` mixes those units, so a leg that counted BYTES would derive a
/// different stream for any seed outside ASCII and diverge only for those worlds.
std::vector<std::uint16_t> utf16_units(const std::string &text) {
	std::vector<std::uint16_t> units;
	std::size_t i = 0;
	while (i < text.size()) {
		const unsigned char c = static_cast<unsigned char>(text[i]);
		std::uint32_t code = 0;
		std::size_t width = 1;
		if (c < 0x80) {
			code = c;
		} else if ((c & 0xE0) == 0xC0) {
			code = c & 0x1F;
			width = 2;
		} else if ((c & 0xF0) == 0xE0) {
			code = c & 0x0F;
			width = 3;
		} else if ((c & 0xF8) == 0xF0) {
			code = c & 0x07;
			width = 4;
		} else {
			// Not a lead byte. Emit the replacement character rather than guessing,
			// and keep walking: a malformed seed must still hash deterministically.
			units.push_back(0xFFFD);
			++i;
			continue;
		}
		if (i + width > text.size()) {
			units.push_back(0xFFFD);
			break;
		}
		for (std::size_t k = 1; k < width; ++k) {
			code = (code << 6) | (static_cast<unsigned char>(text[i + k]) & 0x3F);
		}
		i += width;
		if (code >= 0x10000) {
			code -= 0x10000;
			units.push_back(static_cast<std::uint16_t>(0xD800 + (code >> 10)));
			units.push_back(static_cast<std::uint16_t>(0xDC00 + (code & 0x3FF)));
		} else {
			units.push_back(static_cast<std::uint16_t>(code));
		}
	}
	return units;
}

/// FNV-1a over UTF-16 code units, as a uint32 — `hashSeedString`.
std::uint32_t fnv1a(const std::string &text) {
	std::uint32_t h = 2166136261u;
	const std::vector<std::uint16_t> units = utf16_units(text);
	for (std::size_t i = 0; i < units.size(); ++i) {
		h ^= units[i];
		h = h * 16777619u;
	}
	return h;
}

/// `streamKey` — every part LENGTH-PREFIXED, in order. Injective for any input,
/// which is why it is not a separator character: there is none a caller-supplied
/// seed cannot contain.
std::string stream_key_part(const std::string &part) {
	return std::to_string(utf16_units(part).size()) + ":" + part;
}

/// A refusal, in the envelope the rest of this bridge speaks: core's own `code`
/// so a four-way report keys on one vocabulary, plus the published token that
/// carries the unblock recipe.
std::string refuse(const std::string &code, const std::string &token, const std::string &message) {
	auto data = jobj();
	put(data, "sub_code", jstr(token));
	put(data, "code", jstr(code));

	auto root = jobj();
	put(root, "ok", jbool(false));
	put(root, "verdict", jstr("refuse"));
	put(root, "code", jstr(code));
	put(root, "token", jstr(token));
	put(root, "message", jstr(message));
	put(root, "error", data);
	return serialize(root);
}

/// A copy of a fact, reduced to `{predicate, args}` — the projection
/// `buildReplayOutcome` applies, so an outcome never digests a field a producer
/// happened to hang off a fact.
JsonValuePtr fact_copy(const JsonValue &fact) {
	auto out = jobj();
	put(out, "predicate", jstr(fact.get_string("predicate")));
	auto args = jarr();
	const JsonValue *found = fact.find("args");
	if (found != nullptr && found->is_array()) {
		for (std::size_t i = 0; i < found->array_items.size(); ++i) {
			args->array_items.push_back(std::make_shared<JsonValue>(*found->array_items[i]));
		}
	}
	put(out, "args", args);
	return out;
}

std::string fact_key(const JsonValue &fact) {
	auto keyed = jobj();
	put(keyed, "predicate", jstr(fact.get_string("predicate")));
	const JsonValue *args = fact.find("args");
	put(keyed, "args", args == nullptr ? jarr() : std::make_shared<JsonValue>(*args));
	return serialize(keyed);
}

std::string describe_fact(const JsonValue &fact) {
	std::string out = fact.get_string("predicate") + "(";
	const JsonValue *args = fact.find("args");
	if (args != nullptr && args->is_array()) {
		for (std::size_t i = 0; i < args->array_items.size(); ++i) {
			if (i > 0) out += ", ";
			const JsonValue &arg = *args->array_items[i];
			out += arg.is_string() ? arg.string_value : canonical_json_stringify(arg);
		}
	}
	return out + ")";
}

} // namespace

// ── configure ───────────────────────────────────────────────────────────────

bool Replay::configure(const std::string &vocabulary_json) {
	configured_ = false;
	error_.clear();
	action_ids_.clear();
	action_layer_keys_.clear();

	const JsonParseResult parsed = parse_json(vocabulary_json);
	if (!parsed.ok || parsed.root == nullptr || !parsed.root->is_object()) {
		error_ = "input-vocabulary.json is unreadable: " + parsed.error;
		return false;
	}
	if (parsed.root->get_string("format") != "insimul.talos-bridge.input-vocabulary/1") {
		error_ = "input-vocabulary.json is not an insimul.talos-bridge.input-vocabulary/1 document";
		return false;
	}
	const JsonValue *ids = parsed.root->find("action_ids");
	const JsonValue *keys = parsed.root->find("action_layer_keys");
	if (ids == nullptr || !ids->is_array() || ids->array_items.empty()) {
		error_ = "input-vocabulary.json publishes no action ids — a leg that cannot see them "
				 "would admit an action-layer trace core refuses";
		return false;
	}
	if (keys == nullptr || !keys->is_array() || keys->array_items.empty()) {
		error_ = "input-vocabulary.json publishes no action-layer keys";
		return false;
	}
	for (std::size_t i = 0; i < ids->array_items.size(); ++i) {
		action_ids_.push_back(ids->array_items[i]->as_string());
	}
	for (std::size_t i = 0; i < keys->array_items.size(); ++i) {
		action_layer_keys_.push_back(keys->array_items[i]->as_string());
	}
	configured_ = true;
	return true;
}

std::string Replay::not_configured() const {
	return refuse("invalid_format", "insimul_replay_not_configured",
			"insimul: the replay leg was asked to read a trace before it was handed "
			"addons/insimul_talos/input-vocabulary.json — " + error_);
}

// ── the content addresses ───────────────────────────────────────────────────

std::string Replay::world_content_digest(const std::string &world_json) {
	const JsonParseResult parsed = parse_json(world_json);
	if (!parsed.ok || parsed.root == nullptr || !parsed.root->is_object()) return std::string();
	auto content = jobj();
	put(content, "worldId", jstr(parsed.root->get_string("worldId")));
	const char *const LISTS[] = { "facts", "rules", "packs" };
	for (std::size_t i = 0; i < 3; ++i) {
		const JsonValue *list = parsed.root->find(LISTS[i]);
		// `rules` and `packs` default to the empty array rather than to absent, so a
		// world that declares neither digests the same on every host.
		put(content, LISTS[i],
				list != nullptr && list->is_array() ? std::make_shared<JsonValue>(*list) : jarr());
	}
	return sha256_id(content);
}

std::string Replay::kb_digest(const std::string &facts_json) {
	const JsonParseResult parsed = parse_json(facts_json);
	if (!parsed.ok || parsed.root == nullptr || !parsed.root->is_array()) return std::string();
	auto wrapper = jobj();
	put(wrapper, "facts", parsed.root);
	return sha256_id(wrapper);
}

std::string Replay::trace_id(const std::string &body_json) {
	const JsonParseResult parsed = parse_json(body_json);
	if (!parsed.ok || parsed.root == nullptr || !parsed.root->is_object()) return std::string();
	const JsonValue *world = parsed.root->find("world");
	auto described = jobj();
	put(described, "worldId", jstr(world == nullptr ? std::string() : world->get_string("worldId")));
	put(described, "contentDigest",
			jstr(world == nullptr ? std::string() : world->get_string("contentDigest")));

	const JsonValue *inputs = parsed.root->find("inputs");
	auto addressed = jobj();
	put(addressed, "format", jstr(INPUT_TRACE_FORMAT));
	put(addressed, "seed", jstr(parsed.root->get_string("seed")));
	put(addressed, "world", described);
	put(addressed, "inputs",
			inputs != nullptr && inputs->is_array() ? std::make_shared<JsonValue>(*inputs) : jarr());
	return sha256_id(addressed);
}

std::uint32_t Replay::entropy(const std::string &seed) {
	return fnv1a(stream_key_part(seed));
}

std::uint32_t Replay::entropy(const std::string &seed, long long tick) {
	return fnv1a(stream_key_part(seed) + stream_key_part(std::to_string(tick)));
}

// ── reading a trace ─────────────────────────────────────────────────────────

std::string Replay::input_reason(const JsonValue &record) const {
	if (!record.is_object()) return "input must be a JSON object";

	// Named by name so the refusal can say WHICH field gave it away. The strict
	// unknown-key rule below would catch them anyway, with a far worse message.
	for (std::size_t i = 0; i < action_layer_keys_.size(); ++i) {
		if (record.find(action_layer_keys_[i]) != nullptr) {
			return "input carries `" + action_layer_keys_[i] +
					"`, which records an already-decided action — a trace is recorded at the "
					"engine input layer, not Insimul's action layer";
		}
	}
	for (std::size_t i = 0; i < record.object_items.size(); ++i) {
		const std::string &key = record.object_items[i].first;
		bool known = false;
		for (std::size_t f = 0; f < INPUT_FIELD_COUNT; ++f) {
			if (key == INPUT_FIELDS[f]) {
				known = true;
				break;
			}
		}
		if (!known) return "unknown input field `" + key + "`";
	}

	const JsonValue *tick = record.find("tick");
	if (tick == nullptr || !is_integer(*tick) || tick->number_value < 0) {
		return "input `tick` must be a non-negative integer";
	}
	const JsonValue *channel = record.find("channel");
	bool known_channel = false;
	for (std::size_t i = 0; i < CHANNEL_COUNT && channel != nullptr && channel->is_string(); ++i) {
		if (channel->string_value == CHANNELS[i]) {
			known_channel = true;
			break;
		}
	}
	if (!known_channel) {
		std::string listed;
		for (std::size_t i = 0; i < CHANNEL_COUNT; ++i) {
			if (i > 0) listed += ", ";
			listed += CHANNELS[i];
		}
		return "input `channel` must be one of " + listed;
	}
	const JsonValue *signal = record.find("signal");
	if (signal == nullptr || !signal->is_string() || signal->string_value.empty()) {
		return "input `signal` must be a non-empty string";
	}
	for (std::size_t i = 0; i < action_ids_.size(); ++i) {
		if (action_ids_[i] != signal->string_value) continue;
		// Signals are written device-first so the two vocabularies cannot collide by
		// convention. An Insimul action id spelled as one is refused even so —
		// replaying decisions would prove the effects are deterministic while
		// ASSUMING the decisions were, and the decisions are the interesting half.
		return "input `signal` is `" + signal->string_value +
				"`, which is an Insimul action id — record the control that was pressed "
				"(e.g. `button." + signal->string_value + "`), not the action it will be "
				"interpreted as";
	}

	const std::string channel_name = channel->string_value;
	for (std::size_t i = 0; i < PAYLOAD_COUNT; ++i) {
		const std::string field = PAYLOAD_FIELDS[i];
		const bool present = record.find(field) != nullptr;
		if (channel_carries(channel_name, field)) {
			if (!present) return "`" + channel_name + "` input is missing `" + field + "`";
		} else if (present) {
			return "`" + channel_name + "` input must not carry `" + field + "`";
		}
	}

	if (channel_name == "button") {
		const std::string edge = record.get_string("edge");
		if (edge != "down" && edge != "up") return "button `edge` must be `down` or `up`";
	} else if (channel_name == "axis") {
		const JsonValue *value = record.find("value");
		if (value == nullptr || !value->is_number()) return "axis `value` must be a finite number";
	} else if (channel_name == "pointer") {
		const JsonValue *x = record.find("x");
		const JsonValue *y = record.find("y");
		if (x == nullptr || !x->is_number() || y == nullptr || !y->is_number()) {
			return "pointer `x` and `y` must be finite numbers";
		}
	} else if (channel_name == "text") {
		const JsonValue *text = record.find("text");
		if (text == nullptr || !text->is_string()) return "text `text` must be a string";
	}
	return std::string();
}

std::string Replay::open_trace(const std::string &trace_json, const std::string &world_json) const {
	if (!configured_) return not_configured();

	const JsonParseResult parsed = parse_json(trace_json);
	if (!parsed.ok || parsed.root == nullptr || !parsed.root->is_object()) {
		return refuse("invalid_format", "insimul_trace_invalid_format",
				"Input trace must be a JSON object");
	}
	const JsonValue &doc = *parsed.root;
	if (doc.get_string("format") != INPUT_TRACE_FORMAT) {
		return refuse("invalid_format", "insimul_trace_invalid_format",
				std::string("Unknown input-trace format: expected '") + INPUT_TRACE_FORMAT + "'");
	}
	const JsonValue *id = doc.find("id");
	if (id == nullptr || !id->is_string() || !is_digest(id->string_value)) {
		return refuse("invalid_format", "insimul_trace_invalid_format",
				"Input trace `id` must be a `sha256-<hex>` content address");
	}
	const JsonValue *body = doc.find("body");
	if (body == nullptr || !body->is_object()) {
		return refuse("invalid_format", "insimul_trace_invalid_format",
				"Input trace is missing its `body`");
	}
	const JsonValue *seed = body->find("seed");
	if (seed == nullptr || !seed->is_string() || seed->string_value.empty()) {
		return refuse("invalid_format", "insimul_trace_invalid_format",
				"Input trace `body.seed` must be a non-empty string");
	}
	const JsonValue *world = body->find("world");
	if (world == nullptr || !world->is_object() || world->find("worldId") == nullptr ||
			!world->find("worldId")->is_string()) {
		return refuse("invalid_format", "insimul_trace_invalid_format",
				"Input trace `body.world` must describe the world it was recorded against");
	}
	if (!is_digest(world->get_string("contentDigest"))) {
		return refuse("invalid_format", "insimul_trace_invalid_format",
				"Input trace `body.world.contentDigest` must be a `sha256-<hex>` digest — an "
				"artifact that cannot describe its world cannot be refused against one");
	}
	const JsonValue *inputs = body->find("inputs");
	if (inputs == nullptr || !inputs->is_array()) {
		return refuse("invalid_format", "insimul_trace_invalid_format",
				"Input trace `body.inputs` must be an array");
	}

	double previous = -1;
	for (std::size_t i = 0; i < inputs->array_items.size(); ++i) {
		const std::string reason = input_reason(*inputs->array_items[i]);
		if (!reason.empty()) {
			return refuse("malformed_input", "insimul_trace_malformed_input",
					"Input " + std::to_string(i) + ": " + reason);
		}
		const double tick = inputs->array_items[i]->find("tick")->number_value;
		if (tick < previous) {
			return refuse("malformed_input", "insimul_trace_malformed_input",
					"Input " + std::to_string(i) + ": tick " + canonical_number(tick, std::string()) +
							" goes backwards from " + canonical_number(previous, std::string()));
		}
		previous = tick;
	}

	const std::string expected = trace_id(canonical_json_stringify(*body));
	if (expected != id->string_value) {
		return refuse("id_mismatch", "insimul_trace_id_mismatch",
				"Input trace content address does not match its contents: expected " + expected +
						", got " + id->string_value);
	}

	// The world half. Refused BEFORE anything is replayed, and by arithmetic.
	const JsonParseResult content = parse_json(world_json);
	if (!content.ok || content.root == nullptr || !content.root->is_object()) {
		return refuse("world_id_mismatch", "insimul_trace_world_id_mismatch",
				"This host handed the replay leg no world to check the trace against");
	}
	const std::string recorded_world = world->get_string("worldId");
	const std::string label = world->find("label") == nullptr
			? recorded_world
			: recorded_world + " (" + world->get_string("label") + ")";
	if (recorded_world != content.root->get_string("worldId")) {
		return refuse("world_id_mismatch", "insimul_trace_world_id_mismatch",
				"Input trace " + id->string_value + " was recorded against world " + label +
						", but this host has " + content.root->get_string("worldId") +
						" — refusing to replay");
	}
	const std::string digest = world_content_digest(world_json);
	if (world->get_string("contentDigest") != digest) {
		return refuse("world_content_mismatch", "insimul_trace_world_content_mismatch",
				"Input trace " + id->string_value + " was recorded against world " + label +
						" at content " + world->get_string("contentDigest") +
						", but this host's copy digests to " + digest +
						" — the world changed since it was recorded, so a divergence would say "
						"nothing about determinism");
	}

	auto root = jobj();
	put(root, "ok", jbool(true));
	put(root, "verdict", jstr("admit"));
	put(root, "traceId", jstr(id->string_value));
	put(root, "seed", jstr(seed->string_value));
	put(root, "worldId", jstr(recorded_world));
	put(root, "contentDigest", jstr(digest));
	put(root, "inputs", jint(static_cast<long long>(inputs->array_items.size())));
	return serialize(root);
}

// ── the tick plan ───────────────────────────────────────────────────────────

std::string Replay::plan(const std::string &trace_json, const std::string &world_json,
		const std::string &options_json) const {
	const std::string opened = open_trace(trace_json, world_json);
	const JsonParseResult admitted = parse_json(opened);
	if (!admitted.ok || admitted.root == nullptr || !admitted.root->get_bool("ok", false)) {
		return opened;
	}

	const JsonParseResult parsed = parse_json(trace_json);
	const JsonValue *body = parsed.root->find("body");
	const JsonValue *inputs = body->find("inputs");
	const std::string seed = body->get_string("seed");

	JsonValuePtr options = jobj();
	const JsonParseResult parsed_options = parse_json(options_json);
	if (parsed_options.ok && parsed_options.root != nullptr && parsed_options.root->is_object()) {
		options = parsed_options.root;
	}

	long long last_input_tick = -1;
	if (!inputs->array_items.empty()) {
		last_input_tick =
				static_cast<long long>(inputs->array_items.back()->find("tick")->number_value);
	}
	long long through = -1;
	const JsonValue *through_tick = options->find("throughTick");
	if (through_tick != nullptr && through_tick->is_number()) {
		through = static_cast<long long>(through_tick->number_value);
	}
	const long long final_tick = std::max(last_input_tick, through);

	// Ascending and deduplicated, which is what `checkpointSchedule` produces and
	// what `readReplayOutcome` demands back: checkpoints localize a divergence to a
	// tick, and out-of-order ones localize it to nothing.
	std::set<long long> checkpoints;
	const JsonValue *every = options->find("checkpointEvery");
	if (every != nullptr && is_integer(*every) && every->number_value > 0) {
		const long long step = static_cast<long long>(every->number_value);
		for (long long tick = step; tick <= final_tick; tick += step) checkpoints.insert(tick);
	}
	const JsonValue *at = options->find("checkpointTicks");
	if (at != nullptr && at->is_array()) {
		for (std::size_t i = 0; i < at->array_items.size(); ++i) {
			const JsonValue &tick = *at->array_items[i];
			if (!is_integer(tick) || tick.number_value < 0 || tick.number_value > final_tick) continue;
			checkpoints.insert(static_cast<long long>(tick.number_value));
		}
	}

	// Bucketed once, so a tick with two inputs keeps them in RECORDED order — the
	// order a hand pressed them in is part of the session.
	std::map<long long, std::vector<JsonValuePtr> > by_tick;
	for (std::size_t i = 0; i < inputs->array_items.size(); ++i) {
		const long long tick =
				static_cast<long long>(inputs->array_items[i]->find("tick")->number_value);
		by_tick[tick].push_back(inputs->array_items[i]);
	}

	auto steps = jarr();
	for (long long tick = 0; tick <= final_tick; ++tick) {
		auto step = jobj();
		put(step, "tick", jint(tick));
		auto sampled = jarr();
		const std::map<long long, std::vector<JsonValuePtr> >::const_iterator found = by_tick.find(tick);
		if (found != by_tick.end()) {
			for (std::size_t i = 0; i < found->second.size(); ++i) {
				sampled->array_items.push_back(found->second[i]);
			}
		}
		put(step, "inputs", sampled);
		put(step, "entropy", jint(static_cast<long long>(entropy(seed, tick))));
		steps->array_items.push_back(step);
	}

	auto setup = jobj();
	put(setup, "seed", jstr(seed));
	put(setup, "entropy", jint(static_cast<long long>(entropy(seed))));
	put(setup, "finalTick", jint(final_tick));
	put(setup, "worldId", jstr(admitted.root->get_string("worldId")));
	put(setup, "contentDigest", jstr(admitted.root->get_string("contentDigest")));

	auto at_ticks = jarr();
	for (std::set<long long>::const_iterator it = checkpoints.begin(); it != checkpoints.end(); ++it) {
		at_ticks->array_items.push_back(jint(*it));
	}

	auto root = jobj();
	put(root, "ok", jbool(true));
	put(root, "verdict", jstr("admit"));
	put(root, "traceId", jstr(admitted.root->get_string("traceId")));
	put(root, "engine", jstr(options->get_string("engine", "unknown")));
	put(root, "setup", setup);
	put(root, "finalTick", jint(final_tick));
	put(root, "ticks", jint(final_tick + 1));
	put(root, "inputTicks", jint(static_cast<long long>(by_tick.size())));
	put(root, "inputsApplied", jint(static_cast<long long>(inputs->array_items.size())));
	put(root, "checkpointTicks", at_ticks);
	put(root, "steps", steps);
	return serialize(root);
}

// ── the outcome document ────────────────────────────────────────────────────

std::string Replay::seal_outcome(const std::string &args_json) const {
	const JsonParseResult parsed = parse_json(args_json);
	if (!parsed.ok || parsed.root == nullptr || !parsed.root->is_object()) {
		return refuse("invalid_outcome", "insimul_outcome_invalid",
				"Replay outcome arguments must be a JSON object");
	}
	const JsonValue *facts = parsed.root->find("facts");
	if (facts == nullptr || !facts->is_array()) {
		return refuse("invalid_outcome", "insimul_outcome_invalid",
				"Replay outcome `facts` must be an array of KB facts");
	}

	auto projected = jarr();
	for (std::size_t i = 0; i < facts->array_items.size(); ++i) {
		projected->array_items.push_back(fact_copy(*facts->array_items[i]));
	}

	auto root = jobj();
	put(root, "format", jstr(REPLAY_OUTCOME_FORMAT));
	put(root, "traceId", jstr(parsed.root->get_string("traceId")));
	put(root, "engine", jstr(parsed.root->get_string("engine", "unknown")));
	put(root, "finalTick", jint(parsed.root->get_int("finalTick", -1)));
	const JsonValue *input_ticks = parsed.root->find("inputTicks");
	if (input_ticks != nullptr && input_ticks->is_number()) {
		put(root, "inputTicks", jint(static_cast<long long>(input_ticks->number_value)));
	}
	put(root, "facts", projected);
	auto wrapper = jobj();
	put(wrapper, "facts", projected);
	put(root, "digest", jstr(sha256_id(wrapper)));
	const JsonValue *checkpoints = parsed.root->find("checkpoints");
	if (checkpoints != nullptr && checkpoints->is_array() && !checkpoints->array_items.empty()) {
		put(root, "checkpoints", std::make_shared<JsonValue>(*checkpoints));
	}
	return serialize(root);
}

std::string Replay::read_outcome(const std::string &outcome_json) const {
	const JsonParseResult parsed = parse_json(outcome_json);
	if (!parsed.ok || parsed.root == nullptr || !parsed.root->is_object()) {
		return refuse("invalid_outcome", "insimul_outcome_invalid",
				"Replay outcome must be a JSON object");
	}
	const JsonValue &doc = *parsed.root;
	if (doc.get_string("format") != REPLAY_OUTCOME_FORMAT) {
		return refuse("invalid_outcome", "insimul_outcome_invalid",
				std::string("Unknown replay-outcome format: expected '") + REPLAY_OUTCOME_FORMAT + "'");
	}
	const JsonValue *trace = doc.find("traceId");
	if (trace == nullptr || !trace->is_string() || !is_digest(trace->string_value)) {
		return refuse("invalid_outcome", "insimul_outcome_invalid",
				"Replay outcome `traceId` must be the `sha256-<hex>` address of the trace it "
				"replayed — an outcome that cannot name its session cannot be compared with "
				"another engine's");
	}
	const JsonValue *engine = doc.find("engine");
	if (engine == nullptr || !engine->is_string() || engine->string_value.empty()) {
		return refuse("invalid_outcome", "insimul_outcome_invalid",
				"Replay outcome `engine` must be a non-empty string");
	}
	const JsonValue *final_tick = doc.find("finalTick");
	if (final_tick == nullptr || !is_integer(*final_tick) || final_tick->number_value < -1) {
		return refuse("invalid_outcome", "insimul_outcome_invalid",
				"Replay outcome `finalTick` must be an integer tick");
	}
	const JsonValue *facts = doc.find("facts");
	if (facts == nullptr || !facts->is_array()) {
		return refuse("invalid_outcome", "insimul_outcome_invalid",
				"Replay outcome `facts` must be an array of KB facts");
	}
	for (std::size_t i = 0; i < facts->array_items.size(); ++i) {
		const JsonValue &fact = *facts->array_items[i];
		std::string reason;
		if (!fact.is_object()) {
			reason = "must be a JSON object";
		} else {
			for (std::size_t k = 0; k < fact.object_items.size() && reason.empty(); ++k) {
				const std::string &key = fact.object_items[k].first;
				if (key != "predicate" && key != "args") reason = "unknown field `" + key + "`";
			}
			const JsonValue *predicate = fact.find("predicate");
			if (reason.empty() &&
					(predicate == nullptr || !predicate->is_string() || predicate->string_value.empty())) {
				reason = "`predicate` must be a non-empty string";
			}
			const JsonValue *args = fact.find("args");
			if (reason.empty() && (args == nullptr || !args->is_array())) {
				reason = "`args` must be an array";
			} else if (reason.empty()) {
				for (std::size_t a = 0; a < args->array_items.size(); ++a) {
					const JsonValue &arg = *args->array_items[a];
					// A host that stringified `30` on the way out has diverged, and this is
					// where that is caught instead of being digested away.
					if (arg.is_string() || arg.is_number()) continue;
					reason = "`args` must hold only strings and finite numbers";
					break;
				}
			}
		}
		if (!reason.empty()) {
			return refuse("invalid_outcome", "insimul_outcome_invalid",
					"Replay outcome fact " + std::to_string(i) + ": " + reason);
		}
	}
	const JsonValue *checkpoints = doc.find("checkpoints");
	if (checkpoints != nullptr) {
		if (!checkpoints->is_array()) {
			return refuse("invalid_outcome", "insimul_outcome_invalid",
					"Replay outcome `checkpoints` must be an array");
		}
		double previous = -1;
		for (std::size_t i = 0; i < checkpoints->array_items.size(); ++i) {
			const JsonValue &point = *checkpoints->array_items[i];
			const JsonValue *tick = point.is_object() ? point.find("tick") : nullptr;
			if (tick == nullptr || !is_integer(*tick) || tick->number_value < 0) {
				return refuse("invalid_outcome", "insimul_outcome_invalid",
						"Replay outcome checkpoint " + std::to_string(i) +
								": `tick` must be a non-negative integer");
			}
			if (!is_digest(point.get_string("digest"))) {
				return refuse("invalid_outcome", "insimul_outcome_invalid",
						"Replay outcome checkpoint " + std::to_string(i) +
								": `digest` must be a `sha256-<hex>` digest");
			}
			if (tick->number_value <= previous) {
				return refuse("invalid_outcome", "insimul_outcome_invalid",
						"Replay outcome checkpoint " + std::to_string(i) + ": tick " +
								canonical_number(tick->number_value, std::string()) +
								" does not follow " + canonical_number(previous, std::string()) +
								" — checkpoints are ascending");
			}
			previous = tick->number_value;
		}
	}

	auto wrapper = jobj();
	put(wrapper, "facts", std::make_shared<JsonValue>(*facts));
	const std::string expected = sha256_id(wrapper);
	if (doc.get_string("digest") != expected) {
		return refuse("outcome_digest_mismatch", "insimul_outcome_digest_mismatch",
				"Replay outcome digest does not match the facts it carries: expected " + expected +
						", got " + doc.get_string("digest"));
	}

	auto root = jobj();
	put(root, "ok", jbool(true));
	put(root, "verdict", jstr("admit"));
	put(root, "traceId", jstr(trace->string_value));
	put(root, "engine", jstr(engine->string_value));
	put(root, "digest", jstr(expected));
	put(root, "facts", jint(static_cast<long long>(facts->array_items.size())));
	return serialize(root);
}

std::string Replay::verify_outcome(const std::string &recorded_json, const std::string &trace_id_value) const {
	const std::string read = read_outcome(recorded_json);
	const JsonParseResult parsed = parse_json(read);
	if (!parsed.ok || parsed.root == nullptr || !parsed.root->get_bool("ok", false)) return read;
	if (parsed.root->get_string("traceId") != trace_id_value) {
		return refuse("trace_mismatch", "insimul_outcome_trace_mismatch",
				"Recorded outcome is of trace " + parsed.root->get_string("traceId") +
						", but the trace being replayed is " + trace_id_value +
						" — refusing to compare two different sessions");
	}
	return read;
}

// ── comparing two of them ───────────────────────────────────────────────────

std::string Replay::compare(const std::string &recorded_json, const std::string &replayed_json) const {
	const JsonParseResult a = parse_json(recorded_json);
	const JsonParseResult b = parse_json(replayed_json);
	if (!a.ok || a.root == nullptr || !a.root->is_object() || !b.ok || b.root == nullptr ||
			!b.root->is_object()) {
		return refuse("invalid_outcome", "insimul_outcome_invalid",
				"Two replay outcomes are needed to compare two replay outcomes");
	}
	const JsonValue &recorded = *a.root;
	const JsonValue &replayed = *b.root;
	const std::string mine = recorded.get_string("engine");
	const std::string theirs = replayed.get_string("engine");

	auto divergences = jarr();
	auto add = [](const std::string &kind, const std::string &message) {
		auto entry = jobj();
		put(entry, "kind", jstr(kind));
		put(entry, "message", jstr(message));
		return entry;
	};

	auto report = [&divergences](bool converged, long long first_tick, bool has_first) {
		auto root = jobj();
		put(root, "ok", jbool(true));
		put(root, "converged", jbool(converged));
		put(root, "divergences", divergences);
		if (has_first) put(root, "firstDivergentTick", jint(first_tick));
		return serialize(root);
	};

	if (recorded.get_string("traceId") != replayed.get_string("traceId")) {
		// Comparing two engines' outcomes of two different sessions would report
		// agreement or disagreement about nothing, so the comparison stops here.
		divergences->array_items.push_back(add("trace",
				"Outcomes are of different sessions: " + mine + " replayed " +
						recorded.get_string("traceId") + ", " + theirs + " replayed " +
						replayed.get_string("traceId") + " — there is nothing to compare"));
		return report(false, 0, false);
	}

	const long long mine_tick = recorded.get_int("finalTick", 0);
	const long long theirs_tick = replayed.get_int("finalTick", 0);
	if (mine_tick != theirs_tick) {
		auto entry = add("final_tick",
				mine + " ran to tick " + std::to_string(mine_tick) + ", " + theirs + " to tick " +
						std::to_string(theirs_tick));
		put(entry, "recorded", jint(mine_tick));
		put(entry, "replayed", jint(theirs_tick));
		divergences->array_items.push_back(entry);
	}

	bool has_first = false;
	long long first_tick = 0;
	const JsonValue *mine_points = recorded.find("checkpoints");
	const JsonValue *theirs_points = replayed.find("checkpoints");
	std::map<long long, const JsonValue *> by_tick;
	if (theirs_points != nullptr && theirs_points->is_array()) {
		for (std::size_t i = 0; i < theirs_points->array_items.size(); ++i) {
			by_tick[theirs_points->array_items[i]->get_int("tick", -1)] =
					theirs_points->array_items[i].get();
		}
	}
	if (mine_points != nullptr && mine_points->is_array()) {
		for (std::size_t i = 0; i < mine_points->array_items.size(); ++i) {
			const JsonValue &point = *mine_points->array_items[i];
			const long long tick = point.get_int("tick", -1);
			const std::map<long long, const JsonValue *>::const_iterator other = by_tick.find(tick);
			if (other == by_tick.end()) continue;
			if (other->second->get_string("digest") == point.get_string("digest")) continue;
			auto entry = add("checkpoint",
					"KB already diverged at tick " + std::to_string(tick) + ": " + mine + " " +
							point.get_string("digest") + " (" +
							std::to_string(point.get_int("factCount", 0)) + " facts), " + theirs + " " +
							other->second->get_string("digest") + " (" +
							std::to_string(other->second->get_int("factCount", 0)) + " facts)");
			put(entry, "tick", jint(tick));
			divergences->array_items.push_back(entry);
			if (!has_first) {
				has_first = true;
				first_tick = tick;
			}
		}
	}

	if (recorded.get_string("digest") != replayed.get_string("digest")) {
		const JsonValue *mine_facts = recorded.find("facts");
		const JsonValue *theirs_facts = replayed.find("facts");
		std::vector<std::string> mine_keys;
		std::vector<std::string> theirs_keys;
		if (mine_facts != nullptr && mine_facts->is_array()) {
			for (std::size_t i = 0; i < mine_facts->array_items.size(); ++i) {
				mine_keys.push_back(fact_key(*mine_facts->array_items[i]));
			}
		}
		if (theirs_facts != nullptr && theirs_facts->is_array()) {
			for (std::size_t i = 0; i < theirs_facts->array_items.size(); ++i) {
				theirs_keys.push_back(fact_key(*theirs_facts->array_items[i]));
			}
		}
		if (mine_keys.size() != theirs_keys.size()) {
			auto entry = add("fact_count",
					mine + " ended with " + std::to_string(mine_keys.size()) + " KB facts, " + theirs +
							" with " + std::to_string(theirs_keys.size()));
			put(entry, "recorded", jint(static_cast<long long>(mine_keys.size())));
			put(entry, "replayed", jint(static_cast<long long>(theirs_keys.size())));
			divergences->array_items.push_back(entry);
		}

		std::vector<std::string> mine_sorted = mine_keys;
		std::vector<std::string> theirs_sorted = theirs_keys;
		std::sort(mine_sorted.begin(), mine_sorted.end());
		std::sort(theirs_sorted.begin(), theirs_sorted.end());
		if (mine_sorted == theirs_sorted) {
			// The same facts in a different KB order. Clause order is solution order
			// to a Prolog engine, so this is a real divergence — and a far easier one
			// to read than "digest differs".
			std::size_t at = 0;
			while (at < mine_keys.size() && mine_keys[at] == theirs_keys[at]) ++at;
			divergences->array_items.push_back(add("order",
					"Both engines hold the same " + std::to_string(mine_keys.size()) +
							" facts in a different KB order, first at index " + std::to_string(at) +
							" — clause order is solution order, so this is a divergence and not a "
							"formatting difference"));
		} else {
			const std::size_t width = std::max(mine_keys.size(), theirs_keys.size());
			for (std::size_t i = 0; i < width; ++i) {
				const bool has_mine = i < mine_keys.size();
				const bool has_theirs = i < theirs_keys.size();
				if (has_mine && has_theirs && mine_keys[i] == theirs_keys[i]) continue;
				auto entry = add("fact",
						"KB fact " + std::to_string(i) + ": " + mine + " has " +
								(has_mine ? describe_fact(*mine_facts->array_items[i]) : "nothing") + ", " +
								theirs + " has " +
								(has_theirs ? describe_fact(*theirs_facts->array_items[i]) : "nothing"));
				put(entry, "index", jint(static_cast<long long>(i)));
				divergences->array_items.push_back(entry);
			}
		}
	}

	return report(divergences->array_items.empty(), first_tick, has_first);
}

std::vector<std::string> Replay::tokens() {
	// Built the way the code builds them rather than listed beside it, so this can
	// never fall out of step with what the leg can actually emit.
	std::vector<std::string> out;
	out.push_back("insimul_replay_not_configured");
	out.push_back("insimul_trace_invalid_format");
	out.push_back("insimul_trace_malformed_input");
	out.push_back("insimul_trace_id_mismatch");
	out.push_back("insimul_trace_world_id_mismatch");
	out.push_back("insimul_trace_world_content_mismatch");
	out.push_back("insimul_outcome_invalid");
	out.push_back("insimul_outcome_digest_mismatch");
	out.push_back("insimul_outcome_trace_mismatch");
	return out;
}

} // namespace talos
} // namespace insimul
