// prolog_value.h — engine-agnostic marshalling core for the Insimul GDExtension.
//
// This header is deliberately FREE of both godot-cpp and libinsimul: it models a
// Prolog term as a small tagged variant (PrologValue) and parses libinsimul's
// query-binding JSON format into it. Keeping it dependency-free is what makes the
// marshalling layer host-testable under a plain clang toolchain (see test/), the
// same discipline the Unreal wrapper (tools/verify-unreal) uses.
//
// The libinsimul binding-set JSON format (see libinsimul US-LI2 / docs/consuming.md):
//   insimul_query_next() yields ONE solution as a JSON object mapping each query
//   variable name to a Prolog term value:
//     { "Var": <term>, ... }              // one solution; {} == success, no bindings
//   Terms map as:
//     atom            -> JSON string      -> PrologValue::Atom
//     integer         -> JSON int         -> PrologValue::Int
//     float           -> JSON float       -> PrologValue::Float
//     list            -> JSON array       -> PrologValue::List
//     compound f(a,b) -> {"functor":"f","args":[<term>,...]} -> PrologValue::Compound
//     true / false    -> JSON bool        -> PrologValue::Bool
//     null            -> JSON null        -> PrologValue::Null
//
// insimul_prolog.cpp (the godot-cpp layer) converts PrologValue -> godot::Variant.

#ifndef INSIMUL_GODOT_PROLOG_VALUE_H
#define INSIMUL_GODOT_PROLOG_VALUE_H

#include <cstdint>
#include <string>
#include <utility>
#include <vector>

namespace insimul {

enum class PrologKind {
	Atom,      // string atom              -> Godot String
	Int,       // 64-bit integer           -> Godot int
	Float,     // double                   -> Godot float
	Bool,      // true / false             -> Godot bool
	Null,      // null                     -> Godot nil
	List,      // ordered terms            -> Godot Array
	Compound,  // functor + arg terms      -> Godot Dictionary{functor,args}
};

struct PrologValue {
	PrologKind kind = PrologKind::Null;
	std::string text;                 // Atom text, or Compound functor
	int64_t int_value = 0;            // Int
	double float_value = 0.0;         // Float
	bool bool_value = false;          // Bool
	std::vector<PrologValue> items;   // List elements, or Compound args

	static PrologValue atom(std::string a) {
		PrologValue v;
		v.kind = PrologKind::Atom;
		v.text = std::move(a);
		return v;
	}
	static PrologValue integer(int64_t n) {
		PrologValue v;
		v.kind = PrologKind::Int;
		v.int_value = n;
		return v;
	}
	static PrologValue real(double d) {
		PrologValue v;
		v.kind = PrologKind::Float;
		v.float_value = d;
		return v;
	}
	static PrologValue boolean(bool b) {
		PrologValue v;
		v.kind = PrologKind::Bool;
		v.bool_value = b;
		return v;
	}
	static PrologValue null() { return PrologValue(); }
	static PrologValue list(std::vector<PrologValue> xs) {
		PrologValue v;
		v.kind = PrologKind::List;
		v.items = std::move(xs);
		return v;
	}
	static PrologValue compound(std::string functor, std::vector<PrologValue> args) {
		PrologValue v;
		v.kind = PrologKind::Compound;
		v.text = std::move(functor);
		v.items = std::move(args);
		return v;
	}

	bool operator==(const PrologValue &o) const;
	bool operator!=(const PrologValue &o) const { return !(*this == o); }
};

// A single query solution: an ordered list of (variable name, bound term) pairs.
// Order preserves libinsimul's emission order so debug output is stable; equality
// comparisons in tests treat it as an unordered set of pairs.
using Binding = std::pair<std::string, PrologValue>;
using BindingSet = std::vector<Binding>;

// Outcome of parsing one binding-set JSON string.
struct ParseResult {
	bool ok = false;
	BindingSet bindings;    // valid iff ok
	std::string error;      // human-readable reason iff !ok
};

// Parse ONE libinsimul solution JSON object (e.g. `{"X":"bob"}`, `{}`) into a
// BindingSet. The top level MUST be a JSON object; every value is decoded as a
// Prolog term. Returns ok=false with a reason on malformed JSON or a non-object
// top level. A NULL/empty string is treated as "no more solutions" by callers, not
// here — pass only non-empty solution strings.
ParseResult parse_binding_set(const std::string &json);

// Debug rendering of a term (canonical Prolog-ish text), used by the host test
// harness and optional GDExtension logging. Not a serialization format.
std::string to_debug_string(const PrologValue &v);
std::string to_debug_string(const BindingSet &b);

} // namespace insimul

#endif // INSIMUL_GODOT_PROLOG_VALUE_H
