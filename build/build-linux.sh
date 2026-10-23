#!/bin/sh
# platform: host-agnostic
#   usage: build-linux.sh -- run inside the locked baseline container
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/versions.sh"
[ "$(uname -s)/$(uname -m)" = Linux/x86_64 ] || { echo 'build-linux: requires Linux x86_64' >&2; exit 1; }
. "$SHIPYARD_SCRIPTS/mavericks_fetch.sh"
mkdir -p "$WORK"
tb="$WORK/llvm-project-$LLVM_VERSION.src.tar.xz"
[ -f "$tb" ] || shipyard_curl "$LLVM_SRC_URL" "$tb"
[ -f "$tb.sig" ] || shipyard_curl "$LLVM_SIG_URL" "$tb.sig"
GNUPGHOME="$WORK/gpg"; export GNUPGHOME
mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
gpg --batch --quiet --import "$HERE/../keys/llvm-release.asc"
gpg --batch --quiet --verify "$tb.sig" "$tb"
SRC="$WORK/llvm-project-$LLVM_VERSION.src"
rm -rf "$SRC"; tar -xf "$tb" -C "$WORK"
mav_apply_patches "$SRC" "$REPO_ROOT/patches"
BLD="$WORK/linux-build"; PREFIX="$WORK/linux-host"
sh "$HERE/configure-linux.sh" "$SRC" "$BLD" "$PREFIX"
if [ -n "${MAVERICKS_JOBS:-}" ]; then jobs=$MAVERICKS_JOBS
else
  cores="$(getconf _NPROCESSORS_ONLN)"
  memory="$(awk '/MemAvailable:/ { print $2 }' /proc/meminfo)"
  jobs="$(sh "$HERE/linux-jobs.sh" "$cores" "$memory")"
fi
case "$jobs" in ''|*[!0-9]*|0) echo "build-linux: invalid job count '$jobs'" >&2; exit 2 ;; esac
TOOLS='clang lld llvm-ar llvm-ranlib llvm-lipo llvm-otool llvm-nm llvm-strings llvm-strip llvm-install-name-tool llvm-objdump llvm-readobj llvm-profdata llvm-cov'
# platform: upstream install targets bring executable aliases and clang resource headers too
set --
for tool in $TOOLS; do set -- "$@" "install-$tool"; done
cmake --build "$BLD" --parallel "$jobs" --target "$@"
for tool in clang clang++ ld64.lld llvm-ar llvm-ranlib llvm-lipo llvm-otool llvm-nm llvm-strings llvm-strip llvm-install-name-tool llvm-objdump llvm-readobj llvm-profdata llvm-cov; do
  [ -x "$PREFIX/bin/$tool" ] || { echo "build-linux: missing installed $tool" >&2; exit 1; }
done
sh "$HERE/verify-linux-host.sh" "$PREFIX"
sh "$HERE/probe-linux-tools.sh" "$PREFIX"
sh "$HERE/target-manifest.sh" record "$PREFIX"
echo "OK: staged Linux tools at $PREFIX"
