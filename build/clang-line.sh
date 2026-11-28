#!/bin/sh
# platform: host-agnostic
#   usage: clang-line.sh
#          Prints the clang LINE, the LLVM major of the root UPSTREAM_VERSION (22.1.8 -> 22).
# One repo ships ONE LLVM major LINE, from the root UPSTREAM_VERSION -- never a per-line file. The
# LINE is derived from the upstream version, never configured separately: CMakeLists.txt derives
# MAV_CLANG_LINE the same way, and two sources of truth for "which line is this" is how a repo builds
# 22 and stamps a clang23 identifier. A caller-supplied $CLANG_LINE is honoured only as a CHECK
# against the derived value, never as an override.
set -eu
up="$(cd "$(dirname "$0")/.." && pwd)/UPSTREAM_VERSION"
[ -f "$up" ] || { echo "clang-line: no UPSTREAM_VERSION at repo root" >&2; exit 1; }
line="$(tr -d '[:space:]' < "$up" | sed -n 's/^\([0-9][0-9]*\)\..*$/\1/p')"
[ -n "$line" ] || { echo "clang-line: cannot derive the line from $up" >&2; exit 1; }
if [ -n "${CLANG_LINE:-}" ] && [ "$CLANG_LINE" != "$line" ]; then
  echo "clang-line: CLANG_LINE=$CLANG_LINE was given but $up derives $line -- one source of truth" >&2
  exit 1
fi
printf '%s\n' "$line"
