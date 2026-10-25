#!/bin/sh
# platform: host-agnostic
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
. "$HERE/support/target-test-lib.sh"

SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
[ -d "$SDK" ] || { echo "FAIL: 10.9 SDK not found: '$SDK'"; exit 1; }
SDK113="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch arm64)"
[ -d "$SDK113/usr/include/c++/v1" ] || { echo "FAIL: no libc++ headers in the 11.3 SDK '$SDK113'"; exit 1; }

target_workspace cxxabi
fail=0

# clang.cfg names <CFGDIR>/../SDKs/MacOSX10.9.sdk, which a stage does not carry (see smoke-target.sh).
if [ ! -e "$TC/SDKs/MacOSX10.9.sdk" ]; then
  [ ! -L "$TC/SDKs" ] || rm -f "$TC/SDKs"
  mkdir -p "$TC/SDKs"; ln -sfn "$SDK" "$TC/SDKs/MacOSX10.9.sdk"
fi

cc_plain() {
  "$TC/bin/clang++" --no-default-config --target="$TARGET_TRIPLE" -isysroot "$SDK" \
    -mmacosx-version-min="$MACOS_MIN" --ld-path="$TC/bin/ld64.lld" "$@"
}
cc_plain -nostdinc++ -isystem "$SDK113/usr/include/c++/v1" -std=c++14 -O1 \
  -dynamiclib "$HERE/cxxabi/sys.cpp" -o "$t/libsys.dylib" -install_name @loader_path/libsys.dylib -lc++ \
  || { echo "FAIL: could not build the system-libc++ side"; exit 1; }
ours() {
  "$@" -std=c++20 -O1 -fobjc-exceptions "-I$HERE/cxxabi" "$HERE/cxxabi/interop.mm" \
    -framework Foundation "$t/libsys.dylib"
}

# Static libc++ must not mix per-image locale state when a C++ plugin is loaded.
"$TC/bin/clang++" -std=c++20 -dynamiclib "$HERE/cxxabi/stream-plugin.cpp" \
  -o "$t/libstream.dylib" -install_name @loader_path/libstream.dylib
"$TC/bin/clang++" -std=c++20 "$HERE/cxxabi/stream-host.cpp" -o "$t/stream-host"

shapes="static"
ours "$TC/bin/clang++" -o "$t/interop-static" || { echo "FAIL: the toolchain's clang++ could not build interop.mm"; exit 1; }
# Its pointer and member-pointer handlers catch by LLVM 22's rules on 10.9 too: the cfg's librecaulk.a
# must supply the two vtables they point at (Recaulk's cxxabi_pointer_catch.c, private to the program),
# ahead of /usr/lib/libc++abi.dylib's. Checked here on any host; the catch-* cases run them.
for vt in __ZTVN10__cxxabiv119__pointer_type_infoE __ZTVN10__cxxabiv129__pointer_to_member_type_infoE; do
  "$TC/bin/llvm-nm" -m "$t/interop-static" | grep -q "non-external (was a private external) $vt\$" \
    || { echo "FAIL: the toolchain's clang++ takes $vt from libc++abi, not Recaulk, so 10.9's catch rules apply"; exit 1; }
done
echo "ok: the pointer catch rules are linked in"
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
  ours cc_plain -nostdinc++ -isystem "$TC/include/c++/v1" \
    -isystem "$TC/include/recaulk" -o "$t/interop-dylib" \
    -nostdlib++ "$LIBCXX_LIB/libc++.1.dylib" "$TC/lib/librecaulk.a" -lobjc \
    || { echo "FAIL: could not build interop.mm against libcxx22"; exit 1; }
  # ...and on libcxx22, its libc++abi.1.dylib exports them, ahead of the system's it re-exports.
  for vt in __ZTVN10__cxxabiv119__pointer_type_infoE __ZTVN10__cxxabiv129__pointer_to_member_type_infoE; do
    "$TC/bin/llvm-nm" -gU "$LIBCXX_LIB/libc++abi.1.dylib" | grep -q " $vt\$" \
      || { echo "FAIL: libcxx22's libc++abi.1.dylib does not export $vt, so programs on it keep 10.9's catch rules"; exit 1; }
  done
  shapes="static dylib"
else
  echo "note: libcxx22 not staged at $LIBCXX_LIB -- the dylib shape is not checked"
fi

printf '%s\n' "$shapes" > "$t/shapes"
if [ "$shapes" = 'static dylib' ]; then
  mkdir -p "$t/libcxx"
  cp "$LIBCXX_LIB/libc++.1.dylib" "$LIBCXX_LIB/libc++abi.1.dylib" "$t/libcxx/"
fi
target_finish cxxabi
