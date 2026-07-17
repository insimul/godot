#!/usr/bin/env bash
# run_binding_dock_headless.sh — the US-GB3 Binding Editor dock LOGIC-LAYER gate.
#
# Runs binding_dock_test.gd end-to-end through a real Godot binary when one is on
# PATH: it drives InsimulBindingDockModel (taxonomy tree, bound/unbound status,
# suggestion ranking, bind / bind-descendants, pack import/export round-trip).
# The dock UI (insimul_binding_dock.gd) needs a running editor and is covered by
# the structural lint + the human end-to-end pass (VERIFICATION.md), not here.
#
# To keep the addon's global class_names resolvable, it stages the addon into a
# throwaway project (Godot registers `class_name` scripts during a project scan),
# then runs the SceneTree test with --headless -s.
#
# When NO godot binary is available (the Ralph harness), this SKIPS with exit 0 —
# the GDScript structural lint covers the .gd files on a bare box. This mirrors
# the host-vs-editor split used by run_scene_generator_headless.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# addons/insimul/editor/dock -> addons/insimul/editor -> addons/insimul -> addons -> insimul (pkg root)
pkg_root="$(cd "$here/../../../.." && pwd)"          # packages/godot

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
	echo "binding-dock: no godot binary on PATH — SKIP (structural lint covers the .gd on a bare box)"
	exit 0
fi

proj="$(mktemp -d)"
trap 'rm -rf "$proj"' EXIT
mkdir -p "$proj/addons"
cp -r "$pkg_root/addons/insimul" "$proj/addons/insimul"
cat > "$proj/project.godot" <<'EOF'
config_version=5

[application]
config/name="insimul-binding-dock-test"
EOF

echo "binding-dock: running headless test with $GODOT ..."
# First pass lets Godot import/scan the project so global class_names register.
"$GODOT" --headless --path "$proj" --quit >/dev/null 2>&1 || true
"$GODOT" --headless --path "$proj" \
	-s "addons/insimul/editor/dock/binding_dock_test.gd"
