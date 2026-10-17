#!/bin/sh
# platform: macOS-only -- compiles and links x86_64 Mach-O against the 10.9 SDK and librecaulk.a
# The QoS API compiles and links for 10.9 through the toolchain's header search order: our overlay
# (build/shim/include, shipped as include/mavericks-compat) BEFORE the pinned Recaulk's headers, then
# librecaulk.a. A program calling qos_class_self, qos_class_main and pthread_set_qos_class_self_np
# must build: neither copy may contradict the other, and every call must resolve.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
fail() { echo "FAIL: $*"; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/qos-overlay.XXXXXX")"; trap 'rm -rf "$T"' EXIT
SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
CC_="${CC:-cc} -arch x86_64 -isysroot $SDK -mmacosx-version-min=$MACOS_MIN"
printf 'int main(void){return 0;}\n' > "$T/probe.c"
$CC_ "$T/probe.c" -o "$T/probe" >/dev/null 2>&1 || { echo "no working ${CC:-cc} for x86_64/10.9 -- skipping"; exit 77; }
A="$(MAVERICKS_WORK="$T/work" sh "$ROOT/build/fetch-recaulk.sh" 2>"$T/fetch.err" | tail -1)" \
  || { cat "$T/fetch.err"; fail "cannot fetch the pinned Recaulk"; }
INC="$(dirname "$(dirname "$A")")/include"
cat > "$T/q.c" <<'C'
#include <pthread/qos.h>
int main(void) {
  qos_class_t s = qos_class_self(), m = qos_class_main();
  (void)pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, 0);
  return (s == QOS_CLASS_UNSPECIFIED || m == QOS_CLASS_UNSPECIFIED) ? 1 : 0;
}
C
$CC_ -Werror=implicit-function-declaration -isystem "$ROOT/build/shim/include" -isystem "$INC/recaulk" \
  "$T/q.c" "$A" -framework CoreFoundation -framework Security -framework CoreServices -lobjc -o "$T/q" \
  || fail "a 10.9 program calling the QoS API does not build through the overlay and Recaulk $RECAULK_VERSION"
echo "OK qos-overlay-test"
