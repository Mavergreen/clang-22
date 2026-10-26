#!/bin/sh
# platform: Mac OS X 10.9 only -- the expected results are 10.9's libc++abi's; elsewhere it skips (77)
# LLVM's own libc++abi tests, run on 10.9 against the toolchain as users get it, in both shapes:
#   static  the toolchain's own `clang++`, no flags: clang++.cfg's libc++.a, Recaulk and -lc++abi.
#   dylib   libcxx22 (LIBCXX_LIB), whose libc++abi.1.dylib re-exports the system's.
# Every test in the suite has a line in tests/libcxxabi/expected.txt -- pass, fail or skip, with a
# reason for the last two -- and the gate is that list: a test that newly fails, newly passes, or is
# not listed fails it, so a change to the catch rules Recaulk gives 10.9 (cxxabi_pointer_catch.c),
# or an LLVM bump, cannot move a result unseen.
#
#   TC=<toolchain> LIBCXX_LIB=<libcxx22 lib> LIBCXXABI_TESTS=<llvm-project src> sh tests/libcxxabi-suite-test.sh
# LIBCXXABI_TESTS needs only libcxxabi/ and libcxx/test/support/ from the release's LLVM source.
# MAVERICKS_LIBCXXABI_ONLY=<name> runs one test, verbosely.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
TC="${TC:-$WORK/stage$CROSS_PREFIX}"
LIBCXX_LIB="${LIBCXX_LIB:-$LIBCXX_STAGE/lib}"
SRC="${LIBCXXABI_TESTS:-$SRC}"
EXPECTED="$HERE/libcxxabi/expected.txt"
[ "$(sw_vers -productVersion 2>/dev/null | cut -d. -f1-2)" = 10.9 ] || { echo "not Mac OS X 10.9 -- skipping"; exit 77; }
[ -x "$TC/bin/clang++" ] || { echo "no toolchain at $TC -- skipping"; exit 77; }
[ -f "$LIBCXX_LIB/libc++.1.dylib" ] || { echo "FAIL: libcxx22 not at $LIBCXX_LIB"; exit 1; }
T="$SRC/libcxxabi/test"
[ -f "$T/catch_ptr.pass.cpp" ] || { echo "FAIL: libc++abi's tests not at $T"; exit 1; }
w="$(mktemp -d "${TMPDIR:-/tmp}/libcxxabi-suite.XXXXXX")"
trap 'rm -rf "$w"' EXIT

# dyld tries the install name first, so a staged libcxx22 would lose to an installed one (as
# tests/libcxx-runtime-test.sh).
RUN_ENV=""
if [ "$LIBCXX_LIB" != "$LIBCXX_PREFIX/lib" ]; then
  [ ! -e "$LIBCXX_PREFIX/lib/libc++.1.dylib" ] \
    || { echo "FAIL: libcxx22 is installed at $LIBCXX_PREFIX, which dyld would load instead of $LIBCXX_LIB"; exit 1; }
  RUN_ENV="DYLD_FALLBACK_LIBRARY_PATH=$LIBCXX_LIB"
fi

# spec: libcxxabi/test/configs/llvm-libc++abi-shared.cfg.in -- the suite's own %{compile_flags}:
#       its support headers and libc++'s, libc++'s src/ (the guard and fallback-malloc tests include
#       libc++abi's sources), and libc++abi's own headers ahead of the SDK's cxxabi.h.
INC="-I$T/support -I$SRC/libcxx/test/support -I$SRC/libcxx/src -I$SRC/libcxxabi/include -D_LIBCPP_ENABLE_CXX17_REMOVED_UNEXPECTED_FUNCTIONS"
cxx() {
  case "$shape" in
    static) "$TC/bin/clang++" "$@" ;;
    dylib)  "$TC/bin/clang++" -nostdinc++ -isystem "$TC/include/c++/v1" -isystem "$TC/include/recaulk" \
              -nostdlib++ "$@" "$LIBCXX_LIB/libc++.1.dylib" "$TC/lib/librecaulk.a" ;;
  esac
}
# spec: llvm/utils/lit and libcxx/utils/libcxx/test/format.py -- the lit directives the suite's tests
#       use that change how one is built, and no others: a test's ADDITIONAL_COMPILE_FLAGS; REQUIRES
#       c++14, which lit meets by running it in that dialect; a .compile test is only compiled.
#       UNSUPPORTED, XFAIL and other REQUIRES are not read: expected.txt says each test's result.
flags() {
  sed -n 's|^// *ADDITIONAL_COMPILE_FLAGS: *||p' "$1" | tr '\n' ' '
  if grep -q '^// *REQUIRES:.*c++14' "$1"; then echo ' -std=c++14'; else echo ' -std=c++17'; fi
}
build() { # name src exe
  # spec: libcxxabi/test/incomplete_type.sh.cpp -- its RUN lines: two translation units, one -DTU_ONE
  if [ "$1" = incomplete_type ]; then
    cxx -std=c++17 -w $INC -c "$2" -o "$3.one.o" && cxx -std=c++17 -w $INC -DTU_ONE -c "$2" -o "$3.two.o" \
      && cxx "$3.one.o" "$3.two.o" -o "$3"
  else
    case "$1" in
      *.compile) cxx -w $INC $(flags "$2") -c "$2" -o "$3.o" && printf '#!/bin/sh\n' > "$3" && chmod +x "$3" ;;
      *) cxx -w $INC $(flags "$2") -pthread "$2" -o "$3" ;;
    esac
  fi
}

listed="$w/listed"; sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$EXPECTED" > "$listed"
fail=0; n=0
for src in "$T"/*.pass.cpp "$T"/incomplete_type.sh.cpp; do
  name="$(basename "$src")"; name="${name%.pass.cpp}"; name="${name%.sh.cpp}"
  [ -z "${MAVERICKS_LIBCXXABI_ONLY:-}" ] || [ "$name" = "$MAVERICKS_LIBCXXABI_ONLY" ] || continue
  for shape in static dylib; do
    want="$(awk -v n="$name" -v s="$shape" '$1 == n && ($2 == s || $2 == "both") { print $3 }' "$listed")"
    case "$want" in
      '') echo "FAIL: $name ($shape) is not in tests/libcxxabi/expected.txt"; fail=1; continue ;;
      skip) continue ;;
      pass|fail) : ;;
      *) echo "FAIL: $name ($shape): expected.txt says '$want'"; fail=1; continue ;;
    esac
    exe="$w/$shape-$name"; n=$((n + 1))
    if build "$name" "$src" "$exe" > "$exe.log" 2>&1 && (cd "$w" && env $RUN_ENV "$exe") >> "$exe.log" 2>&1; then
      got=pass
    else
      got=fail
    fi
    [ -z "${MAVERICKS_LIBCXXABI_ONLY:-}" ] || cat "$exe.log"
    if [ "$got" != "$want" ]; then
      echo "FAIL: $name ($shape) was expected to $want, and it ${got}ed:"; sed 's/^/    /' "$exe.log" | head -20
      fail=1
    fi
  done
done
# A listed test that no longer exists is a stale line.
awk '{ print $1 }' "$listed" | sort -u | while read -r name; do
  [ -f "$T/$name.pass.cpp" ] || [ -f "$T/$name.sh.cpp" ] || { echo "FAIL: expected.txt lists $name, which the suite no longer has"; echo x >> "$w/stale"; }
done
[ ! -f "$w/stale" ] || fail=1
[ "$fail" = 0 ] || exit 1
echo "ok: libc++abi's suite on 10.9 ($n runs) matches tests/libcxxabi/expected.txt"
