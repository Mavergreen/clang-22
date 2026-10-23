#!/bin/sh
# platform: macOS-only -- runs Linux-built witnesses on Mavericks
set -eu
[ $# -eq 1 ] || { echo 'usage: target-runner.sh BUNDLE' >&2; exit 2; }
[ "$(uname -s)/$(uname -m)" = Darwin/x86_64 ] || { echo 'target-runner: requires Darwin x86_64' >&2; exit 1; }
BUNDLE="$(cd "$1" && pwd -P)"
for name in catch-align weak-bind cxxabi profile; do
  [ -f "$BUNDLE/$name/run.sh" ] || { echo "target-runner: missing required $name" >&2; exit 1; }
done
rm -f "$BUNDLE/results.txt"
for name in catch-align weak-bind cxxabi profile; do
  sh "$BUNDLE/$name/run.sh" || { echo "target-runner: $name failed (skips are failures)" >&2; exit 1; }
  printf 'PASS %s\n' "$name" >> "$BUNDLE/results.txt"
done
