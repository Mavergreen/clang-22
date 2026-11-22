#!/bin/sh
# platform: host-agnostic
#   usage: probe-linux-tools.sh PREFIX -- execute each required host tool before accepting it
set -eu
[ $# -eq 1 ] || exit 2
for tool in clang clang++ ld64.lld llvm-ar llvm-ranlib llvm-lipo llvm-otool llvm-nm llvm-strings llvm-strip llvm-install-name-tool llvm-objdump llvm-readobj llvm-profdata llvm-cov dsymutil strip; do
  [ -x "$1/bin/$tool" ] || { echo "missing required tool: $tool" >&2; exit 1; }
  "$1/bin/$tool" --version >/dev/null || { echo "required tool cannot run: $tool" >&2; exit 1; }
done
# platform: Go's darwin external link runs $CC --print-prog-name=dsymutil and =strip, and dsymutil
#           folds the DWARF in; clang must name its own sibling, not a bare name for PATH to resolve
for tool in dsymutil strip; do
  got="$("$1/bin/clang" --print-prog-name="$tool")"
  [ "$got" -ef "$1/bin/$tool" ] || { echo "clang --print-prog-name=$tool gives '$got', not $1/bin/$tool" >&2; exit 1; }
done
echo 'PASS: every required Linux host tool executes'
