#!/bin/sh
# platform: host-agnostic -- links x86_64 Mach-O with the toolchain and reads its load commands; runs nothing
# SKIP (77) until a toolchain is staged. The cfgs name librecaulk.a and no system library for it: each
# Recaulk member carries the frameworks and libraries it needs (LC_LINKER_OPTION, Recaulk 20261119.1
# on), so the linker adds them when it loads that member. A program calling Recaulk forwarders that
# need Security, CoreServices, CoreFoundation and libobjc must therefore link through each driver's own
# cfg and load them, while a plain program loads libSystem alone.
#
#   TC=<toolchain prefix> sh tests/recaulk-autolink-test.sh     (default: the cross stage)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
TC="${TC:-$WORK/stage$CROSS_PREFIX}"
[ -x "$TC/bin/clang" ] || { echo "not built -- skipping"; exit 77; }
fail() { echo "FAIL: $*"; exit 1; }
t="$(mktemp -d "${TMPDIR:-/tmp}/recaulk-autolink.XXXXXX")"; trap 'rm -rf "$t"' EXIT

for cfg in clang.cfg clang++.cfg; do
  [ -f "$TC/bin/$cfg" ] || fail "no $TC/bin/$cfg"
  if grep -nE '^-(lobjc|framework )' "$TC/bin/$cfg"; then
    fail "$cfg names a system library; Recaulk's members carry their own"
  fi
done

# Recaulk's public forwarders, declared here so no SDK header gates them by availability.
cat > "$t/use.c" <<'EOF'
extern int SSLSetALPNProtocols(void *, void *);
extern void *LSCopyDefaultApplicationURLForURL(void *, unsigned, void *);
extern void *objc_readClassPair(void *, void *);
extern void dispatch_activate(void *);
int main(int argc, char **argv) {
  (void)argv;
  if (argc > 99) {
    (void)SSLSetALPNProtocols(0, 0);
    (void)LSCopyDefaultApplicationURLForURL(0, 0, 0);
    (void)objc_readClassPair(0, 0);
    dispatch_activate(0);
  }
  return 0;
}
EOF
printf 'int main(void) { return 0; }\n' > "$t/plain.c"

OTOOL="$TC/bin/llvm-otool"
for drv in clang clang++; do
  "$TC/bin/$drv" -x c "$t/use.c" -o "$t/use" > "$t/use.log" 2>&1 \
    || { cat "$t/use.log"; fail "$drv could not link a program calling Recaulk's forwarders"; }
  "$OTOOL" -L "$t/use" > "$t/use.L" || fail "$OTOOL -L"
  for lib in /System/Library/Frameworks/Security.framework/ /System/Library/Frameworks/CoreServices.framework/ \
             /System/Library/Frameworks/CoreFoundation.framework/ /usr/lib/libobjc.A.dylib; do
    grep -qF "$lib" "$t/use.L" || { cat "$t/use.L"; fail "$drv: the Recaulk program does not load $lib"; }
  done
  "$TC/bin/$drv" -x c "$t/plain.c" -o "$t/plain" > "$t/plain.log" 2>&1 \
    || { cat "$t/plain.log"; fail "$drv could not link a plain program"; }
  "$OTOOL" -L "$t/plain" > "$t/plain.L" || fail "$OTOOL -L"
  deps="$(tail -n +2 "$t/plain.L" | awk '{print $1}' | grep -v '^/usr/lib/libSystem.B.dylib$' | grep -v '^/usr/lib/libc++abi.dylib$' || true)"
  [ -z "$deps" ] || fail "$drv: a plain program loads more than libSystem (and, for C++, libc++abi):
$deps"
  echo "ok $drv: Recaulk's members bring their libraries; a plain program loads libSystem"
done
echo "PASS: Recaulk autolink"
