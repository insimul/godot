#!/usr/bin/env bash
# run_talos_bridge_tests.sh — the gate for `insimul-talos-bridge` (tasklist 183).
#
# Builds test/test_talos_bridge.cpp against the decision half of the bridge under
# a plain C++ toolchain — no cmake, no scons, no godot-cpp, no Godot binary, and
# no libinsimul either: nothing in the decision half touches a knowledge base, so
# unlike run_corpus_tests.sh this gate has nothing it could be faking and always
# runs.
#
# What it executes is in test_talos_bridge.cpp's header. The short version: the
# refuse-at-hello reference implementation's own 21 cases, replayed through this
# port, plus the two controls that prove the decision is read from the published
# matrix rather than baked into the build.
#
# Usage:
#   bash gdextension/test/run_talos_bridge_tests.sh [<repo root>]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"          # <repo>/gdextension
repo="$(dirname "$root")"          # <repo>

CXX="${CXX:-}"
if [[ -z "$CXX" ]]; then
	if command -v clang++ >/dev/null 2>&1; then CXX=clang++
	elif command -v c++ >/dev/null 2>&1; then CXX=c++
	elif command -v g++ >/dev/null 2>&1; then CXX=g++
	else echo "error: no C++ compiler found (clang++/c++/g++)" >&2; exit 127
	fi
fi

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

echo "Compiling the insimul-talos-bridge decision gate with $CXX ..."
"$CXX" -std=c++17 -Wall -Wextra -O1 -g \
	-I "$root/src" \
	"$root/src/json_value.cpp" \
	"$root/src/sha256.cpp" \
	"$root/src/canonical_json.cpp" \
	"$root/src/talos_bridge.cpp" \
	"$root/test/test_talos_bridge.cpp" \
	-o "$out/test_talos_bridge"

"$out/test_talos_bridge" "${1:-$repo}"
