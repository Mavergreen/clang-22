#!/bin/sh
# platform: macOS-only -- otool and nm read the staged dylibs
# SKIP (77) until libcxx22 is staged. Then assert its shape: install names at $LIBCXX_PREFIX; one C++ ABI,
# the system's (libc++abi.1 re-exports /usr/lib/libc++abi.dylib and libc++ re-exports libc++abi.1), with
# libSystem as the only other dependency; no rpath and no libunwind; of Recaulk's symbols, exactly its
# libc++abi back-fills exported, by libc++abi.1 alone; every parity name reachable; 10.9-safe;
# relocatable.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
L="$LIBCXX_STAGE/lib"
[ -f "$L/libc++.1.dylib" ] || { echo "libcxx22 not staged at $LIBCXX_STAGE -- skipping"; exit 77; }
CROSS_STAGE="$WORK/stage$CROSS_PREFIX"
RECAULK_A="${RECAULK_A:-$CROSS_STAGE/lib/librecaulk.a}"
[ -f "$RECAULK_A" ] || { echo "FAIL: $RECAULK_A missing"; exit 1; }
NM="${NM:-nm}"; OTOOL="${OTOOL:-otool}"
fail() { echo "FAIL: $*"; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/libcxx-shape.XXXXXX")"; trap 'rm -rf "$T"' EXIT

# Defined exports, one name per line, LC_ALL=C sort -u (for comm). Not a pipeline, so a reader that
# fails fails the test instead of yielding an empty list.
exports() {  # $1 Mach-O, $2 out
  "$NM" -gUj "$1" > "$2.raw" || fail "$NM -gUj $1"
  LC_ALL=C sort -u "$2.raw" > "$2"
}
exports "$RECAULK_A" "$T/recaulk"
# An empty Recaulk set would make the "exports none of Recaulk's symbols" check below pass vacuously.
n="$(grep -c '^_' "$T/recaulk" || true)"
[ "$n" -gt 0 ] || fail "no defined exports read from $RECAULK_A"
# Recaulk's libc++abi back-fills: the names Wowfunhappy's libc++abi.1.dylib exported that 10.9's lacks.
grep -E '^(___cxa_|__ZT[IS])' "$T/recaulk" > "$T/recaulk-cxxabi" || true
[ -s "$T/recaulk-cxxabi" ] || fail "no libc++abi back-fills in $RECAULK_A (older than Recaulk 20261019.1?)"
grep -v '^#' "$ROOT/build/cxxabi-backfills.txt" > "$T/allowed"
SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
for f in "$SDK/usr/lib/libc++abi.dylib" "$SDK/usr/lib/libc++abi.tbd"; do [ -f "$f" ] && exports "$f" "$T/sys" && break; done
[ -s "$T/sys" ] || fail "no exports read from the 10.9 SDK's libc++abi"

for lib in libc++abi.1 libc++.1; do
  d="$L/$lib.dylib"; want_id="$LIBCXX_PREFIX/lib/$lib.dylib"
  "$OTOOL" -D "$d" > "$T/id" || fail "$OTOOL -D $d"
  id="$(tail -n +2 "$T/id")"
  [ "$id" = "$want_id" ] || fail "$lib install name '$id', want '$want_id'"

  "$OTOOL" -L "$d" > "$T/L" || fail "$OTOOL -L $d"
  deps="$(tail -n +2 "$T/L" | sed 's/^[[:space:]]*//' | grep -v -F "$want_id " || true)"
  case "$lib" in
    # libc++abi.1 by @loader_path, so lld finds it beside libc++ wherever libcxx22 sits.
    libc++.1) want_deps="@loader_path/libc++abi.1.dylib /usr/lib/libSystem.B.dylib /usr/lib/libc++abi.dylib"
              reexp="@loader_path/libc++abi.1.dylib /usr/lib/libc++abi.dylib" ;;
    libc++abi.1) want_deps="/usr/lib/libSystem.B.dylib /usr/lib/libc++abi.dylib"; reexp=/usr/lib/libc++abi.dylib ;;
  esac
  [ "$(printf '%s\n' "$deps" | awk '{print $1}' | LC_ALL=C sort)" = "$(printf '%s\n' $want_deps | LC_ALL=C sort)" ] \
    || fail "$lib dependencies:
