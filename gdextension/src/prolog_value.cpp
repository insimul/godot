// prolog_value.cpp — implementation of the dependency-free marshalling core.
//
// Contains a small, self-contained recursive-descent JSON parser (no external
// library — nothing is vendored for the host build) that decodes a libinsimul
// binding-set solution into PrologValue terms. Correctness of THIS file is what
// the host marshalling tests pin down.

#include "prolog_value.h"

#include <cctype>
#include <cmath>
#include <cstdio>
#include <sstream>

namespace insimul {

bool PrologValue::operator==(const PrologValue &o) const {
	if (kind != o.kind) {
		return false;
	}
	switch (kind) {
		case PrologKind::Atom:
			return text == o.text;
		case PrologKind::Int:
			return int_value == o.int_value;
		case PrologKind::Float:
			return float_value == o.float_value;
		case PrologKind::Bool:
			return bool_value == o.bool_value;
		case PrologKind::Null:
			return true;
		case PrologKind::List:
			return items == o.items;
		case PrologKind::Compound:
			return text == o.text && items == o.items;
	}
	return false;
}

namespace {

// ---- Minimal JSON value (internal to the parser) --------------------------
enum class JsonKind { Null, Bool, Int, Float, String, Array, Object };

struct JsonValue {
	JsonKind kind = JsonKind::Null;
	bool b = false;
	int64_t i = 0;
	double d = 0.0;
	std::string s;
	std::vector<JsonValue> arr;
	std::vector<std::pair<std::string, JsonValue>> obj; // insertion-ordered
};

// A tiny recursive-descent JSON parser. Throws std::string on error.
class JsonParser {
public:
	explicit JsonParser(const std::string &src) : src_(src) {}

	JsonValue parse() {
		skip_ws();
		JsonValue v = parse_value();
		skip_ws();
		if (pos_ != src_.size()) {
			fail("trailing characters after JSON value");
		}
		return v;
	}

private:
	const std::string &src_;
	size_t pos_ = 0;

	[[noreturn]] void fail(const std::string &why) const {
		std::ostringstream os;
		os << "JSON parse error at offset " << pos_ << ": " << why;
		throw os.str();
	}

	char peek() const { return pos_ < src_.size() ? src_[pos_] : '\0'; }

	char next() {
		if (pos_ >= src_.size()) {
			fail("unexpected end of input");
		}
		return src_[pos_++];
	}

	void skip_ws() {
		while (pos_ < src_.size()) {
			char c = src_[pos_];
			if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
				pos_++;
			} else {
				break;
			}
		}
	}

	void expect(char c) {
		if (next() != c) {
			fail(std::string("expected '") + c + "'");
		}
	}

	JsonValue parse_value() {
		skip_ws();
		char c = peek();
		switch (c) {
			case '{':
				return parse_object();
			case '[':
				return parse_array();
			case '"':
				return parse_string_value();
			case 't':
			case 'f':
				return parse_bool();
			case 'n':
				return parse_null();
			default:
				if (c == '-' || (c >= '0' && c <= '9')) {
					return parse_number();
				}
				fail("unexpected character");
		}
	}

	JsonValue parse_object() {
		expect('{');
		JsonValue v;
		v.kind = JsonKind::Object;
		skip_ws();
		if (peek() == '}') {
			pos_++;
			return v;
		}
		while (true) {
			skip_ws();
			if (peek() != '"') {
				fail("expected object key string");
			}
			std::string key = parse_string_raw();
			skip_ws();
			expect(':');
			JsonValue val = parse_value();
			v.obj.emplace_back(std::move(key), std::move(val));
			skip_ws();
			char c = next();
			if (c == ',') {
				continue;
			}
			if (c == '}') {
				break;
			}
			fail("expected ',' or '}' in object");
		}
		return v;
	}

