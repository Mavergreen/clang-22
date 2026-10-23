#!/bin/sh
# platform: host-agnostic
#   usage: probe-linux-tools.sh PREFIX -- execute each required host tool before accepting it
set -eu
[ $# -eq 1 ] || exit 2
for tool in clang clang++ ld64.lld llvm-ar llvm-ranlib llvm-lipo llvm-otool llvm-nm llvm-strings llvm-strip llvm-objdump llvm-readobj llvm-profdata llvm-cov; do
  [ -x "$1/bin/$tool" ] || { echo "missing required tool: $tool" >&2; exit 1; }
  "$1/bin/$tool" --version >/dev/null || { echo "required tool cannot run: $tool" >&2; exit 1; }
done
echo 'PASS: every required Linux host tool executes'
