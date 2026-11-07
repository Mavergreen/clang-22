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
# The rewrite must happen before apt reads an index, and be checked: a base image whose sources name
# the archive another way would otherwise install from the live archive unnoticed.
awk '/sed -i/ && /snapshot/ { s = NR } /apt-get update/ { u = NR } END { exit !(s && u && s < u) }' "$D/Dockerfile" \
  || bad "the Dockerfile runs apt-get update before pointing apt at the snapshot"
grep -q "! grep -E '^deb .*(archive|security)" "$D/Dockerfile" \
  || bad "the Dockerfile does not refuse a sources.list that still names the live archive"
# The snapshot archive serves only https (plain http answers 301), and the base image has no CA bundle:
# apt verifies it against the one committed root its chain ends at, never the runner's store.
pem="$D/isrg-root-x1.pem"
if [ -f "$pem" ]; then
  fp="$(openssl x509 -in "$pem" -noout -fingerprint -sha256 | sed 's/.*=//')"
  [ "$fp" = 96:BC:EC:06:26:49:76:F3:74:60:77:9A:CF:28:C5:A7:CF:E8:A3:C0:AA:E1:1A:8F:FC:EE:05:C0:BD:DF:08:C6 ] \
    || bad "build/linux/isrg-root-x1.pem is not ISRG Root X1 (sha256 $fp)"
else
  bad "no build/linux/isrg-root-x1.pem"
fi
grep -Eq '^COPY .*isrg-root-x1\.pem' "$D/Dockerfile" || bad "the Dockerfile does not copy isrg-root-x1.pem into the image"
grep -q 'Acquire::https::snapshot\.ubuntu\.com::CaInfo' "$D/Dockerfile" \
  || bad "the Dockerfile does not point apt's TLS for snapshot.ubuntu.com at the committed root"
grep -q 'https://snapshot\.ubuntu\.com/ubuntu/\$snap' "$D/Dockerfile" \
  || bad "the Dockerfile does not name the snapshot archive by https"
grep -iq 'Verify-Peer' "$D/Dockerfile" && bad "the Dockerfile turns off TLS peer verification"
# A failed index fetch is only a warning to apt-get update by default; the install then fails far from
# the cause, with every package "unable to locate" (2026-11-07).
grep -q 'apt-get update --error-on=any' "$D/Dockerfile" || bad "apt-get update does not fail on a failed fetch"
[ "$fail" = 0 ] && echo 'PASS: the Linux build container installs its locked versions from the pinned apt snapshot'
exit "$fail"
