#!/usr/bin/env bash
# run_world_source_headless.sh — the US-GC1 world-source gate.
#
# Runs world_source_test.gd end-to-end through a real Godot binary when one is
# on PATH: it loads the shared golden save fixture through InsimulWorldSource +
# the generated DTOs and asserts the golden entity counts + the version gate.
#
# To keep the addon's global class_names resolvable, it stages the addon into a
# throwaway project (Godot registers `class_name` scripts during a project scan),
# then runs the SceneTree test with --headless -s.
#
# When NO godot binary is available (the Ralph harness), this SKIPS with exit 0 —
# the GDScript structural lint (gdextension/tests/gdscript_structural_lint.py,
# wired into engines:check) covers the addon `.gd` files structurally, and the
# human toolchain review (autoMerge: false) covers runtime semantics. This mirrors
# the host-vs-editor split used by the GDExtension gates (run_conformance.sh).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# addons/insimul/tests -> addons/insimul -> addons -> insimul (package root)
pkg_root="$(cd "$here/../../.." && pwd)"           # packages/godot
packages_dir="$(cd "$pkg_root/.." && pwd)"          # packages
fixtures="$packages_dir/core/conformance/saves"

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
	echo "world-source: no godot binary on PATH — SKIP (structural lint covers the addon .gd)"
	exit 0
fi

proj="$(mktemp -d)"
trap 'rm -rf "$proj"' EXIT
mkdir -p "$proj/addons"
cp -r "$pkg_root/addons/insimul" "$proj/addons/insimul"
cat > "$proj/project.godot" <<'EOF'
config_version=5

[application]
config/name="insimul-world-source-test"
EOF

echo "world-source: running headless test with $GODOT ..."
# First pass lets Godot import/scan the project so global class_names register.
"$GODOT" --headless --path "$proj" --quit >/dev/null 2>&1 || true
"$GODOT" --headless --path "$proj" \
	-s "addons/insimul/tests/world_source_test.gd" \
	-- --fixtures "$fixtures"
