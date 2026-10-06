#!/bin/sh
# platform: macOS-only -- otool and nm read the staged dylibs
# SKIP (77) until libcxx22 is staged. Then assert its shape: install names at $LIBCXX_PREFIX, exactly
# libSystem (+ libc++abi, reexported, for libc++) as dependencies, no rpath and no libunwind, none of
# Recaulk's symbols exported, every parity name exported, 10.9-safe, relocatable.
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

for lib in libc++abi.1 libc++.1; do
  d="$L/$lib.dylib"; want_id="$LIBCXX_PREFIX/lib/$lib.dylib"
  "$OTOOL" -D "$d" > "$T/id" || fail "$OTOOL -D $d"
  id="$(tail -n +2 "$T/id")"
  [ "$id" = "$want_id" ] || fail "$lib install name '$id', want '$want_id'"

  "$OTOOL" -L "$d" > "$T/L" || fail "$OTOOL -L $d"
  deps="$(tail -n +2 "$T/L" | sed 's/^[[:space:]]*//' | grep -v -F "$want_id " || true)"
  case "$lib" in
    libc++.1)
      [ "$(printf '%s\n' "$deps" | awk '{print $1}')" = "$(printf '%s\n' "$LIBCXX_PREFIX/lib/libc++abi.1.dylib" /usr/lib/libSystem.B.dylib)" ] \
        || fail "$lib dependencies:
$deps"
      printf '%s\n' "$deps" | grep -F "$LIBCXX_PREFIX/lib/libc++abi.1.dylib " | grep -q 'reexport)$' \
        || fail "$lib does not reexport libc++abi:
$deps" ;;
    libc++abi.1)
      [ "$(printf '%s\n' "$deps" | awk '{print $1}')" = /usr/lib/libSystem.B.dylib ] \
        || fail "$lib dependencies:
$deps" ;;
  esac

  "$OTOOL" -l "$d" > "$T/lc" || fail "$OTOOL -l $d"
  if grep -q LC_RPATH "$T/lc"; then fail "$lib has an LC_RPATH"; fi
  if grep -E '@rpath|libunwind' "$T/lc"; then fail "$lib names @rpath or libunwind in a load command"; fi

  exports "$d" "$T/$lib"
  both="$(LC_ALL=C comm -12 "$T/$lib" "$T/recaulk")"
  [ -z "$both" ] || fail "$lib exports Recaulk symbols:
$both"
  missing="$(LC_ALL=C comm -23 "$HERE/fixtures/parity/$lib.exports" "$T/$lib")"
  [ -z "$missing" ] || fail "$lib lacks $(printf '%s\n' "$missing" | wc -l | tr -d ' ') parity export(s):
$missing"
  echo "ok $lib: $(wc -l < "$T/$lib" | tr -d ' ') exports"
done

MAVERICKS_DEVIATIONS_ROOT="$ROOT" sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$L/libc++.1.dylib" "$L/libc++abi.1.dylib"
sh "$ROOT/build/verify-relocatable.sh" "$LIBCXX_STAGE"
echo "PASS: libcxx shape"
