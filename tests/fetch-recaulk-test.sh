#!/bin/sh
# platform: macOS-only -- pkgbuild, productbuild and pkgutil build and expand the fake archive
# fetch-recaulk.sh must pick the dev.mavergreen.recaulk component by identifier (the first Payload
# in a real recaulk pkg is dev.mavergreen.base's), verify against SHA256SUMS, and check the slice.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
command -v pkgbuild >/dev/null 2>&1 || { echo "SKIP: no pkgbuild"; exit 77; }
T="$(mktemp -d -t fetch-recaulk-test.XXXXXX)"; trap 'rm -rf "$T"' EXIT
CC_="${CC:-cc}"
printf 'int mg_probe(void){return 7;}\n' > "$T/probe.c"
"$CC_" -arch x86_64 -c "$T/probe.c" -o "$T/probe.o" >/dev/null 2>&1 || { echo "SKIP: cannot build x86_64 object"; exit 77; }

VER="$(tr -d ' \t\r\n' < "$ROOT/components/recaulk/version")"
REL="$T/rel"; DIR="$REL/$VER"; PKG="recaulk-$VER.pkg"; mkdir -p "$DIR"
L=usr/local/mavergreen/recaulk/lib

# Decoy base component: same library path, different bytes.
mkdir -p "$T/base/$L"; printf 'decoy\n' > "$T/base/$L/librecaulk.a"
pkgbuild --root "$T/base" --identifier dev.mavergreen.base --version 1 "$T/base.pkg" >/dev/null 2>&1

# Real recaulk component.
mkdir -p "$T/rc/$L" "$T/rc/usr/local/mavergreen/recaulk/include/recaulk"
ar rcs "$T/rc/$L/librecaulk.a" "$T/probe.o"
printf '/* time.h */\n' > "$T/rc/usr/local/mavergreen/recaulk/include/recaulk/time.h"
pkgbuild --root "$T/rc" --identifier dev.mavergreen.recaulk --version 1 "$T/rc.pkg" >/dev/null 2>&1

productbuild --package "$T/base.pkg" --package "$T/rc.pkg" "$DIR/$PKG" >/dev/null 2>&1
# Archive with only the base component.
productbuild --package "$T/base.pkg" "$T/nobase.pkg" >/dev/null 2>&1

sums() { ( cd "$DIR" && shasum -a 256 "$PKG" > SHA256SUMS ); }
sums

run() { # prints stdout to $T/out, stderr to $T/err; returns status
  RECAULK_BASE_URL="file://$REL" MAVERICKS_WORK="$T/work" sh "$ROOT/build/fetch-recaulk.sh" >"$T/out" 2>"$T/err"
}
fail() { echo "FAIL: $1"; cat "$T/err" 2>/dev/null; exit 1; }

run || fail "happy path exited non-zero"
lib="$(tail -n 1 "$T/out")"
cmp "$lib" "$T/rc/$L/librecaulk.a" || fail "printed lib is not the recaulk component's (decoy?)"
[ -f "$T/work/recaulk/include/recaulk/time.h" ] || fail "headers not extracted"

: > "$DIR/SHA256SUMS"
if run; then fail "unlisted pkg accepted"; fi
grep -q 'not listed in SHA256SUMS' "$T/err" || fail "no 'not listed' message"

echo "0000000000000000000000000000000000000000000000000000000000000000  $PKG" > "$DIR/SHA256SUMS"
if run; then fail "wrong hash accepted"; fi
grep -q 'sha mismatch' "$T/err" || fail "no 'sha mismatch' message"
[ ! -e "$T/work/recaulk-dl/$PKG" ] || fail "cached pkg not deleted after mismatch"

cp "$T/nobase.pkg" "$DIR/$PKG"; sums
rm -rf "$T/work"
if run; then fail "archive without recaulk component accepted"; fi
grep -q 'dev.mavergreen.recaulk' "$T/err" || fail "error does not name dev.mavergreen.recaulk"


# Swap a variant archive in under the pinned name and expect a FATAL naming `$2`.
variant() { # $1 = pkg to serve, $2 = text the stderr must contain
  cp "$1" "$DIR/$PKG"; sums; rm -rf "$T/work"
  if run; then fail "accepted: $2"; fi
  grep -q "$2" "$T/err" || fail "stderr lacks '$2'"
}

# Not exactly one component with the identifier: two of them.
pkgbuild --root "$T/rc" --identifier dev.mavergreen.recaulk --version 1 "$T/rc2.pkg" >/dev/null 2>&1
productbuild --package "$T/rc.pkg" --package "$T/rc2.pkg" "$T/two.pkg" >/dev/null 2>&1
variant "$T/two.pkg" 'expected exactly one component'

# Right component, but no lib/librecaulk.a in its payload.
mkdir -p "$T/nolib/usr/local/mavergreen/recaulk/include/recaulk"
printf '/* time.h */\n' > "$T/nolib/usr/local/mavergreen/recaulk/include/recaulk/time.h"
pkgbuild --root "$T/nolib" --identifier dev.mavergreen.recaulk --version 1 "$T/nolib.pkg" >/dev/null 2>&1
productbuild --package "$T/base.pkg" --package "$T/nolib.pkg" "$T/nolib-prod.pkg" >/dev/null 2>&1
variant "$T/nolib-prod.pkg" 'librecaulk.a in the'

# Right component, but no include/recaulk in its payload.
mkdir -p "$T/noinc/$L"; cp "$T/rc/$L/librecaulk.a" "$T/noinc/$L/"
pkgbuild --root "$T/noinc" --identifier dev.mavergreen.recaulk --version 1 "$T/noinc.pkg" >/dev/null 2>&1
productbuild --package "$T/base.pkg" --package "$T/noinc.pkg" "$T/noinc-prod.pkg" >/dev/null 2>&1
variant "$T/noinc-prod.pkg" 'include/recaulk in the'

# Library without an x86_64 slice (i386: this 10.9 cc cannot target arm64).
if "$CC_" -arch i386 -c "$T/probe.c" -o "$T/probe32.o" >/dev/null 2>&1; then
  mkdir -p "$T/i386/$L"; ar rcs "$T/i386/$L/librecaulk.a" "$T/probe32.o"
  mkdir -p "$T/i386/usr/local/mavergreen/recaulk/include/recaulk"
  pkgbuild --root "$T/i386" --identifier dev.mavergreen.recaulk --version 1 "$T/i386.pkg" >/dev/null 2>&1
  productbuild --package "$T/base.pkg" --package "$T/i386.pkg" "$T/i386-prod.pkg" >/dev/null 2>&1
  variant "$T/i386-prod.pkg" 'no x86_64 slice'
else
  echo "NOTE: cannot build a non-x86_64 object; slice case not exercised"
fi

echo "PASS: fetch-recaulk-test"
