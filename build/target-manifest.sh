#!/bin/sh
# platform: host-agnostic
#   usage: target-manifest.sh record STAGE | verify EXPORT -- check content and this checkout's identity
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
[ $# -eq 2 ] || { echo 'usage: target-manifest.sh record STAGE | verify EXPORT' >&2; exit 2; }
. "$HERE/versions.sh"
. "$SHIPYARD_SCRIPTS/sdk-pins.sh"
SDK_PIN="$(shipyard_sdk_pin x86_64)"; export SDK_PIN
exec python3 "$HERE/target_manifest.py" "$@"
