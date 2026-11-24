#!/bin/sh
# platform: host-agnostic -- links anywhere; runs what it links only on Mac OS X 10.9
# SKIP (77) until a toolchain is staged. A link that names -lSystem ahead of its inputs, as rustc's
# does, must still bind Recaulk's overrides of libSystem names: ld64.lld binds a name to whichever of an
# archive and a dylib it reaches first, so with librecaulk.a only at the tail it bound libSystem's, and
# pthread_get_stacksize_np reported 512 KB for a 10.9 main thread that has 8 MB. The cfgs put
# librecaulk-libsystem.a (build-cross.sh step 5) ahead of the inputs. On 10.9 the program must also
# report the stack rlimit itself.
#
#   TC=<toolchain prefix> sh tests/recaulk-libsystem-order-test.sh     (default: the cross stage)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
TC="${TC:-$WORK/stage$CROSS_PREFIX}"
[ -x "$TC/bin/clang" ] || { echo "not built -- skipping"; exit 77; }
t="$(mktemp -d "${TMPDIR:-/tmp}/recaulk-order.XXXXXX")"; trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

# clang.cfg names <CFGDIR>/../SDKs/MacOSX10.9.sdk, which a stage does not carry (see smoke-target.sh).
if [ ! -e "$TC/SDKs/MacOSX10.9.sdk" ]; then
  SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
  [ -d "$SDK" ] || fail "10.9 SDK not found: '$SDK'"
  [ ! -L "$TC/SDKs" ] || rm -f "$TC/SDKs"
  mkdir -p "$TC/SDKs"; ln -sfn "$SDK" "$TC/SDKs/MacOSX10.9.sdk"
fi

cat > "$t/stack.c" <<'C'
#include <pthread.h>
#include <stdio.h>
int main(void) { printf("%zu\n", pthread_get_stacksize_np(pthread_self())); return 0; }
C
"$TC/bin/clang" -c "$t/stack.c" -o "$t/stack.o"
for drv in clang clang++; do
  "$TC/bin/$drv" -lSystem "$t/stack.o" -o "$t/stack-$drv"
  "$TC/bin/llvm-nm" -m "$t/stack-$drv" | grep -E ' _pthread_get_stacksize_np( \(from [^)]*\))?$' > "$t/nm-$drv" || true
  ! grep -q 'from libSystem' "$t/nm-$drv" || { cat "$t/nm-$drv"; fail "$drv -lSystem first: pthread_get_stacksize_np is libSystem's, not Recaulk's"; }
  # platform: Recaulk 20261121.8 made librecaulk.a's definition weak and hidden (its
  #           build/image-local-shadows.txt), so the program's copy is non-external; it is still the program's
  grep -Eq '\(__TEXT,__text\) (non-)?external( \(was a private external\))? _pthread_get_stacksize_np$' "$t/nm-$drv" \
    || { cat "$t/nm-$drv"; fail "$drv -lSystem first: the program defines no pthread_get_stacksize_np"; }
done
echo "PASS: -lSystem named first still binds Recaulk's pthread_get_stacksize_np"

[ "$(uname -s)/$(uname -r | cut -d. -f1)" = Darwin/13 ] || { echo "not Mac OS X 10.9: the program is not run"; exit 0; }
lim="$(ulimit -s)"
[ "$lim" != unlimited ] || { echo "stack rlimit unlimited: nothing to compare the main thread's size with"; exit 0; }
want=$((lim * 1024))
for drv in clang clang++; do
  got="$("$t/stack-$drv")"
  [ "$got" = "$want" ] || fail "$drv: pthread_get_stacksize_np reports $got, not the rlimit's $want"
done
echo "PASS: the main thread's stack size is the rlimit's $want on 10.9"
