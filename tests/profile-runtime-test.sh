#!/bin/sh
# platform: host-agnostic
# SKIP (77) until the toolchain is staged, or when this host cannot execute x86_64 at all. Then prove
# coverage works end to end with the shipped toolchain and nothing else: both instrumentation styles
# link (libclang_rt.profile_osx.a is there), the instrumented binary is 10.9-safe, it runs and writes
# its profile, and the toolchain's own llvm-profdata/llvm-cov read back the exact counts.
#
# Configured by environment:
#   TC   toolchain prefix (bin/clang, bin/llvm-profdata, bin/llvm-cov), default $WORK/stage$CROSS_PREFIX.
#        TC=/usr/local/mavergreen/clang22 checks an installed toolchain on the 10.9 box.
#
# In CI an inability to run x86_64 fails the step (the workflow does not treat exit 77 as a skip):
# a profile runtime that links but cannot write a profile is exactly the defect this exists to catch.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
TC="${TC:-$WORK/stage$CROSS_PREFIX}"
CC="$TC/bin/clang"
if [ "${TEST_PHASE:-all}" = verify ]; then
  exec sh "$HERE/support/verify-profile.sh" "$TC" "${TEST_OUT:?}/profile"
fi
[ -x "$CC" ] || { echo "no toolchain at $TC -- skipping"; exit 77; }

# clang.cfg references <CFGDIR>/../SDKs/MacOSX10.9.sdk, which is not redistributed and may be absent
# (a stage; an installed prefix before its first fetch). Never write into TC -- an installed one is
# root's -- but name the pinned SDK on the command line, where it overrides the config's -isysroot.
SDK="$TC/SDKs/MacOSX10.9.sdk"
[ -e "$SDK" ] || SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
[ -d "$SDK" ] || { echo "FAIL: 10.9 SDK not found: '$SDK'" >&2; exit 1; }
cc() { "$CC" -isysroot "$SDK" "$@"; }

. "$HERE/support/target-test-lib.sh"
target_workspace profile
fail() { echo "FAIL: $*" >&2; exit 1; }

# f() runs three times; its taken branch twice, the other once. Markers name the lines to read back.
cat > "$t/p.c" <<'EOF'
static int f(int x) {
  if (x > 0)
    return 1;      /* TAKEN2 */
  return 0;        /* TAKEN1 */
}
int main(void) {
  int i, n = 0;
  for (i = 0; i < 3; i++)
    n += f(i);     /* CALLS3 */
  return n == 2 ? 0 : 1;
}
EOF

# Count llvm-cov show/gcov reports for the line carrying a marker. show: "  9|      3|  n += ...",
# gcov: "        3:    9:  n += ...". Either way the count is the field before the line number's.

echo "==> link (the profile runtime is shipped)"
cc -fprofile-instr-generate -fcoverage-mapping "$t/p.c" -o "$t/instr" \
  || fail "-fprofile-instr-generate does not link: no libclang_rt.profile_osx.a?"
( cd "$t" && cc --coverage p.c -o gcov ) \
  || fail "--coverage does not link: no libclang_rt.profile_osx.a?"

echo "==> compat guard on the instrumented binaries"
sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$t/instr" "$t/gcov"

printf '%s\n' "$t" > "$t/build-path"
target_finish profile
if [ "$TEST_PHASE" = all ]; then sh "$HERE/support/verify-profile.sh" "$TC" "$t"; fi
