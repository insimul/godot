// conformance_host.cpp — the Godot leg of the cross-engine Prolog parity gate.
//
// This is the host-C++ half of US-GP2. It reads the SHARED, language-neutral
// conformance corpus (packages/core/conformance/prolog/*.json — the same JSON
// the tau-prolog TS gate and the future libinsimul C harness read) and drives
// every expected solution through the extension's REAL marshalling layer
// (insimul::parse_binding_set in src/prolog_value.cpp).
//
// Why this proves parity without libinsimul: each corpus `expected` entry is a
// full solution set written in EXACTLY libinsimul's binding-set JSON format
// (var -> term; atom->string, int->number, list->array, compound->
// {functor,args}). So feeding each expected solution object straight through
// parse_binding_set exercises the same decode path that will run when
// libinsimul + godot-cpp are wired up. When a godot binary is on PATH,
// tests/conformance_runner.gd runs the SAME corpus end-to-end (consult+query)
// through the built extension; this host harness covers the marshalling parity
// regardless of toolchain (README documents the split).
//
// Deliberately independent: this file ships its OWN minimal JSON reader (below)
// to load the corpus, so the corpus loader and the code-under-test
// (parse_binding_set) never share a parser — a bug in one cannot mask a bug in
// the other. Builds + runs under plain clang++ (see test/run_conformance.sh).

#include "../src/prolog_value.h"

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

using namespace insimul;

namespace {

// ---------------------------------------------------------------------------
// Independent minimal JSON reader (separate from src/prolog_value.cpp's parser).
// ---------------------------------------------------------------------------
enum class JKind { Null, Bool, Int, Float, Str, Arr, Obj };

struct JVal {
	JKind kind = JKind::Null;
	bool b = false;
	int64_t i = 0;
	double d = 0.0;
	std::string s;
	std::vector<JVal> arr;
	std::vector<std::pair<std::string, JVal>> obj;

	const JVal *get(const std::string &key) const {
		for (const auto &kv : obj) {
			if (kv.first == key) {
				return &kv.second;
			}
		}
		return nullptr;
	}
};

class JReader {
public:
	explicit JReader(const std::string &src) : src_(src) {}

	JVal parse() {
		ws();
		JVal v = value();
		ws();
		if (pos_ != src_.size()) {
			fail("trailing characters");
		}
		return v;
	}

private:
	const std::string &src_;
	size_t pos_ = 0;

	[[noreturn]] void fail(const std::string &why) const {
		std::ostringstream os;
		os << "corpus JSON error at offset " << pos_ << ": " << why;
		throw os.str();
	}

