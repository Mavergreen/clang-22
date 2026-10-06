#!/bin/sh
# platform: macOS-only -- reads the Mach-O reference dylibs with llvm-nm (set NM)
# Usage: generate.sh REF_LIBCXX REF_LIBCXXABI LIBRECAULK_A LIBCLANG_RT_OSX_A OUTDIR
set -eu
[ $# -eq 5 ] || { echo "usage: $0 REF_LIBCXX REF_LIBCXXABI LIBRECAULK_A LIBCLANG_RT_OSX_A OUTDIR" >&2; exit 2; }
CXX="$1"; ABI="$2"; RECAULK_A="$3"; RT_A="$4"; OUT="$5"
NM="${NM:-nm}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"; export REPO_ROOT
CXX_SHA=ac26f5bc579d06e4d4236fea83b083061022e9ce9ace5232b2b12949ac3f9ef7
ABI_SHA=e6027c153de2fc04c340a42f66dee8e61374e5bade6705cf247677ca011c42f9
sha() { shasum -a 256 "$1" | awk '{print $1}'; }
[ "$(sha "$CXX")" = "$CXX_SHA" ] || { echo "generate.sh: $CXX is not the reference libc++" >&2; exit 1; }
[ "$(sha "$ABI")" = "$ABI_SHA" ] || { echo "generate.sh: $ABI is not the reference libc++abi" >&2; exit 1; }
RECAULK_VERSION="$(tr -d ' \t\r\n' < "$REPO_ROOT/components/recaulk/version")"
mkdir -p "$OUT"
T="$(mktemp -d "${TMPDIR:-/tmp}/parity-gen.XXXXXX")"; trap 'rm -rf "$T"' EXIT

# Defined names of an archive, with one trailing .eh removed, as a sorted set.
defs() { "$NM" -gUj "$1" 2>/dev/null | grep -v ':$' | grep -v '^$' | sed 's/\.eh$//' | LC_ALL=C sort -u; }
defs "$RECAULK_A" > "$T/recaulk"
defs "$RT_A" > "$T/builtins"

: > "$T/excluded"
for lib in "$CXX" "$ABI"; do
  b="$(basename "$lib" .dylib)"
  "$NM" -gUj "$lib" | LC_ALL=C sort -u > "$T/$b.all"
  sed 's/\.eh$//' "$T/$b.all" | LC_ALL=C sort -u > "$T/$b.stripped"
  # Reason by name: recaulk wins over builtins when both define it.
  while IFS= read -r n; do
    s="${n%.eh}"
    if grep -qxF -- "$s" "$T/recaulk"; then echo "$n recaulk"
    elif grep -qxF -- "$s" "$T/builtins"; then echo "$n builtins"
    fi
  done < "$T/$b.all" >> "$T/excluded"
  awk '{print $1}' "$T/excluded" | LC_ALL=C sort -u > "$T/ex.names"
  LC_ALL=C comm -23 "$T/$b.all" "$T/ex.names" > "$OUT/$b.exports"
done
LC_ALL=C sort -u "$T/excluded" > "$OUT/excluded.txt"
{
  echo "libc++.1.dylib sha256 $CXX_SHA"
  echo "libc++abi.1.dylib sha256 $ABI_SHA"
  echo "RECAULK_VERSION $RECAULK_VERSION"
  echo "libclang_rt.osx.a sha256 $(sha "$RT_A")"
} > "$OUT/SOURCES"
