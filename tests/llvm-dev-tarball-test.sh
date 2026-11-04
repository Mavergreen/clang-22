#!/bin/sh
# platform: host-agnostic
# Packages a fake install tree and checks the llvm22-dev ingredient tarball's exact contents,
# reproducibility and argument handling.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
FIX="$HERE/fixtures/llvm-dev-stage"
PKG="$ROOT/build/package-llvm-dev.sh"
: "${SHIPYARD_SCRIPTS:=/usr/local/mavergreen/shipyard/share/cmake/MavericksShipyard/scripts}"; export SHIPYARD_SCRIPTS
SOURCE_DATE_EPOCH=1700000000; export SOURCE_DATE_EPOCH
T="$(mktemp -d "${TMPDIR:-/tmp}/llvm-dev-test.XXXXXX")"; trap 'rm -rf "$T"' EXIT
FULL="$(. "$ROOT/build/versions.sh" >/dev/null; echo "$PKG_VERSION")"
LLVMV="$(. "$ROOT/build/versions.sh" >/dev/null; echo "$LLVM_VERSION")"
fail() { echo "FAIL: $*" >&2; exit 1; }

[ -f "$PKG" ] || fail "build/package-llvm-dev.sh is missing"

sh "$PKG" "$FIX" arm64 "$T/a" >/dev/null
TB="$T/a/llvm22-dev-$FULL-darwin-arm64.tar.gz"
[ -f "$TB" ] || fail "no $TB"
tar -tzf "$TB" | LC_ALL=C sort > "$T/arm64.list"
cat > "$T/arm64.want" <<'WANT'
llvm22-dev/
llvm22-dev/BUILD-INFO
llvm22-dev/bin/
llvm22-dev/bin/llvm-config
llvm22-dev/include/
llvm22-dev/include/c++/
llvm22-dev/include/c++/v1/
llvm22-dev/include/c++/v1/vector
llvm22-dev/include/clang-c/
llvm22-dev/include/clang-c/Index.h
llvm22-dev/include/clang/
llvm22-dev/include/clang/Basic/
llvm22-dev/include/clang/Basic/Version.h
llvm22-dev/include/lld/
llvm22-dev/include/lld/Common/
llvm22-dev/include/lld/Common/Driver.h
llvm22-dev/include/llvm-c/
llvm22-dev/include/llvm-c/Core.h
llvm22-dev/include/llvm/
llvm22-dev/include/llvm/ADT/
llvm22-dev/include/llvm/ADT/StringRef.h
llvm22-dev/lib/
llvm22-dev/lib/cmake/
llvm22-dev/lib/cmake/clang/
llvm22-dev/lib/cmake/clang/ClangConfig.cmake
llvm22-dev/lib/cmake/lld/
llvm22-dev/lib/cmake/lld/LLDConfig.cmake
llvm22-dev/lib/cmake/llvm/
llvm22-dev/lib/cmake/llvm/LLVMConfig.cmake
llvm22-dev/lib/libLLVMCore.a
llvm22-dev/lib/libLLVMSupport.a
llvm22-dev/lib/libclangBasic.a
llvm22-dev/lib/libclangFrontend.a
llvm22-dev/lib/liblldCommon.a
llvm22-dev/lib/x86_64-apple-darwin/
llvm22-dev/lib/x86_64-apple-darwin/libc++.a
WANT
LC_ALL=C sort "$T/arm64.want" > "$T/arm64.want.s"
diff "$T/arm64.want.s" "$T/arm64.list" || fail "arm64 file list differs from the contract"
for absent in bin/clang bin/ld64.lld lib/libclang_rt.osx.a lib/libLLVM.dylib; do
  if grep -q "^llvm22-dev/$absent\$" "$T/arm64.list"; then fail "$absent must not be packaged"; fi
done
if grep -q 'libclang_rt' "$T/arm64.list"; then fail "compiler-rt leaked in"; fi
tar -xzOf "$TB" llvm22-dev/BUILD-INFO > "$T/info"
[ "$(cat "$T/info")" = "llvm=$LLVMV clang22=$FULL targets=AArch64;X86 arch=arm64" ] || fail "BUILD-INFO: $(cat "$T/info")"
tar -xzOf "$TB" llvm22-dev/lib/x86_64-apple-darwin/libc++.a | grep -q 'x86_64-apple-macos10.9/libc++.a' || fail "libc++.a not taken from the discovered runtime dir"

sh "$PKG" "$FIX" arm64 "$T/b" >/dev/null
cmp "$TB" "$T/b/llvm22-dev-$FULL-darwin-arm64.tar.gz" || fail "two builds of the same stage differ"

sh "$PKG" "$FIX" x86_64 "$T/x" >/dev/null
TX="$T/x/llvm22-dev-$FULL-darwin-x86_64.tar.gz"
[ -f "$TX" ] || fail "no $TX"
tar -tzf "$TX" > "$T/x.list"
if grep -q 'c++' "$T/x.list"; then fail "x86_64 tarball must carry no libc++"; fi
grep -q '^llvm22-dev/bin/llvm-config$' "$T/x.list" || fail "x86_64 tarball lacks llvm-config"
tar -xzOf "$TX" llvm22-dev/BUILD-INFO | grep -qx "llvm=$LLVMV clang22=$FULL targets=AArch64;X86 arch=x86_64" || fail "x86_64 BUILD-INFO"

rc=0; sh "$PKG" "$FIX" ppc "$T/p" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "unknown arch exited $rc, wanted 2"

# missing_lib_group_fails / missing_cmake_dir_fails / targets_from_llvmconfig
for case_ in "lib/libLLVMCore.a lib/libLLVMSupport.a:libLLVM" "lib/libclangBasic.a lib/libclangFrontend.a:libclang*" "lib/liblldCommon.a:liblld" "lib/cmake/clang:cmake/clang" "include/lld:include/lld"; do
  rm -rf "$T/inc"; cp -R "$FIX" "$T/inc"
  for g in ${case_%%:*}; do rm -rf "$T/inc/$g"; done
  rc=0; sh "$PKG" "$T/inc" arm64 "$T/i" >"$T/i.out" 2>&1 || rc=$?
  [ "$rc" = 1 ] || fail "incomplete stage (${case_%%:*}) exited $rc, wanted 1"
  grep -q "${case_%%:*}" "$T/i.out" 2>/dev/null || grep -q "missing" "$T/i.out" || fail "no diagnosis for ${case_%%:*}"
done
rm -rf "$T/inc"; cp -R "$FIX" "$T/inc"; sed '/LLVM_TARGETS_TO_BUILD/d' "$FIX/lib/cmake/llvm/LLVMConfig.cmake" > "$T/inc/lib/cmake/llvm/LLVMConfig.cmake"
rc=0; sh "$PKG" "$T/inc" arm64 "$T/i" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "stage without LLVM_TARGETS_TO_BUILD exited $rc, wanted 1"

echo "PASS llvm-dev-tarball-test"
