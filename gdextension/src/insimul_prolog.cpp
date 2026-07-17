// insimul_prolog.cpp — Godot-facing wrapper implementation.
//
// Syntax-gated only (needs godot-cpp + libinsimul). The PrologValue -> Variant
// adapter here is the ONLY marshalling logic not covered by the host tests, and
// it is a mechanical 1:1 of the kinds validated in test/test_marshalling.cpp.

#include "insimul_prolog.h"

#include "prolog_value.h"
#include "../vendor/insimul/insimul.h"

#include <godot_cpp/core/class_db.hpp>

#include <string>

using namespace godot;

// Convert a decoded PrologValue term into a Godot Variant. Mirrors the kind
// coverage of the host marshalling tests (atom/int/float/bool/null/list/compound).
static Variant prolog_value_to_variant(const insimul::PrologValue &v) {
	switch (v.kind) {
		case insimul::PrologKind::Atom:
			return String(v.text.c_str());
		case insimul::PrologKind::Int:
			return (int64_t)v.int_value;
		case insimul::PrologKind::Float:
			return (double)v.float_value;
		case insimul::PrologKind::Bool:
			return v.bool_value;
		case insimul::PrologKind::Null:
			return Variant(); // nil
		case insimul::PrologKind::List: {
			Array arr;
			for (const auto &item : v.items) {
				arr.push_back(prolog_value_to_variant(item));
			}
			return arr;
		}
		case insimul::PrologKind::Compound: {
			Dictionary d;
			d["functor"] = String(v.text.c_str());
			Array args;
			for (const auto &item : v.items) {
				args.push_back(prolog_value_to_variant(item));
			}
			d["args"] = args;
			return d;
		}
	}
	return Variant();
}

InsimulProlog::InsimulProlog() {
	kb_ = insimul_kb_create();
}

InsimulProlog::~InsimulProlog() {
	if (kb_) {
		insimul_kb_destroy(kb_);
		kb_ = nullptr;
	}
}

bool InsimulProlog::consult(const String &source) {
	if (!kb_) {
		return false;
	}
	return insimul_kb_consult(kb_, source.utf8().get_data()) != 0;
}

bool InsimulProlog::assert_fact(const String &fact) {
	if (!kb_) {
		return false;
	}
	return insimul_kb_assert(kb_, fact.utf8().get_data()) != 0;
}

bool InsimulProlog::retract_fact(const String &fact) {
	if (!kb_) {
		return false;
	}
	return insimul_kb_retract(kb_, fact.utf8().get_data()) != 0;
}

bool InsimulProlog::binding_json_to_dictionary(const char *json, Dictionary &out) {
	insimul::ParseResult r = insimul::parse_binding_set(std::string(json));
	if (!r.ok) {
		return false;
	}
	for (const auto &b : r.bindings) {
		out[String(b.first.c_str())] = prolog_value_to_variant(b.second);
	}
	return true;
}

Array InsimulProlog::query(const String &goal) {
	Array results;
	if (!kb_) {
		return results;
	}
	insimul_query *q = insimul_query_start(kb_, goal.utf8().get_data());
	if (!q) {
		return results; // parse error; caller inspects last_error()
	}
	for (const char *json = insimul_query_next(q); json != nullptr;
			json = insimul_query_next(q)) {
		Dictionary solution;
		if (binding_json_to_dictionary(json, solution)) {
			results.push_back(solution);
		}
	}
	insimul_query_stop(q);
	return results;
}

String InsimulProlog::snapshot() {
	if (!kb_) {
		return String();
	}
	const char *image = insimul_kb_snapshot(kb_);
	return image ? String(image) : String();
}

bool InsimulProlog::restore(const String &image) {
	if (!kb_) {
		return false;
	}
	return insimul_kb_restore(kb_, image.utf8().get_data()) != 0;
}

String InsimulProlog::last_error() const {
	if (!kb_) {
		return String("knowledge base not initialized");
	}
	const char *err = insimul_last_error(kb_);
	return err ? String(err) : String();
}

void InsimulProlog::_bind_methods() {
	ClassDB::bind_method(D_METHOD("consult", "source"), &InsimulProlog::consult);
	ClassDB::bind_method(D_METHOD("assert_fact", "fact"), &InsimulProlog::assert_fact);
	ClassDB::bind_method(D_METHOD("retract_fact", "fact"), &InsimulProlog::retract_fact);
	ClassDB::bind_method(D_METHOD("query", "goal"), &InsimulProlog::query);
	ClassDB::bind_method(D_METHOD("snapshot"), &InsimulProlog::snapshot);
	ClassDB::bind_method(D_METHOD("restore", "image"), &InsimulProlog::restore);
	ClassDB::bind_method(D_METHOD("last_error"), &InsimulProlog::last_error);
}
