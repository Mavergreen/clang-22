#!/bin/sh
# platform: host-agnostic
# Every download in build/ goes through shipyard's shipyard_curl (retries transient failures, writes
# via .part) or fetch_product_pkg.sh (release pkgs against SHA256SUMS), never a bare curl.
# native-bootstrap/ is exempt: it runs on a stock 10.9 box before any shipyard exists there.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"

if grep -nE '(^|[^_[:alnum:]])curl[[:space:]]+-' "$ROOT"/build/*.sh; then
  echo "FAIL: build/ calls curl directly; use shipyard_curl (mavericks_fetch.sh) or fetch_product_pkg.sh"; exit 1
fi

echo "OK downloads-via-shipyard-test"
