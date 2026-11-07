ARG BASE_IMAGE
FROM ${BASE_IMAGE}
COPY packages.lock apt-snapshot /tmp/
# platform: Ubuntu's live archive drops a package's old version from its index on every update, so
#           an exact-version lock against it broke on each security update (ca-certificates,
#           2026-11-03 and 2026-11-07). The snapshot archive at the pinned timestamp keeps every locked
#           version installable; moving it is a deliberate bump, with packages.lock regenerated.
RUN snap="$(cat /tmp/apt-snapshot)" && \
    sed -i -E "s#https?://(archive|security)\.ubuntu\.com/ubuntu/?#http://snapshot.ubuntu.com/ubuntu/$snap/#" \
      /etc/apt/sources.list && \
    ! grep -E '^deb .*(archive|security)\.ubuntu\.com' /etc/apt/sources.list && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive xargs -r apt-get install -y --no-install-recommends < /tmp/packages.lock && \
    dpkg-query -W -f='${binary:Package}=${Version}\n' | LC_ALL=C sort > /tmp/actual.lock && \
    diff -u /tmp/packages.lock /tmp/actual.lock && \
    rm -rf /var/lib/apt/lists/*
