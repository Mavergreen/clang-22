#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d "${TMPDIR:-/tmp}/linux-probes.XXXXXX")"; trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin"
for tool in clang clang++ ld64.lld llvm-ar llvm-ranlib llvm-lipo llvm-otool llvm-nm llvm-strings llvm-strip llvm-install-name-tool llvm-objdump llvm-readobj llvm-profdata llvm-cov; do
  printf '#!/bin/sh\n[ "$1" = --version ]\n' > "$t/bin/$tool"; chmod +x "$t/bin/$tool"
done
sh "$ROOT/build/probe-linux-tools.sh" "$t"
printf '#!/bin/sh\nexit 127\n' > "$t/bin/llvm-install-name-tool"
if sh "$ROOT/build/probe-linux-tools.sh" "$t"; then echo 'FAIL: unusable shipped reader passed'; exit 1; fi
rm "$t/bin/llvm-install-name-tool"
if sh "$ROOT/build/probe-linux-tools.sh" "$t"; then echo 'FAIL: absent shipped reader passed'; exit 1; fi
echo 'PASS: every required tool is executed, missing/broken tools fail'
