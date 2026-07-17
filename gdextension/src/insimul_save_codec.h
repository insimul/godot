// insimul_save_codec.h — the Godot-facing GDExtension class for the portable
// save-file codec (US-GC2).
//
// InsimulSaveCodec (RefCounted) wraps the dependency-free save core (save_file.h)
// and exposes canonical serialization, SHA-256 integrity, envelope build, version-
// gated load + migration, and KB snapshot/restore to GDScript. The exactness that
// matters — canonical key-sorted JSON + SHA-256 byte-identical to
// packages/core/src/save-envelope.ts — lives ENTIRELY in the host-tested core, so
// GDScript never re-implements it (Godot's JSON.stringify would not match).
//
// Named InsimulSaveCodec (not InsimulSaveFile) to avoid colliding with the
// generated DTO class_name InsimulSaveFile in addons/insimul/generated/.
//
// BUILD NOTE: requires godot-cpp headers. Not available in the Ralph harness (no
// scons/godot/godot-cpp), so this file is *syntax-gated* only — the real gate is
// the host test (test/run_save_tests.sh). See README "Structural fallback".

#ifndef INSIMUL_GODOT_INSIMUL_SAVE_CODEC_H
#define INSIMUL_GODOT_INSIMUL_SAVE_CODEC_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include "save_file.h"

namespace godot {

class InsimulSaveCodec : public RefCounted {
	GDCLASS(InsimulSaveCodec, RefCounted)

public:
	InsimulSaveCodec() = default;
	~InsimulSaveCodec() = default;

	// Parse + version-gate + migrate a SaveFile JSON document. Returns false and
	// sets last_error() on malformed JSON or a future/too-old version.
	bool load(const String &json);

	// Build a fresh, current-version SaveFile around a world-snapshot document.
	bool new_game(const String &world_snapshot_json, const String &id, const String &user_id,
			const String &world_id, const String &name, int slot_index, const String &created_at);

	bool is_loaded() const;
	int version() const;

	// Canonical (key-sorted, minified) JSON of the current SaveFile.
	String serialize_canonical() const;

	// SHA-256 hex of the canonical SaveFile — byte-compatible with TS.
	String compute_integrity() const;

	// SHA-256 hex of the worldSnapshot alone — stable across a currentState-only
	// mutation (the world-hash-stability parity check).
	String world_snapshot_integrity() const;

	// Canonical export Envelope JSON wrapping the current SaveFile + its integrity.
	String build_envelope(const String &insimul_version, const String &exported_at) const;

	// KB snapshot/restore into currentState.prologFacts. Each fact is a
	// Dictionary { "predicate": String, "args": Array[String|int|float] }.
	void snapshot_facts(const Array &facts);
	Array restore_facts() const;

	String last_error() const;

protected:
	static void _bind_methods();

private:
	insimul::SaveSystem save_;
	String last_error_;
};

} // namespace godot

#endif // INSIMUL_GODOT_INSIMUL_SAVE_CODEC_H
