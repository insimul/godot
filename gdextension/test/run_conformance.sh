#!/usr/bin/env bash
# run_conformance.sh — the Godot leg of the cross-engine Prolog parity gate.
#
# Compiles src/prolog_value.cpp with test/conformance_host.cpp under a plain C++
# toolchain (no cmake/godot-cpp/libinsimul) and runs the shared conformance
# corpus (packages/core/conformance/prolog/*.json) through the extension's real
# marshalling layer. This is US-GP2's host gate; it holds parity even on a box
# with no Godot editor. When a `godot` binary IS on PATH, tests/conformance_
# runner.gd runs the SAME corpus end-to-end through the built extension.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"                 # packages/godot/gdextension
# packages/godot/gdextension -> packages -> core/conformance/prolog
corpus="$(cd "$root/../.." && pwd)/core/conformance/prolog"
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

echo "Compiling conformance host harness with $CXX ..."
"$CXX" -std=c++17 -Wall -Wextra -O0 -g \
	"$root/src/prolog_value.cpp" \
	"$root/test/conformance_host.cpp" \
	-o "$out/conformance_host"

"$out/conformance_host" "$corpus"
