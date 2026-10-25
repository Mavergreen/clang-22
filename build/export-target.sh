#!/bin/sh
# platform: host-agnostic
#   usage: export-target.sh STAGE OUT -- export a previously validated Mac cross stage
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
[ $# -eq 2 ] || { echo 'usage: export-target.sh STAGE OUT' >&2; exit 2; }
# Record, verify and export must derive exactly the same build identity.
exec sh "$HERE/target-manifest.sh" export "$1" "$2"
