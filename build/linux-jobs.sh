#!/bin/sh
# platform: host-agnostic
#   usage: linux-jobs.sh CORES AVAILABLE_KIB -- at least one job, 3 GiB per compile
set -eu
[ $# -eq 2 ] || exit 2
case "$1:$2" in *[!0-9:]*|:*|*:) exit 2 ;; esac
[ "$1" -gt 0 ] || exit 2
jobs=$(( $2 / 3145728 ))
[ "$jobs" -ge 1 ] || jobs=1
[ "$jobs" -le "$1" ] || jobs=$1
printf '%s\n' "$jobs"
