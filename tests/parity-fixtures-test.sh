#!/bin/sh
# platform: host-agnostic
# Parity fixtures: the exports Wowfunhappy's libc++/libc++abi offer, minus what Recaulk/builtins own.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; D="$HERE/fixtures/parity"
fail() { echo "FAIL: $*"; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/parity.XXXXXX")"; trap 'rm -rf "$T"' EXIT
for l in libc++.1 libc++abi.1; do
  f="$D/$l.exports"
  [ -s "$f" ] || fail "$f missing or empty"
  LC_ALL=C sort -u "$f" | cmp -s - "$f" || fail "$f is not LC_ALL=C sort -u"
  grep -q '\.eh$' "$f" && fail "$f has .eh names"
  [ -f "$D/excluded.txt" ] || fail "excluded.txt missing"
  awk '{print $1}' "$D/excluded.txt" | LC_ALL=C sort -u > "$T/ex"
  [ -z "$(LC_ALL=C comm -12 "$T/ex" "$f")" ] || fail "excluded names appear in $f"
done
grep -qv '^__Z' "$D/libc++.1.exports" && fail "libc++ export not starting __Z"
grep -Ev '^(__Z|___cxa_|___dynamic_cast$|___gxx_personality_v0$)' "$D/libc++abi.1.exports" | grep -q . \
  && fail "unexpected libc++abi export"
for x in "_clock_gettime recaulk" "_openat recaulk" "___muloti4 builtins"; do
  grep -qx "$x" "$D/excluded.txt" || fail "excluded.txt lacks '$x'"
done
[ "$(wc -l < "$D/libc++.1.exports" | tr -d ' ')" = 1967 ] || fail "libc++ count $(wc -l < "$D/libc++.1.exports")"
[ "$(wc -l < "$D/libc++abi.1.exports" | tr -d ' ')" = 368 ] || fail "libc++abi count $(wc -l < "$D/libc++abi.1.exports")"
echo "PASS: parity fixtures"
