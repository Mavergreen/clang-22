#!/bin/sh
# platform: macOS-only -- compiles Mach-O fixtures and verify-relocatable.sh reads them with otool
# verify-relocatable.sh must pass a prefix whose images name only allowed paths, fail one that names
# an absolute path outside them, and fail -- not pass everything -- when its otool cannot run.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
fail() { echo "FAIL: $*"; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/verify-relocatable-gate.XXXXXX")"; trap 'rm -rf "$T"' EXIT
CC_="${CC:-cc}"
printf 'int main(void){return 0;}\n' > "$T/main.c"
"$CC_" "$T/main.c" -o "$T/probe" >/dev/null 2>&1 || { echo "no working $CC_ -- skipping"; exit 77; }
gate() { sh "$ROOT/build/verify-relocatable.sh" "$1" > "$T/out" 2>&1; }

mkdir -p "$T/good/bin"
"$CC_" "$T/main.c" -o "$T/good/bin/tool" || fail "cannot compile the good fixture"
gate "$T/good" || { cat "$T/out"; fail "a prefix naming only libSystem must pass"; }

mkdir -p "$T/bad/bin"
printf 'int dep(void){return 0;}\n' > "$T/dep.c"
"$CC_" -dynamiclib "$T/dep.c" -install_name "$T/libdep.dylib" -o "$T/libdep.dylib" || fail "cannot compile the dependency"
"$CC_" "$T/main.c" "$T/libdep.dylib" -o "$T/bad/bin/tool" || fail "cannot compile the bad fixture"
if gate "$T/bad"; then cat "$T/out"; fail "a prefix naming $T/libdep.dylib must fail"; fi

if OTOOL="$T/no-such-otool" gate "$T/bad"; then cat "$T/out"; fail "an otool that cannot run must fail the gate"; fi
grep -q 'no-such-otool' "$T/out" || { cat "$T/out"; fail "the failure names the otool that could not run"; }

echo "OK verify-relocatable-gate-test"
