#!/usr/bin/env bash
# run_save_tests.sh — the US-GC2 portable-save gate.
#
# Compiles the dependency-free save core (src/{json_value,sha256,canonical_json,
# save_file}.cpp) with test/test_save_system.cpp under a plain C++ toolchain (no
# cmake/godot-cpp/libinsimul) and runs it. This proves the canonical-JSON +
# SHA-256 save contract is byte-identical to packages/core/src/save-envelope.ts:
#   - canonical-JSON fixture vectors,
#   - integrity hashes vs the committed golden vectors (shared with Unreal US-XC2),
#   - v1 -> v3 migration + round-trip,
#   - KB snapshot/restore, and
#   - a Godot-produced export envelope byte-matching the committed cross-check
#     golden the TS guard (save-integrity-crosscheck-godot.test.ts) validates.
#
# When BOOTSTRAP_GOLDEN=1 is set, the produced envelope is written to the
# committed cross-check dir instead of a temp dir (used once to regenerate the
# golden after a fixture change); by default the test compares against it.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"                          # packages/godot/gdextension
pkg_godot="$(cd "$root/.." && pwd)"                 # packages/godot
packages_dir="$(cd "$pkg_godot/.." && pwd)"        # packages
fixtures="$packages_dir/core/conformance/saves"
crosscheck="$pkg_godot/tools/cross-check"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

gen_dir="$out"
if [[ "${BOOTSTRAP_GOLDEN:-0}" == "1" ]]; then
	mkdir -p "$crosscheck"
	gen_dir="$crosscheck"
fi

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

echo "Compiling save-system host tests with $CXX ..."
"$CXX" -std=c++17 -Wall -Wextra -O0 -g \
	-I "$root/src" \
	-DINSIMUL_FIXTURE_DIR="\"$fixtures\"" \
	-DINSIMUL_CROSSCHECK_DIR="\"$crosscheck\"" \
	-DINSIMUL_GEN_DIR="\"$gen_dir\"" \
	"$root/src/json_value.cpp" \
	"$root/src/sha256.cpp" \
	"$root/src/canonical_json.cpp" \
	"$root/src/save_file.cpp" \
	"$root/test/test_save_system.cpp" \
	-o "$out/test_save_system"

"$out/test_save_system"