$deps"
  for r in $reexp; do
    printf '%s\n' "$deps" | grep -F "$r " | grep -q 'reexport)$' \
      || fail "$lib does not reexport $r:
$deps"
  done
  # One C++ ABI: neither dylib defines the ABI library's exception machinery, exported or not, but for
  # the __cxa_ functions Recaulk back-fills (build/cxxabi-backfills.txt), which libc++abi.1 exports.
  "$NM" -m "$d" > "$T/nm" || fail "$NM -m $d"
  grep -v '(undefined)' "$T/nm" | awk '{ print $NF }' | grep -E "$MAV_CXXABI_MACHINERY" | LC_ALL=C sort -u > "$T/machinery" || true
  own="$(LC_ALL=C comm -23 "$T/machinery" "$T/allowed")"
  [ -z "$own" ] || fail "$lib defines C++ ABI machinery of its own:
$own"

  # Extension-safe, as Apple's libc++ is, so an app extension or an extension-safe library (libswiftCore
  # links -application_extension) may link it on a macOS that has extensions, without a warning.
  "$OTOOL" -hv "$d" > "$T/hv" || fail "$OTOOL -hv $d"
  grep -q 'APP_EXTENSION_SAFE' "$T/hv" || fail "$lib is not marked MH_APP_EXTENSION_SAFE"
  "$OTOOL" -l "$d" > "$T/lc" || fail "$OTOOL -l $d"
  # The two greps below pass on empty input, so first prove otool printed the load commands.
  grep -q 'LC_ID_DYLIB' "$T/lc" || fail "$OTOOL -l $d printed no LC_ID_DYLIB, so no load commands were read"
  if grep -q LC_RPATH "$T/lc"; then fail "$lib has an LC_RPATH"; fi
  if grep -E '@rpath|libunwind' "$T/lc"; then fail "$lib names @rpath or libunwind in a load command"; fi

  exports "$d" "$T/$lib"
  # libRecaulkSystem stays the one exporter of Recaulk's back-fills, but for those a program built
  # against Wowfunhappy's libc++abi.1.dylib binds to it by name: libc++abi.1 exports exactly them.
  case "$lib" in
    libc++.1)
      both="$(LC_ALL=C comm -12 "$T/$lib" "$T/recaulk")"
      [ -z "$both" ] || fail "$lib exports Recaulk symbols:
$both" ;;
    libc++abi.1)
      cmp -s "$T/$lib" "$T/recaulk-cxxabi" || fail "$lib exports other than Recaulk's libc++abi back-fills:
$(diff "$T/recaulk-cxxabi" "$T/$lib")" ;;
  esac
  echo "ok $lib: $(wc -l < "$T/$lib" | tr -d ' ') exports"
done

# Parity, through libc++.1.dylib, as every program linked with -lc++ binds: its own exports, libc++abi.1's
# it re-exports, and the system libc++abi that one re-exports. The aligned and sized new and delete moved
# from libc++abi.1 to libc++.1, which defines them when built on the system's libc++abi.
cat "$T/libc++.1" "$T/libc++abi.1" "$T/sys" | LC_ALL=C sort -u > "$T/closure"
for lib in libc++.1 libc++abi.1; do
  missing="$(LC_ALL=C comm -23 "$HERE/fixtures/parity/$lib.exports" "$T/closure")"
  [ -z "$missing" ] || fail "$(printf '%s\n' "$missing" | wc -l | tr -d ' ') of $lib's parity export(s) are not reachable:
$missing"
done
echo "ok parity: every reference name reachable through libc++.1.dylib"

MAVERICKS_DEVIATIONS_ROOT="$ROOT" sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$L/libc++.1.dylib" "$L/libc++abi.1.dylib"
sh "$ROOT/build/verify-relocatable.sh" "$LIBCXX_STAGE"
echo "PASS: libcxx shape"
