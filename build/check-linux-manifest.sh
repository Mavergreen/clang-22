#!/bin/sh
# platform: host-agnostic
#   usage: check-linux-manifest.sh DIST -- the Linux archive's opt/mavergreen/clang<line>/mavergreen.plist
#          must be the native pkg's usr/local/mavergreen/clang<line>/mavergreen.plist, byte for byte:
#          shipyard's install@v1 reads one in place of the other (render-linux-manifest.sh).
set -eu
[ $# -eq 1 ] || { echo 'usage: check-linux-manifest.sh DIST' >&2; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
P="clang${CLANG_LINE}"
set -- "$1"/*native*.pkg; [ -f "$1" ] || { echo "check-linux-manifest: no native pkg in ${1%/*}" >&2; exit 1; }
pkg="$1"
set -- "${pkg%/*}"/"$P"-*-linux-x86_64.tar.gz; [ -f "$1" ] || { echo "check-linux-manifest: no Linux archive beside $pkg" >&2; exit 1; }
tgz="$1"
t="$(mktemp -d "${TMPDIR:-/tmp}/linux-manifest-check.XXXXXX")"; trap 'rm -rf "$t"' EXIT
tar -xzf "$tgz" -C "$t" "opt/mavergreen/$P/mavergreen.plist" \
  || { echo "check-linux-manifest: $tgz has no opt/mavergreen/$P/mavergreen.plist" >&2; exit 1; }
"$(sh "$SHIPYARD_SCRIPTS/fetch_stevedore.sh")" expand "$pkg" "$t/x" >/dev/null
# platform: a component's Payload is a gzip'd cpio archive (as artifact-facts.sh reads it); the native
#           pkg installs at /, so the marker is ./usr/local/mavergreen/P/mavergreen.plist in one of them.
find "$t/x" -name Payload -type f > "$t/payloads"
n=0
while IFS= read -r pl; do
  n=$((n + 1)); mkdir -p "$t/root$n"
  gzip -dc "$pl" > "$t/p.cpio"
  (cd "$t/root$n" && cpio -id '*usr/local/mavergreen/'"$P"'/mavergreen.plist' < "$t/p.cpio" 2>/dev/null)
done < "$t/payloads"
set -- $(find "$t" -path "$t/root*/usr/local/mavergreen/$P/mavergreen.plist")
[ $# -eq 1 ] || { echo "check-linux-manifest: $pkg holds $# usr/local/mavergreen/$P/mavergreen.plist, not one" >&2; exit 1; }
cmp "$1" "$t/opt/mavergreen/$P/mavergreen.plist" \
  || { echo "check-linux-manifest: the Linux archive's mavergreen.plist differs from the native pkg's:" >&2; diff "$1" "$t/opt/mavergreen/$P/mavergreen.plist" >&2 || true; exit 1; }
echo "check-linux-manifest: the Linux archive carries the native pkg's mavergreen.plist"
