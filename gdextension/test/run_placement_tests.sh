#!/usr/bin/env bash
# run_placement_tests.sh — host gate for the scene-generation placement math
# core (US-GB2). Compiles src/scene_placement.cpp + src/binding_resolver.cpp +
# src/json_value.cpp + src/canonical_json.cpp + src/sha256.cpp with
# test/test_scene_placement.cpp under a plain C++ toolchain (no cmake, no
# godot-cpp, no libinsimul) and runs golden-match + placeholder-coverage +
# determinism against the shared golden IR.
#
# When a `godot` binary IS on PATH the @tool GDScript twin
# (addons/insimul/editor/scene/run_scene_generator_headless.sh) runs the SAME
# fixtures end-to-end; this host gate holds the placement contract on a bare box.
#
# Pass `dump` as the first arg to print the freshly computed manifest (used to
# regenerate editor/scene/fixtures/golden-placement-manifest.json).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"           # packages/godot/gdextension
fixtures="$(cd "$root/.." && pwd)/addons/insimul/editor/scene/fixtures"
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

echo "Compiling scene-placement host tests with $CXX ..."
"$CXX" -std=c++17 -Wall -Wextra -O0 -g \
	"$root/src/scene_placement.cpp" \
	"$root/src/binding_resolver.cpp" \
	"$root/src/json_value.cpp" \
	"$root/src/canonical_json.cpp" \
	"$root/src/sha256.cpp" \
	"$root/test/test_scene_placement.cpp" \
	-o "$out/test_scene_placement"

if [[ "${1:-}" == "dump" ]]; then
	"$out/test_scene_placement" "$fixtures" dump
else
	"$out/test_scene_placement" "$fixtures"
fi
