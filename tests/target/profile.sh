#!/bin/sh
# platform: macOS-only -- executes saved profile-instrumented Mach-O binaries
set -eu
t="$(cd "$(dirname "$0")" && pwd)"
LLVM_PROFILE_FILE="$t/instr.profraw" "$t/instr"
[ -s "$t/instr.profraw" ] || { echo 'FAIL: no raw profile' >&2; exit 1; }
(cd "$t" && GCOV_PREFIX="$t" GCOV_PREFIX_STRIP=99 ./gcov)
[ -s "$t/gcov-p.gcda" ] || { echo 'FAIL: no gcov counts' >&2; exit 1; }
echo 'PASS: target profile data collected'
