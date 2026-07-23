#!/usr/bin/env bash
# run_content_roundtrip_headless.sh — the content-library ROUND-TRIP parity gate
# (content-portability, US-IM2).
#
# Runs content_roundtrip_test.gd end-to-end through a real Godot binary when one
# is on PATH: it imports the shared content-library fixture through
# InsimulContentLibrary, re-exports the materialized entities, re-imports that
# fresh, and asserts the result matches the shared golden (library.json)
# collection-for-collection and field-for-field — the per-engine leg of the
# author-once / use-anywhere proof.
#
# It stages the addon into a throwaway project (so the addon's global class_names
# resolve during Godot's project scan) then runs the SceneTree test headless,
# pointing --fixtures at the real vendored corpus.
#
# When NO godot binary is available (the Ralph harness), this SKIPS with exit 0 —
# the GDScript structural lint (tools/verify-godot/check.mjs) covers the addon
# `.gd` files. Mirrors run_content_import_headless.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# addons/insimul/tests -> addons/insimul -> addons -> <pkg root>
pkg_root="$(cd "$here/../../.." && pwd)"

# Prefer the vendored corpus (standalone repo); fall back to the monorepo sibling
# layout (packages/core/conformance/content).
if [ -d "$pkg_root/conformance/content" ]; then
	fixtures="$pkg_root/conformance/content"
else
	fixtures="$(cd "$pkg_root/.." && pwd)/core/conformance/content"
fi

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
	echo "content-roundtrip: no godot binary on PATH — SKIP (structural lint covers the addon .gd)"
	exit 0
fi

proj="$(mktemp -d)"
trap 'rm -rf "$proj"' EXIT
mkdir -p "$proj/addons"
cp -r "$pkg_root/addons/insimul" "$proj/addons/insimul"
cat > "$proj/project.godot" <<'EOF'
config_version=5

[application]
config/name="insimul-content-roundtrip-test"
EOF

echo "content-roundtrip: running headless test with $GODOT ..."
# First pass lets Godot import/scan the project so global class_names register.
"$GODOT" --headless --path "$proj" --quit >/dev/null 2>&1 || true
"$GODOT" --headless --path "$proj" \
	-s "addons/insimul/tests/content_roundtrip_test.gd" \
	-- --fixtures "$fixtures"
