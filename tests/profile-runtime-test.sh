#!/bin/sh
# platform: macOS-only -- compiles against the 10.9 SDK and runs x86_64 binaries
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
[ -x "$CC" ] || { echo "no toolchain at $TC -- skipping"; exit 77; }

# clang.cfg references <CFGDIR>/../SDKs/MacOSX10.9.sdk, which is not redistributed and may be absent
# (a stage; an installed prefix before its first fetch). Never write into TC -- an installed one is
# root's -- but name the pinned SDK on the command line, where it overrides the config's -isysroot.
SDK="$TC/SDKs/MacOSX10.9.sdk"
[ -e "$SDK" ] || SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
[ -d "$SDK" ] || { echo "FAIL: 10.9 SDK not found: '$SDK'" >&2; exit 1; }
cc() { "$CC" -isysroot "$SDK" "$@"; }

t="$(mktemp -d "${TMPDIR:-/tmp}/profile-runtime.XXXXXX")"; trap 'rm -rf "$t"' EXIT   # template: 10.9 BSD mktemp requires one
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
count_show() { awk -F'|' -v m="$2" 'index($0, m) { gsub(/ /, "", $2); print $2; exit }' "$1"; }
count_gcov() { awk -F':' -v m="$2" 'index($0, m) { gsub(/ /, "", $1); print $1; exit }' "$1"; }
expect() {   # expect <what> <got> <want>
  [ "$2" = "$3" ] || fail "$1: expected $3, got '${2:-nothing}'"
}

echo "==> link (the profile runtime is shipped)"
cc -fprofile-instr-generate -fcoverage-mapping "$t/p.c" -o "$t/instr" \
  || fail "-fprofile-instr-generate does not link: no libclang_rt.profile_osx.a?"
( cd "$t" && cc --coverage p.c -o gcov ) \
  || fail "--coverage does not link: no libclang_rt.profile_osx.a?"

echo "==> compat guard on the instrumented binaries"
sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$t/instr" "$t/gcov"

echo "==> run"
# Prime Rosetta on a non-x86_64 host. An instrumented binary that will not execute here is a SKIP
# locally; CI turns the 77 into a failure.
[ "$(uname -m)" = x86_64 ] || softwareupdate --install-rosetta --agree-to-license >/dev/null 2>&1 || true
printf 'int main(void){return 0;}\n' > "$t/probe.c"
cc "$t/probe.c" -o "$t/probe" || fail "cannot compile the execution probe"
"$t/probe" 2>/dev/null || { echo "cannot execute an x86_64/10.9 binary here -- skipping"; exit 77; }

LLVM_PROFILE_FILE="$t/instr.profraw" "$t/instr" || fail "the -fprofile-instr-generate binary exited non-zero"
[ -s "$t/instr.profraw" ] || fail "the -fprofile-instr-generate binary wrote no profile"
( cd "$t" && ./gcov ) || fail "the --coverage binary exited non-zero"
ls "$t"/*.gcda >/dev/null 2>&1 || fail "the --coverage binary wrote no .gcda"

echo "==> read back with the toolchain's own tools"
"$TC/bin/llvm-profdata" merge -o "$t/instr.profdata" "$t/instr.profraw" || fail "llvm-profdata merge"
"$TC/bin/llvm-cov" show -use-color=false -instr-profile "$t/instr.profdata" "$t/instr" > "$t/show.txt" \
  || fail "llvm-cov show"
expect "llvm-cov show CALLS3"  "$(count_show "$t/show.txt" CALLS3)"  3
expect "llvm-cov show TAKEN2"  "$(count_show "$t/show.txt" TAKEN2)"  2
expect "llvm-cov show TAKEN1"  "$(count_show "$t/show.txt" TAKEN1)"  1

( cd "$t" && "$TC/bin/llvm-cov" gcov gcov-p.gcda >/dev/null ) || fail "llvm-cov gcov"
[ -f "$t/p.c.gcov" ] || fail "llvm-cov gcov wrote no p.c.gcov"
expect "llvm-cov gcov CALLS3" "$(count_gcov "$t/p.c.gcov" CALLS3)" 3
expect "llvm-cov gcov TAKEN2" "$(count_gcov "$t/p.c.gcov" TAKEN2)" 2
expect "llvm-cov gcov TAKEN1" "$(count_gcov "$t/p.c.gcov" TAKEN1)" 1

echo "OK profile-runtime"
