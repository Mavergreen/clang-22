#!/bin/sh
# platform: macOS-only -- links Mach-O dylibs with the staged cross clang and reads archives with nm
# build-libcxx.sh -- relink libcxx22, the runtime dylibs installed at $LIBCXX_PREFIX/lib, from what
# build-cross.sh already staged. No compile: the bytes in libc++.a that clang22 users link statically
# are the bytes in libcxx22.
#
# ONE C++ ABI, the system's (build-cross.sh step 3). libc++.1.dylib is LLVM's libc++, built on
# /usr/lib/libc++abi.dylib. libc++abi.1.dylib is not LLVM's libc++abi: it re-exports the system's and
# adds what 10.9's lacks and Wowfunhappy's libc++abi.1.dylib exported (Recaulk's libc++abi back-fills),
# so a program built against his still finds every name, and still only one libc++abi runs.
#
# What each link line decides:
#   -force_load               every member of libc++.a goes in, used or not -- it is a library.
#   librecaulk.a (plain)      back-fills only what libc++ references (clock_gettime &c), linked IN,
#                             never exported: libRecaulkSystem stays the one exporter of back-fills,
#                             or two images would offer clock_gettime to one process. The exception
#                             is libc++abi.1.dylib's, which exports the libc++abi back-fills (-u pulls
#                             each in by name): those are names his libc++abi.1.dylib exported, so a
#                             program bound to it looks for them here.
#   -exported_symbols_list    each dylib's own interface and nothing else.
#   -application_extension    marks both MH_APP_EXTENSION_SAFE, as Apple's libc++ is, so an extension or
#                             an extension-safe library (libswiftCore) links them on a macOS that has
#                             extensions without a warning; libc++ calls no extension-unavailable API.
#                             lld warns that 10.9's own libraries are not so marked: they predate
#                             extensions (10.10), so the warning is expected and harmless.
#   -reexport_library         libc++ re-exports libc++abi.1, as Apple's and Wowfunhappy's do, and
#   -reexport-lc++abi         both re-export the system's /usr/lib/libc++abi.dylib, libc++ directly
#                             too, so its one C++ ABI is visible in its own load commands.
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
[ -f "$RTDIR/libc++.a" ] || { echo "FATAL: libc++.a missing from $RTDIR" >&2; exit 1; }
# Nothing below links the builtins: each dylib gets them from clang's own driver, which links
# lib/clang/*/lib/darwin/libclang_rt.osx.a by default. The check is a guard that the cross stage is
# whole, so a broken runtimes build fails here, by name, instead of as unresolved ___muloti4 & co.
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
# llvm-nm warns "<archive>:<member>: no symbols" for each empty member (fstream.cpp.o, ...): expected,
# so it is dropped; anything else nm says still reaches the log.
mav_export_list "$RTDIR/libc++.a" > "$EXP/libc++.exp" 2> "$EXP/libc++.err" || { cat "$EXP/libc++.err" >&2; exit 1; }
grep -v ': no symbols$' "$EXP/libc++.err" >&2 || true
# Recaulk's libc++abi back-fills: its __cxa_ functions and the type_info objects (__ZTI/__ZTS).
mav_export_list "$RECAULK_A" > "$EXP/recaulk.all" || exit 1
grep -E '^(___cxa_|__ZT[IS])' "$EXP/recaulk.all" > "$EXP/libc++abi.exp" || true
for lib in libc++ libc++abi; do
  [ -s "$EXP/$lib.exp" ] || { echo "FATAL: nothing for $lib.1.dylib to export (is Recaulk older than 20261019.1?)" >&2; exit 1; }
  echo "    $lib.exp: $(wc -l < "$EXP/$lib.exp" | tr -d ' ') symbols"
done
set --
while read -r sym; do set -- "$@" "-Wl,-u,$sym"; done < "$EXP/libc++abi.exp"

echo "==> link"
LINK="--no-default-config --target=$TARGET_TRIPLE -isysroot $SDK -mmacosx-version-min=$MACOS_MIN -fuse-ld=lld -dynamiclib -compatibility_version 1.0.0 -current_version 1.0.0 -Wl,-application_extension"
"$CC" $LINK -install_name "$LIBCXX_PREFIX/lib/libc++abi.1.dylib" \
  -Wl,-reexport-lc++abi "$@" "$RECAULK_A" \
  -Wl,-exported_symbols_list,"$EXP/libc++abi.exp" -o "$OUT/libc++abi.1.dylib"
"$CC" $LINK -install_name "$LIBCXX_PREFIX/lib/libc++.1.dylib" \
  -Wl,-force_load,"$RTDIR/libc++.a" -Wl,-reexport_library,"$OUT/libc++abi.1.dylib" -Wl,-reexport-lc++abi "$RECAULK_A" \
  -Wl,-exported_symbols_list,"$EXP/libc++.exp" -o "$OUT/libc++.1.dylib"

echo "OK: libcxx22 staged at $LIBCXX_STAGE"
