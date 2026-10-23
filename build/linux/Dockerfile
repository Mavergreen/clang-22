ARG BASE_IMAGE
FROM ${BASE_IMAGE}
COPY packages.lock /tmp/packages.lock
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive xargs -r apt-get install -y --no-install-recommends < /tmp/packages.lock && \
    dpkg-query -W -f='${binary:Package}=${Version}\n' | LC_ALL=C sort > /tmp/actual.lock && \
    diff -u /tmp/packages.lock /tmp/actual.lock && \
    rm -rf /var/lib/apt/lists/*
