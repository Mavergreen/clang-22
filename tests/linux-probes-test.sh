#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d "${TMPDIR:-/tmp}/linux-probes.XXXXXX")"; trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin"
for tool in clang clang++ ld64.lld llvm-ar llvm-ranlib llvm-lipo llvm-otool llvm-nm llvm-strings llvm-strip llvm-install-name-tool llvm-objdump llvm-readobj llvm-profdata llvm-cov dsymutil strip lipo; do
  printf '#!/bin/sh\n[ "$1" = --version ]\n' > "$t/bin/$tool"; chmod +x "$t/bin/$tool"
done
# platform: Go's darwin external link runs $CC --print-prog-name=dsymutil and =strip
printf '#!/bin/sh\ncase "$1" in --version) ;; --print-prog-name=*) echo "$(dirname "$0")/${1#*=}" ;; *) exit 1 ;; esac\n' > "$t/bin/clang"
sh "$ROOT/build/probe-linux-tools.sh" "$t"
printf '#!/bin/sh\ncase "$1" in --version) ;; --print-prog-name=*) echo "${1#*=}" ;; esac\n' > "$t/bin/clang"
if sh "$ROOT/build/probe-linux-tools.sh" "$t" 2>/dev/null; then echo 'FAIL: clang that does not find its own dsymutil passed'; exit 1; fi
printf '#!/bin/sh\ncase "$1" in --version) ;; --print-prog-name=*) echo "$(dirname "$0")/${1#*=}" ;; esac\n' > "$t/bin/clang"
for tool in dsymutil strip lipo; do
  mv "$t/bin/$tool" "$t/$tool"
  if sh "$ROOT/build/probe-linux-tools.sh" "$t" 2>/dev/null; then echo "FAIL: absent $tool passed"; exit 1; fi
  mv "$t/$tool" "$t/bin/$tool"
done
printf '#!/bin/sh\nexit 127\n' > "$t/bin/llvm-install-name-tool"
if sh "$ROOT/build/probe-linux-tools.sh" "$t"; then echo 'FAIL: unusable shipped reader passed'; exit 1; fi
rm "$t/bin/llvm-install-name-tool"
if sh "$ROOT/build/probe-linux-tools.sh" "$t"; then echo 'FAIL: absent shipped reader passed'; exit 1; fi
echo 'PASS: every required tool is executed, missing/broken tools fail'
