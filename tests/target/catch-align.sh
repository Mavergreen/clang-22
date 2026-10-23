#!/bin/sh
# platform: macOS-only -- executes a saved Mach-O witness
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
out="$("$HERE/r")"
[ "$out" = 'caught 5' ] || { echo "FAIL: caught value: $out" >&2; exit 1; }
out="$("$HERE/wide" wide)"
[ "$out" = 'caught 6' ] || { echo "FAIL: caught aligned class: $out" >&2; exit 1; }
echo 'PASS: catch alignment runtime (scalar and aligned class)'
