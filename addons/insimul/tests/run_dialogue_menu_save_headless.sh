#!/usr/bin/env bash
# run_dialogue_menu_save_headless.sh — the default-UI dialogue / menu / save gate
# (npm run test:ui-dialogue-menu-save).
#
# Runs dialogue_menu_save_test.gd end-to-end through a real Godot binary when one
# is on PATH: the shared engine-neutral matrices
# (conformance/ui/{chat-cases,pause-menu-cases,save-slot-cases}.json) against the
# pure GDScript view-models (InsimulChatModel, InsimulPauseMenuModel,
# InsimulSaveSlotModel), PLUS the node-level legs — the dialogue panel driven by a
# stub streaming service (chunks, TTS, lip-sync, KB actions, history into
# save.conversations), the ESC menu's tab bodies resolved through the registry, the
# menu shell, the save/load rows and the main-menu gate. No GDExtension is needed.
#
# Two things this wrapper exists for, both learned the hard way:
#
#   * THE IMPORT PASS. Godot only registers the addon's global `class_name`s once
#     the project has been scanned. Without `--import` every script in the test
#     fails to parse and `godot -s` STILL EXITS 0 — a green gate that ran nothing.
#     So the import pass is checked (the class cache must appear) and the log is
#     grepped for parse errors afterwards.
#   * STAGING ONLY ui/. The runtime readers call into InsimulCore, which does not
#     exist in a plain godot project, so staging the whole addon fills the log with
#     unrelated errors and makes the log grep useless.
#
# When NO godot binary is available (the Ralph harness), this SKIPS with exit 0 —
# there the GDScript structural lint plus tools/verify-ui/check-ui.mjs cover the
# data-side claims. Mirrors run_quest_trade_headless.sh.
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
	echo "dialogue-menu-save: no godot binary on PATH — SKIP (structural lint + check-ui.mjs cover the .gd files)"
	exit 0
fi

if [[ ! -d "$conformance/ui" ]]; then
	echo "dialogue-menu-save: no vendored corpus at $conformance/ui" >&2
	exit 1
fi

proj="$(mktemp -d)"
log="$proj/run.log"
trap 'rm -rf "$proj"' EXIT
mkdir -p "$proj/addons/insimul/tests"
cp -r "$pkg_root/addons/insimul/ui" "$proj/addons/insimul/ui"
cp "$here/dialogue_menu_save_test.gd" "$proj/addons/insimul/tests/dialogue_menu_save_test.gd"
cat > "$proj/project.godot" <<'EOF'
config_version=5

[application]
config/name="insimul-dialogue-menu-save-test"
EOF

echo "dialogue-menu-save: importing project with $GODOT ..."
"$GODOT" --headless --path "$proj" --import >/dev/null 2>&1 || true
if [[ ! -f "$proj/.godot/global_script_class_cache.cfg" ]]; then
	echo "dialogue-menu-save: godot did not register the addon class names (import pass failed)" >&2
	exit 1
fi

echo "dialogue-menu-save: running headless test with $GODOT ..."
set +e
"$GODOT" --headless --path "$proj" \
	-s "addons/insimul/tests/dialogue_menu_save_test.gd" \
	-- --ui "$conformance/ui" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e

# `godot -s` exits 0 on a script that failed to PARSE, so the log is the check.
if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script' "$log"; then
	echo "dialogue-menu-save: script errors in the run — see the log above" >&2
	exit 1
fi
if ! grep -q '\[insimul-ui3\] .* passed, 0 failed' "$log"; then
	echo "dialogue-menu-save: the test did not report a clean pass" >&2
	exit 1
fi
exit "$status"
