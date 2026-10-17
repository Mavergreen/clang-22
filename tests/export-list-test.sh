#!/bin/sh
# platform: macOS-only -- compiles and archives a fixture object
# mav_export_list prints an archive's defined, external, non-hidden symbols: a default-visibility
# function, a weak (inline, out-of-line) one and a weak automatically-hidden one, but neither a hidden
# one, a weak hidden one, nor an undefined reference.
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
# The two weak flavours a compiler may or may not emit for the C++ above, pinned by assembler
# directives so every compiler produces both: `weak external automatically hidden` (an inline
# function's usual form, still exported) and `weak private external` (hidden, so never listed).
cat > "$T/w.s" <<'EOF'
	.text
	.globl	_mg_autohid
	.weak_def_can_be_hidden	_mg_autohid
_mg_autohid:
	retq
	.globl	_mg_weakhid
	.private_extern	_mg_weakhid
	.weak_definition	_mg_weakhid
_mg_weakhid:
	retq
EOF
# SKIP only when this host cannot compile x86_64 at all; once it can, a fixture that fails to build
# is a failure, not a skip.
printf 'int mg_probe;\n' > "$T/probe.c"
"${CC:-cc}" -arch x86_64 -c "$T/probe.c" -o "$T/probe.o" 2>/dev/null \
  || { echo "no working ${CC:-cc} -arch x86_64 -- skipping"; exit 77; }
"${CC:-cc}" -arch x86_64 -x c++ -fno-exceptions -fno-asynchronous-unwind-tables \
  -c "$T/t.cc" -o "$T/t.o" || fail "cannot compile the C++ fixture"
"${CC:-cc}" -arch x86_64 -c "$T/w.s" -o "$T/w.o" || fail "cannot assemble the weak-symbol fixture"
"${NM:-nm}" -m "$T/w.o" | grep -q 'weak external automatically hidden _mg_autohid$' \
  || fail "the fixture does not define _mg_autohid as weak external automatically hidden"
"${NM:-nm}" -m "$T/w.o" | grep -q 'weak private external _mg_weakhid$' \
  || fail "the fixture does not define _mg_weakhid as weak private external"
ar rcs "$T/libt.a" "$T/t.o" "$T/w.o"
got="$(mav_export_list "$T/libt.a")" || fail "mav_export_list failed"
want="$(printf '%s\n' _mg_autohid _mg_pub _mg_weak)"
[ "$got" = "$want" ] || fail "mav_export_list printed:
$got
want:
$want"
echo "PASS: export list"
