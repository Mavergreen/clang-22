#!/bin/sh
# platform: host-agnostic
#   usage: assemble-linux.sh HOST EXPORT DEST
set -eu
[ $# -eq 3 ] || { echo 'usage: assemble-linux.sh HOST EXPORT DEST' >&2; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
sh "$HERE/target-manifest.sh" verify "$2"
exec python3 "$HERE/linux/assemble.py" "$1" "$2" "$3"
