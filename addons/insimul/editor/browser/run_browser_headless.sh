#!/usr/bin/env bash
# run_browser_headless.sh — the US-GE2 browser dock LOGIC-LAYER gate.
#
# Runs browser_test.gd end-to-end through a real Godot binary when one is on PATH.
# The dock UI needs a running editor and is covered by the structural lint + the
# human end-to-end pass (VERIFICATION.md), not here. The machine-runnable source of
# truth is packages/core/src/editor/*.ts + their vitest suites (bare box, npm test).
#
# When NO godot binary is available (the Ralph harness), this SKIPs with exit 0 —
# mirroring run_connect_headless.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# addons/insimul/editor/browser -> addons/insimul/editor -> addons/insimul -> addons -> insimul (pkg root)
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
	echo "browser: no godot binary on PATH — SKIP (structural lint + npm-test view-models cover the .gd on a bare box)"
	exit 0
fi

proj="$(mktemp -d)"
trap 'rm -rf "$proj"' EXIT
mkdir -p "$proj/addons"
cp -r "$pkg_root/addons/insimul" "$proj/addons/insimul"
cat > "$proj/project.godot" <<'PROJ'
config_version=5

[application]
config/name="insimul-browser-test"
PROJ

echo "browser: running headless test with $GODOT ..."
# First pass lets Godot import/scan the project so global class_names register.
"$GODOT" --headless --path "$proj" --quit >/dev/null 2>&1 || true
"$GODOT" --headless --path "$proj" \
	-s "addons/insimul/editor/browser/browser_test.gd"
