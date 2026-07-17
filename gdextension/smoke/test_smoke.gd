# test_smoke.gd — headless smoke test for the native InsimulProlog GDExtension.
#
# Godot is scriptable and free, so when a `godot` binary is on PATH this runs the
# real extension end-to-end (the advantage the plan calls out for the Godot leg):
#
#   godot --headless -s packages/godot/gdextension/smoke/test_smoke.gd
#
# It exits 0 on success, non-zero on failure — CI-consumable. When godot / the
# built extension are absent (the Ralph harness), the host marshalling tests
# (test/run_host_tests.sh) cover the same decode logic; see README.
extends SceneTree


func _fail(msg: String) -> void:
	push_error("[insimul-smoke] FAIL: %s" % msg)
	quit(1)


func _initialize() -> void:
	if not ClassDB.class_exists("InsimulProlog"):
		_fail("InsimulProlog class not registered — is the GDExtension built and installed?")
		return

	var kb: Object = ClassDB.instantiate("InsimulProlog")

	# consult a trivial KB
	if not kb.consult("parent(tom, bob).\nparent(bob, ann)."):
		_fail("consult failed: %s" % kb.last_error())
		return

	# query with one binding
	var sols: Array = kb.query("parent(tom, X)")
	if sols.size() != 1 or String(sols[0].get("X", "")) != "bob":
		_fail("query parent(tom,X) -> %s (expected [{X:bob}])" % str(sols))
		return

	# assert + re-query
	if not kb.assert_fact("parent(ann, cid)."):
		_fail("assert_fact failed: %s" % kb.last_error())
		return
	var grand: Array = kb.query("parent(ann, X)")
	if grand.size() != 1 or String(grand[0].get("X", "")) != "cid":
		_fail("query after assert -> %s" % str(grand))
		return

	# snapshot / restore round-trip
	var image: String = kb.snapshot()
	var kb2: Object = ClassDB.instantiate("InsimulProlog")
	kb2.consult("parent(tom, bob).\nparent(bob, ann).")
	if not kb2.restore(image):
		_fail("restore failed: %s" % kb2.last_error())
		return
	var restored: Array = kb2.query("parent(ann, X)")
	if restored.size() != 1 or String(restored[0].get("X", "")) != "cid":
		_fail("query after restore -> %s" % str(restored))
		return

	print("[insimul-smoke] OK — consult/query/assert/snapshot/restore all green")
	quit(0)