	JsonValue parse_array() {
		expect('[');
		JsonValue v;
		v.kind = JsonKind::Array;
		skip_ws();
		if (peek() == ']') {
			pos_++;
			return v;
		}
		while (true) {
			JsonValue val = parse_value();
			v.arr.push_back(std::move(val));
			skip_ws();
			char c = next();
			if (c == ',') {
				continue;
			}
			if (c == ']') {
				break;
			}
			fail("expected ',' or ']' in array");
		}
		return v;
	}

	std::string parse_string_raw() {
		expect('"');
		std::string out;
		while (true) {
			char c = next();
			if (c == '"') {
				break;
			}
			if (c == '\\') {
				char e = next();
				switch (e) {
					case '"': out.push_back('"'); break;
					case '\\': out.push_back('\\'); break;
					case '/': out.push_back('/'); break;
					case 'b': out.push_back('\b'); break;
					case 'f': out.push_back('\f'); break;
					case 'n': out.push_back('\n'); break;
					case 'r': out.push_back('\r'); break;
					case 't': out.push_back('\t'); break;
					case 'u': {
						unsigned int cp = parse_hex4();
						append_utf8(out, cp);
						break;
					}
					default:
						fail("invalid string escape");
				}
			} else {
				out.push_back(c);
			}
		}
		return out;
	}

	unsigned int parse_hex4() {
		unsigned int cp = 0;
		for (int k = 0; k < 4; k++) {
			char c = next();
			cp <<= 4;
			if (c >= '0' && c <= '9') {
				cp |= (unsigned int)(c - '0');
			} else if (c >= 'a' && c <= 'f') {
				cp |= (unsigned int)(c - 'a' + 10);
			} else if (c >= 'A' && c <= 'F') {
				cp |= (unsigned int)(c - 'A' + 10);
			} else {
				fail("invalid \\u hex digit");
			}
		}
		return cp;
	}

	static void append_utf8(std::string &out, unsigned int cp) {
		if (cp < 0x80) {
			out.push_back((char)cp);
		} else if (cp < 0x800) {
			out.push_back((char)(0xC0 | (cp >> 6)));
			out.push_back((char)(0x80 | (cp & 0x3F)));
		} else {
			out.push_back((char)(0xE0 | (cp >> 12)));
			out.push_back((char)(0x80 | ((cp >> 6) & 0x3F)));
			out.push_back((char)(0x80 | (cp & 0x3F)));
		}
	}

	JsonValue parse_string_value() {
		JsonValue v;
		v.kind = JsonKind::String;
		v.s = parse_string_raw();
		return v;
	}

	JsonValue parse_bool() {
		JsonValue v;
		v.kind = JsonKind::Bool;
		if (src_.compare(pos_, 4, "true") == 0) {
			v.b = true;
			pos_ += 4;
		} else if (src_.compare(pos_, 5, "false") == 0) {
			v.b = false;
			pos_ += 5;
		} else {
			fail("invalid literal");
		}
		return v;
	}

	JsonValue parse_null() {
		if (src_.compare(pos_, 4, "null") == 0) {
			pos_ += 4;
			JsonValue v;
			v.kind = JsonKind::Null;
			return v;
		}
		fail("invalid literal");
	}

