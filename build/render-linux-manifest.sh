#!/bin/sh
# platform: host-agnostic
#   usage: render-linux-manifest.sh PREFIX -- writes PREFIX/mavergreen.plist, the native pkg's product
#          marker, byte for byte, so shipyard's install@v1 reads version and requires from the Linux
#          archive instead of downloading the pkg. The arguments are the native pkg's
#          (clang-manifest-args.sh); `outside` is what that pkg stages beside the product, its updater
#          app and LaunchAgent, named by shipyard's registry. collect cmp's the two files.
set -eu
[ $# -eq 1 ] || { echo 'usage: render-linux-manifest.sh PREFIX' >&2; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"; PREFIX="$1"
. "$HERE/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
VER="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$PREFIX/share/clang${CLANG_LINE}/identity.json")"
[ -n "$VER" ] || { echo "render-linux-manifest: no version in $PREFIX/share/clang${CLANG_LINE}/identity.json" >&2; exit 1; }
P="clang${CLANG_LINE}"
t="$(mktemp -d "${TMPDIR:-/tmp}/linux-manifest.XXXXXX")"; trap 'rm -rf "$t"' EXIT
mkdir -p "$t/usr/local/mavergreen/$P" "$t/$(sh "$SHIPYARD_SCRIPTS/product-name.sh" updater-app "$P")/Contents" "$t/Library/LaunchAgents"
: > "$t/$(sh "$SHIPYARD_SCRIPTS/product-name.sh" updater-app "$P")/Contents/Info.plist"
: > "$t/Library/LaunchAgents/$(sh "$SHIPYARD_SCRIPTS/product-name.sh" agent-label "$P").plist"
. "$HERE/clang-manifest-args.sh"
sh "$SHIPYARD_SCRIPTS/render-manifest.sh" --stage "$t" "$@" --has-updater
cp "$t/usr/local/mavergreen/$P/mavergreen.plist" "$PREFIX/mavergreen.plist"
echo "render-linux-manifest: wrote $PREFIX/mavergreen.plist ($VER)"
