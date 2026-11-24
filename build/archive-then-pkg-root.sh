#!/bin/sh
# platform: host-agnostic -- shipyard's stage_standalone.sh and stage_pkg_from_archive.sh run on any host
#   usage: archive-then-pkg-root.sh STAGE_ROOT SHORT VERSION ARCH DIST PKG_ROOT
#          Archive-first packaging for a toolchain: STAGE_ROOT/usr/local/mavergreen/SHORT, the staged
#          tree, becomes DIST/SHORT-VERSION-macos-ARCH.tar.gz, the standalone archive, and the pkg's
#          staged root PKG_ROOT is derived from that archive. The archive carries no SDK: bin/setup-sdk
#          (setup-macos-sdk.sh) wires one, as the Linux archive's does. The pkg adds only SDKs, a link to
#          the sdk109 product's (its --pkg-only path), and requires sdk109. packaging/SHORT.standalone-bundled
#          lists what the archive bundles: nothing.
set -eu
[ $# -eq 6 ] || { echo 'usage: archive-then-pkg-root.sh STAGE_ROOT SHORT VERSION ARCH DIST PKG_ROOT' >&2; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
ST="${1%/}" P="$2" V="$3" A="$4" D="$5" PR="$6"
T="$ST/usr/local/mavergreen/$P"
[ -x "$T/bin/clang" ] || { echo "archive-then-pkg-root: no staged toolchain at $T" >&2; exit 1; }
# platform: the staged root must hold the product's tree alone; a previous local run's updater, LaunchAgent
#           or pkg-only SDKs link would otherwise ride into the archive
rm -rf "$ST/Library" "$ST/Applications" "$T/SDKs" "$T/mavergreen.plist"
install -m 755 "$HERE/setup-macos-sdk.sh" "$T/bin/setup-sdk"
mkdir -p "$D"
archive="$D/$P-$V-macos-$A.tar.gz"
sh "$SHIPYARD_SCRIPTS/stage_standalone.sh" "$ST" "$P" "$V" "$A" "$archive"
w="$(mktemp -d "${TMPDIR:-/tmp}/archive-then-pkg.XXXXXX")"; trap 'rm -rf "$w"' EXIT
ln -s ../sdk109/SDKs "$w/SDKs"
rm -rf "$PR"
sh "$SHIPYARD_SCRIPTS/stage_pkg_from_archive.sh" --repo "$REPO" --requires sdk109 --pkg-only "$w/SDKs=SDKs" \
  "$archive" "$REPO/packaging/$P.standalone-bundled" "$PR"
echo "archive-then-pkg-root: $archive, and the pkg's root at $PR"
