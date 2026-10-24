#!/bin/sh
# platform: macOS-only -- compiles and links x86_64 Mach-O against the 10.9 SDK and librecaulk.a
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
fail() { echo "FAIL: $*"; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/recaulk-headers.XXXXXX")"; trap 'rm -rf "$T"' EXIT
SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
CC_="${CC:-cc} -arch x86_64 -isysroot $SDK -mmacosx-version-min=$MACOS_MIN"
MAVERICKS_WORK="$T/work" sh "$ROOT/build/fetch-recaulk.sh" > "$T/fetch.out" 2>"$T/fetch.err" \
  || { cat "$T/fetch.err"; fail "cannot fetch the pinned Recaulk $RECAULK_VERSION"; }
RECAULK_A="$(tail -1 "$T/fetch.out")"
RECAULK_INC="$(dirname "$(dirname "$RECAULK_A")")/include"
rc_line="$(grep '^RC=' "$ROOT/build/build-cross.sh")" || fail "build/build-cross.sh sets no RC"
eval "$rc_line"
printf 'int main(void){return 0;}\n' > "$T/probe.c"
if ! $CC_ $RC "$T/probe.c" -o "$T/probe" >/dev/null 2>"$T/probe.err"; then
  grep -q 'unknown argument' "$T/probe.err" && { echo "${CC:-cc} predates the runtimes' flags ($RC) -- skipping"; exit 77; }
  $CC_ "$T/probe.c" -o "$T/probe" >/dev/null 2>&1 || { echo "no working ${CC:-cc} for x86_64/10.9 -- skipping"; exit 77; }
  cat "$T/probe.err"; fail "an empty 10.9 C program does not build with the runtimes' flags ($RC)"
fi
LINK="$RECAULK_A -framework CoreFoundation -framework Security -framework CoreServices -lobjc"
cat > "$T/q.c" <<'C'
#include <stdlib.h>
#include <pthread/qos.h>
int main(void) {
  void *p = aligned_alloc(16, 32);
  free(p);
  (void)qos_class_self();
  (void)qos_class_main();
  (void)pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, 0);
  return 0;
}
C
for std in "" -std=c11; do
  $CC_ $std -Werror=implicit-function-declaration $RC "$T/q.c" $LINK -o "$T/q" \
    || fail "a 10.9 C program (${std:-default}) calling aligned_alloc and the QoS API does not build with the runtimes' flags and Recaulk $RECAULK_VERSION"
done
CXX_="${CXX:-c++} -arch x86_64 -isysroot $SDK -mmacosx-version-min=$MACOS_MIN -std=c++17"
printf '#include <cstdlib>\nint main(){return 0;}\n' > "$T/probe.cpp"
# platform: a current Apple clang looks for libc++'s headers in the SDK, and the 10.9 SDK has none
$CXX_ "$T/probe.cpp" -o "$T/probe" >/dev/null 2>&1 \
  || CXX_="$CXX_ -nostdinc++ -isystem $(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch arm64)/usr/include/c++/v1"
if $CXX_ "$T/probe.cpp" -o "$T/probe" >/dev/null 2>&1; then
  cat > "$T/q.cpp" <<'C'
#include <cstdlib>
#include <pthread/qos.h>
int main() {
  void *p = ::aligned_alloc(16, 32);
  std::free(p);
  (void)qos_class_self();
  return 0;
}
C
  $CXX_ $RC "$T/q.cpp" $LINK -o "$T/qx" \
    || fail "a 10.9 C++17 program calling ::aligned_alloc and the QoS API does not build with the runtimes' flags and Recaulk $RECAULK_VERSION"
else
  echo "note: ${CXX:-c++} cannot build C++17 for x86_64/10.9 here -- the C++ case is not checked"
fi
echo "OK recaulk-headers-test"
