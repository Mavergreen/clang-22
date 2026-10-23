#!/bin/sh
# platform: host-agnostic
#   usage: verify-linux-host.sh PREFIX -- read ELF metadata without executing the tools
set -eu
[ $# -eq 1 ] || { echo 'usage: verify-linux-host.sh PREFIX' >&2; exit 2; }
exec python3 "$(dirname "$0")/linux/verify-host.py" "$1"
