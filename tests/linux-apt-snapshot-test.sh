#!/bin/sh
# platform: host-agnostic
# spec: build/linux/Dockerfile -- the Linux build container installs packages.lock's exact versions from
#       Ubuntu's snapshot archive at build/linux/apt-snapshot, never the live archive, whose index drops
#       a locked version on its next update (2026-11-03 and 2026-11-07).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D="$ROOT/build/linux"
fail=0
bad() { echo "FAIL: $*"; fail=1; }
[ -f "$D/apt-snapshot" ] || { echo "FAIL: no build/linux/apt-snapshot"; exit 1; }
grep -Eqx '[0-9]{8}T[0-9]{6}Z' "$D/apt-snapshot" \
  || bad "build/linux/apt-snapshot is not one snapshot timestamp (YYYYMMDDTHHMMSSZ): $(cat "$D/apt-snapshot")"
grep -Eq '^COPY .*apt-snapshot' "$D/Dockerfile" || bad "the Dockerfile does not copy apt-snapshot into the image"
grep -q 'snapshot\.ubuntu\.com/ubuntu/\$snap' "$D/Dockerfile" \
  || bad "the Dockerfile does not point apt at snapshot.ubuntu.com at the pinned timestamp"
# The rewrite must happen before apt reads an index, and be checked: a base image whose sources name
# the archive another way would otherwise install from the live archive unnoticed.
awk '/sed -i/ && /snapshot/ { s = NR } /apt-get update/ { u = NR } END { exit !(s && u && s < u) }' "$D/Dockerfile" \
  || bad "the Dockerfile runs apt-get update before pointing apt at the snapshot"
grep -q "! grep -E '^deb .*(archive|security)" "$D/Dockerfile" \
  || bad "the Dockerfile does not refuse a sources.list that still names the live archive"
[ "$fail" = 0 ] && echo 'PASS: the Linux build container installs its locked versions from the pinned apt snapshot'
exit "$fail"
