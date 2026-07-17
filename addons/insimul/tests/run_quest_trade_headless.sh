#!/usr/bin/env bash
# run_quest_trade_headless.sh — the US-GU2 default-UI quest+trade headless gate.
#
# Runs quest_trade_test.gd end-to-end through a real Godot binary when one is on
# PATH: the shared engine-neutral matrices
# (packages/core/conformance/ui/{quest-journal-cases,trade-cases}.json) against the
# pure GDScript view-models (InsimulQuestJournalModel, InsimulTradeModel) plus the
# state-location invariant. No GDExtension is needed (all pure GDScript).
#
# It stages the addon into a throwaway project (so the addon's global class_names
# resolve during Godot's project scan) then runs the SceneTree test headless,
# passing the corpus dir with --ui.
#
# When NO godot binary is available (the Ralph harness), this SKIPS with exit 0 —
# the GDScript structural lint covers the addon `.gd` files there. Mirrors
# run_ui_registry_headless.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# addons/insimul/tests -> addons/insimul -> addons -> insimul (package root)
pkg_root="$(cd "$here/../../.." && pwd)"           # packages/godot
packages_dir="$(cd "$pkg_root/.." && pwd)"          # packages
ui_corpus="$packages_dir/core/conformance/ui"

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
	echo "quest-trade: no godot binary on PATH — SKIP (structural lint covers the .gd files)"
	exit 0
fi

proj="$(mktemp -d)"
trap 'rm -rf "$proj"' EXIT
mkdir -p "$proj/addons"
cp -r "$pkg_root/addons/insimul" "$proj/addons/insimul"
cat > "$proj/project.godot" <<'EOF'
config_version=5

[application]
config/name="insimul-quest-trade-test"
EOF

echo "quest-trade: running headless test with $GODOT ..."
# First pass lets Godot import/scan the project so global class_names register.
"$GODOT" --headless --path "$proj" --quit >/dev/null 2>&1 || true
"$GODOT" --headless --path "$proj" \
	-s "addons/insimul/tests/quest_trade_test.gd" \
	-- --ui "$ui_corpus"
