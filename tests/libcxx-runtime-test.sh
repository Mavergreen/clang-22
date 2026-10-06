#!/bin/sh
# platform: macOS-only -- compiles against the 10.9 SDK and runs x86_64 binaries
# SKIP (77) until libcxx22 is staged, or when this host cannot execute x86_64 at all. Then prove a real
# C++ program runs against the relinked dylibs: an exception thrown in one image and caught in another,
# iostreams, threads, futures, steady_clock, and the system /usr/lib/libc++.1.dylib loaded into the same
# process (spec Review Focus 1 and 4).
#
# Configured by environment:
#   TC         toolchain prefix (bin/clang++, include/c++/v1, include/mavericks-compat, include/recaulk)
#              default $WORK/stage$CROSS_PREFIX
#   LIBCXX_LIB directory holding libc++.1.dylib and libc++abi.1.dylib, default $LIBCXX_STAGE/lib.
#              When it is $LIBCXX_PREFIX/lib (an installed product) no DYLD_* is set at all.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
TC="${TC:-$WORK/stage$CROSS_PREFIX}"
LIBCXX_LIB="${LIBCXX_LIB:-$LIBCXX_STAGE/lib}"
NM="${NM:-nm}"; OTOOL="${OTOOL:-otool}"
[ -x "$TC/bin/clang++" ] || { echo "no toolchain at $TC -- skipping"; exit 77; }
[ -f "$LIBCXX_LIB/libc++.1.dylib" ] && [ -f "$LIBCXX_LIB/libc++abi.1.dylib" ] \
  || { echo "libcxx22 not staged at $LIBCXX_LIB -- skipping"; exit 77; }

SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
[ -d "$SDK" ] || { echo "FAIL: 10.9 SDK not found: '$SDK'" >&2; exit 1; }

t="$(mktemp -d "${TMPDIR:-/tmp}/libcxx-runtime.XXXXXX")"; trap 'rm -rf "$t"' EXIT   # template: 10.9 BSD mktemp requires one

# libc++ re-exports libc++abi by install name ($LIBCXX_PREFIX/lib), which lld resolves on disk under a
# -syslibroot. A staged lib is not installed there, so give lld a root in which it is.
ROOTFLAG=""
if [ "$LIBCXX_LIB" != "$LIBCXX_PREFIX/lib" ]; then
  mkdir -p "$t/root$LIBCXX_PREFIX"; ln -s "$LIBCXX_LIB" "$t/root$LIBCXX_PREFIX/lib"
  ROOTFLAG="-Wl,-syslibroot,$t/root"
fi

cxx() {
  "$TC/bin/clang++" --no-default-config --target="$TARGET_TRIPLE" -isysroot "$SDK" \
    -mmacosx-version-min="$MACOS_MIN" -fuse-ld=lld -nostdinc++ \
    -isystem "$TC/include/c++/v1" -isystem "$TC/include/mavericks-compat" -isystem "$TC/include/recaulk" \
    -nostdlib++ "$LIBCXX_LIB/libc++.1.dylib" $ROOTFLAG "$@"
}

# How to execute an x86_64 binary. On an x86_64 host, directly. Elsewhere also directly, never through
# /usr/bin/arch: SIP strips DYLD_* across a protected binary, so the dylibs would not be found.
# A staged lib whose install name points at a prefix that is not installed needs a DYLD path on every
# host; an installed one ($LIBCXX_PREFIX/lib) needs none. It is the FALLBACK path on purpose: dyld tries
# the install name first, and only then the leaf name in the fallback directory. DYLD_LIBRARY_PATH would
# also redirect the program's dlopen("/usr/lib/libc++.1.dylib") to the staged dylib (same leaf name),
# so the system libc++ would never load and the coexistence check would be hollow.
# ONE env invocation sets every DYLD_* and execs the program itself: no protected binary (env, sh, arch)
# may sit between an assignment and the program. Usage: run [VAR=val ...] program
run() {
  if [ "$LIBCXX_LIB" = "$LIBCXX_PREFIX/lib" ]; then env "$@"
  else env DYLD_FALLBACK_LIBRARY_PATH="$LIBCXX_LIB" "$@"; fi
}

echo "==> compile"
cxx -dynamiclib -install_name @executable_path/libthrower.dylib "$HERE/libcxx/thrower.cpp" -o "$t/libthrower.dylib" \
  || { echo "FAIL: cannot compile the thrower dylib" >&2; exit 1; }
cxx "$HERE/libcxx/runtime.cpp" "$t/libthrower.dylib" -o "$t/runtime" \
  || { echo "FAIL: cannot compile the runtime program" >&2; exit 1; }

