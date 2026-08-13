#!/usr/bin/env bash
# run_mechanic_tests.sh — the band-120 mechanic-module gate (tasklist 147, US-1).
#
# Builds libinsimulcore (QuickJS + the vendored @insimul/core bundle) together
# with test/test_mechanic_bridge.cpp under a plain C++ toolchain — no cmake, no
# scons, no godot-cpp, no Godot binary — and drives the SEVEN band-120 decision
# layers across the C ABI, end to end, on the natively linked libinsimul.
#
# WHAT IT PROVES, and why each part is worth a gate:
#
#   1. The rows EXIST in the shipped bundle (`mechanic.modules` + `core.methods`),
#      which is the only honest way to ask a build what it can do.
#   2. The inversion WORKS: a reading handed in reaches core, and every call core
#      would have made to a host interface comes back out as an order.
#   3. The host cannot DECIDE. The same attack is run twice with opposite
#      trajectory readings and with none at all; core's damage is core's damage.
#   4. Sessions are real: two sessions of one module do not share state, and a
#      disposed session is gone.
#   5. The Prolog seam's assert/retract path works — a fact delta with a KB wired
#      reports `applied: true` and is queryable afterwards.
#
# Like run_radiant_tests.sh it LINKS libinsimul (every decision layer writes its
# delta into a KB) and FAILS LOUDLY when the library is absent rather than
# skipping — a gate that cannot fail is worse than no gate.
#
# Point it at libinsimul with either:
#   INSIMUL_NATIVE_DIST=<dir>   a packaged dist: <dir>/include + <dir>/lib
#   INSIMUL_NATIVE_DIR=<dir>    an insimul-native checkout: <dir>/include + <dir>/build
#
# Usage:
#   bash gdextension/test/run_mechanic_tests.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"          # <repo>/gdextension
repo="$(dirname "$root")"          # <repo>
bridge="$root/corebridge"

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
	error: libinsimul not found — this gate runs core's mechanic decision
	       layers on the NATIVE Prolog engine and cannot be faked.

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
echo "Compiling QuickJS $qjs_version with $CC (once; ~3s) ..."
# -O1: quickjs at -O0 is slow enough to dominate the gate's runtime, and at -O2
# the compile itself is. -Wno-* : vendored third-party source is not ours to lint.
qjs_flags=(-std=c11 -O1 -w -DCONFIG_VERSION="\"$qjs_version\"" -I "$qjs")
for unit in quickjs libregexp libunicode cutils dtoa; do
	"$CC" "${qjs_flags[@]}" -c "$qjs/$unit.c" -o "$out/$unit.o" &
done
wait

echo "Compiling libinsimulcore + the mechanic gate ..."
"$CC" -std=c11 -Wall -Wextra -O1 -g \
	-DCONFIG_VERSION="\"$qjs_version\"" \
	-I "$qjs" -I "$bridge/include" -I "$bridge/vendor/core" -I "$insimul_include" \
	-c "$bridge/src/insimulcore.c" -o "$out/insimulcore.o"
"$CC" -std=c11 -w -O1 -I "$bridge/vendor/core" \
	-c "$bridge/vendor/core/insimul_core_bundle.c" -o "$out/bundle.o"

"$CXX" -std=c++17 -Wall -Wextra -O1 -g \
	-I "$root/src" -I "$bridge/include" \
	"$root/src/json_value.cpp" \
	"$root/src/sha256.cpp" \
	"$root/src/canonical_json.cpp" \
	"$root/test/test_mechanic_bridge.cpp" \
	"$out"/*.o \
	"$insimul_lib" \
	-o "$out/test_mechanic_bridge"

"$out/test_mechanic_bridge" "$@"
