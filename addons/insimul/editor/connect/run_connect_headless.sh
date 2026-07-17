#!/usr/bin/env bash
# run_connect_headless.sh — the US-GE1 editor-connect LOGIC-LAYER gate.
#
# Runs connect_test.gd end-to-end through a real Godot binary when one is on PATH:
# it drives InsimulV1Client (operation resolve, unknown-op guard, request build)
# and InsimulEditorSession (health probe, login success, 401-clears-token) over the
# InsimulV1MockTransport. The HTTP transport + settings persistence need a running
# editor and are covered by the structural lint + the human end-to-end pass
# (VERIFICATION.md), not here.
#
# The machine-runnable operation-table conformance + secret-storage guards run on a
# bare box under `npm test` (packages/core/src/editor/__tests__/operations.test.ts).
#
# When NO godot binary is available (the Ralph harness), this SKIPs with exit 0 —
# mirroring run_binding_dock_headless.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# addons/insimul/editor/connect -> addons/insimul/editor -> addons/insimul -> addons -> insimul (pkg root)
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
	echo "editor-connect: no godot binary on PATH — SKIP (structural lint + npm-test conformance cover the .gd on a bare box)"
	exit 0
fi

proj="$(mktemp -d)"
trap 'rm -rf "$proj"' EXIT
mkdir -p "$proj/addons"
cp -r "$pkg_root/addons/insimul" "$proj/addons/insimul"
cat > "$proj/project.godot" <<'EOF'
config_version=5

[application]
config/name="insimul-editor-connect-test"
EOF

echo "editor-connect: running headless test with $GODOT ..."
# First pass lets Godot import/scan the project so global class_names register.
"$GODOT" --headless --path "$proj" --quit >/dev/null 2>&1 || true
"$GODOT" --headless --path "$proj" \
	-s "addons/insimul/editor/connect/connect_test.gd"
