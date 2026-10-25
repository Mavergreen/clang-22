#!/bin/sh
# platform: macOS-only -- runs the staged cross clang and the binaries it emits
# SKIP (77) until staged. Compile hello.cpp with the cross clang, assert the OUTPUT and the shipped
# x86_64/10.9 runtimes are 10.9-safe (arch x86_64 + LC_VERSION_MIN_MACOSX 10.9, no post-10.9 imports).
#
# This is the in-CI equivalence proof that stands in for the absent 10.9 runner. It is deliberately
# an END-TO-END test: it invokes clang++ with NO flags at all, so it fails if clang.cfg stops being
# auto-loaded, if the default target drifts, or if the polyfill stops being linked -- the whole
# batteries-included claim, not just the presence of some files.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
STAGE="${TC:-$WORK/stage$CROSS_PREFIX}"
CLANGXX="$STAGE/bin/clang++"
[ -x "$CLANGXX" ] || { echo "not built -- skipping"; exit 77; }

# clang.cfg references <CFGDIR>/../SDKs/MacOSX10.9.sdk, which is not redistributed; point it at the
# fetched SDK here. After packaging, SDKs is a link into ../sdk109/ that dangles in the stage, so it goes.
if [ ! -e "$STAGE/SDKs/MacOSX10.9.sdk" ]; then
  [ ! -L "$STAGE/SDKs" ] || rm -f "$STAGE/SDKs"
  mkdir -p "$STAGE/SDKs"
  SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"; ln -sfn "$SDK" "$STAGE/SDKs/MacOSX10.9.sdk"
fi

t="$(mktemp -d "${TMPDIR:-/tmp}/smoke-target.XXXXXX")"; trap 'rm -rf "$t"' EXIT   # template: 10.9 BSD mktemp requires one
cat > "$t/hello.cpp" <<'EOF'
#include <iostream>
int main(){ std::cout << "hello mavericks\n"; return 0; }
EOF
"$CLANGXX" "$t/hello.cpp" -o "$t/hello"
"$STAGE/bin/llvm-lipo" -info "$t/hello" | sed -n 's/.*: //p' | grep -qw x86_64 || { echo "FAIL: not x86_64"; exit 1; }
# clang++.cfg links libobjc and three frameworks for librecaulk's members; -dead_strip_dylibs must
# drop every one hello does not use, as clang.cfg does for C, so it depends on libSystem and the
# system's libc++abi (the one C++ ABI, build-cross.sh step 3) alone, both on every macOS since 10.7.
OTOOL="$STAGE/bin/llvm-otool"; [ -x "$OTOOL" ] || OTOOL=otool
deps="$("$OTOOL" -L "$t/hello" | sed 1d | awk '{print $1}')"
[ "$(printf '%s\n' "$deps" | LC_ALL=C sort)" = "$(printf '%s\n' /usr/lib/libSystem.B.dylib /usr/lib/libc++abi.dylib | LC_ALL=C sort)" ] \
  || { echo "FAIL: hello links other than libSystem and /usr/lib/libc++abi.dylib:"; echo "$deps"; exit 1; }

# Over-aligned allocation, with no flags. clang gates aligned new below 10.13 because the SYSTEM libc++
# lacked it; this toolchain always links its own libc++.a, which has it (patches/0007).
# Without that, make_unique of an alignas(64) type does not compile, and vector's storage silently gets
# only malloc's 16-byte alignment.
cat > "$t/aligned.cpp" <<'EOF'
#include <cstdint>
#include <cstdio>
#include <memory>
#include <vector>
struct alignas(64) Line { char c[64]; };
int main() {
  std::vector<std::vector<Line>> keep; std::vector<std::unique_ptr<Line>> owned; int bad = 0;
  for (int i = 0; i < 100; i++) {
    keep.emplace_back(1 + i % 5); bad += (uintptr_t)keep.back().data() % 64 != 0;
    owned.push_back(std::make_unique<Line>()); bad += (uintptr_t)owned.back().get() % 64 != 0;
  }
  std::printf("%d of 200 misaligned\n", bad);
  return bad != 0;
}
EOF
"$CLANGXX" -std=c++17 -O1 "$t/aligned.cpp" -o "$t/aligned" \
  || { echo "FAIL: over-aligned allocation does not compile with the default flags"; exit 1; }
if [ "$(uname -m)" = x86_64 ] || arch -x86_64 /usr/bin/true 2>/dev/null; then
  out="$("$t/aligned")" || { echo "FAIL: over-aligned allocation: $out"; exit 1; }
  echo "ok: over-aligned allocation ($out)"
