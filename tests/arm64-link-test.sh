#!/bin/sh
# platform: host-agnostic -- links arm64 Mach-O with the toolchain; runs nothing it links
# SKIP (77) until a toolchain is staged. A program for arm64-apple-macos11.0 must link with no warning:
# the cfgs add librecaulk.a and the builtins to every link, so each must carry an
# arm64 slice. librecaulk.a's is a stub, as arm64 targets 11.0 and needs no back-fill; a link warned
# "has architecture x86_64 which is incompatible" without it. The builtins' is the real compiler-rt,
# against the 11.3 SDK; without it @available's ___isPlatformVersionAtLeast failed to link.
#
#   TC=<toolchain prefix> [ARM64_SDK=<MacOSX11.3.sdk>] sh tests/arm64-link-test.sh
#   (default TC: the cross stage; default ARM64_SDK: shipyard's fetch_sdk.sh --arch arm64)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
TC="${TC:-$WORK/stage$CROSS_PREFIX}"
[ -x "$TC/bin/clang" ] || { echo "not built -- skipping"; exit 77; }
fail() { echo "FAIL: $*"; exit 1; }
"$TC/bin/clang" --print-targets 2>/dev/null | grep -qw aarch64 || fail "$TC/bin/clang cannot target arm64"
ARM64_SDK="${ARM64_SDK:-$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch arm64)}"
[ -d "$ARM64_SDK" ] || fail "no arm64 SDK at '$ARM64_SDK'"
t="$(mktemp -d "${TMPDIR:-/tmp}/arm64-link.XXXXXX")"; trap 'rm -rf "$t"' EXIT

cat > "$t/main.c" <<'EOF'
int main(void) {
  if (__builtin_available(macOS 12.0, *)) return 0;
  return 1;
}
EOF
# -arch as rustc and the cc crate pass it; -fatal_warnings turns either wrong-arch archive into a failure.
"$TC/bin/clang" -arch arm64 -mmacosx-version-min=11.0 -isysroot "$ARM64_SDK" "$t/main.c" -o "$t/main" \
  -Wl,-fatal_warnings -Wl,-t > "$t/link.log" 2>&1 \
  || { cat "$t/link.log"; fail "an arm64 program using @available does not link cleanly"; }
archs="$("$TC/bin/llvm-lipo" -info "$t/main" | sed -n 's/.*: //p' | xargs)"
[ "$archs" = arm64 ] || fail "linked archs '$archs', want arm64"
grep -q 'libclang_rt\.osx\.a(os_version_check\.c\.o)' "$t/link.log" \
  || { cat "$t/link.log"; fail "___isPlatformVersionAtLeast did not come from the arm64 builtins"; }
! grep -q 'librecaulk\.a(' "$t/link.log" || { cat "$t/link.log"; fail "an arm64 link loaded a librecaulk.a member"; }
echo "PASS: arm64 links take the builtins' arm64 slice and nothing from Recaulk"
