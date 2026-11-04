#!/bin/sh
# platform: host-agnostic
# Static wiring check: release.yml packs the llvm22-dev tarballs (once per arch, on live lines) and
# carries them through each variant's upload and the combined release artifact.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
Y="$ROOT/.github/workflows/release.yml"
fail() { echo "FAIL $*"; exit 1; }
live="$(grep -v '^[[:space:]]*#' "$Y")"
for a in arm64 x86_64; do
  n="$(printf '%s\n' "$live" | grep -c "package-llvm-dev\.sh .* $a " || true)"
  [ "$n" = 1 ] || fail "release.yml: want 1 live package-llvm-dev.sh call for $a, got $n"
done
printf '%s\n' "$live" | grep -q 'stage\$CROSS_PREFIX" arm64' || fail "arm64 tarball is not packed from the cross stage"
printf '%s\n' "$live" | grep -q 'stage-native\$NATIVE_PREFIX" x86_64' || fail "x86_64 tarball is not packed from the native stage"
for a in arm64 x86_64; do
  n="$(printf '%s\n' "$live" | grep -c "dist/llvm22-dev-\*-darwin-$a\.tar\.gz" || true)"
  [ "$n" = 2 ] || fail "release.yml: want the $a tarball uploaded by its variant and by the combined artifact (2 path lines), got $n"
done
echo "PASS llvm-dev-wiring-test"
