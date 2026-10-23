#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ "$(sh "$ROOT/build/linux-jobs.sh" 8 6291456)" = 2 ]
[ "$(sh "$ROOT/build/linux-jobs.sh" 2 67108864)" = 2 ]
[ "$(sh "$ROOT/build/linux-jobs.sh" 8 1000)" = 1 ]
if sh "$ROOT/build/linux-jobs.sh" 0 1000; then exit 1; fi
echo 'PASS: Linux job cap respects memory, cores and a one-job minimum'
