#!/usr/bin/env bash
# run_save_system_headless.sh — the US-GC2 save-system headless gate.
#
# Runs save_system_test.gd end-to-end through a real Godot binary when one is on
# PATH: new-game -> save -> load with envelope integrity, KB snapshot/restore, and
# tamper detection through InsimulSaveSystem + the InsimulSaveCodec GDExtension.
#
# It stages the addon into a throwaway project (so the addon's global class_names
# resolve during Godot's project scan) then runs the SceneTree test headless.
#
# When NO godot binary is available (the Ralph harness), this SKIPS with exit 0.
# The test itself ALSO skips when the InsimulSaveCodec GDExtension is not built.
# Either way the save contract is covered by the host C++ gate
# (gdextension/test/run_save_tests.sh, wired into engines:check) and the TS
# cross-check — the structural lint covers the addon `.gd` files. Mirrors
# run_world_source_headless.sh.
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
	echo "save-system: no godot binary on PATH — SKIP (host gate run_save_tests.sh covers the codec)"
	exit 0
fi

proj="$(mktemp -d)"
trap 'rm -rf "$proj"' EXIT
mkdir -p "$proj/addons"
cp -r "$pkg_root/addons/insimul" "$proj/addons/insimul"
cat > "$proj/project.godot" <<'EOF'
config_version=5

[application]
config/name="insimul-save-system-test"
EOF

echo "save-system: running headless test with $GODOT ..."
# First pass lets Godot import/scan the project so global class_names register.
"$GODOT" --headless --path "$proj" --quit >/dev/null 2>&1 || true
"$GODOT" --headless --path "$proj" \
	-s "addons/insimul/tests/save_system_test.gd" \
	-- --fixtures "$fixtures"