	JsonValue parse_number() {
		size_t start = pos_;
		bool is_float = false;
		if (peek() == '-') {
			pos_++;
		}
		while (pos_ < src_.size()) {
			char c = src_[pos_];
			if (c >= '0' && c <= '9') {
				pos_++;
			} else if (c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-') {
				is_float = true;
				pos_++;
			} else {
				break;
			}
		}
		std::string num = src_.substr(start, pos_ - start);
		JsonValue v;
		if (is_float) {
			v.kind = JsonKind::Float;
			v.d = std::strtod(num.c_str(), nullptr);
		} else {
			v.kind = JsonKind::Int;
			v.i = (int64_t)std::strtoll(num.c_str(), nullptr, 10);
		}
		return v;
	}
};

// ---- JSON term -> PrologValue --------------------------------------------
bool is_compound_object(const JsonValue &v) {
	if (v.kind != JsonKind::Object) {
		return false;
	}
	bool has_functor = false;
	bool has_args = false;
	for (const auto &kv : v.obj) {
		if (kv.first == "functor") {
			has_functor = true;
		} else if (kv.first == "args") {
			has_args = true;
		}
	}
	return has_functor && has_args;
}

PrologValue json_to_term(const JsonValue &v); // fwd

PrologValue json_object_to_compound(const JsonValue &v) {
	std::string functor;
	std::vector<PrologValue> args;
	for (const auto &kv : v.obj) {
		if (kv.first == "functor") {
			if (kv.second.kind != JsonKind::String) {
				throw std::string("compound 'functor' must be a string");
			}
			functor = kv.second.s;
		} else if (kv.first == "args") {
			if (kv.second.kind != JsonKind::Array) {
				throw std::string("compound 'args' must be an array");
			}
			for (const auto &a : kv.second.arr) {
				args.push_back(json_to_term(a));
			}
		}
	}
	return PrologValue::compound(std::move(functor), std::move(args));
}

PrologValue json_to_term(const JsonValue &v) {
	switch (v.kind) {
		case JsonKind::String:
			return PrologValue::atom(v.s);
		case JsonKind::Int:
			return PrologValue::integer(v.i);
		case JsonKind::Float:
			return PrologValue::real(v.d);
		case JsonKind::Bool:
			return PrologValue::boolean(v.b);
		case JsonKind::Null:
			return PrologValue::null();
		case JsonKind::Array: {
			std::vector<PrologValue> items;
			items.reserve(v.arr.size());
			for (const auto &e : v.arr) {
				items.push_back(json_to_term(e));
			}
			return PrologValue::list(std::move(items));
		}
		case JsonKind::Object:
			if (is_compound_object(v)) {
				return json_object_to_compound(v);
			}
			throw std::string("term object is not a compound (missing functor/args)");
	}
	throw std::string("unreachable term kind");
}

} // namespace

ParseResult parse_binding_set(const std::string &json) {
	ParseResult result;
	try {
		JsonParser parser(json);
		JsonValue root = parser.parse();
		if (root.kind != JsonKind::Object) {
			result.error = "binding set top level must be a JSON object";
			return result;
		}
		for (const auto &kv : root.obj) {
			result.bindings.emplace_back(kv.first, json_to_term(kv.second));
		}
		result.ok = true;
	} catch (const std::string &why) {
		result.ok = false;
		result.bindings.clear();
		result.error = why;
	} catch (...) {
		result.ok = false;
		result.bindings.clear();
		result.error = "unknown parse failure";
	}
	return result;
}

std::string to_debug_string(const PrologValue &v) {
	std::ostringstream os;
	switch (v.kind) {
		case PrologKind::Atom:
			os << v.text;
			break;
		case PrologKind::Int:
			os << v.int_value;
			break;
		case PrologKind::Float: {
			char buf[64];
			std::snprintf(buf, sizeof(buf), "%g", v.float_value);
			os << buf;
			break;
		}
		case PrologKind::Bool:
			os << (v.bool_value ? "true" : "false");
			break;
		case PrologKind::Null:
			os << "null";
			break;
		case PrologKind::List: {
			os << "[";
			for (size_t k = 0; k < v.items.size(); k++) {
				if (k) {
					os << ", ";
				}
				os << to_debug_string(v.items[k]);
			}
			os << "]";
			break;
		}
		case PrologKind::Compound: {
			os << v.text << "(";
			for (size_t k = 0; k < v.items.size(); k++) {
				if (k) {
					os << ", ";
				}
				os << to_debug_string(v.items[k]);
			}
			os << ")";
			break;
		}
	}
	return os.str();
}

std::string to_debug_string(const BindingSet &b) {
	std::ostringstream os;
	os << "{";
	for (size_t k = 0; k < b.size(); k++) {
		if (k) {
			os << ", ";
		}
		os << b[k].first << ": " << to_debug_string(b[k].second);
	}
	os << "}";
	return os.str();
}

} // namespace insimul
