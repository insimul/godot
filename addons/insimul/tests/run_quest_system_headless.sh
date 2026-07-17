#!/usr/bin/env bash
# run_quest_system_headless.sh — the US-GC3 quest-system headless gate.
#
# Runs quest_system_test.gd end-to-end through a real Godot binary when one is on
# PATH: hydration + radiant parity vs the shared golden corpus, query-driven
# completion with fact-asserting transitions + preserved signals, and a save
# round-trip preserving quest+radiant KB facts through InsimulQuestSystem +
# InsimulSaveSystem + the InsimulQuestCore/InsimulSaveCodec GDExtensions.
#
# It stages the addon into a throwaway project (so the addon's global class_names
# resolve during Godot's project scan) then runs the SceneTree test headless.
#
# When NO godot binary is available (the Ralph harness), this SKIPS with exit 0.
# The test itself ALSO skips when the InsimulQuestCore GDExtension is not built.
# Either way the quest contract is covered by the host C++ gate
# (gdextension/test/run_quest_tests.sh, wired into engines:check) — the structural
# lint covers the addon `.gd` files. Mirrors run_save_system_headless.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# addons/insimul/tests -> addons/insimul -> addons -> insimul (package root)
pkg_root="$(cd "$here/../../.." && pwd)"           # packages/godot
packages_dir="$(cd "$pkg_root/.." && pwd)"          # packages
fixtures="$packages_dir/core/conformance/saves"
quests="$packages_dir/core/conformance/quests"

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
	echo "quest-system: no godot binary on PATH — SKIP (host gate run_quest_tests.sh covers the quest core)"
	exit 0
fi

proj="$(mktemp -d)"
trap 'rm -rf "$proj"' EXIT
mkdir -p "$proj/addons"
cp -r "$pkg_root/addons/insimul" "$proj/addons/insimul"
cat > "$proj/project.godot" <<'EOF'
config_version=5

[application]
config/name="insimul-quest-system-test"
EOF

echo "quest-system: running headless test with $GODOT ..."
# First pass lets Godot import/scan the project so global class_names register.
"$GODOT" --headless --path "$proj" --quit >/dev/null 2>&1 || true
"$GODOT" --headless --path "$proj" \
	-s "addons/insimul/tests/quest_system_test.gd" \
	-- --quests "$quests" --fixtures "$fixtures"
