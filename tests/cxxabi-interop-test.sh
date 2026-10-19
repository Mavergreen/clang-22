#!/bin/sh
# platform: macOS-only -- compiles against the 10.9 and 11.3 SDKs and runs x86_64 binaries
# SKIP (77) until the toolchain is staged, or when this host cannot execute x86_64 at all. Then prove a
# program built by it uses ONE C++ ABI, the system's /usr/lib/libc++abi.dylib, which Foundation's
# libobjc uses too, so C++ and Objective-C exceptions cross between our code, the system's C++ and Cocoa
# in every direction. With a libc++abi of our own in the process, catching an exception the other copy
# threw freed the wrong pointer and crashed ("pointer being freed was not allocated"): the copies'
# exception headers differ.
#
# Two shapes, each built from tests/cxxabi/interop.mm:
#   static  the toolchain's own `clang++`, no flags: clang++.cfg's libc++.a, Recaulk and -lc++abi.
#   dylib   libcxx22 (LIBCXX_LIB), whose libc++abi.1.dylib re-exports the system's.
# The other side, tests/cxxabi/sys.cpp, is built on the system's libc++ (the 11.3 SDK's headers).
#
# Configured by environment, as tests/libcxx-runtime-test.sh:
#   TC          toolchain prefix, default $WORK/stage$CROSS_PREFIX
#   LIBCXX_LIB  libcxx22's lib directory, default $LIBCXX_STAGE/lib; the dylib shape is skipped without it
# On a 10.9 box with both installed:
#   TC=/usr/local/mavergreen/clang22 LIBCXX_LIB=/usr/local/mavergreen/libcxx22/lib sh tests/cxxabi-interop-test.sh
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
TC="${TC:-$WORK/stage$CROSS_PREFIX}"
LIBCXX_LIB="${LIBCXX_LIB:-$LIBCXX_STAGE/lib}"
[ -x "$TC/bin/clang++" ] || { echo "no toolchain at $TC -- skipping"; exit 77; }
if [ "$(uname -m)" != x86_64 ] && ! arch -x86_64 /usr/bin/true 2>/dev/null; then
  echo "this host cannot execute x86_64 -- skipping"; exit 77
fi

SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
[ -d "$SDK" ] || { echo "FAIL: 10.9 SDK not found: '$SDK'"; exit 1; }
SDK113="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch arm64)"
[ -d "$SDK113/usr/include/c++/v1" ] || { echo "FAIL: no libc++ headers in the 11.3 SDK '$SDK113'"; exit 1; }

t="$(mktemp -d "${TMPDIR:-/tmp}/cxxabi-interop.XXXXXX")"; trap 'rm -rf "$t"' EXIT
fail=0

# clang.cfg names <CFGDIR>/../SDKs/MacOSX10.9.sdk, which a stage does not carry (see smoke-target.sh).
if [ ! -e "$TC/SDKs/MacOSX10.9.sdk" ]; then
  [ ! -L "$TC/SDKs" ] || rm -f "$TC/SDKs"
  mkdir -p "$TC/SDKs"; ln -sfn "$SDK" "$TC/SDKs/MacOSX10.9.sdk"
fi

F="--target=$TARGET_TRIPLE -isysroot $SDK -mmacosx-version-min=$MACOS_MIN -fuse-ld=lld"
"$TC/bin/clang++" --no-default-config $F -nostdinc++ -isystem "$SDK113/usr/include/c++/v1" -std=c++14 -O1 \
  -dynamiclib "$HERE/cxxabi/sys.cpp" -o "$t/libsys.dylib" -install_name "$t/libsys.dylib" -lc++ \
  || { echo "FAIL: could not build the system-libc++ side"; exit 1; }
OURS="-std=c++20 -O1 -fobjc-exceptions -I$HERE/cxxabi $HERE/cxxabi/interop.mm -framework Foundation $t/libsys.dylib"

