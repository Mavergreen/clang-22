#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/src/llvm"
cat > "$T/bin/cmake" <<'SH'
#!/bin/sh
printf '%s\n' "$@" > "$CONFIG_LOG"
SH
chmod +x "$T/bin/cmake"
CONFIG_LOG="$T/args" PATH="$T/bin:$PATH" sh "$ROOT/build/configure-linux.sh" "$T/src" "$T/build dir" "$T/prefix"
grep -Fx -- '-DCMAKE_C_COMPILER=gcc-12' "$T/args"
grep -Fx -- '-DCMAKE_CXX_COMPILER=g++-12' "$T/args"
grep -Fx -- '-DLLVM_ENABLE_PROJECTS=clang;lld' "$T/args"
grep -Fx -- '-DLLVM_ENABLE_RUNTIMES=' "$T/args"
grep -Fx -- '-DLLVM_PARALLEL_LINK_JOBS=1' "$T/args"
grep -Fx -- "$T/build dir" "$T/args"
if grep -E 'CMAKE_OSX|march=native' "$T/args"; then echo 'FAIL: Linux host config contains host-specific target flags'; exit 1; fi
echo 'PASS: Linux host configuration'
