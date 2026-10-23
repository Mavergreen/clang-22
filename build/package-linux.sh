#!/bin/sh
# platform: host-agnostic
#   usage: package-linux.sh PREFIX DIST
set -eu
[ $# -eq 2 ] || { echo 'usage: package-linux.sh PREFIX DIST' >&2; exit 2; }
exec python3 "$(dirname "$0")/linux/package.py" "$1" "$2"
