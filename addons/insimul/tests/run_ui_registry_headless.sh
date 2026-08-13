#!/usr/bin/env bash
# run_ui_registry_headless.sh — the default-UI headless gate (npm run test:ui).
#
# Runs ui_registry_test.gd end-to-end through a real Godot binary when one is on
# PATH: the shared engine-neutral UI corpus (conformance/ui/*.json) and the
# band-111 activation table (conformance/modules/genre-activation.json) against
# the pure GDScript view-models (InsimulUiRegistry, InsimulLoadingScreenModel,
# InsimulNotifications, InsimulUiTokens) and the SHIPPED panel manifest — every
# panel key, every scene, every module gate. No GDExtension is needed.
#
# It stages the addon + the corpus into a throwaway project and IMPORTS it first:
# Godot only registers the addon's global `class_name`s once the project has been
# scanned, and without that pass every script in the test fails to parse while
# `godot -s` still exits 0 — a green gate that ran nothing. So the import pass is
# not a convenience, and the log is checked for parse errors afterwards.
#
# When NO godot binary is available (the Ralph harness), this SKIPS with exit 0 —
# there, the GDScript structural lint plus tools/verify-ui/check-ui.mjs cover the
# manifest / token / module-gate claims from the data side. Mirrors
# run_save_system_headless.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# addons/insimul/tests -> addons/insimul -> addons -> repo root
pkg_root="$(cd "$here/../../.." && pwd)"
conformance="$pkg_root/conformance"

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
	echo "ui-registry: no godot binary on PATH — SKIP (structural lint + check-ui.mjs cover the .gd files)"
	exit 0
fi

if [[ ! -d "$conformance/ui" ]]; then
	echo "ui-registry: no vendored corpus at $conformance/ui" >&2
	exit 1
fi

proj="$(mktemp -d)"
log="$proj/run.log"
trap 'rm -rf "$proj"' EXIT
# ONLY the UI layer and this test are staged, and that is the point: the default
# UI must compile with no GDExtension present (the runtime readers call into
# InsimulCore, which does not exist in a plain godot project), so ANY parse error
# in the staged tree is a UI bug rather than a missing native build.
mkdir -p "$proj/addons/insimul/tests"
cp -r "$pkg_root/addons/insimul/ui" "$proj/addons/insimul/ui"
cp "$here/ui_registry_test.gd" "$proj/addons/insimul/tests/ui_registry_test.gd"
cat > "$proj/project.godot" <<'EOF'
config_version=5

[application]
config/name="insimul-ui-registry-test"
EOF

echo "ui-registry: importing project with $GODOT ..."
# The import pass is what registers the addon's global class_names.
"$GODOT" --headless --path "$proj" --import >/dev/null 2>&1 || true
if [[ ! -f "$proj/.godot/global_script_class_cache.cfg" ]]; then
	echo "ui-registry: godot did not register the addon class names (import pass failed)" >&2
	exit 1
fi

echo "ui-registry: running headless test with $GODOT ..."
set +e
"$GODOT" --headless --path "$proj" \
	-s "addons/insimul/tests/ui_registry_test.gd" \
	-- --conformance "$conformance" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e

# `godot -s` exits 0 on a script that failed to PARSE, so the log is the check.
if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script' "$log"; then
	echo "ui-registry: script errors in the run — see the log above" >&2
	exit 1
fi
if ! grep -q '\[insimul-ui\] .* passed, 0 failed' "$log"; then
	echo "ui-registry: the test did not report a clean pass" >&2
	exit 1
fi
exit "$status"