	char peek() const { return pos_ < src_.size() ? src_[pos_] : '\0'; }
	char next() {
		if (pos_ >= src_.size()) {
			fail("unexpected end of input");
		}
		return src_[pos_++];
	}
	void ws() {
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

	JVal value() {
		ws();
		char c = peek();
		switch (c) {
			case '{': return object();
			case '[': return array();
			case '"': return str();
			case 't':
			case 'f': return boolean();
			case 'n': return null_lit();
			default:
				if (c == '-' || (c >= '0' && c <= '9')) {
					return number();
				}
				fail("unexpected character");
		}
	}

	JVal object() {
		expect('{');
		JVal v;
		v.kind = JKind::Obj;
		ws();
		if (peek() == '}') {
			pos_++;
			return v;
		}
		while (true) {
			ws();
			if (peek() != '"') {
				fail("expected object key");
			}
			std::string key = raw_string();
			ws();
			expect(':');
			v.obj.emplace_back(std::move(key), value());
			ws();
			char c = next();
			if (c == ',') {
				continue;
			}
			if (c == '}') {
				break;
			}
			fail("expected ',' or '}'");
		}
		return v;
	}

	JVal array() {
		expect('[');
		JVal v;
		v.kind = JKind::Arr;
		ws();
		if (peek() == ']') {
			pos_++;
			return v;
		}
		while (true) {
			v.arr.push_back(value());
			ws();
			char c = next();
			if (c == ',') {
				continue;
			}
			if (c == ']') {
				break;
			}
			fail("expected ',' or ']'");
		}
		return v;
	}

	std::string raw_string() {
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
						unsigned int cp = hex4();
						utf8(out, cp);
						break;
					}
					default: fail("invalid string escape");
				}
			} else {
				out.push_back(c);
			}
		}
		return out;
	}

	unsigned int hex4() {
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

	static void utf8(std::string &out, unsigned int cp) {
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

	JVal str() {
		JVal v;
		v.kind = JKind::Str;
		v.s = raw_string();
		return v;
	}

	JVal boolean() {
		JVal v;
		v.kind = JKind::Bool;
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

	JVal null_lit() {
		if (src_.compare(pos_, 4, "null") == 0) {
			pos_ += 4;
			JVal v;
			v.kind = JKind::Null;
			return v;
		}
		fail("invalid literal");
	}

	JVal number() {
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
		JVal v;
		if (is_float) {
			v.kind = JKind::Float;
			v.d = std::strtod(num.c_str(), nullptr);
		} else {
			v.kind = JKind::Int;
			v.i = (int64_t)std::strtoll(num.c_str(), nullptr, 10);
		}
		return v;
	}
};

// ---------------------------------------------------------------------------
// Reference decode + re-serialize (the "independent" side of the comparison).
// ---------------------------------------------------------------------------

// Convert a corpus JSON term to the PrologValue we EXPECT the marshalling layer
// to produce. Mirrors the libinsimul term mapping documented in prolog_value.h.
PrologValue reference_term(const JVal &v) {
	switch (v.kind) {
		case JKind::Str: return PrologValue::atom(v.s);
		case JKind::Int: return PrologValue::integer(v.i);
		case JKind::Float: return PrologValue::real(v.d);
		case JKind::Bool: return PrologValue::boolean(v.b);
		case JKind::Null: return PrologValue::null();
		case JKind::Arr: {
			std::vector<PrologValue> items;
			items.reserve(v.arr.size());
			for (const auto &e : v.arr) {
				items.push_back(reference_term(e));
			}
			return PrologValue::list(std::move(items));
		}
		case JKind::Obj: {
			const JVal *fn = v.get("functor");
			const JVal *ar = v.get("args");
			if (fn && ar && fn->kind == JKind::Str && ar->kind == JKind::Arr) {
				std::vector<PrologValue> args;
				for (const auto &a : ar->arr) {
					args.push_back(reference_term(a));
				}
				return PrologValue::compound(fn->s, std::move(args));
			}
			throw std::string("corpus term object is not a compound");
		}
	}
	throw std::string("unreachable corpus term kind");
}

// Re-serialize a corpus term to compact JSON — the exact bytes libinsimul emits
// for this term, fed to parse_binding_set as the code-under-test's input.
void serialize(std::string &out, const JVal &v) {
	switch (v.kind) {
		case JKind::Null: out += "null"; break;
		case JKind::Bool: out += v.b ? "true" : "false"; break;
		case JKind::Int: out += std::to_string(v.i); break;
		case JKind::Float: {
			char buf[32];
			std::snprintf(buf, sizeof(buf), "%.17g", v.d);
			out += buf;
			break;
		}
		case JKind::Str: {
			out.push_back('"');
			for (char c : v.s) {
				switch (c) {
					case '"': out += "\\\""; break;
					case '\\': out += "\\\\"; break;
					case '\b': out += "\\b"; break;
					case '\f': out += "\\f"; break;
					case '\n': out += "\\n"; break;
					case '\r': out += "\\r"; break;
					case '\t': out += "\\t"; break;
					default:
						if ((unsigned char)c < 0x20) {
							char u[8];
							std::snprintf(u, sizeof(u), "\\u%04x", (unsigned char)c);
							out += u;
						} else {
							out.push_back(c);
						}
				}
			}
			out.push_back('"');
			break;
		}
		case JKind::Arr: {
			out.push_back('[');
			for (size_t k = 0; k < v.arr.size(); k++) {
				if (k) {
					out.push_back(',');
				}
				serialize(out, v.arr[k]);
			}
			out.push_back(']');
			break;
		}
		case JKind::Obj: {
			out.push_back('{');
			for (size_t k = 0; k < v.obj.size(); k++) {
				if (k) {
					out.push_back(',');
				}
				JVal key;
				key.kind = JKind::Str;
				key.s = v.obj[k].first;
				serialize(out, key);
				out.push_back(':');
				serialize(out, v.obj[k].second);
			}
			out.push_back('}');
			break;
		}
	}
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------
int g_pass = 0;
int g_fail = 0;
int g_solutions = 0;

bool bindings_equal_unordered(const BindingSet &a, const BindingSet &b) {
	if (a.size() != b.size()) {
		return false;
	}
	std::vector<bool> used(b.size(), false);
	for (const auto &want : a) {
		bool matched = false;
		for (size_t k = 0; k < b.size(); k++) {
			if (used[k]) {
				continue;
			}
			if (b[k].first == want.first && b[k].second == want.second) {
				used[k] = true;
				matched = true;
				break;
			}
		}
		if (!matched) {
			return false;
		}
	}
	return true;
}

// Drive one corpus case's full expected solution set through parse_binding_set.
void run_case(const std::string &area, const JVal &c) {
	std::string name = c.get("name") ? c.get("name")->s : "<unnamed>";
	std::string label = area + " / " + name;

	const JVal *expected = c.get("expected");
	if (!expected || expected->kind != JKind::Arr) {
		std::printf("  FAIL  %-52s  missing expected[]\n", label.c_str());
		g_fail++;
		return;
	}

	// expected == [] means the query fails: no solution to marshal. Nothing for
	// the marshalling layer to decode, so it trivially passes parity here (the
	// GDScript runner asserts the empty result end-to-end).
	for (const auto &sol : expected->arr) {
		if (sol.kind != JKind::Obj) {
			std::printf("  FAIL  %-52s  solution not an object\n", label.c_str());
			g_fail++;
			return;
		}
		g_solutions++;

		// Reference bindings decoded by the independent reader.
		BindingSet ref;
		try {
			for (const auto &kv : sol.obj) {
				ref.emplace_back(kv.first, reference_term(kv.second));
			}
		} catch (const std::string &why) {
			std::printf("  FAIL  %-52s  corpus decode: %s\n", label.c_str(),
					why.c_str());
			g_fail++;
			return;
		}

		// The exact JSON bytes libinsimul would emit for this solution, driven
		// through the extension's real marshalling layer.
		std::string wire;
		serialize(wire, sol);
		ParseResult got = parse_binding_set(wire);
		if (!got.ok) {
			std::printf("  FAIL  %-52s  parse_binding_set rejected %s: %s\n",
					label.c_str(), wire.c_str(), got.error.c_str());
			g_fail++;
			return;
		}
		if (!bindings_equal_unordered(ref, got.bindings)) {
			std::printf("  FAIL  %-52s  decode mismatch: want %s got %s\n",
					label.c_str(), to_debug_string(ref).c_str(),
					to_debug_string(got.bindings).c_str());
			g_fail++;
			return;
		}
	}

	std::printf("  PASS  %-52s  (%zu solution%s)\n", label.c_str(),
			expected->arr.size(), expected->arr.size() == 1 ? "" : "s");
	g_pass++;
}

std::string read_file(const std::filesystem::path &p) {
	std::ifstream in(p, std::ios::binary);
	if (!in) {
		throw std::string("cannot open ") + p.string();
	}
	std::ostringstream ss;
	ss << in.rdbuf();
	return ss.str();
}

} // namespace

int main(int argc, char **argv) {
	// Corpus dir: argv[1] or default relative to this source's package.
	std::filesystem::path corpus_dir =
			argc > 1 ? std::filesystem::path(argv[1])
					 : std::filesystem::path(
							   "../../core/conformance/prolog");

	std::printf("Insimul GDExtension — conformance corpus (host marshalling)\n");
	std::printf("corpus: %s\n", corpus_dir.string().c_str());
	std::printf("-----------------------------------------------------------\n");

	if (!std::filesystem::is_directory(corpus_dir)) {
		std::fprintf(stderr, "error: corpus dir not found: %s\n",
				corpus_dir.string().c_str());
		return 2;
	}

	// Deterministic ordering so output is stable across runs/platforms.
	std::vector<std::filesystem::path> files;
	for (const auto &entry :
			std::filesystem::directory_iterator(corpus_dir)) {
		if (entry.is_regular_file() &&
				entry.path().extension() == ".json") {
			files.push_back(entry.path());
		}
	}
	std::sort(files.begin(), files.end());

	int corpus_files = 0;
	for (const auto &f : files) {
		std::string text;
		try {
			text = read_file(f);
			JReader reader(text);
			JVal root = reader.parse();
			const JVal *area = root.get("area");
			const JVal *cases = root.get("cases");
			if (!cases || cases->kind != JKind::Arr) {
				std::fprintf(stderr, "error: %s has no cases[]\n",
						f.string().c_str());
				return 2;
			}
			corpus_files++;
			std::string area_name = area ? area->s : f.stem().string();
			for (const auto &c : cases->arr) {
				run_case(area_name, c);
			}
		} catch (const std::string &why) {
			std::fprintf(stderr, "error reading %s: %s\n",
					f.string().c_str(), why.c_str());
			return 2;
		}
	}

	std::printf("-----------------------------------------------------------\n");
	std::printf("%d corpus files, %d cases, %d solutions marshalled\n",
			corpus_files, g_pass + g_fail, g_solutions);
	std::printf("%d passed, %d failed\n", g_pass, g_fail);
	return g_fail == 0 ? 0 : 1;
}