shapes="static"
"$TC/bin/clang++" $OURS -o "$t/interop-static" || { echo "FAIL: the toolchain's clang++ could not build interop.mm"; exit 1; }
RUN_DYLIB=""
# dyld tries the install name first, so with libcxx22 installed a staged copy would never load (as
# tests/libcxx-runtime-test.sh): the run would test the installed one.
if [ "$LIBCXX_LIB" != "$LIBCXX_PREFIX/lib" ] && [ -e "$LIBCXX_PREFIX/lib/libc++.1.dylib" ]; then
  echo "note: libcxx22 is installed at $LIBCXX_PREFIX, which dyld would load instead of $LIBCXX_LIB -- the dylib shape is not checked"
elif [ -f "$LIBCXX_LIB/libc++.1.dylib" ] && [ -f "$LIBCXX_LIB/libc++abi.1.dylib" ]; then
  # As tests/libcxx-runtime-test.sh: a staged libcxx22 links where it is (its re-export is by
  # @loader_path) and is reached at run time through DYLD_FALLBACK_LIBRARY_PATH; an installed one needs
  # neither.
  [ "$LIBCXX_LIB" = "$LIBCXX_PREFIX/lib" ] || RUN_DYLIB="DYLD_FALLBACK_LIBRARY_PATH=$LIBCXX_LIB"
  "$TC/bin/clang++" --no-default-config $F -nostdinc++ -isystem "$TC/include/c++/v1" \
    -isystem "$TC/include/mavericks-compat" -isystem "$TC/include/recaulk" $OURS -o "$t/interop-dylib" \
    -nostdlib++ "$LIBCXX_LIB/libc++.1.dylib" "$TC/lib/librecaulk.a" -lobjc \
    || { echo "FAIL: could not build interop.mm against libcxx22"; exit 1; }
  shapes="static dylib"
else
  echo "note: libcxx22 not staged at $LIBCXX_LIB -- the dylib shape is not checked"
fi

PASSING="one-abi control-new-new control-sys-sys sys-runtime-as-runtime_error sys-runtime-as-exception sys-custom
  sys-any new-runtime-caught-by-sys new-custom-caught-by-sys new-through-sys-frame uncaught-count-across objc-catch-cxx
  objc-raise-through-cxx cxx-catch-objc-any cxx-catch-objc-typed objc-raise-through-sys exception_ptr-across
  make_exception_ptr promise-set-exception uncaught_exceptions bad_array_new_length char8_t const-char8_t-pointer"
TERMINATING="terminate-ours-through-sys terminate-sys terminate-noexcept"
for s in $shapes; do
  env=""; [ "$s" = dylib ] && env="$RUN_DYLIB"
  for c in $PASSING; do
    out="$(env $env "$t/interop-$s" "$c" 2>&1)" && rc=0 || rc=$?
    if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q "^PASS $c:" && ! printf '%s\n' "$out" | grep -q 'pointer being freed'; then echo "ok $s $c"
    else echo "FAIL $s $c (exit $rc): $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"; fail=1; fi
  done
  # Meant to call std::terminate, which reports the exception once and aborts: the system's libc++abi's
  # message, the one runtime's ("libc++abi.dylib: terminating ..." on 10.9, "libc++abi: terminating due
  # to ..." on current macOS). A crash elsewhere, or a second message, is a failure.
  for c in $TERMINATING; do
    out="$(env $env "$t/interop-$s" "$c" 2>&1)" && rc=0 || rc=$?
    if [ "$rc" = 134 ] && [ "$(printf '%s\n' "$out" | grep -c 'terminating')" = 1 ] \
       && printf '%s\n' "$out" | grep -Eq '^libc\+\+abi(\.dylib)?: terminating' && ! printf '%s\n' "$out" | grep -q 'pointer being freed'; then
      echo "ok $s $c (terminated)"
    else echo "FAIL $s $c (exit $rc, want std::terminate's abort): $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"; fail=1; fi
  done
done
[ "$fail" = 0 ] && echo "PASS: one C++ ABI ($shapes)"
exit "$fail"
