// talos_replay.h — the replay leg of `insimul-talos-bridge`: the part that turns
// tasklist 180's portable input-trace artifact into a KB state a four-way
// comparison can diff (TALOS_INSIMUL_BRIDGE.md §8.6, tasklist 183 US-2).
//
// WHAT THIS IS FOR. §8's four-way gameplay conformance is a claim about *four
// engines given the same inputs reaching the same world state*, and §8.6 settles
// how one recorded session reaches four engines: not over TBP — `play_input_trace`
// refuses a foreign-session `trace_ref` by design (Talos RISK-60, open) — but as
// an ARTIFACT. Core ships it: `insimul-input-trace-v1` is `(seed, world content,
// the raw inputs that were pressed)`, content-addressed, and
// `insimul-replay-outcome-v1` is what a session came to, in KB facts. This file
// is the Godot leg's half: read the artifact, refuse it when it does not belong
// here, plan the tick sequence, and seal the outcome.
//
// WHY IT IS A PORT AND NOT AN ADOPTION, which is this project's default. Core's
// replay module opens with `import { createHash } from 'node:crypto'`, and
// `gdextension/corebridge/js/host-crypto.js` makes that throw on purpose — "the
// adopted surface does not hash", and the fix it names for a slice that DOES is
// "route it to libinsimul/the C host rather than grow a second SHA-256 here."
// The C host hash already exists and is already the pinned one: `sha256.cpp` is
// byte-compatible with Node's, and `canonical_json.cpp` is byte-compatible with
// `canonicalJSONStringify`. So the content address costs nothing here and would
// cost a second SHA-256 in the bundle.
//
// AND THE PORT IS PINNED TO CORE'S OWN ANSWERS. `tools/vendor-replay-fixtures.mjs`
// runs core's real module under Node and writes down what it said — the ids it
// minted, the documents it refused and with which code, the entropy it derived
// per tick, and the outcome its own driver produced over a declared world
// program. `test/test_talos_replay.cpp` replays every one of them. A leg that
// digests differently fails there rather than in a four-way run, where it would
// read as Godot diverging from Babylon.
//
// READINGS IN, ORDERS OUT — the same shape as the mechanic host and the rest of
// this bridge. There is no `IReplayWorld` here: core's driver calls back into the
// world once per tick and the C ABI has no callbacks, so instead this file hands
// out the whole tick PLAN as one document and the addon carries it out against
// the live knowledge base. Nothing here touches libinsimul or godot-cpp.

#ifndef INSIMUL_GODOT_TALOS_REPLAY_H
#define INSIMUL_GODOT_TALOS_REPLAY_H

#include "json_value.h"

#include <cstdint>
#include <string>
#include <vector>

namespace insimul {
namespace talos {

/// The two document tags, from core's `input-trace.ts` / `kb-outcome.ts`.
extern const char *const INPUT_TRACE_FORMAT;
extern const char *const REPLAY_OUTCOME_FORMAT;

/// The replay leg. Configured from the addon's shipped input vocabulary, which
/// is what makes "a signal may not name an action" checkable here at all — the
/// action ids are core's and are mirrored, never compiled in.
class Replay {
public:
	/// Hand the leg `addons/insimul_talos/input-vocabulary.json`. Returns false —
	/// and leaves `error()` set — when it is missing or is not that document,
	/// because a leg that could not refuse an action-layer trace would admit one
	/// core refuses, which is the divergence §8.7's rider exists to prevent.
	bool configure(const std::string &vocabulary_json);
	bool configured() const { return configured_; }
	const std::string &error() const { return error_; }

	// ── The content addresses. Byte-identical to core's, and that is the whole
	// claim: an identical session must mint an identical id in any process. ──

	/// `sha256-…` over `{worldId, facts, rules, packs}`. Authored order is kept:
	/// clause order is solution order to a Prolog engine, so two KBs holding the
	/// same facts in a different order are two different worlds.
	static std::string world_content_digest(const std::string &world_json);

	/// `sha256-…` over `{facts}`, in KB order, for the same reason.
	static std::string kb_digest(const std::string &facts_json);

	/// `sha256-…` over `{format, seed, world:{worldId, contentDigest}, inputs}`.
	/// The world's label and the artifact's provenance are excluded on purpose:
	/// the id answers "is this the same session", not "is this the same file".
	static std::string trace_id(const std::string &body_json);

	/// FNV-1a over the length-prefixed key `derivedStream` mixes — one algorithm
	/// for four engines. A world seeds its own PRNG from this `uint32`, so a leg
	/// that derived a different one diverges in the KB for a reason that has
	/// nothing to do with its mechanics.
	static std::uint32_t entropy(const std::string &seed);
	static std::uint32_t entropy(const std::string &seed, long long tick);

	// ── Reading an artifact, and refusing it ──

	/// Validate an untrusted trace and check it against the world this host has.
	/// Refuses BEFORE anything is replayed: a divergence caused by a world that
	/// changed since recording says nothing about determinism, and is the one
	/// failure worth catching by arithmetic.
	std::string open_trace(const std::string &trace_json, const std::string &world_json) const;

	/// The tick PLAN: every tick from 0 to the last, the raw inputs sampled on
	/// it, and its entropy — plus the ticks at which the KB should be polled.
	///
	/// Every tick, not every input. Skipping the empty ones would replay a
	/// different session: a routine, a radiant beat and a Prolog re-derivation all
	/// happen on ticks nobody touched a control, and those decisions are exactly
	/// the half an input-layer trace exists to put under test.
	std::string plan(const std::string &trace_json, const std::string &world_json,
			const std::string &options_json) const;

	/// Seal `{traceId, engine, finalTick, inputTicks?, facts, checkpoints?}` into
	/// an outcome document, computing its digest.
	std::string seal_outcome(const std::string &args_json) const;

	/// Validate an untrusted outcome document, including its self-consistency: an
	/// outcome whose digest does not describe its own facts cannot be compared
	/// with anything, because whichever half a consumer believed would be the
	/// half that disagrees with the document.
	std::string read_outcome(const std::string &outcome_json) const;

	/// `verifyReplay`'s guard: an outcome that arrived from another engine is read
	/// and checked against its own digest before it is believed, and its `traceId`
	/// must be the trace actually being replayed. Comparing two engines' outcomes
	/// of two different sessions would report agreement about nothing.
	std::string verify_outcome(const std::string &recorded_json, const std::string &trace_id) const;

	/// Compare two engines' outcomes of the same trace. Symmetric in everything
	/// but the names it prints; reports ALL the ways they differ, because "the KB
	/// diverged" is a bug report and the useful version of it names the facts.
	std::string compare(const std::string &recorded_json, const std::string &replayed_json) const;

	/// Every why-not token this leg can emit. The gate checks each one against the
	/// contract's published vocabulary.
	static std::vector<std::string> tokens();

private:
	bool configured_ = false;
	std::string error_;
	std::vector<std::string> action_ids_;
	std::vector<std::string> action_layer_keys_;

	/// `null` when the record is a well-formed engine input; otherwise the reason,
	/// worded as core words it.
	std::string input_reason(const JsonValue &record) const;
	std::string not_configured() const;
};

} // namespace talos
} // namespace insimul

#endif // INSIMUL_GODOT_TALOS_REPLAY_H
