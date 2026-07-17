# conformance_runner.gd — the Godot end-to-end leg of the Prolog parity gate.
#
# Godot is free and scriptable, so when a `godot` binary is on PATH this runs the
# SHARED conformance corpus (packages/core/conformance/prolog/*.json — the same
# JSON the tau-prolog TS gate and the host C++ harness read) end-to-end through
# the real, built InsimulProlog GDExtension: consult each case's knowledge base,
# run its query, and compare the returned Array[Dictionary] against the corpus
# `expected` solution set as an UNORDERED multiset (a native engine may enumerate
# solutions in any order).
#
#   godot --headless -s packages/godot/gdextension/tests/conformance_runner.gd
#
# Point it at a different corpus dir with a trailing user arg:
#   godot --headless -s .../conformance_runner.gd -- --corpus /abs/path/to/prolog
#
# Exit 0 iff every case matches; non-zero (and a per-case FAIL line) otherwise —
# CI-consumable. When godot / the built extension are absent (the Ralph harness),
# test/run_conformance.sh drives the identical corpus through the extension's
# marshalling layer under plain clang++, so parity is verified either way; see
# README for the host-vs-editor split.
extends SceneTree

var _pass := 0
var _fail := 0
var _solutions := 0


func _initialize() -> void:
	if not ClassDB.class_exists("InsimulProlog"):
		push_error("[insimul-conformance] InsimulProlog class not registered — is the GDExtension built and installed?")
		quit(1)
		return

	var corpus_dir := _resolve_corpus_dir()
	print("[insimul-conformance] corpus: %s" % corpus_dir)

	var dir := DirAccess.open(corpus_dir)
	if dir == null:
		push_error("[insimul-conformance] cannot open corpus dir: %s" % corpus_dir)
		quit(2)
		return

	# Deterministic file ordering so output is stable across platforms.
	var files := dir.get_files()
	files.sort()

	var corpus_files := 0
	for fname in files:
		if not fname.ends_with(".json"):
			continue
		var path := corpus_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			push_error("[insimul-conformance] cannot read %s" % path)
			quit(2)
			return
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("cases"):
			push_error("[insimul-conformance] %s has no cases[]" % path)
			quit(2)
			return
		corpus_files += 1
		var area: String = parsed.get("area", fname.get_basename())
		for c in parsed["cases"]:
			_run_case(area, c)

	print("-----------------------------------------------------------")
	print("[insimul-conformance] %d corpus files, %d cases, %d solutions" % [corpus_files, _pass + _fail, _solutions])
	print("[insimul-conformance] %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


# Run one corpus case end-to-end through the native extension.
func _run_case(area: String, c: Dictionary) -> void:
	var name: String = c.get("name", "<unnamed>")
	var label := "%s / %s" % [area, name]

	var kb: Object = ClassDB.instantiate("InsimulProlog")
	# Each case is self-contained: consult the full knowledge base fresh.
	var program := "\n".join(PackedStringArray(c.get("kb", [])))
	if not kb.consult(program):
		_report(label, false, "consult failed: %s" % kb.last_error())
		return

	var expected: Array = c.get("expected", [])
	var got: Array = kb.query(c.get("query", ""))
	_solutions += expected.size()

	if not _multiset_matches(expected, got):
		_report(label, false, "want %s got %s" % [str(expected), str(got)])
		return

	_report(label, true, "(%d solution%s)" % [expected.size(), "" if expected.size() == 1 else "s"])


# Unordered multiset comparison of two solution lists (Array[Dictionary]).
func _multiset_matches(expected: Array, actual: Array) -> bool:
	if expected.size() != actual.size():
		return false
	var used := []
	used.resize(actual.size())
	used.fill(false)
	for want in expected:
		var matched := false
		for k in actual.size():
			if used[k]:
				continue
			if _dict_equal(want, actual[k]):
				used[k] = true
				matched = true
				break
		if not matched:
			return false
	return true


# Two binding dictionaries are equal iff they bind the same variables to
# term-equal values.
func _dict_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key):
			return false
		if not _terms_equal(a[key], b[key]):
			return false
	return true


# Structural term equality across the corpus/extension type mappings. Numbers are
# compared by value so the corpus's JSON ints match the extension's int/float
# (atom->String, list->Array, compound->Dictionary{functor,args}).
func _terms_equal(a: Variant, b: Variant) -> bool:
	var an := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var bn := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	if an and bn:
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_ARRAY:
			if a.size() != b.size():
				return false
			for k in a.size():
				if not _terms_equal(a[k], b[k]):
					return false
			return true
		TYPE_DICTIONARY:
			return _dict_equal(a, b)
		_:
			return a == b


func _report(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s  %s" % [label, detail])
	else:
		_fail += 1
		push_error("  FAIL  %s  %s" % [label, detail])


# Corpus dir: a `--corpus <dir>` user arg, else derived from this script's path
# (gdextension/tests/ -> ../../core/conformance/prolog).
func _resolve_corpus_dir() -> String:
	var user_args := OS.get_cmdline_user_args()
	for i in user_args.size():
		if user_args[i] == "--corpus" and i + 1 < user_args.size():
			return user_args[i + 1]
	var script_path := (get_script() as Resource).resource_path
	var gdext_dir := script_path.get_base_dir().get_base_dir() # .../gdextension
	# gdextension -> packages/godot; corpus lives at packages/core/conformance/prolog
	var packages_dir := gdext_dir.get_base_dir().get_base_dir() # .../packages
	return packages_dir.path_join("core/conformance/prolog")
