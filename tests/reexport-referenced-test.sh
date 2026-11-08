#!/bin/sh
# platform: host-agnostic
# SKIP (77) until a toolchain is staged. ld64.lld must re-export only the dylib symbols a link
# references, as ld64 does (patches/0009). Unpatched, it re-exports every dylib symbol matching an
# -exported_symbols_list pattern; with -dead_strip_dylibs the dylib those come from can be dropped,
# leaving export-trie entries with library ordinal 0. This is FFmpeg's shape, scaled down: util,
# codec and format, each exporting _av*, format resolving util's symbol through codec's re-export.
# Checked on the export tries, so on any host.
#
#   TC=<toolchain prefix> sh tests/reexport-referenced-test.sh     (default: the cross stage)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
TC="${TC:-$WORK/stage$CROSS_PREFIX}"
[ -x "$TC/bin/clang" ] && [ -x "$TC/bin/ld64.lld" ] || { echo "not built -- skipping"; exit 77; }
OBJDUMP="$TC/bin/llvm-objdump"; [ -x "$OBJDUMP" ] || { echo "FAIL: no llvm-objdump in $TC/bin"; exit 1; }
SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
t="$(mktemp -d "${TMPDIR:-/tmp}/reexport.XXXXXX")"; trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

printf 'int av_util_used(void) { return 1; }\nint avutil_version(void) { return 2; }\n' > "$t/util.c"
printf 'int av_util_used(void);\nint av_codec(void) { return av_util_used(); }\n' > "$t/codec.c"
printf 'int av_util_used(void);\nint av_format(void) { return av_util_used(); }\n' > "$t/format.c"
echo '_av*' > "$t/exports"
# --ld-path, not -fuse-ld=lld: the driver would take the ld64.lld beside the clang it resolves to.
cc() { "$TC/bin/clang" --no-default-config --target="$TARGET_TRIPLE" -isysroot "$SDK" -mmacosx-version-min="$MACOS_MIN" --ld-path="$TC/bin/ld64.lld" -dynamiclib "$@"; }
cc "$t/util.c" -o "$t/libutil.dylib" -install_name @loader_path/libutil.dylib
cc "$t/codec.c" "$t/libutil.dylib" -Wl,-exported_symbols_list,"$t/exports" -o "$t/libcodec.dylib" -install_name @loader_path/libcodec.dylib
cc "$t/format.c" "$t/libcodec.dylib" "$t/libutil.dylib" -Wl,-dead_strip_dylibs \
  -Wl,-exported_symbols_list,"$t/exports" -o "$t/libformat.dylib" -install_name @loader_path/libformat.dylib

exports() { "$OBJDUMP" --macho --exports-trie "$t/$1" > "$t/$1.trie" || fail "$OBJDUMP --exports-trie $1"; }
has() { awk -v s="$2" '{ for (i = 1; i <= NF; i++) if ($i == s) f = 1 } END { exit !f }' "$t/$1.trie"; }
exports libcodec.dylib; exports libformat.dylib
# The case is set up only if codec re-exports the symbol format uses and format dropped util.
has libcodec.dylib _av_util_used || { cat "$t/libcodec.dylib.trie"; fail 'libcodec re-exports no _av_util_used, so nothing was checked'; }
has libformat.dylib _av_format || { cat "$t/libformat.dylib.trie"; fail 'libformat exports no _av_format'; }
"$OBJDUMP" --macho --dylibs-used "$t/libformat.dylib" | grep -q libutil \
  && fail 'libformat still loads libutil, so -dead_strip_dylibs was not exercised'
for case in 'libcodec.dylib _avutil_version' 'libformat.dylib _avutil_version' 'libformat.dylib _av_codec'; do
  set -- $case
  ! has "$1" "$2" || { cat "$t/$1.trie"; fail "$1 re-exports $2, which its link never referenced"; }
done
echo "PASS: ld64.lld re-exports only referenced dylib symbols"
