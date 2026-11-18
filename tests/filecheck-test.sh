#!/bin/sh
# platform: host-agnostic -- runs the toolchain's own FileCheck, which runs where its clang runs
# SKIP (77) until a toolchain is staged. The toolchain ships LLVM's FileCheck, so a 10.9 test gate can
# check output as lit does (asked by swift: its self-test gate skipped tests whose RUN lines pipe
# through FileCheck). It must pass matching input and fail the rest.
#
#   TC=<toolchain prefix> sh tests/filecheck-test.sh     (default: the cross stage)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
TC="${TC:-$WORK/stage$CROSS_PREFIX}"
[ -x "$TC/bin/clang" ] || { echo "not built -- skipping"; exit 77; }
fail() { echo "FAIL: $*"; exit 1; }
FC="$TC/bin/FileCheck"
[ -x "$FC" ] || fail "no $FC"
t="$(mktemp -d "${TMPDIR:-/tmp}/filecheck.XXXXXX")"; trap 'rm -rf "$t"' EXIT

printf '%s\n' '// CHECK: hello' '// CHECK-NEXT: world' '// CHECK-NOT: goodbye' > "$t/checks"
printf 'hello\nworld\n' | "$FC" "$t/checks" || fail "FileCheck rejected matching input"
if printf 'hello\nthere\nworld\n' | "$FC" "$t/checks" 2>/dev/null; then
  fail "FileCheck accepted input that breaks CHECK-NEXT"
fi
echo "PASS: FileCheck matches and rejects as lit expects"
