#!/usr/bin/env bash
# run_binding_tests.sh — host gate for the Asset Binding Layer resolver core
# (US-GB1). Compiles src/binding_resolver.cpp + src/json_value.cpp +
# src/canonical_json.cpp + src/sha256.cpp with test/test_binding_resolver.cpp
# under a plain C++ toolchain (no cmake, no godot-cpp, no libinsimul) and runs
# the shared resolver matrix + cross-engine pack round-trip + determinism cases.
#
# When a `godot` binary IS on PATH the GDScript twin
# (addons/insimul/editor/binding/run_binding_resolver_headless.sh) runs the SAME
# fixtures end-to-end; this host gate holds the contract on a bare box.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"           # packages/godot/gdextension
fixtures="$(cd "$root/.." && pwd)/addons/insimul/editor/binding/fixtures"
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

echo "Compiling binding-resolver host tests with $CXX ..."
"$CXX" -std=c++17 -Wall -Wextra -O0 -g \
	"$root/src/binding_resolver.cpp" \
	"$root/src/json_value.cpp" \
	"$root/src/canonical_json.cpp" \
	"$root/src/sha256.cpp" \
	"$root/test/test_binding_resolver.cpp" \
	-o "$out/test_binding_resolver"

"$out/test_binding_resolver" "$fixtures"
