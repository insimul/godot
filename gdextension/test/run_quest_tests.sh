#!/usr/bin/env bash
# run_quest_tests.sh — the US-GC3 portable quest gate.
#
# Compiles the dependency-free quest core (src/{json_value,sha256,canonical_json,
# save_file,quest_system}.cpp) with test/test_quest_system.cpp under a plain C++
# toolchain (no cmake/godot-cpp/libinsimul) and runs it. This proves the three
# quest guarantees are byte-identical to the TS semantics authority:
#   - HYDRATION parity vs the golden corpus (conformance/quests/hydration-cases.json),
#   - RADIANT parity vs the golden corpus (conformance/quests/radiant-cases.json),
#   - query-driven completion + fact-asserting transitions on the KB, and a
#     save round-trip preserving quest+radiant facts while worldSnapshot hash stays
#     stable (shared golden fixture conformance/saves/v2-typical.json).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"                          # packages/godot/gdextension
pkg_godot="$(cd "$root/.." && pwd)"                 # packages/godot
packages_dir="$(cd "$pkg_godot/.." && pwd)"        # packages
fixtures="$packages_dir/core/conformance/saves"
quests="$packages_dir/core/conformance/quests"
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

echo "Compiling quest-system host tests with $CXX ..."
"$CXX" -std=c++17 -Wall -Wextra -O0 -g \
	-I "$root/src" \
	-DINSIMUL_FIXTURE_DIR="\"$fixtures\"" \
	-DINSIMUL_QUESTS_DIR="\"$quests\"" \
	"$root/src/json_value.cpp" \
	"$root/src/sha256.cpp" \
	"$root/src/canonical_json.cpp" \
	"$root/src/save_file.cpp" \
	"$root/src/quest_system.cpp" \
	"$root/test/test_quest_system.cpp" \
	-o "$out/test_quest_system"

"$out/test_quest_system"
