#!/usr/bin/env bash
# run_reimport_tests.sh — host gate for the re-import diff policy core (US-GB3).
# Compiles src/reimport_diff.cpp + src/scene_placement.cpp + src/binding_resolver.cpp
# + src/json_value.cpp + src/canonical_json.cpp + src/sha256.cpp with
# test/test_reimport_diff.cpp under a plain C++ toolchain (no cmake, no
# godot-cpp, no libinsimul) and runs golden-match + policy-coverage +
# determinism against the shared old/new manifests.
#
# When a `godot` binary IS on PATH the @tool GDScript twin
# (addons/insimul/editor/reimport/run_reimport_headless.sh) runs the SAME
# fixtures end-to-end AND applies the diff to a live scene tree; this host gate
# holds the re-import policy contract on a bare box.
#
# Pass `dump` as the first arg to print the freshly computed diff report (used to
# regenerate editor/reimport/fixtures/golden-diff-report.json).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"           # packages/godot/gdextension
fixtures="$(cd "$root/.." && pwd)/addons/insimul/editor/reimport/fixtures"
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

echo "Compiling re-import diff host tests with $CXX ..."
"$CXX" -std=c++17 -Wall -Wextra -O0 -g \
	"$root/src/reimport_diff.cpp" \
	"$root/src/scene_placement.cpp" \
	"$root/src/binding_resolver.cpp" \
	"$root/src/json_value.cpp" \
	"$root/src/canonical_json.cpp" \
	"$root/src/sha256.cpp" \
	"$root/test/test_reimport_diff.cpp" \
	-o "$out/test_reimport_diff"

if [[ "${1:-}" == "dump" ]]; then
	"$out/test_reimport_diff" "$fixtures" dump
else
	"$out/test_reimport_diff" "$fixtures"
fi
