#!/bin/sh
# platform: host-agnostic
#   usage: target-manifest.sh record STAGE | verify EXPORT | export STAGE OUT
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
case "$#:${1:-}" in
  2:record|2:verify|3:export) ;;
  *) echo 'usage: target-manifest.sh record STAGE | verify EXPORT | export STAGE OUT' >&2; exit 2 ;;
esac
. "$HERE/versions.sh"
. "$SHIPYARD_SCRIPTS/sdk-pins.sh"
SDK_PIN="$(shipyard_sdk_pin x86_64)"; export SDK_PIN
# Older shipyard releases leave the SDK archive unchanged; newer ones declare
# the generated metadata alongside the archive pin. Carry that contract with us.
SDK_SETTINGS_JSON=""
if command -v shipyard_sdk_settings_json >/dev/null 2>&1; then
  SDK_SETTINGS_JSON="$(shipyard_sdk_settings_json x86_64)"
fi
export SDK_SETTINGS_JSON
exec python3 "$HERE/target_manifest.py" "$@"
