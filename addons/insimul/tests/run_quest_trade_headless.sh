#!/usr/bin/env bash
# run_quest_trade_headless.sh — the US-GU2 default-UI quest+trade headless gate.
#
# Runs quest_trade_test.gd end-to-end through a real Godot binary when one is on
# PATH: the shared engine-neutral matrices (conformance/ui/{quest-journal-cases,
# trade-cases}.json) against the pure GDScript view-models
# (InsimulQuestJournalModel, InsimulTradeModel), the STATE-LOCATION INVARIANT, the
# real-quest-system binding (a radiant quest_offered arrival landing in the
# journal), and the view-models behind the ahead-of-corpus panels. No GDExtension
# is needed (all pure GDScript).
#
# It stages ONLY addons/insimul/ui/ plus this test into a throwaway project and
# IMPORTS it first. Both of those are load-bearing:
#
#   - the import pass is what registers the addon's global `class_name`s. Without
#     it every script in the test fails to parse and `godot -s` STILL EXITS 0 — a
#     green gate that ran nothing, which is what this script used to be.
#   - staging only ui/ means any parse error in the staged tree is a UI bug.
#     addons/insimul/runtime/** calls into InsimulCore, which does not exist in a
#     project with no native build, so staging the whole addon fills the log with
#     unrelated errors and makes the log grep useless.
#
# When NO godot binary is available (the Ralph harness), this SKIPS with exit 0 —
# there the GDScript structural lint plus tools/verify-ui/check-ui.mjs cover the
# data-side claims. Mirrors run_ui_registry_headless.sh.
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
	echo "quest-trade: no godot binary on PATH — SKIP (structural lint + check-ui.mjs cover the .gd files)"
	exit 0
fi

if [[ ! -d "$conformance/ui" ]]; then
	echo "quest-trade: no vendored corpus at $conformance/ui" >&2
	exit 1
fi

proj="$(mktemp -d)"
log="$proj/run.log"
trap 'rm -rf "$proj"' EXIT
mkdir -p "$proj/addons/insimul/tests"
cp -r "$pkg_root/addons/insimul/ui" "$proj/addons/insimul/ui"
cp "$here/quest_trade_test.gd" "$proj/addons/insimul/tests/quest_trade_test.gd"
cat > "$proj/project.godot" <<'EOF'
config_version=5

[application]
config/name="insimul-quest-trade-test"
EOF

echo "quest-trade: importing project with $GODOT ..."
"$GODOT" --headless --path "$proj" --import >/dev/null 2>&1 || true
if [[ ! -f "$proj/.godot/global_script_class_cache.cfg" ]]; then
	echo "quest-trade: godot did not register the addon class names (import pass failed)" >&2
	exit 1
fi

echo "quest-trade: running headless test with $GODOT ..."
set +e
"$GODOT" --headless --path "$proj" \
	-s "addons/insimul/tests/quest_trade_test.gd" \
	-- --ui "$conformance/ui" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e

# `godot -s` exits 0 on a script that failed to PARSE, so the log is the check.
if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script' "$log"; then
	echo "quest-trade: script errors in the run — see the log above" >&2
	exit 1
fi
if ! grep -q '\[insimul-ui2\] .* passed, 0 failed' "$log"; then
	echo "quest-trade: the test did not report a clean pass" >&2
	exit 1
fi
exit "$status"
