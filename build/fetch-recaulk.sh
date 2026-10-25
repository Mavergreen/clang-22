#!/bin/sh
# platform: macOS-only -- pkgutil unpacks the Recaulk .pkg
# Fetch the PREBUILT Recaulk back-fill library (librecaulk.a + headers) from the Mavergreen/recaulk
# release pinned in components/recaulk/version. shipyard's fetch_product_pkg.sh does the download
# (with retries), re-checks the release's SHA256SUMS EVERY run, so a poisoned download cache cannot
# silently change the shipped archive, and picks the component by its PackageInfo identifier.
# Prints the path of the extracted .a on stdout; everything else goes to stderr.
set -eu
. "$(cd "$(dirname "$0")" && pwd)/versions.sh"
: "${RECAULK_VERSION:?set RECAULK_VERSION}"

OUT="$WORK/recaulk"
A="$OUT/lib/librecaulk.a"
root="$WORK/recaulk-tree"
sh "$SHIPYARD_SCRIPTS/fetch_product_pkg.sh" recaulk "$RECAULK_VERSION" "$root" >/dev/null
[ -f "$root/lib/librecaulk.a" ] || { echo "FATAL: no lib/librecaulk.a in the dev.mavergreen.recaulk payload" >&2; exit 1; }
[ -d "$root/include/recaulk" ] || { echo "FATAL: no include/recaulk in the dev.mavergreen.recaulk payload" >&2; exit 1; }
# The pointer catch vtables, public, for libcxx22's libc++abi.1.dylib alone (build/build-libcxx.sh).
[ -f "$root/lib/librecaulk-cxxabi-exports.a" ] \
  || { echo "FATAL: no lib/librecaulk-cxxabi-exports.a in the dev.mavergreen.recaulk payload (older than 20261025.4?)" >&2; exit 1; }

rm -rf "$OUT"; mkdir -p "$OUT/lib" "$OUT/include"
cp "$root/lib/librecaulk.a" "$root/lib/librecaulk-cxxabi-exports.a" "$OUT/lib/"
cp -R "$root/include/recaulk" "$OUT/include/"

# Must be for the target we cross-build against, not the host.
lipo -info "$A" 2>/dev/null | sed -n 's/.*: //p' | grep -qw x86_64 \
  || { echo "FATAL: $A has no x86_64 slice (archs: $(lipo -info "$A" 2>&1 | sed -n 's/.*: //p'))" >&2; exit 1; }

echo "$A"