echo "==> the program links the dylibs, not a static runtime"
deps="$("$OTOOL" -L "$t/runtime")"
printf '%s\n' "$deps" | grep -q "$LIBCXX_PREFIX/lib/libc++.1.dylib" \
  || { echo "FAIL: does not link $LIBCXX_PREFIX/lib/libc++.1.dylib" >&2; printf '%s\n' "$deps" >&2; exit 1; }
if printf '%s\n' "$deps" | grep -q '/usr/lib/libc++\.1\.dylib '; then
  echo "FAIL: links the system /usr/lib/libc++.1.dylib" >&2; exit 1
fi
# The brief's blanket "defines no __ZNSt3__1 symbol" cannot hold: header-only template instantiations
# (vector<thread>'s allocator_traits, __thread_specific_ptr, ...) are legitimately defined in the
# program. What a static runtime would add is the out-of-line, non-template entities, so assert none of
# those is defined, and that the program imports libc++ symbols from the dylib instead.
syms="$("$NM" -g "$t/runtime")"
if printf '%s\n' "$syms" | grep -E ' [A-Za-z] __ZNSt3__1(8ios_base|6locale|6thread|5mutex|18condition_variable|12system_error|17bad_function_call)[0-9A-Z]' \
    | grep -v ' [Uu] ' | grep -q .; then
  echo "FAIL: the program defines out-of-line libc++ symbols itself (static runtime)" >&2; exit 1
fi
printf '%s\n' "$syms" | grep -q ' U __ZNSt3__1' \
  || { echo "FAIL: the program imports no libc++ symbols" >&2; exit 1; }

echo "==> can this host execute x86_64?"
# A fresh arm64 runner may not have Rosetta yet; prime it as tests/smoke-native.sh does.
if [ "$(uname -m)" != x86_64 ]; then
  softwareupdate --install-rosetta --agree-to-license >/dev/null 2>&1 || true
fi
printf 'int main(void){return 0;}\n' > "$t/probe.c"
"$TC/bin/clang" --no-default-config --target="$TARGET_TRIPLE" -isysroot "$SDK" -mmacosx-version-min="$MACOS_MIN" \
  -fuse-ld=lld "$t/probe.c" -o "$t/probe" || { echo "FAIL: cannot compile the probe" >&2; exit 1; }
if ! "$t/probe" >/dev/null 2>&1; then
  echo "    SKIP: cannot execute an x86_64/10.9 binary here (no Rosetta)"; exit 77
fi

echo "==> run"
run "$t/runtime" > "$t/out" 2> "$t/err" || { echo "FAIL: the program exited non-zero" >&2; cat "$t/out" "$t/err" >&2; exit 1; }
cat > "$t/want" <<'WANT'
caught across images: from thrower 7
iostream: 3.14 0x2a
threads: 400000
future exception: from worker
steady_clock: monotonic
after system libc++: caught from thrower 9
WANT
cmp -s "$t/want" "$t/out" || { echo "FAIL: unexpected output" >&2; cat "$t/out" >&2; exit 1; }

echo "==> which images loaded"
run DYLD_PRINT_LIBRARIES=1 "$t/runtime" > /dev/null 2> "$t/libs" || { echo "FAIL: rerun failed" >&2; exit 1; }
for l in libc++.1.dylib libc++abi.1.dylib; do
  # dyld may print the directory normalized (no ".." components) or physical, so accept LIBCXX_LIB as given (10.9 dyld keeps
  # "..") and its logical and physical canonical spellings; fixed-string suffix match, dots are not wildcards.
  ok=""
  for d in "$LIBCXX_LIB" "$(cd "$LIBCXX_LIB" && pwd)" "$(cd "$LIBCXX_LIB" && pwd -P)"; do
    awk -v p="$d/$l" '{ n = length($0) - length(p) + 1; if (n > 1 && substr($0, n) == p && substr($0, n - 1, 1) ~ /[ :]/) f = 1 } END { exit !f }' "$t/libs" && ok=1
  done
  [ -n "$ok" ] \
    || { echo "FAIL: $l not loaded from $LIBCXX_LIB" >&2; cat "$t/libs" >&2; exit 1; }
done
# libcxx22 ships no libunwind: the system one (/usr/lib/system/libunwind.dylib, part of libSystem) is
# the unwinder, and anything else would be a libunwind of ours.
if grep 'libunwind' "$t/libs" | grep -qv '[ :]/usr/lib/system/libunwind\.dylib$'; then
  echo "FAIL: a libunwind other than the system's was loaded" >&2; grep libunwind "$t/libs" >&2; exit 1
fi
# The dlopen really loaded the system libc++, so the coexistence claim is a fact, not a no-op.
grep -q '[ :]/usr/lib/libc++\.1\.dylib$' "$t/libs" \
  || { echo "FAIL: the system /usr/lib/libc++.1.dylib never loaded into the process" >&2; exit 1; }
echo "OK libcxx-runtime"
