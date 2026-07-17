#!/usr/bin/env bash
# run_bootstrap_tests.sh — the US-GC4 startup-orchestrator gate.
#
# Compiles the dependency-free bootstrap core (src/{json_value,sha256,
# canonical_json,save_file,quest_system,bootstrap}.cpp) with test/test_bootstrap.cpp
# under a plain C++ toolchain (no cmake/godot-cpp/libinsimul) and runs it. This
# proves the full template-startup loop — world source -> save slot -> KB ->
# systems — end-to-end in the portable core, matching the Unreal US-XC4 host test:
#   - boot RESUMES the golden v2-typical save (entity counts = the parity numbers),
#   - NEW-GAME + corrupt-save fallback never bricks startup, and
#   - the full RADIANT -> objective -> save -> reload sequence round-trips quest +
#     radiant facts while the worldSnapshot hash stays stable throughout.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"                          # packages/godot/gdextension
pkg_godot="$(cd "$root/.." && pwd)"                 # packages/godot
packages_dir="$(cd "$pkg_godot/.." && pwd)"        # packages
fixtures="$packages_dir/core/conformance/saves"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

CXX="${CXX:-}"
if [[ -z "$CXX" ]]; then
	if command -v clang++ >/dev/null 2>&1; then
		CXX=clang++
	elif command -v c++ >/dev/null 2>&1; then
		CXX=c++
	elif command -v g++ >/dev/null 2>&1; then
		CXX=g++
	else
		echo "error: no C++ compiler found (clang++/c++/g++)" >&2
		exit 127
	fi
fi

echo "Compiling bootstrap host tests with $CXX ..."
"$CXX" -std=c++17 -Wall -Wextra -O0 -g \
	-I "$root/src" \
	-DINSIMUL_FIXTURE_DIR="\"$fixtures\"" \
	"$root/src/json_value.cpp" \
	"$root/src/sha256.cpp" \
	"$root/src/canonical_json.cpp" \
	"$root/src/save_file.cpp" \
	"$root/src/quest_system.cpp" \
	"$root/src/bootstrap.cpp" \
	"$root/test/test_bootstrap.cpp" \
	-o "$out/test_bootstrap"

"$out/test_bootstrap"
