#!/bin/sh
# platform: macOS-only -- runs a toolchain's clang and ld64.lld
# SKIP (77) until staged. ld64.lld must read a .tbd whose targets name an architecture it has no
# slice for: macOS 27's SDK stubs (usr/lib/libSystem.tbd, libc++.tbd, ...) list arm64e.x1-macos, and
# LLVM 22.1.8's TextAPI reader rejects the whole file ("unknown architecture"), so nothing linked
# against the host SDK there. patches/ carries upstream's fix. Linking x86_64 against a stub that
# lists x86_64 too checks the reader, not the slice: the failure was parsing, whatever -arch asked for.
#
#   TC=<toolchain prefix> sh tests/tbd-arch-test.sh     (default: the cross stage)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
TC="${TC:-$WORK/stage$CROSS_PREFIX}"
[ -x "$TC/bin/clang" ] && [ -x "$TC/bin/ld64.lld" ] || { echo "not built -- skipping"; exit 77; }
OTOOL="$TC/bin/llvm-otool"; [ -x "$OTOOL" ] || OTOOL=otool

t="$(mktemp -d "${TMPDIR:-/tmp}/tbd-arch.XXXXXX")"; trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

printf 'extern int mg_tbd(void);\nint f(void) { return mg_tbd(); }\n' > "$t/f.c"
"$TC/bin/clang" --no-default-config --target=x86_64-apple-macos10.9 -c "$t/f.c" -o "$t/f.o"

stub() { # $1 file, $2 targets; dyld_stub_binder is the one symbol lld wants of libSystem
  cat > "$1" <<EOF
--- !tapi-tbd
tbd-version: 4
targets: [ $2 ]
install-name: '/usr/lib/libmgtbd.dylib'
exports:
  - targets: [ $2 ]
    symbols: [ _mg_tbd, dyld_stub_binder ]
...
EOF
}

link() { # $1 stub, $2 output
  "$TC/bin/ld64.lld" -dylib -arch x86_64 -platform_version macos 10.9.0 10.9.0 \
    -install_name /usr/lib/libmgf.dylib -o "$2" "$t/f.o" "$1" > "$2.log" 2>&1
}

# The control: a stub of known architectures links, so a failure below is the reader's.
stub "$t/plain.tbd" 'x86_64-macos, arm64-macos, arm64e-macos'
link "$t/plain.tbd" "$t/plain.dylib" || { cat "$t/plain.dylib.log"; fail "a plain .tbd did not link"; }

stub "$t/x1.tbd" 'x86_64-macos, arm64e-macos, arm64e.x1-macos'
link "$t/x1.tbd" "$t/x1.dylib" || { cat "$t/x1.dylib.log"; fail "ld64.lld cannot read a .tbd that lists arm64e.x1 (macOS 27's SDK)"; }
"$OTOOL" -L "$t/x1.dylib" | grep -q '/usr/lib/libmgtbd.dylib' || fail "the arm64e.x1 stub linked, but its dylib is not a dependency"
echo "OK tbd-arch"
