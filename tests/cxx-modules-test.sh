#!/bin/sh
# platform: host-agnostic
# SKIP (77) until a toolchain is staged. `-fmodules` on C++ or Objective-C++ against the 10.9 SDK must
# compile: libc++ 22's modulemap gives each C wrapper (string.h, math.h...) a module of its own, which
# include_nexts into the SDK's single `Darwin` module, whose headers include those names back, so clang
# reported "cyclic dependency in module 'Darwin'". The cfgs pass -fno-cxx-modules, as Xcode 5 left C++
# modules off for this SDK, so C++ includes stay textual; C and Objective-C keep their modules.
#
#   TC=<toolchain prefix> sh tests/cxx-modules-test.sh     (default: the cross stage)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
TC="${TC:-$WORK/stage$CROSS_PREFIX}"
[ -x "$TC/bin/clang" ] || { echo "not built -- skipping"; exit 77; }
SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
t="$(mktemp -d "${TMPDIR:-/tmp}/cxx-modules.XXXXXX")"; trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

# clang.cfg names <CFGDIR>/../SDKs/MacOSX10.9.sdk, which a stage does not carry (see smoke-target.sh).
if [ ! -e "$TC/SDKs/MacOSX10.9.sdk" ]; then
  [ ! -L "$TC/SDKs" ] || rm -f "$TC/SDKs"
  mkdir -p "$TC/SDKs"; ln -sfn "$SDK" "$TC/SDKs/MacOSX10.9.sdk"
fi

printf '#include <string.h>\n#include <string>\n#include <cmath>\nint f(const char *s) { return (int)strlen(s) + (int)std::string(s).size() + (int)std::sqrt(4.0); }\n' > "$t/a.cpp"
printf '#import <Foundation/Foundation.h>\n#include <string>\nint g(void) { return (int)[@"x" length] + (int)std::string("y").size(); }\n' > "$t/b.mm"
printf '#import <Foundation/Foundation.h>\nint h(void) { return (int)[@"x" length]; }\n' > "$t/c.m"
M="-fmodules -fmodules-cache-path=$t/mc -Wno-deprecated-module-dot-map"
"$TC/bin/clang++" $M -c "$t/a.cpp" -o "$t/a.o" 2>"$t/err" || { cat "$t/err"; fail "C++ with -fmodules did not compile"; }
"$TC/bin/clang++" $M -c "$t/b.mm" -o "$t/b.o" 2>"$t/err" || { cat "$t/err"; fail "Objective-C++ with -fmodules did not compile"; }
! grep -q cyclic "$t/err" || { cat "$t/err"; fail "a module cycle was reported"; }
"$TC/bin/clang" $M -c "$t/c.m" -o "$t/c.o" 2>"$t/err" || { cat "$t/err"; fail "Objective-C with -fmodules did not compile"; }
# C and Objective-C still build modules: Foundation's is in the cache.
find "$t/mc" -name 'Foundation-*.pcm' | grep -q . || fail "Objective-C -fmodules built no Foundation module"
echo 'PASS: -fmodules compiles C++, Objective-C++ and Objective-C against the 10.9 SDK'
