#!/bin/sh
# platform: host-agnostic
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"

for b in build-cross.sh build-native.sh; do
  for s in fetch_sdk.sh sdk-pins.sh mavericks_fetch.sh; do
    if grep -n "$s" "$ROOT/build/$b" | grep 'libexec'; then
      echo "FAIL: build/$b stages $s into libexec/; Longboat's sdk109 installs the SDK (sudo longboat install 10.9), so neither toolchain ships a fetcher"; exit 1
    fi
  done
done

echo "OK no-sdk-fetcher-test"
