#!/bin/sh
# platform: host-agnostic
#   usage: verify-profile.sh TOOLCHAIN PROFILE_BUNDLE
set -eu
TC=$1; t="$(cd "$2" && pwd -P)"
fail() { echo "FAIL: $*" >&2; exit 1; }
count_show() { awk -F'|' -v m="$2" 'index($0, m) { gsub(/ /, "", $2); print $2; exit }' "$1"; }
count_gcov() { awk -F':' -v m="$2" 'index($0, m) { gsub(/ /, "", $1); print $1; exit }' "$1"; }
expect() {   # expect <what> <got> <want>
  [ "$2" = "$3" ] || fail "$1: expected $3, got '${2:-nothing}'"
}

echo "==> read back with the toolchain's own tools"
"$TC/bin/llvm-profdata" merge -o "$t/instr.profdata" "$t/instr.profraw" || fail "llvm-profdata merge"
"$TC/bin/llvm-cov" show "-path-equivalence=$(cat "$t/build-path"),$t" -use-color=false -instr-profile "$t/instr.profdata" "$t/instr" > "$t/show.txt" \
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
