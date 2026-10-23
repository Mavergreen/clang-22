#!/bin/sh
# platform: host-agnostic
#   usage: export-target.sh STAGE OUT -- export a previously validated Mac cross stage
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
[ $# -eq 2 ] || { echo 'usage: export-target.sh STAGE OUT' >&2; exit 2; }
. "$HERE/versions.sh"
. "$SHIPYARD_SCRIPTS/sdk-pins.sh"
SDK_PIN="$(shipyard_sdk_pin x86_64)"; export SDK_PIN
exec python3 "$HERE/target_manifest.py" export "$1" "$2"
