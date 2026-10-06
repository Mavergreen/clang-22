#!/bin/sh
# platform: macOS-only -- pkgutil unpacks the Recaulk .pkg
# Fetch the PREBUILT Recaulk back-fill library (librecaulk.a + headers) from the Mavergreen/recaulk
# release pinned in components/recaulk/version. Integrity is re-checked against the release's
# SHA256SUMS EVERY run, so a poisoned download cache cannot silently change the shipped archive.
# The recaulk pkg is a product archive of several components; the first Payload is
# dev.mavergreen.base's, so the component is selected by its PackageInfo identifier, never by order.
# Prints the path of the extracted .a on stdout; everything else goes to stderr.
set -eu
. "$(cd "$(dirname "$0")" && pwd)/versions.sh"
: "${RECAULK_VERSION:?set RECAULK_VERSION}"
: "${RECAULK_BASE_URL:?set RECAULK_BASE_URL}"

OUT="$WORK/recaulk"
A="$OUT/lib/librecaulk.a"
CACHE="$WORK/recaulk-dl"
ID="dev.mavergreen.recaulk"
pkg_name="recaulk-$RECAULK_VERSION.pkg"
base="$RECAULK_BASE_URL/$RECAULK_VERSION"

mkdir -p "$CACHE"
pkg="$CACHE/$pkg_name"; sums="$CACHE/SHA256SUMS"

# Download once, atomically (tmp+mv) so an interrupted fetch cannot poison the cache.
if [ ! -f "$pkg" ]; then
  tmp="$pkg.tmp.$$"; curl -fsSL -o "$tmp" "$base/$pkg_name"; mv "$tmp" "$pkg"
fi
tmp="$sums.tmp.$$"; curl -fsSL -o "$tmp" "$base/SHA256SUMS"; mv "$tmp" "$sums"
want=$(awk -v f="$pkg_name" '$2==f {print $1}' "$sums")
[ -n "$want" ] || { echo "FATAL: $pkg_name not listed in SHA256SUMS" >&2; exit 1; }
got=$(shasum -a 256 "$pkg" | awk '{print $1}')
[ "$want" = "$got" ] || { echo "FATAL: recaulk pkg sha mismatch: $got != $want" >&2; rm -f "$pkg"; exit 1; }

# Expand (10.9 has no --expand-full) and pick the component by identifier.
exp="$CACHE/expanded"; rm -rf "$exp"
pkgutil --expand "$pkg" "$exp" 1>&2
matches=$(grep -l "identifier=\"$ID\"" "$exp"/*/PackageInfo 2>/dev/null || true)
n=$(printf '%s\n' "$matches" | grep -c . || true)
[ "$n" = 1 ] || { echo "FATAL: expected exactly one component with identifier $ID in $pkg_name, found $n" >&2; exit 1; }
comp=$(dirname "$matches")

pay="$CACHE/payload"; rm -rf "$pay"; mkdir -p "$pay"
( cd "$pay" && gzip -dc "$comp/Payload" | cpio -id ) 1>&2 2>&1 || { echo "FATAL: cannot unpack Payload of $ID" >&2; exit 1; }
root="$pay/usr/local/mavergreen/recaulk"
[ -f "$root/lib/librecaulk.a" ] || { echo "FATAL: no usr/local/mavergreen/recaulk/lib/librecaulk.a in the $ID payload" >&2; exit 1; }
[ -d "$root/include/recaulk" ] || { echo "FATAL: no usr/local/mavergreen/recaulk/include/recaulk in the $ID payload" >&2; exit 1; }

rm -rf "$OUT"; mkdir -p "$OUT/lib" "$OUT/include"
cp "$root/lib/librecaulk.a" "$OUT/lib/"
cp -R "$root/include/recaulk" "$OUT/include/"

# Must be for the target we cross-build against, not the host.
lipo -info "$A" 2>/dev/null | sed -n 's/.*: //p' | grep -qw x86_64 \
  || { echo "FATAL: $A has no x86_64 slice (archs: $(lipo -info "$A" 2>&1 | sed -n 's/.*: //p'))" >&2; exit 1; }

echo "$A"
