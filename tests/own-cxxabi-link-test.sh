#!/bin/sh
# platform: host-agnostic -- links only; nothing it builds is run
# SKIP (77) until a toolchain is staged. A program that brings its own static libc++abi, as rusty_v8's
# prebuilt archive does for codex-cli, must link: its definitions win, and no member of librecaulk.a
# that defines the same names is loaded beside them. The cfgs put librecaulk.a at the tail of the link
# (clang's `$` config options), after every input the program names, so the program's archives reach
# each symbol first and Recaulk only fills what is still missing. With librecaulk.a ahead of them,
# ld64.lld loaded Recaulk's __cxa_uncaught_exceptions, __cxa_init_primary_exception and pointer-catch
# vtables first, then the program's own members for other symbols: duplicate symbols.
#
#   TC=<toolchain prefix> sh tests/own-cxxabi-link-test.sh     (default: the cross stage)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
TC="${TC:-$WORK/stage$CROSS_PREFIX}"
[ -x "$TC/bin/clang++" ] || { echo "not built -- skipping"; exit 77; }
t="$(mktemp -d "${TMPDIR:-/tmp}/own-cxxabi.XXXXXX")"; trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

# clang.cfg names <CFGDIR>/../SDKs/MacOSX10.9.sdk, which a stage does not carry (see smoke-target.sh).
if [ ! -e "$TC/SDKs/MacOSX10.9.sdk" ]; then
  SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
  [ -d "$SDK" ] || fail "10.9 SDK not found: '$SDK'"
  [ ! -L "$TC/SDKs" ] || rm -f "$TC/SDKs"
  mkdir -p "$TC/SDKs"; ln -sfn "$SDK" "$TC/SDKs/MacOSX10.9.sdk"
fi

# The program's own libc++abi, shaped as libc++abi's: cxa_exception.o defines the exception entry
# points with __cxa_throw, and private_typeinfo.o the pointer vtables with __dynamic_cast. Each member
# is loaded for the symbol the program names, and brings the rest of its definitions with it.
cat > "$t/cxa_exception.c" <<'EOF'
int __cxa_uncaught_exceptions(void) { return 0; }
void *__cxa_init_primary_exception(void *o, void *t, void (*d)(void *)) { (void)t; (void)d; return o; }
void own_cxa_throw(void) {}
EOF
cat > "$t/private_typeinfo.c" <<'EOF'
const void *const own_pointer_vt[7] __asm__("__ZTVN10__cxxabiv119__pointer_type_infoE") = {0};
const void *const own_ptm_vt[7] __asm__("__ZTVN10__cxxabiv129__pointer_to_member_type_infoE") = {0};
void own_dynamic_cast(void) {}
EOF
# The program names the shared symbols before anything names its own: as a C++ program's catch
# clauses reference the vtables, and libc++ calls __cxa_uncaught_exceptions.
cat > "$t/main.c" <<'EOF'
extern const void *const pointer_vt[] __asm__("__ZTVN10__cxxabiv119__pointer_type_infoE");
extern const void *const ptm_vt[] __asm__("__ZTVN10__cxxabiv129__pointer_to_member_type_infoE");
int __cxa_uncaught_exceptions(void);
void *__cxa_init_primary_exception(void *, void *, void (*)(void *));
void own_cxa_throw(void), own_dynamic_cast(void);
int main(void) {
  own_cxa_throw(); own_dynamic_cast();
  return __cxa_uncaught_exceptions() + (pointer_vt[0] != ptm_vt[0]) + (__cxa_init_primary_exception(0, 0, 0) != 0);
}
EOF
for f in main cxa_exception private_typeinfo; do
  "$TC/bin/clang" -c "$t/$f.c" -o "$t/$f.o" || fail "could not compile $f.c"
done
rm -f "$t/libownabi.a"
"$TC/bin/llvm-ar" rcs "$t/libownabi.a" "$t/cxa_exception.o" "$t/private_typeinfo.o"

# The librecaulk.a members that define any of the shared names (llvm-nm -A: "<archive>:<member>: ...").
"$TC/bin/llvm-nm" -gU -A "$TC/lib/librecaulk.a" \
  | grep -E ' (___cxa_uncaught_exceptions|___cxa_init_primary_exception|__ZTVN10__cxxabiv1(19__pointer|29__pointer_to_member)_type_infoE)$' \
  | sed 's/^[^:]*:\([^:]*\):.*/\1/' | sort -u > "$t/shared-members"
[ "$(wc -l < "$t/shared-members")" -ge 3 ] || fail "librecaulk.a defines too few of the shared names for this test to mean anything: $(cat "$t/shared-members")"

for drv in clang clang++; do
  "$TC/bin/$drv" "$t/main.o" "$t/libownabi.a" -o "$t/prog-$drv" -Wl,-t > "$t/$drv.log" 2>&1 \
    || { grep -E 'error|duplicate' "$t/$drv.log"; fail "$drv: a program bringing its own static libc++abi does not link"; }
  # -t names each archive member as it is loaded.
  while read -r m; do
    ! grep -q -F "librecaulk.a($m)" "$t/$drv.log" || fail "$drv: librecaulk.a($m) was loaded beside the program's own libc++abi"
  done < "$t/shared-members"
  grep -q -F 'libownabi.a(private_typeinfo.o)' "$t/$drv.log" || fail "$drv: the program's own private_typeinfo.o was not loaded"
done
echo "PASS: a program's own static libc++abi wins, and Recaulk's copies stay out"
