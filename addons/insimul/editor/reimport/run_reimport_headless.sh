#!/usr/bin/env bash
# run_reimport_headless.sh — the US-GB3 re-import diff policy editor gate.
#
# Runs reimport_test.gd end-to-end through a real Godot binary when one is on
# PATH: it drives InsimulReimport on the shared old/new manifests, asserts the
# diff buckets match the committed golden, then builds two live scene trees,
# applies the reconciliation, and checks the mutated tree honors the policy
# (hand edits untouched, dropped generated nodes deprecated, new nodes added).
#
# To keep the addon's global class_names resolvable, it stages the addon into a
# throwaway project (Godot registers `class_name` scripts during a project scan),
# then runs the SceneTree test with --headless -s.
#
# When NO godot binary is available (the Ralph harness), this SKIPS with exit 0 —
# the host C++ gate (gdextension/test/run_reimport_tests.sh) proves the policy on
# a bare box, and the GDScript structural lint covers the .gd files. This mirrors
# the host-vs-editor split used by run_scene_generator_headless.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# addons/insimul/editor/reimport -> addons/insimul/editor -> addons/insimul -> addons -> insimul (pkg root)
pkg_root="$(cd "$here/../../../.." && pwd)"          # packages/godot
fixtures="$here/fixtures"

GODOT="${GODOT:-}"
if [[ -z "$GODOT" ]]; then
	for cand in godot godot4 Godot; do
		if command -v "$cand" >/dev/null 2>&1; then
			GODOT="$cand"
			break
		fi
	done
fi

if [[ -z "$GODOT" ]]; then
	echo "reimport: no godot binary on PATH — SKIP (host gate run_reimport_tests.sh covers the diff policy)"
	exit 0
fi

proj="$(mktemp -d)"
trap 'rm -rf "$proj"' EXIT
mkdir -p "$proj/addons"
cp -r "$pkg_root/addons/insimul" "$proj/addons/insimul"
cat > "$proj/project.godot" <<'EOF'
config_version=5

[application]
config/name="insimul-reimport-test"
EOF

echo "reimport: running headless test with $GODOT ..."
# First pass lets Godot import/scan the project so global class_names register.
"$GODOT" --headless --path "$proj" --quit >/dev/null 2>&1 || true
"$GODOT" --headless --path "$proj" \
	-s "addons/insimul/editor/reimport/reimport_test.gd" \
	-- --fixtures "$fixtures"
