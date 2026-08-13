#!/usr/bin/env bash
# run_talos_replay_tests.sh — the gate for the bridge's replay leg (tasklist 183,
# US-2): the Godot leg of §8.6's four-way gameplay conformance.
#
# Builds test/test_talos_replay.cpp against src/talos_replay.cpp under a plain
# C++ toolchain — no cmake, no scons, no godot-cpp, no Godot binary, and no
# libinsimul: the leg reads the portable artifact, plans the ticks and seals the
# outcome, and the knowledge base it plans against belongs to the addon. So this
# gate has nothing it could be faking and always runs.
#
# What it executes is in test_talos_replay.cpp's header. The short version:
# core's own answers about the input-trace artifact, replayed through the C++
# port, plus the mis-ticked control that must diverge.
#
# Usage:
#   bash gdextension/test/run_talos_replay_tests.sh [<repo root>]
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

echo "Compiling the insimul-talos-bridge replay gate with $CXX ..."
"$CXX" -std=c++17 -Wall -Wextra -O1 -g \
	-I "$root/src" \
	"$root/src/json_value.cpp" \
	"$root/src/sha256.cpp" \
	"$root/src/canonical_json.cpp" \
	"$root/src/talos_replay.cpp" \
	"$root/test/test_talos_replay.cpp" \
	-o "$out/test_talos_replay"

"$out/test_talos_replay" "${1:-$repo}"
