#!/bin/sh
# platform: macOS-only -- runs the toolchain's clang and, where x86_64 runs, the program it links
# SKIP (77) until a toolchain is staged. An ARC program for 10.9 must link with no libarclite
# (patches/0005), as Apple's toolchains of that era linked it only below 10.8: 10.8's runtime has native
# ARC and its Foundation the subscripting methods arclite back-filled. clang 22 links it below 10.11,
# and ships none, so every -fobjc-arc link for 10.9 failed. The 10.7 control must still ask for it.
#
#   TC=<toolchain prefix> sh tests/arc-link-test.sh     (default: the cross stage)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
TC="${TC:-$WORK/stage$CROSS_PREFIX}"
[ -x "$TC/bin/clang" ] || { echo "not built -- skipping"; exit 77; }
t="$(mktemp -d "${TMPDIR:-/tmp}/arc-link.XXXXXX")"; trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

cat > "$t/arc.m" <<'EOF'
#import <Foundation/Foundation.h>
int main(void) {
  int bad = 0;
  @autoreleasepool {
    NSArray *a = @[@1, @2, @3]; NSDictionary *d = @{@"k": @"v"};
    bad += [a[1] intValue] != 2; bad += ![d[@"k"] isEqual:@"v"];
    NSMutableArray *m = [a mutableCopy]; m[0] = @9; bad += [m[0] intValue] != 9;
    __weak id w = nil;
    @autoreleasepool { id strong = [NSObject new]; w = strong; bad += w != strong; }
    bad += w != nil;
  }
  printf("arc: %d bad\n", bad);
  return bad;
}
EOF
links_arclite() { "$TC/bin/clang" -fobjc-arc "$@" "$t/arc.m" -framework Foundation -o "$t/arc" -### 2>&1 | grep -q arclite; }
links_arclite --target=x86_64-apple-macos10.7 || fail "for 10.7 the driver no longer asks for libarclite, so the 10.9 check proves nothing"
! links_arclite || fail "for 10.9 the driver links libarclite, which 10.9 does not need and the toolchain does not ship"
echo "ok: no libarclite for 10.9, asked for 10.7"

"$TC/bin/clang" -fobjc-arc "$t/arc.m" -framework Foundation -o "$t/arc" || fail "an ARC program for 10.9 does not link"
if [ "$(uname -m)" = x86_64 ] || arch -x86_64 /usr/bin/true 2>/dev/null; then
  out="$("$t/arc")" || fail "ARC program: $out"
  [ "$out" = 'arc: 0 bad' ] || fail "ARC program: $out"
  echo "ok: $out"
else
  echo "note: x86_64 does not run here; linked, not run"
fi
echo "PASS: ARC links without libarclite"
