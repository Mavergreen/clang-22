#!/bin/sh
# platform: macOS-only -- links Mach-O dylibs with the staged cross clang and reads archives with nm
# build-libcxx.sh -- relink libcxx22: LLVM's libc++ and libc++abi as runtime dylibs installed at
# $LIBCXX_PREFIX/lib, made from the x86_64/10.9 runtimes archives build-cross.sh already staged. No
# compile: the bytes in libc++.a that clang22 users link statically are the bytes in libcxx22.
#
# What each link line decides:
#   -force_load               every member of the archive goes in, used or not -- it is a library.
#   librecaulk.a (plain)      back-fills only what the runtimes reference (clock_gettime &c), linked
#                             IN, never exported: libRecaulkSystem stays the one exporter of
#                             back-fills, or two images would offer clock_gettime to one process.
#   -exported_symbols_list    the archive's own interface and nothing else (mav_export_list).
#   -reexport_library         libc++ re-exports libc++abi, as Apple's and Wowfunhappy's do.
#   --no-default-config       keeps the toolchain's clang.cfg (-dead_strip_dylibs, frameworks, its own
#                             librecaulk.a) out. The C driver adds -lSystem and the builtins, never
#                             libc++, and nothing names libunwind: exceptions unwind through the
#                             system unwinder in libSystem.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/versions.sh"
: "${SHIPYARD_SCRIPTS:?mavericks-shipyard not found; install it -- see its README}"

CROSS_STAGE="$WORK/stage$CROSS_PREFIX"
[ -x "$CROSS_STAGE/bin/clang" ] || { echo "FATAL: run build-cross.sh first (need $CROSS_STAGE/bin/clang)" >&2; exit 1; }
CC="$CROSS_STAGE/bin/clang"
SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
[ -d "$SDK" ] || { echo "FATAL: 10.9 SDK not found: '$SDK'" >&2; exit 1; }

# Where LLVM put the x86_64/10.9 C++ runtime: discovered exactly as build-cross.sh discovers it.
RTDIR="$(dirname "$(find "$CROSS_STAGE/lib" -name 'libc++.a' -print 2>/dev/null | head -1)")"
[ -d "$RTDIR" ] || { echo "FATAL: no libc++.a under $CROSS_STAGE/lib -- did the runtimes build run?" >&2; exit 1; }
for lib in libc++.a libc++abi.a; do
  [ -f "$RTDIR/$lib" ] || { echo "FATAL: $lib missing from $RTDIR" >&2; exit 1; }
done
set -- "$CROSS_STAGE"/lib/clang/*/lib/darwin/libclang_rt.osx.a
[ -f "$1" ] || { echo "FATAL: no compiler-rt builtins (lib/clang/*/lib/darwin/libclang_rt.osx.a) under $CROSS_STAGE" >&2; exit 1; }
RECAULK_A="$CROSS_STAGE/lib/librecaulk.a"
[ -f "$RECAULK_A" ] || { echo "FATAL: $RECAULK_A missing -- run build-cross.sh first" >&2; exit 1; }
echo "==> runtimes archives: ${RTDIR#"$CROSS_STAGE"/}"

EXP="$WORK/libcxx-exports"
OUT="$LIBCXX_STAGE/lib"
# Only the two products are replaced: LIBCXX_STAGE may be pointed at a tree that holds more.
rm -rf "$EXP"; mkdir -p "$EXP" "$OUT"
rm -f "$OUT/libc++.1.dylib" "$OUT/libc++abi.1.dylib"

echo "==> export lists"
for lib in libc++abi libc++; do
  mav_export_list "$RTDIR/$lib.a" > "$EXP/$lib.exp"
  [ -s "$EXP/$lib.exp" ] || { echo "FATAL: $RTDIR/$lib.a exports nothing" >&2; exit 1; }
  echo "    $lib.exp: $(wc -l < "$EXP/$lib.exp" | tr -d ' ') symbols"
done

echo "==> link"
LINK="--no-default-config --target=$TARGET_TRIPLE -isysroot $SDK -mmacosx-version-min=$MACOS_MIN -fuse-ld=lld -dynamiclib -compatibility_version 1.0.0 -current_version 1.0.0"
"$CC" $LINK -install_name "$LIBCXX_PREFIX/lib/libc++abi.1.dylib" \
  -Wl,-force_load,"$RTDIR/libc++abi.a" "$RECAULK_A" \
  -Wl,-exported_symbols_list,"$EXP/libc++abi.exp" -o "$OUT/libc++abi.1.dylib"
"$CC" $LINK -install_name "$LIBCXX_PREFIX/lib/libc++.1.dylib" \
  -Wl,-force_load,"$RTDIR/libc++.a" -Wl,-reexport_library,"$OUT/libc++abi.1.dylib" "$RECAULK_A" \
  -Wl,-exported_symbols_list,"$EXP/libc++.exp" -o "$OUT/libc++.1.dylib"

echo "OK: libcxx22 staged at $LIBCXX_STAGE"
