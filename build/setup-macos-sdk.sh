#!/bin/sh
# platform: macOS-only -- shipped as bin/setup-sdk in the standalone Mac archives; plain sh, runs on 10.9
#   usage: setup-sdk [SDK]
#          Wires a Mac OS X 10.9 SDK into this toolchain, which clang.cfg finds at
#          <toolchain>/SDKs/MacOSX10.9.sdk. SDK is a MacOSX10.9.sdk directory: shipyard's fetch_sdk.sh
#          prints the pinned one's path. With no SDK, the one the sdk109 product installs is used.
#          The Linux archive's setup-sdk does the same (build/setup-linux-sdk.py). The pkgs need no
#          setup: they link SDKs to the sdk109 product's.
set -eu
usage() { echo 'usage: setup-sdk [SDK] -- SDK is a MacOSX10.9.sdk directory (shipyard fetch_sdk.sh prints the pinned one)' >&2; exit 2; }
[ $# -le 1 ] || usage
case "${1:-}" in -*) usage ;; esac
SDK="${1:-/usr/local/mavergreen/sdk109/SDKs/MacOSX10.9.sdk}"
[ -d "$SDK" ] || { echo "setup-sdk: no SDK at $SDK -- give a MacOSX10.9.sdk directory" >&2; exit 1; }
SDK="$(cd "$SDK" && pwd -P)"
grep -A1 '<key>Version</key>' "$SDK/SDKSettings.plist" 2>/dev/null | grep -q '<string>10\.9</string>' \
  && [ -e "$SDK/usr/lib/libSystem.dylib" ] \
  || { echo "setup-sdk: $SDK is not a Mac OS X 10.9 SDK (SDKSettings.plist Version 10.9 and usr/lib/libSystem.dylib)" >&2; exit 1; }
here="$(cd "$(dirname "$0")/.." && pwd -P)"
link="$here/SDKs/MacOSX10.9.sdk"
if [ -L "$link" ] && [ "$(cd "$link" 2>/dev/null && pwd -P)" = "$SDK" ]; then echo "$link"; exit 0; fi
if [ -L "$here/SDKs" ]; then
  echo "setup-sdk: $here/SDKs is a link ($(readlink "$here/SDKs")): this is an installed toolchain, which uses the sdk109 product's SDK" >&2; exit 1
fi
[ ! -e "$link" ] || [ -L "$link" ] || { echo "setup-sdk: refusing to replace the SDK directory $link" >&2; exit 1; }
mkdir -p "$here/SDKs"
# platform: -n replaces an existing link to a directory instead of following it into the directory
ln -sfn "$SDK" "$link"
echo "$link"
