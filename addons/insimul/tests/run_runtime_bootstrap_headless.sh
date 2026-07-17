#!/usr/bin/env bash
# run_runtime_bootstrap_headless.sh — the US-GC4 startup-orchestrator headless gate.
#
# Runs runtime_bootstrap_test.gd end-to-end through a real Godot binary when one is
# on PATH: the full template-startup loop (world source -> save slot -> KB ->
# systems) driven through InsimulRuntime + InsimulWorldSource + InsimulSaveSystem +
# InsimulQuestSystem and the InsimulSaveCodec/InsimulQuestCore GDExtensions —
# new-game boot, radiant tick, objective completion, save, resume, corrupt-slot
# fallback, and worldSnapshot-hash stability.
#
# It stages the addon into a throwaway project (so the addon's global class_names
# resolve during Godot's project scan) then runs the SceneTree test headless.
#
# When NO godot binary is available (the Ralph harness), this SKIPS with exit 0.
# The test itself ALSO skips when the GDExtensions are not built. Either way the
# full loop is covered by the host C++ gate
# (gdextension/test/run_bootstrap_tests.sh, wired into engines:check) — the
# structural lint covers the addon `.gd` files. Mirrors run_quest_system_headless.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
	echo "runtime-bootstrap: no godot binary on PATH — SKIP (host gate run_bootstrap_tests.sh covers the full loop)"
	exit 0
fi

proj="$(mktemp -d)"
trap 'rm -rf "$proj"' EXIT
mkdir -p "$proj/addons"
cp -r "$pkg_root/addons/insimul" "$proj/addons/insimul"
cat > "$proj/project.godot" <<'EOF'
config_version=5

[application]
config/name="insimul-runtime-bootstrap-test"
EOF

echo "runtime-bootstrap: running headless test with $GODOT ..."
# First pass lets Godot import/scan the project so global class_names register.
"$GODOT" --headless --path "$proj" --quit >/dev/null 2>&1 || true
"$GODOT" --headless --path "$proj" \
	-s "addons/insimul/tests/runtime_bootstrap_test.gd" \
	-- --fixtures "$fixtures"
