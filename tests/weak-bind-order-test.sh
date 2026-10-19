#!/bin/sh
# platform: macOS-only -- links with the toolchain's ld64.lld and reads the result with llvm-objdump
# SKIP (77) until a toolchain is staged. ld64.lld must write a program's weak binding info sorted by
# symbol name, as ld64 does (patches/0002). dyld before dyld3, 10.9's among them, coalesces weak
# symbols across images by merging every image's weak binding info as name-sorted streams: an image
# whose info is in address order instead is passed over for the names it reaches late, and two images
# each keep their own definition. A type_info so duplicated makes a catch in one image miss an
# exception thrown in the other; a function-local static in an inline function is duplicated the same
# way. Checked on the table on any host, and at run time where x86_64 runs.
#
#   TC=<toolchain prefix> sh tests/weak-bind-order-test.sh     (default: the cross stage)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
TC="${TC:-$WORK/stage$CROSS_PREFIX}"
[ -x "$TC/bin/clang" ] && [ -x "$TC/bin/ld64.lld" ] || { echo "not built -- skipping"; exit 77; }
OBJDUMP="$TC/bin/llvm-objdump"; [ -x "$OBJDUMP" ] || { echo "FAIL: no llvm-objdump in $TC/bin"; exit 1; }
SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
t="$(mktemp -d "${TMPDIR:-/tmp}/weak-bind.XXXXXX")"; trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

# Weak definitions whose addresses run opposite to their names: z_first is laid out first, a_last last.
# b_override is weak in the dylib and strong in the program, which must win: lld records that as a
# non-weak definition in the program's weak binding info, among the names, so it must be in order too.
cat > "$t/weak.c" <<'EOF'
__attribute__((weak)) int z_first = 1;
__attribute__((weak)) int m_middle = 2;
__attribute__((weak)) int a_last = 3;
int *where_z(void) { return &z_first; }
int *where_m(void) { return &m_middle; }
int *where_a(void) { return &a_last; }
__attribute__((weak)) int b_override = 4;
int *where_b(void) { return &b_override; }
EOF
cat > "$t/main.c" <<'EOF'
#include <stdio.h>
__attribute__((weak)) int z_first = 10;
__attribute__((weak)) int m_middle = 20;
__attribute__((weak)) int a_last = 30;
int b_override = 40;
int *where_z(void); int *where_m(void); int *where_a(void); int *where_b(void);
int main(void) {
  int same = (where_z() == &z_first) + (where_m() == &m_middle) + (where_a() == &a_last) + (where_b() == &b_override);
  printf("%d of 4 weak symbols coalesced\n", same);
  return same == 4 ? 0 : 1;
}
EOF
# --ld-path, not -fuse-ld=lld: the driver would take the ld64.lld beside the clang it resolves to.
cc() { "$TC/bin/clang" --no-default-config --target="$TARGET_TRIPLE" -isysroot "$SDK" -mmacosx-version-min="$MACOS_MIN" --ld-path="$TC/bin/ld64.lld" "$@"; }
cc -dynamiclib "$t/weak.c" -o "$t/libweak.dylib" -install_name "$t/libweak.dylib"
cc "$t/main.c" "$t/libweak.dylib" -o "$t/main"

for f in "$t/libweak.dylib" "$t/main"; do
  "$OBJDUMP" --macho --weak-bind "$f" > "$t/wb" || fail "$OBJDUMP --weak-bind ${f##*/}"
  awk '$1 ~ /^__/ { print $NF }' "$t/wb" > "$t/names"
  grep -qx _a_last "$t/names" || { cat "$t/wb"; fail "${f##*/} has no weak binding for _a_last, so nothing was checked"; }
  LC_ALL=C sort -c "$t/names" 2>/dev/null || { cat "$t/wb"; fail "${f##*/}'s weak binding info is not sorted by symbol name"; }
done
echo "ok: weak binding info sorted by name"

if [ "$(uname -m)" = x86_64 ] || arch -x86_64 /usr/bin/true 2>/dev/null; then
  out="$("$t/main" 2>&1)" || fail "dyld did not coalesce the weak symbols: $out"
  echo "ok: $out"
fi
echo "PASS: weak bind order"
