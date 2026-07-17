// insimul_prolog.h — the Godot-facing GDExtension class.
//
// InsimulProlog (RefCounted) wraps libinsimul's C ABI (vendor/insimul/insimul.h)
// and exposes a curated Prolog surface to GDScript. All non-trivial term decoding
// is delegated to the dependency-free marshalling core (prolog_value.h) so it can
// be host-tested; this file only owns the KB handle and maps PrologValue ->
// godot::Variant.
//
// BUILD NOTE: this file requires godot-cpp headers and links libinsimul. Neither
// is available in the Ralph harness (no scons/godot/godot-cpp, libinsimul not yet
// built), so it is *syntax-gated* only — see README "Structural fallback".

#ifndef INSIMUL_GODOT_INSIMUL_PROLOG_H
#define INSIMUL_GODOT_INSIMUL_PROLOG_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

struct insimul_kb; // from vendor/insimul/insimul.h

namespace godot {

class InsimulProlog : public RefCounted {
	GDCLASS(InsimulProlog, RefCounted)

public:
	InsimulProlog();
	~InsimulProlog();

	// Load a Prolog program (clauses + directives). Returns false on error;
	// last_error() then holds the reason.
	bool consult(const String &source);

	// Assert / retract a single fact or clause. Returns false on error.
	bool assert_fact(const String &fact);
	bool retract_fact(const String &fact);

	// Run `goal`, returning Array[Dictionary] — one Dictionary per solution,
	// mapping each query variable name (String) to its bound term (Variant:
	// String | int | float | bool | Array | Dictionary{functor,args}). An empty
	// Array means the goal failed; a single empty Dictionary means it succeeded
	// with no variable bindings.
	Array query(const String &goal);

	// Serialize / restore the dynamic-fact set (save-file bridge). snapshot()
	// returns canonical Prolog text; restore() replaces the dynamic set.
	String snapshot();
	bool restore(const String &image);

	// Human-readable message for the most recent failure ("" if none).
	String last_error() const;

protected:
	static void _bind_methods();

private:
	insimul_kb *kb_ = nullptr;

	// Decode one libinsimul binding-set JSON string into a Godot Dictionary.
	// Returns false if the string is malformed (recorded via the marshaller).
	static bool binding_json_to_dictionary(const char *json, Dictionary &out);
};

} // namespace godot

#endif // INSIMUL_GODOT_INSIMUL_PROLOG_H
