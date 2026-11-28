#!/bin/sh
# platform: host-agnostic
# versions.sh exports the pins the build reads, and the clang LINE is derived from UPSTREAM_VERSION.
# The release version itself is shipyard's release-version.sh (INGREDIENTS.md's ## Versioning: port),
# tested there.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
# spec: SKILL.md "Versioning" -- a test that encodes the upstream version reads it from UPSTREAM_VERSION,
#       so a Renovate bump never fails its own CI.
U="$(sed -n 1p "$ROOT/UPSTREAM_VERSION")"

( . "$ROOT/build/versions.sh"
  [ "$LLVM_VERSION" = "$U" ] || { echo "FAIL LLVM_VERSION=$LLVM_VERSION"; exit 1; }
  [ "$TARGET_TRIPLE" = "x86_64-apple-macos10.9" ] || { echo "FAIL TARGET_TRIPLE=$TARGET_TRIPLE"; exit 1; }
  expr "$RECAULK_VERSION" : '^[0-9]\{8\}\.[0-9][0-9]*$' >/dev/null || { echo "FAIL RECAULK_VERSION=$RECAULK_VERSION"; exit 1; }
  case "$LLVM_SRC_URL" in *"$LLVM_VERSION"*) : ;; *) echo "FAIL LLVM_SRC_URL=$LLVM_SRC_URL"; exit 1 ;; esac
) || exit 1
echo "OK versions.sh pins"

# CLANG_LINE is DERIVED from the upstream version, not configured. Two sources of truth for "which
# line is this" is how a repo ends up building 22 and stamping a clang23 pkg identifier.
derived="$(CLANG_LINE= sh "$ROOT/build/clang-line.sh")"
[ "$derived" = "${U%%.*}" ] || { echo "FAIL: derived line '$derived', expected ${U%%.*}"; exit 1; }

# A caller-supplied CLANG_LINE is a CHECK, not an override: pairing CLANG_LINE=99 with a 22.x
# UPSTREAM_VERSION must fail loudly, not silently build the wrong line.
mismatch_out="$(CLANG_LINE=99 sh "$ROOT/build/clang-line.sh" 2>&1)" && { echo "FAIL: CLANG_LINE=99 sh build/clang-line.sh should have failed, printed: $mismatch_out"; exit 1; }
echo "PASS: CLANG_LINE derived, mismatch rejected"
