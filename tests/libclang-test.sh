#!/bin/sh
# platform: host-agnostic
#   usage: TC=PREFIX libclang-test.sh -- PREFIX has the 10.9 SDK set up (bin/setup-sdk)
# Builds a host program against PREFIX's libclang and clang-c headers and parses Objective-C for
# x86_64/10.9 with it, the way shipyard's objc-source-inventory does: Foundation must parse with no
# errors, every message send must resolve a receiver type, and the library must be this clang.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
# SKIP (77) until a toolchain is staged; rehearse-linux.sh sets TC, and a skip fails it there.
[ -n "${TC:-}" ] && [ -x "$TC/bin/clang" ] || { echo "not built -- skipping"; exit 77; }
fail() { echo "FAIL: libclang: $*" >&2; exit 1; }
case "$(uname -s)" in
  Linux) lib=libclang.so; cc=${HOST_CC:-gcc-12} ;;
  Darwin) lib=libclang.dylib; cc=${HOST_CC:-/usr/bin/clang} ;;
  *) fail "unsupported host $(uname -s)" ;;
esac
[ -r "$TC/include/clang-c/Index.h" ] || fail 'missing include/clang-c/Index.h'
[ -e "$TC/lib/$lib" ] || fail "missing lib/$lib"
SDK="$TC/SDKs/MacOSX10.9.sdk"
[ -r "$SDK/SDKSettings.plist" ] || fail "no 10.9 SDK at $SDK; run bin/setup-sdk"
resource="$("$TC/bin/clang" -print-resource-dir)" || fail 'cannot query the resource directory'
T="$(mktemp -d "${TMPDIR:-/tmp}/libclang.XXXXXX")"; trap 'rm -rf "$T"' EXIT
"$cc" -std=c99 -Wall -Wextra -Werror -I"$TC/include" "$HERE/libclang/parse-objc.c" \
  -L"$TC/lib" "-Wl,-rpath,$TC/lib" -lclang -o "$T/parse-objc" || fail 'host program did not build'
cat > "$T/probe.m" <<'EOF'
#import <Foundation/Foundation.h>
int main(void) {
  NSString *s = [[NSString alloc] initWithUTF8String:"x"];
  return (int)[s length];
}
EOF
out="$("$T/parse-objc" "$resource" "$SDK" "$T/probe.m")" || fail 'parse failed'
printf '%s\n' "$out"
case "$out" in *"clang version 22."*) ;; *) fail 'not a clang 22 libclang' ;; esac
case "$out" in *'errors=0 messages=3'*) ;; *) fail 'expected no errors and 3 resolved message sends' ;; esac
echo 'PASS: libclang parses Objective-C for x86_64/10.9 from a host program'
