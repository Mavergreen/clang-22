#!/bin/sh
# platform: host-agnostic -- assembles and compiles Mach-O objects with the toolchain; runs nothing
# SKIP (77) until a toolchain is staged. An assembled object records the SDK version, as a compiled one
# does (patches/0010): the driver passes cc1as -target-sdk-version, which it ignored, so a .S object
# recorded "sdk n/a" and compiler-rt's arm64 builtins failed the family's arm64 SDK pin.
#
#   TC=<toolchain prefix> sh tests/asm-sdk-version-test.sh     (default: the cross stage)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
TC="${TC:-$WORK/stage$CROSS_PREFIX}"
[ -x "$TC/bin/clang" ] || { echo "not built -- skipping"; exit 77; }
fail() { echo "FAIL: $*"; exit 1; }
t="$(mktemp -d "${TMPDIR:-/tmp}/asm-sdk.XXXXXX")"; trap 'rm -rf "$t"' EXIT

# A sysroot holding only what the driver reads the SDK version from.
mkdir "$t/sdk"
printf '%s\n' '{"CanonicalName":"macosx11.3","MaximumDeploymentTarget":"11.3.99","Version":"11.3"}' \
  > "$t/sdk/SDKSettings.json"
printf '%s\n' '.text' '.globl _f' '_f:' '  ret' > "$t/f.S"
printf '%s\n' 'int g(void) { return 0; }' > "$t/g.c"
sdk_of() { "$TC/bin/llvm-otool" -l "$1" | awk '$1 == "sdk" { print $2; exit }'; }
for src in g.c f.S; do
  "$TC/bin/clang" --no-default-config --target=x86_64-apple-macos11.0 -isysroot "$t/sdk" \
    -c "$t/$src" -o "$t/$src.o" || fail "could not build $src"
  sdk="$(sdk_of "$t/$src.o")"
  [ "$sdk" = 11.3 ] || fail "$src: object records sdk '$sdk', want 11.3"
  echo "ok: $src records sdk $sdk"
done
echo "PASS: assembled objects record the SDK version"
