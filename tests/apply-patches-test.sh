#!/bin/sh
# platform: host-agnostic
# mav_apply_patches (build/lib.sh) applies patches/ to an unpacked LLVM tree once, and both build
# scripts call it: CI's build-native job unpacks its own pristine copy of the tarball, so a tree
# patched only by build-cross.sh shipped a native toolchain without the patches (release run
# 39137828356). Run against synthetic trees, so it needs no LLVM.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$ROOT"; export REPO_ROOT
. "$ROOT/build/lib.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/apply-patches.XXXXXX")"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

tree() { # $1 dir: a three-line file the patches below change
  rm -rf "$1"; mkdir -p "$1/sub"; printf 'one\ntwo\nthree\n' > "$1/sub/f.txt"
}
mkdir -p "$T/p1" "$T/p2" "$T/fuzzy"
cat > "$T/p1/0001-two.patch" <<'EOF'
Header prose, as in patches/0001.

diff --git a/sub/f.txt b/sub/f.txt
--- a/sub/f.txt
+++ b/sub/f.txt
@@ -1,3 +1,3 @@
 one
-two
+TWO
 three
EOF
sed 's/^+TWO$/+Two/' "$T/p1/0001-two.patch" > "$T/p2/0001-two.patch"
sed 's/^ one$/ ONE-drifted/' "$T/p1/0001-two.patch" > "$T/fuzzy/0001-two.patch"

# 1. a fresh tree is patched
tree "$T/s"
mav_apply_patches "$T/s" "$T/p1" > "$T/out" 2>&1 || { cat "$T/out"; fail "a fresh tree was not patched"; }
[ "$(sed -n 2p "$T/s/sub/f.txt")" = TWO ] || fail "the patch did not reach the tree"
find "$T/s" -name '*.orig' -o -name '*.rej' -o -name '*~' | grep -q . && fail "patch left backup or reject files"

# 2. the same set again is a no-op that succeeds (build-native.sh after build-cross.sh, locally) --
#    not a failure, and above all not patch's "reversed patch" undoing it
mav_apply_patches "$T/s" "$T/p1" > "$T/out" 2>&1 || { cat "$T/out"; fail "re-applying the same set failed"; }
[ "$(sed -n 2p "$T/s/sub/f.txt")" = TWO ] || fail "re-applying the same set changed the tree"

# 2b. a patched tree with no record of it (interrupted before the stamp, or patched by hand) is refused,
#     where patch -t alone would take the patch as reversed and silently undo it
cp -R "$T/s" "$T/u"; rm -f "$T/u/.mavergreen-patches"
mav_apply_patches "$T/u" "$T/p1" > "$T/out" 2>&1 && fail "an unrecorded patched tree was accepted"
[ "$(sed -n 2p "$T/u/sub/f.txt")" = TWO ] || fail "an unrecorded patched tree had its patch undone"

# 3. a tree patched with a different set is refused, by name
mav_apply_patches "$T/s" "$T/p2" > "$T/out" 2>&1 && fail "a tree patched with a different set was accepted"
grep -q 'different' "$T/out" || { cat "$T/out"; fail "the refusal does not say the set differs"; }

# 4. a patch that needs fuzz is refused, by name
tree "$T/z"
mav_apply_patches "$T/z" "$T/fuzzy" > "$T/out" 2>&1 && fail "a patch needing fuzz was applied"
grep -q '0001-two.patch' "$T/out" || { cat "$T/out"; fail "the refusal does not name the patch"; }

# 5. both builds call it: the native one may receive a pristine tree
for s in build-cross.sh build-native.sh; do
  grep -q '^mav_apply_patches "\$SRC" "\$REPO_ROOT/patches"' "$ROOT/build/$s" || fail "build/$s does not apply patches/"
done
echo "OK apply-patches"