else
  echo "note: x86_64 does not run here; over-aligned allocation compiled, not run"
fi

# std::cout from a global constructor (patches/0006). libc++.a is appended last, and Mach-O orders
# initializers by input order (init_priority only orders them within one object), so libc++'s own
# stream initializer ran after the program's: the write crashed (exit 139 on 10.9.5). With libc++ as a
# dylib, dyld initializes it first, which is why Apple's toolchain never meets this.
cat > "$t/early.cpp" <<'EOF'
#include <iostream>
struct Early { Early() { std::cout << "early "; } } early;
int main() { std::cout << "main\n"; return 0; }
EOF
"$CLANGXX" -std=c++17 "$t/early.cpp" -o "$t/early"
if [ "$(uname -m)" = x86_64 ] || arch -x86_64 /usr/bin/true 2>/dev/null; then
  out="$("$t/early")" || { echo "FAIL: std::cout from a global constructor crashed"; exit 1; }
  [ "$out" = 'early main' ] || { echo "FAIL: std::cout from a global constructor: $out"; exit 1; }
  echo "ok: std::cout from a global constructor"
fi

# ...without forcing either into a standard that lacks it: forced on in C++03, clang's implicit
# std::align_val_t clashed with libc++'s, so every header that reaches <new> failed to compile.
printf '#include <algorithm>\n#include <memory>\nint main() { return 0; }\n' > "$t/cxx03.cpp"
"$CLANGXX" -std=c++03 -Werror "$t/cxx03.cpp" -o "$t/cxx03" \
  || { echo "FAIL: <algorithm> and <memory> do not compile as C++03"; exit 1; }
echo "ok: C++03 headers"

# Sized deallocation, the same kind of gate (off below 10.12): a delete must call the sized operator.
printf 'struct S { long v[4]; };\nvoid drop(S *p) { delete p; }\n' > "$t/sized.cpp"
"$CLANGXX" -std=c++17 -c "$t/sized.cpp" -o "$t/sized.o"
"$STAGE/bin/llvm-nm" -u "$t/sized.o" | grep -q '__ZdlPvm$' \
  || { echo "FAIL: delete does not call the sized operator delete(void*, size_t)"; exit 1; }
echo "ok: sized deallocation"

# A project's own deployment target wins over the cfg's 10.9 default (CMAKE_OSX_DEPLOYMENT_TARGET is
# passed this way). A versioned --target in the cfgs overrode it: a project asking for 10.12 silently
# got 10.9, with at most a -Woverriding-option warning.
minos() { "$OTOOL" -l "$1" | awk '/LC_VERSION_MIN_MACOSX/ { f = 1 } f && $1 == "version" { print $2; exit }'; }
[ "$(minos "$t/hello")" = 10.9 ] || { echo "FAIL: default deployment target is $(minos "$t/hello"), not 10.9"; exit 1; }
for drv in clang clang++; do
  "$STAGE/bin/$drv" -x c -Werror -mmacosx-version-min=10.12 /dev/null -c -o "$t/dt.o" 2>"$t/dt.err" \
    || { echo "FAIL: $drv -mmacosx-version-min=10.12 -Werror:"; cat "$t/dt.err"; exit 1; }
  "$CLANGXX" -mmacosx-version-min=10.12 "$t/hello.cpp" -o "$t/hello1012"
  [ "$(minos "$t/hello1012")" = 10.12 ] \
    || { echo "FAIL: -mmacosx-version-min=10.12 gives deployment target $(minos "$t/hello1012")"; exit 1; }
done
echo "ok: a project's deployment target wins; the default is 10.9"

# The compat guard: assert the emitted binary is 10.9-safe. Do NOT point it at the arm64 host clang --
# it asserts arch x86_64 by design and would fail for the wrong reason.
sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$t/hello"

# ...and the shipped target runtime dylibs, if the runtimes build produced any. Discovered rather than
# assumed: LLVM lays per-target runtimes under lib/<triple>/ and the triple is the runtimes-build one
# (x86_64-apple-darwin), not the product's default target.
rtlib="$(find "$STAGE/lib" -name 'libc++.*dylib' -print 2>/dev/null | head -1)"
if [ -n "$rtlib" ]; then
  RTDIR="$(dirname "$rtlib")"
  for d in "$RTDIR"/libc++.*dylib "$RTDIR"/libc++abi.*dylib; do
    [ -f "$d" ] && sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$d"
  done
else
  echo "note: no target libc++ dylib staged (static-only runtimes); the emitted binary is the proof"
fi
echo "OK smoke-target"
