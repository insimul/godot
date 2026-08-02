// insimul_core.h — the Godot-facing wrapper for `@insimul/core`.
//
// InsimulCore (RefCounted) is to libinsimulcore what InsimulProlog is to
// libinsimul: a thin handle-owning wrapper, deliberately shaped the same way
// (create in the constructor, `last_error()` for the reason a call returned
// nothing, no engine types beyond the boundary).
//
// THE SURFACE IS JSON IN / JSON OUT, ON PURPOSE. It would be friendlier to take
// a Dictionary and hand back a Dictionary, and that is exactly what this class
// must NOT do: US-2 of tasklist 100 requires that engine types are translated to
// core's shapes in ONE place, and that place is
// addons/insimul/runtime/radiant_source.gd (see RUNTIME_CORE_ADOPTION.md §5.4).
// If this class also converted, there would be two translation sites that could
// disagree, and the C++ one would be the invisible one. So this class marshals
// bytes and nothing else.
//
// BUILD NOTE: needs godot-cpp and links libinsimulcore (corebridge/), which in
// turn links libinsimul. Like the rest of src/, it is syntax-gated in this
// harness rather than compiled; what actually runs the adopted code path here is
// test/run_radiant_tests.sh, which drives the same C ABI without Godot.

#ifndef INSIMUL_GODOT_INSIMUL_CORE_H
#define INSIMUL_GODOT_INSIMUL_CORE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>

struct insimul_core; // from corebridge/include/insimulcore.h

namespace godot {

class InsimulCore : public RefCounted {
	GDCLASS(InsimulCore, RefCounted)

public:
	InsimulCore();
	~InsimulCore();

	// True when the core runtime started. A false here means the plugin was
	// built without libinsimulcore, or the vendored bundle failed to evaluate;
	// callers should fall back rather than treat it as a per-call error.
	bool is_available() const { return core_ != nullptr; }

	// Call an adopted core method. `args_json` is a JSON object string ("" for
	// no arguments); the return is the result as a JSON string, or "" on
	// failure, in which case last_error() holds the reason.
	//
	// Cost: one JSON encode + decode per call, plus core's own work. Call it
	// when a decision is needed (a director tick, a craft attempt) — NEVER from
	// _process/_physics_process. See insimulcore.h, "THE ONE HARD RULE".
	String call_json(const String &method, const String &args_json);

	// "<abi> (quickjs <pin>, core <commit>)" — quote this in a bug report.
	String get_version() const;

	// Reason for the most recent failure, or "" if none.
	String last_error() const;

protected:
	static void _bind_methods();

private:
	insimul_core *core_ = nullptr;
	String last_error_;
};

} // namespace godot

#endif // INSIMUL_GODOT_INSIMUL_CORE_H
