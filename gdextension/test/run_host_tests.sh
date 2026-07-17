#!/usr/bin/env bash
# run_host_tests.sh — build and run the host marshalling tests with a plain
# C++ toolchain (no cmake, no godot-cpp, no libinsimul required).
#
# This is the US-GP1 marshalling gate. It compiles src/prolog_value.cpp together
# with test/test_marshalling.cpp using clang++ (falls back to c++/g++) and runs
# the resulting binary. Exit non-zero if any case fails.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"           # packages/godot/gdextension
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

echo "Compiling host marshalling tests with $CXX ..."
"$CXX" -std=c++17 -Wall -Wextra -O0 -g \
	"$root/src/prolog_value.cpp" \
	"$root/test/test_marshalling.cpp" \
	-o "$out/test_marshalling"

"$out/test_marshalling"
