#!/usr/bin/env bash
# run_quest_parity_tests.sh — the two-implementation diff (tasklist 100, US-3).
#
# Runs conformance/quests/{hydration,radiant}-cases.json through BOTH this repo's
# hand-ported C++ quest core (gdextension/src/quest_system.cpp) AND @insimul/core
# through libinsimulcore, and classifies every case as AGREE / FIX / SHAPE /
# REGRESSION against the committed corpus. See test/test_quest_parity.cpp for
# what each classification means and why this diff exists.
#
# Like run_radiant_tests.sh this gate LINKS libinsimul, and FAILS LOUDLY when the
# library is absent rather than skipping — except under `--source cpp`, which
# runs the hand-port alone and needs neither libinsimul nor QuickJS.
#
# Point it at libinsimul with either:
#   INSIMUL_NATIVE_DIST=<dir>   a packaged dist: <dir>/include + <dir>/lib
#   INSIMUL_NATIVE_DIR=<dir>    an insimul-native checkout: <dir>/include + <dir>/build
#
# Usage:
#   bash gdextension/test/run_quest_parity_tests.sh                # both legs
#   bash gdextension/test/run_quest_parity_tests.sh --source cpp   # hand-port only
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"          # <repo>/gdextension
repo="$(dirname "$root")"          # <repo>
bridge="$root/corebridge"

source_arg="both"
args=()
while [ $# -gt 0 ]; do
	case "$1" in
		--source) source_arg="$2"; args+=("$1" "$2"); shift 2 ;;
		*) args+=("$1"); shift ;;
	esac
done

# ── corpus: prefer the vendored copy (this repo is standalone by design) ──────
if [ -d "$repo/conformance/quests" ]; then
	corpus="$repo/conformance/quests"
elif [ -d "$repo/../core/conformance/quests" ]; then
	corpus="$(cd "$repo/../core/conformance/quests" && pwd)"
else
	echo "error: no quest conformance corpus found (looked in $repo/conformance/quests)" >&2
	exit 1
fi

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

cxx_sources=(
	"$root/src/json_value.cpp"
	"$root/src/sha256.cpp"
	"$root/src/canonical_json.cpp"
	"$root/src/save_file.cpp"
	"$root/src/quest_system.cpp"
	"$root/test/test_quest_parity.cpp"
)
cxx_flags=(-std=c++17 -Wall -Wextra -O1 -g -I "$root/src" -I "$bridge/include"
	-DINSIMUL_QUESTS_DIR="\"$corpus\"")
link_objs=()
link_libs=()

if [ "$source_arg" != "cpp" ]; then
	# ── libinsimul: header + static/shared library ───────────────────────────
	insimul_include=""
	insimul_lib=""
	candidates=()
	[ -n "${INSIMUL_NATIVE_DIST:-}" ] && candidates+=("$INSIMUL_NATIVE_DIST:lib")
	[ -n "${INSIMUL_NATIVE_DIR:-}" ] && candidates+=("$INSIMUL_NATIVE_DIR:build")
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
		error: libinsimul not found — the core leg of this diff runs @insimul/core
		       on the NATIVE engine and cannot be faked.

		       Build it (in the insimul-native checkout):
		           cmake -S . -B build && cmake --build build
		       then re-run with one of:
		           INSIMUL_NATIVE_DIR=/path/to/insimul-native  bash $0
		           INSIMUL_NATIVE_DIST=/path/to/dist/<platform> bash $0
		       Or run the hand-port alone:
		           bash $0 --source cpp

		       Searched: ${candidates[*]}
		EOF
		exit 1
	fi
	# Fall back to the vendored contract header (a verbatim copy of the shipping one).
	[ -n "$insimul_include" ] || insimul_include="$root/vendor/insimul"

	qjs="$bridge/vendor/quickjs"
	qjs_version="$(cat "$qjs/VERSION")"
	echo "libinsimul: $insimul_lib"
	echo "Compiling QuickJS $qjs_version with $CC (once; ~3s) ..."
	qjs_flags=(-std=c11 -O1 -w -DCONFIG_VERSION="\"$qjs_version\"" -I "$qjs")
	for unit in quickjs libregexp libunicode cutils dtoa; do
		"$CC" "${qjs_flags[@]}" -c "$qjs/$unit.c" -o "$out/$unit.o" &
	done
	wait

	echo "Compiling libinsimulcore ..."
	"$CC" -std=c11 -Wall -Wextra -O1 -g \
		-DCONFIG_VERSION="\"$qjs_version\"" \
		-I "$qjs" -I "$bridge/include" -I "$bridge/vendor/core" -I "$insimul_include" \
		-c "$bridge/src/insimulcore.c" -o "$out/insimulcore.o"
	"$CC" -std=c11 -w -O1 -I "$bridge/vendor/core" \
		-c "$bridge/vendor/core/insimul_core_bundle.c" -o "$out/bundle.o"

	link_objs=("$out"/*.o)
	link_libs=("$insimul_lib")
else
	# The core leg is off, but test_quest_parity.cpp still includes insimulcore.h
	# and calls into it, so the ABI must still link: compile the C host WITHOUT
	# a Prolog engine is not an option (libinsimulcore needs it). Instead the
	# `cpp` mode links nothing and relies on the binary never calling create().
	echo "note: --source cpp — the hand-port runs alone; libinsimulcore is stubbed out."
	cat > "$out/nocore.c" <<-'EOF'
	/* Link-time stub for --source cpp: the core leg is not run, so these are
	   never called. Aborting rather than returning NULL means a future edit that
	   DOES call them under --source cpp fails loudly instead of silently
	   reporting perfect agreement between one implementation and nothing. */
	#include <stdlib.h>
	#include <stdio.h>
	struct insimul_core;
	static void nope(const char *fn) {
		fprintf(stderr, "test_quest_parity: %s called under --source cpp\n", fn);
		abort();
	}
	struct insimul_core *insimul_core_create(void) { nope("insimul_core_create"); return 0; }
	void insimul_core_destroy(struct insimul_core *c) { (void)c; nope("insimul_core_destroy"); }
	const char *insimul_core_call(struct insimul_core *c, const char *m, const char *a) {
		(void)c; (void)m; (void)a; nope("insimul_core_call"); return 0;
	}
	const char *insimul_core_last_error(struct insimul_core *c) { (void)c; nope("insimul_core_last_error"); return 0; }
	const char *insimul_core_version(void) { nope("insimul_core_version"); return 0; }
	EOF
	"$CC" -std=c11 -O1 -c "$out/nocore.c" -o "$out/nocore.o"
	link_objs=("$out/nocore.o")
fi

echo "Compiling the quest-parity diff with $CXX ..."
"$CXX" "${cxx_flags[@]}" "${cxx_sources[@]}" "${link_objs[@]}" ${link_libs[@]+"${link_libs[@]}"} \
	-o "$out/test_quest_parity"

"$out/test_quest_parity" ${args[@]+"${args[@]}"}
