#!/bin/sh
# platform: macOS-only -- executes a saved Mach-O witness
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
out="$("$HERE/main")"
[ "$out" = '4 of 4 weak symbols coalesced' ] || { echo "FAIL: $out" >&2; exit 1; }
echo 'PASS: weak binding runtime'
