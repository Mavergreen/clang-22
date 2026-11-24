#!/bin/sh
# platform: host-agnostic
# SKIP (77) until a toolchain is staged. llvm-install-name-tool must edit a dylib that re-exports
# another, as libcxx22's libc++.1.dylib re-exports libc++abi.1.dylib: -id, -add_rpath and -change on it,
# with -change rewriting the re-exported dylib's name too, as Apple's install_name_tool does. LLVM 22.1.8
# refused the whole image, "unsupported load command (cmd=0x8000001f)" (patches/0012).
#
#   TC=<toolchain prefix> sh tests/install-name-reexport-test.sh     (default: the cross stage)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
TC="${TC:-$WORK/stage$CROSS_PREFIX}"
[ -x "$TC/bin/clang" ] && [ -x "$TC/bin/ld64.lld" ] || { echo "not built -- skipping"; exit 77; }
INT="$TC/bin/llvm-install-name-tool"; OTOOL="$TC/bin/llvm-otool"
[ -x "$INT" ] && [ -x "$OTOOL" ] || { echo "FAIL: no llvm-install-name-tool or llvm-otool in $TC/bin"; exit 1; }
SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
t="$(mktemp -d "${TMPDIR:-/tmp}/install-name-reexport.XXXXXX")"; trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

# clang.cfg names <CFGDIR>/../SDKs/MacOSX10.9.sdk, which a stage does not carry (see smoke-target.sh).
if [ ! -e "$TC/SDKs/MacOSX10.9.sdk" ]; then
  [ ! -L "$TC/SDKs" ] || rm -f "$TC/SDKs"
  mkdir -p "$TC/SDKs"; ln -sfn "$SDK" "$TC/SDKs/MacOSX10.9.sdk"
fi

printf 'int base(void) { return 1; }\n' > "$t/base.c"
printf 'int base(void);\nint re(void) { return base() + 1; }\n' > "$t/re.c"
"$TC/bin/clang" -dynamiclib "$t/base.c" -install_name /old/libbase.dylib -o "$t/libbase.dylib"
"$TC/bin/clang" -dynamiclib "$t/re.c" -install_name /old/libre.dylib -Wl,-reexport_library,"$t/libbase.dylib" \
  -o "$t/libre.dylib"
"$OTOOL" -l "$t/libre.dylib" | grep -q LC_REEXPORT_DYLIB || fail "the fixture carries no LC_REEXPORT_DYLIB"

"$INT" -id @rpath/libre.dylib "$t/libre.dylib" 2>"$t/err" || { cat "$t/err"; fail "-id refused a dylib that re-exports another"; }
[ "$("$OTOOL" -D "$t/libre.dylib" | tail -1)" = @rpath/libre.dylib ] || fail "-id did not take"
"$INT" -add_rpath /some/where "$t/libre.dylib" 2>"$t/err" || { cat "$t/err"; fail "-add_rpath refused it"; }
"$INT" -change /old/libbase.dylib @rpath/libbase.dylib "$t/libre.dylib" 2>"$t/err" || { cat "$t/err"; fail "-change refused it"; }
"$OTOOL" -l "$t/libre.dylib" > "$t/l"
grep -A2 LC_REEXPORT_DYLIB "$t/l" | grep -q ' name @rpath/libbase.dylib ' || { cat "$t/l"; fail "-change left the re-exported dylib's name"; }
grep -A2 LC_RPATH "$t/l" | grep -q ' path /some/where ' || fail "-add_rpath wrote no LC_RPATH"
echo 'PASS: llvm-install-name-tool edits a dylib that re-exports another'
