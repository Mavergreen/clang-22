#!/bin/sh
# platform: host-agnostic
# Static wiring check: the toolchain links Recaulk (librecaulk.a + include/recaulk), and nothing
# tracked still names macports-legacy-support's old artifacts or pin.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT"
fail() { echo "FAIL $*"; exit 1; }

# 1. no stale references (history lives in native-bootstrap/ and release-notes/)
stale="$(git grep -n -E 'libMacportsLegacySupport|include/LegacySupport|LegacySupport/|MLS_VERSION|fetch-legacy-support|mavericks-legacysupport' \
  -- . ':!native-bootstrap' ':!release-notes' ':!tests/recaulk-wiring-test.sh' || true)"
[ -z "$stale" ] || fail "stale legacy-support references:
$stale"

# 2. both cfgs carry the Recaulk lines
B=build/build-cross.sh
n="$(grep -c -x -F "  '-isystem <CFGDIR>/../include/recaulk' \\" "$B" || true)"
[ "$n" = 2 ] || fail "$B: want 2 recaulk -isystem cfg lines, got $n"
n="$(grep -c -x -F "  '<CFGDIR>/../lib/librecaulk.a' \\" "$B" || true)"
[ "$n" = 2 ] || fail "$B: want 2 librecaulk.a cfg lines, got $n"

# 3. the libc++ build's compile and link flags
grep '^RC=' "$B" | grep -q -F -e '-isystem $RECAULK_INC/recaulk' || fail "RC lacks -isystem \$RECAULK_INC/recaulk"
n="$(grep 'RUNTIMES_.*_LINKER_FLAGS' "$B" | grep -c -F '=$RECAULK_A"' || true)"
[ "$n" = 2 ] || fail "want 2 RUNTIMES_*_LINKER_FLAGS lines ending =\$RECAULK_A\", got $n"

# 4. the repackage trigger watches the Recaulk pin, not versions.sh
W=.github/workflows/repackage-on-ingredient-bump.yml
grep -q -F 'components/recaulk/version' "$W" || fail "$W does not watch components/recaulk/version"
if sed -n '/paths:/,/^jobs:/p' "$W" | grep -q -F 'build/versions.sh'; then fail "$W still watches build/versions.sh"; fi

# 5. no repo-local Renovate manager: shipyard's shared preset tracks the pin
if grep -q -F 'components/recaulk/version' .github/renovate.json; then
  fail "renovate.json names components/recaulk/version (shared preset already tracks it)"
fi

# 6. both packagers record recaulk in build-info
for f in build/package-cross-pkg.sh build/package-native-pkg.sh; do
  grep -q -F 'recaulk="$RECAULK_VERSION"' "$f" || fail "$f does not pass recaulk=\"\$RECAULK_VERSION\""
done
echo "PASS recaulk wiring"
