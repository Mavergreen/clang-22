#!/bin/sh
# platform: macOS-only -- compiles and archives a fixture object
# mav_export_list prints an archive's defined, external, non-hidden symbols: a default-visibility
# function and a weak (inline, out-of-line) one, but neither a hidden one nor an undefined reference.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
fail() { echo "FAIL: $*"; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/export-list.XXXXXX")"; trap 'rm -rf "$T"' EXIT
# extern "C" for unmangled names; -fno-exceptions and no unwind tables so an older Apple clang
# emits no *.eh twins beside each function.
cat > "$T/t.cc" <<'EOF'
extern "C" {
int mg_undef(void);
inline __attribute__((noinline)) int mg_weak(void) { return 2; }
__attribute__((visibility("hidden"))) int mg_hid(void) { return 1; }
int mg_pub(void) { return mg_undef() + mg_weak(); }
}
EOF
"${CC:-cc}" -arch x86_64 -x c++ -fno-exceptions -fno-asynchronous-unwind-tables \
  -c "$T/t.cc" -o "$T/t.o" 2>/dev/null \
  || { echo "no working ${CC:-cc} -arch x86_64 -- skipping"; exit 77; }
ar rcs "$T/libt.a" "$T/t.o"
got="$(mav_export_list "$T/libt.a")" || fail "mav_export_list failed"
want="$(printf '%s\n' _mg_pub _mg_weak)"
[ "$got" = "$want" ] || fail "mav_export_list printed:
$got
want:
$want"
echo "PASS: export list"
