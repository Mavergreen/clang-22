#!/bin/sh
# platform: host-agnostic
# SKIP (77) until a toolchain is staged. A value caught by value must be read at no more than the
# alignment the exception object has (patches/0003). Before macOS 10.14, libc++abi places a thrown object
# 8 bytes past a 16-byte boundary, and clang knows it (getExnObjectAlignment is 8 there, and the throw
# side uses it), but its catch side read a caught __int128, or a 16-byte-aligned class, at the type's own
# alignment: an aligned SSE load, which faults on 10.9 to 10.13. Checked in the IR on any host, with a
# 10.14 control that must keep the type's own alignment, and at run time where x86_64 runs (only a 10.9
# to 10.13 runtime can fault, so CI's on-mavericks job is the run that proves it).
#
# Still unsafe, and not this test's: catching such a type BY REFERENCE, which binds to the exception
# object itself, so every use of the reference assumes the type's alignment.
#
#   TC=<toolchain prefix> sh tests/catch-align-test.sh     (default: the cross stage)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
TC="${TC:-$WORK/stage$CROSS_PREFIX}"
[ -x "$TC/bin/clang++" ] || { echo "not built -- skipping"; exit 77; }
SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
. "$HERE/support/target-test-lib.sh"
target_workspace catch-align
fail() { echo "FAIL: $*"; exit 1; }

cat > "$t/c.cpp" <<'EOF'
#include <cstdio>
#include <cstring>
struct alignas(16) Wide { __int128 v; };
__attribute__((noinline)) static void throw_wide() { throw Wide{6}; }
int main(int argc, char **argv) {
  const char *c = argc > 1 ? argv[1] : "";
  if (!std::strcmp(c, "int128")) {
    // Thrown and caught in one function, and compared, so clang uses SSE: unpatched, a movdqa of the
    // caught value faults on 10.9.
    try { throw (__int128)5; } catch (__int128 v) { std::printf("caught %s\n", v == 5 ? "5" : "a wrong value"); return v == 5 ? 0 : 1; }
  }
  if (!std::strcmp(c, "wide")) {
    try { throw_wide(); } catch (Wide w) { std::printf("caught %s\n", w.v == 6 ? "6" : "a wrong value"); return w.v == 6 ? 0 : 1; }
  }
  return 2;
}
EOF
ir() { # $1 deployment target, $2 output
  "$TC/bin/clang++" --no-default-config --target=x86_64-apple-macos"$1" -isysroot "$SDK" -nostdinc++ \
    -isystem "$TC/include/c++/v1" -std=c++17 -O0 -S -emit-llvm -Wno-underaligned-exception-object "$t/c.cpp" -o "$2"
}
# The caught value's read: a load of i128 from the pointer __cxa_begin_catch returned, or the copy of a
# Wide out of it (memcpy, for a trivial copy). At -O0, so the two catches stay apart.
caught_aligns() { # $1 IR: prints the alignment of the first read of a caught value after each begin_catch
  awk '/call ptr @__cxa_(begin_catch|get_exception_ptr)\(/ { look = 1; next }
       look && /load i128, ptr/ { match($0, /align [0-9]+/); print substr($0, RSTART + 6, RLENGTH - 6); look = 0; next }
       look && /llvm\.memcpy/ { s = $0; sub(/^.*ptr align [0-9]+ %[^,]*, ptr /, "", s); match(s, /align [0-9]+/); print substr(s, RSTART + 6, RLENGTH - 6); look = 0 }' "$1"
}
ir 10.9 "$t/old.ll"
ir 10.14 "$t/new.ll"
caught_aligns "$t/old.ll" > "$t/old"
caught_aligns "$t/new.ll" > "$t/new"
# Two reads each: the __int128's and the Wide's. Fewer means the IR changed shape and is not being checked.
[ "$(wc -l < "$t/old" | tr -d ' ')" -ge 2 ] || { cat "$t/old.ll"; fail "found $(wc -l < "$t/old" | tr -d ' ') reads of a caught value in the 10.9 IR, want both cases"; }
[ "$(wc -l < "$t/new" | tr -d ' ')" -ge 2 ] || fail "found $(wc -l < "$t/new" | tr -d ' ') reads of a caught value in the 10.14 IR, want both cases"
if awk '$1 > 8 { bad = 1 } END { exit !bad }' "$t/old"; then
  fail "for 10.9 a caught value is read at alignment $(sort -n "$t/old" | tail -1), but the exception object has 8"
fi
awk '$1 != 16 { bad = 1 } END { exit bad }' "$t/new" || fail "for 10.14 a caught value no longer keeps its 16-byte alignment: $(tr '\n' ' ' < "$t/new")"
echo "ok: caught values read at $(sort -nu "$t/old" | tr '\n' ' ')for 10.9, $(sort -nu "$t/new" | tr '\n' ' ')for 10.14"

# The run: whether a 16-byte read of the caught value becomes an aligned SSE instruction depends on the
# code around it, so this is the shape that faulted on 10.9.5 with unpatched clang 22.1.8 (exit 139, a
# movdqa of the caught __int128), and nothing else. Only a 10.9 to 10.13 runtime can fault.
cat > "$t/r.cpp" <<'EOF'
#include <cstdio>
int main() {
  try { throw (__int128)5; } catch (__int128 v) { std::printf("caught %s\n", v == 5 ? "5" : "a wrong value"); return v == 5 ? 0 : 1; }
}
EOF
"$TC/bin/clang++" -std=c++17 -O1 -Wno-underaligned-exception-object "$t/r.cpp" -o "$t/r"
target_finish catch-align
echo "PASS: catch alignment"
