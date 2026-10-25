#!/bin/sh
# platform: host-agnostic
# SKIP (77) until a toolchain is staged. What the toolchain links must stay relocatable after the
# fact, the way ld64's output is: clang.cfg and clang++.cfg pass -headerpad_max_install_names, since
# ld64.lld's default header pad left a dylib 40 bytes for new load commands. And when they still do not
# fit, llvm-install-name-tool must refuse, as Apple's install_name_tool does, rather than write them
# over __text and exit 0 with a corrupt file (patches/0008).
#
#   TC=<toolchain prefix> sh tests/headerpad-test.sh     (default: the cross stage)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
TC="${TC:-$WORK/stage$CROSS_PREFIX}"
[ -x "$TC/bin/clang" ] && [ -x "$TC/bin/ld64.lld" ] || { echo "not built -- skipping"; exit 77; }
INT="$TC/bin/llvm-install-name-tool"; OTOOL="$TC/bin/llvm-otool"
[ -x "$INT" ] && [ -x "$OTOOL" ] || { echo "FAIL: no llvm-install-name-tool or llvm-otool in $TC/bin"; exit 1; }
SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
t="$(mktemp -d "${TMPDIR:-/tmp}/headerpad.XXXXXX")"; trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

# clang.cfg names <CFGDIR>/../SDKs/MacOSX10.9.sdk, which a stage does not carry (see smoke-target.sh).
if [ ! -e "$TC/SDKs/MacOSX10.9.sdk" ]; then
  [ ! -L "$TC/SDKs" ] || rm -f "$TC/SDKs"
  mkdir -p "$TC/SDKs"; ln -sfn "$SDK" "$TC/SDKs/MacOSX10.9.sdk"
fi

printf 'int f(void) { return 1; }\n' > "$t/f.c"
# Eight rpaths of this length need over 600 bytes, many times ld64.lld's default pad.
long=@loader_path/../../../../lib/rustlib/x86_64-apple-darwin/lib
add_rpaths() { for i in 1 2 3 4 5 6 7 8; do "$INT" -add_rpath "$long/$i" "$1" || return 1; done; }

for drv in clang clang++; do
  "$TC/bin/$drv" -x c -dynamiclib "$t/f.c" -o "$t/cfg.dylib"
  add_rpaths "$t/cfg.dylib" || fail "$drv's cfg links a dylib with no room for 8 more rpaths"
  "$OTOOL" -l "$t/cfg.dylib" > "$t/lc" || fail "8 rpaths added to $drv's dylib left it unreadable"
  [ "$(grep -c LC_RPATH "$t/lc")" = 8 ] || fail "$drv's dylib has $(grep -c LC_RPATH "$t/lc") rpaths, not 8"
done
echo "ok: the cfgs leave room to add rpaths"

# Without the cfgs, ld64.lld's default pad: the rpaths do not fit, and the tool must say so.
"$TC/bin/clang" --no-default-config --target="$TARGET_TRIPLE" -isysroot "$SDK" -mmacosx-version-min="$MACOS_MIN" \
  --ld-path="$TC/bin/ld64.lld" -dynamiclib "$t/f.c" -o "$t/tight.dylib"
# Each rpath that is added must leave the file readable; the first that does not fit must be refused.
for i in 1 2 3 4 5 6 7 8; do
  if "$INT" -add_rpath "$long/$i" "$t/tight.dylib" 2>"$t/err"; then
    "$OTOOL" -l "$t/tight.dylib" >/dev/null 2>&1 \
      || fail "llvm-install-name-tool wrote rpath $i past the header pad, over __text, and exited 0"
  else
    break
  fi
done
[ -s "$t/err" ] || fail "8 rpaths fit in ld64.lld's default pad, so the refusal was not checked"
grep -q 'headerpad_max_install_names' "$t/err" || { cat "$t/err"; fail "llvm-install-name-tool failed, but not for lack of header space"; }
"$OTOOL" -l "$t/tight.dylib" >/dev/null || fail "llvm-install-name-tool refused but left the dylib unreadable"
echo "ok: llvm-install-name-tool refuses what does not fit: $(head -1 "$t/err")"
echo "PASS: headerpad"
