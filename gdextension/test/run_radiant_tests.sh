#!/usr/bin/env bash
# run_radiant_tests.sh — the radiant-adoption gate (tasklist 100, US-2/US-3).
#
# Builds libinsimulcore (QuickJS + the vendored @insimul/core bundle) together
# with test/test_radiant_bridge.cpp under a plain C++ toolchain — no cmake, no
# scons, no godot-cpp, no Godot binary — and runs the shared radiant conformance
# corpus (conformance/radiant/*.json, 5 files / 11 cases) through core's REAL
# TypeScript implementation.
#
# UNLIKE this repo's other host gates, this one LINKS libinsimul: core's radiant
# algorithm is Prolog-driven, and the whole point of the adoption (see
# corebridge/js/host-prolog-engine.js) is that it runs on the native Trealla this
# plugin already ships rather than on a wasm copy of it. So the gate needs the
# library, and it FAILS LOUDLY when it is absent rather than skipping — a gate
# that cannot fail is worse than no gate.
#
# Point it at libinsimul with either:
#   INSIMUL_NATIVE_DIST=<dir>   a packaged dist: <dir>/include + <dir>/lib
#   INSIMUL_NATIVE_DIR=<dir>    an insimul-native checkout: <dir>/include + <dir>/build
# Otherwise the usual sibling layouts are probed (see `candidates` below).
#
# Usage:
#   bash gdextension/test/run_radiant_tests.sh                # source=core
#   bash gdextension/test/run_radiant_tests.sh --source none   # pre-adoption leg
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"          # <repo>/gdextension
repo="$(dirname "$root")"          # <repo>
bridge="$root/corebridge"

# ── corpus: prefer the vendored copy (this repo is standalone by design) ──────
if [ -d "$repo/conformance/radiant" ]; then
	corpus="$repo/conformance/radiant"
elif [ -d "$repo/../core/conformance/radiant" ]; then
	corpus="$(cd "$repo/../core/conformance/radiant" && pwd)"
else
	echo "error: no radiant conformance corpus found (looked in $repo/conformance/radiant)" >&2
	exit 1
fi

# ── libinsimul: header + static/shared library ───────────────────────────────
insimul_include=""
insimul_lib=""
candidates=()
if [ -n "${INSIMUL_NATIVE_DIST:-}" ]; then
	candidates+=("$INSIMUL_NATIVE_DIST:lib")
fi
if [ -n "${INSIMUL_NATIVE_DIR:-}" ]; then
	candidates+=("$INSIMUL_NATIVE_DIR:build")
fi
candidates+=(
	"$repo/../native:build"        # <project>/godot + <project>/native
	"$repo/../../native:build"     # packages/godot layout
	"$root/vendor/insimul:lib"     # a dist dropped into the plugin
)
for candidate in "${candidates[@]}"; do
	dir="${candidate%:*}"
	libsub="${candidate##*:}"
	[ -d "$dir" ] || continue
	for name in libinsimul.a libinsimul.dylib libinsimul.so; do
		if [ -f "$dir/$libsub/$name" ]; then
			insimul_lib="$(cd "$dir/$libsub" && pwd)/$name"
			[ -f "$dir/include/insimul.h" ] && insimul_include="$(cd "$dir/include" && pwd)"
			break 2
		fi
	done
done

if [ -z "$insimul_lib" ]; then
	cat >&2 <<-EOF
	error: libinsimul not found — this gate runs core's Prolog-driven radiant
	       algorithm on the NATIVE engine and cannot be faked.

	       Build it (in the insimul-native checkout):
	           cmake -S . -B build && cmake --build build
	       then re-run with one of:
	           INSIMUL_NATIVE_DIR=/path/to/insimul-native  bash $0
	           INSIMUL_NATIVE_DIST=/path/to/dist/<platform> bash $0

	       Searched: ${candidates[*]}
	EOF
	exit 1
fi
# Fall back to the vendored contract header, which is a verbatim copy of the
# shipping one (gdextension/vendor/insimul/insimul.h).
[ -n "$insimul_include" ] || insimul_include="$root/vendor/insimul"

CC="${CC:-}"
CXX="${CXX:-}"
if [[ -z "$CXX" ]]; then
	if command -v clang++ >/dev/null 2>&1; then CXX=clang++
	elif command -v c++ >/dev/null 2>&1; then CXX=c++
	elif command -v g++ >/dev/null 2>&1; then CXX=g++
	else echo "error: no C++ compiler found (clang++/c++/g++)" >&2; exit 127
	fi
fi
if [[ -z "$CC" ]]; then
	if command -v clang >/dev/null 2>&1; then CC=clang
	elif command -v cc >/dev/null 2>&1; then CC=cc
	elif command -v gcc >/dev/null 2>&1; then CC=gcc
	else echo "error: no C compiler found (clang/cc/gcc)" >&2; exit 127
	fi
fi

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

qjs="$bridge/vendor/quickjs"
qjs_version="$(cat "$qjs/VERSION")"

echo "libinsimul: $insimul_lib"
echo "corpus:     $corpus"
echo "Compiling QuickJS $qjs_version with $CC (once; ~3s) ..."
# -O1: quickjs at -O0 is slow enough to dominate the gate's runtime, and at -O2
# the compile itself is. -Wno-* : vendored third-party source is not ours to lint.
qjs_flags=(-std=c11 -O1 -w -DCONFIG_VERSION="\"$qjs_version\"" -I "$qjs")
for unit in quickjs libregexp libunicode cutils dtoa; do
	"$CC" "${qjs_flags[@]}" -c "$qjs/$unit.c" -o "$out/$unit.o" &
done
wait

echo "Compiling libinsimulcore + the radiant gate ..."
"$CC" -std=c11 -Wall -Wextra -O1 -g \
	-DCONFIG_VERSION="\"$qjs_version\"" \
	-I "$qjs" -I "$bridge/include" -I "$bridge/vendor/core" -I "$insimul_include" \
	-c "$bridge/src/insimulcore.c" -o "$out/insimulcore.o"
"$CC" -std=c11 -w -O1 -I "$bridge/vendor/core" \
	-c "$bridge/vendor/core/insimul_core_bundle.c" -o "$out/bundle.o"

"$CXX" -std=c++17 -Wall -Wextra -O1 -g \
	-I "$root/src" -I "$bridge/include" \
	-DINSIMUL_RADIANT_DIR="\"$corpus\"" \
	"$root/src/json_value.cpp" \
	"$root/src/sha256.cpp" \
	"$root/src/canonical_json.cpp" \
	"$root/test/test_radiant_bridge.cpp" \
	"$out"/*.o \
	"$insimul_lib" \
	-o "$out/test_radiant_bridge"

"$out/test_radiant_bridge" "$@"
