#!/bin/sh
# platform: host-agnostic
#   usage: rehearse-linux.sh EXPORT TEST_LIBCXX -- inside the baseline build container
set -eu
[ $# -eq 2 ] || exit 2
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/versions.sh"
TC="$WORK/relocated compiler"; export TC
sh "$HERE/assemble-linux.sh" "$WORK/linux-host" "$1" "$TC"
sh "$HERE/verify-linux-host.sh" "$TC"
"$TC/bin/setup-sdk" "$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
NM="$TC/bin/llvm-nm"; LIPO="$TC/bin/llvm-lipo"; OTOOL="$TC/bin/llvm-otool"; STRINGS="$TC/bin/llvm-strings"
export NM LIPO OTOOL STRINGS
sh "$HERE/../tests/smoke-target.sh"
sh "$HERE/../tests/tbd-arch-test.sh"
TEST_PHASE=build; TEST_OUT="$WORK/witnesses"; LIBCXX_LIB=$2
export TEST_PHASE TEST_OUT LIBCXX_LIB
for test in catch-align weak-bind-order cxxabi-interop profile-runtime; do
  sh "$HERE/../tests/$test-test.sh"
done
[ "$(cat "$TEST_OUT/cxxabi/shapes")" = 'static dylib' ] || { echo 'missing required dylib interop shape' >&2; exit 1; }
sh "$HERE/package-linux.sh" "$TC" "$WORK/linux-dist"
