#!/bin/sh
# platform: host-agnostic
# Every build applies patches/ through shipyard's apply_patches.sh, which owns (and tests) applying a
# patch set once, refusing fuzz and refusing a tree patched with another set. Each build script must
# call it: CI's build-native job unpacks its own pristine copy of the tarball, so a tree patched only
# by build-cross.sh once shipped a native toolchain without the patches (release run 39137828356).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
fail() { echo "FAIL: $*"; exit 1; }
for s in build-cross.sh build-native.sh build-linux.sh; do
  grep -q '^sh "\$SHIPYARD_SCRIPTS/apply_patches.sh" "\$SRC" "\$REPO_ROOT/patches"' "$ROOT/build/$s" \
    || fail "build/$s does not apply patches/ with shipyard's apply_patches.sh"
done
grep -q 'mav_apply_patches' "$ROOT/build/lib.sh" && fail "build/lib.sh still defines its own patch applier"
echo "OK apply-patches"
