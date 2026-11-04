#!/bin/sh
# platform: host-agnostic
#   usage: package-llvm-dev.sh STAGE_PREFIX ARCH OUTDIR
#          Packs the LLVM/clang/lld static libraries, headers, cmake modules and llvm-config out of
#          an installed clang-22 stage (the directory a build's `DESTDIR=... ninja install` leaves
#          at the product prefix) as OUTDIR/llvm22-dev-<FULL_VERSION>-darwin-<ARCH>.tar.gz, for
#          products that link LLVM statically. ARCH is x86_64 (build-native.sh's stage) or arm64
#          (build-cross.sh's stage, which also carries the x86_64/10.9 libc++.a and its headers).
#          The archive is byte-reproducible: sorted entries, uid/gid 0, every mtime
#          $SOURCE_DATE_EPOCH (shipyard's source-date-epoch.sh). It is written by python3's
#          tarfile because bsdtar and GNU tar spell owner and mtime overrides differently.
set -eu
[ $# -eq 3 ] || { echo 'usage: package-llvm-dev.sh STAGE_PREFIX ARCH OUTDIR' >&2; exit 2; }
STAGE="$1"; ARCH="$2"; OUT="$3"
case "$ARCH" in
  x86_64) TARGETS="X86" ;;
  arm64) TARGETS="X86;AArch64" ;;
  *) echo "package-llvm-dev: unknown ARCH '$ARCH' (x86_64 or arm64)" >&2; exit 2 ;;
esac
[ -d "$STAGE/lib" ] || { echo "package-llvm-dev: no lib/ under $STAGE -- run the build first" >&2; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
EPOCH="$(sh "$SHIPYARD_SCRIPTS/source-date-epoch.sh")"
NAME="llvm22-dev-$PKG_VERSION-darwin-$ARCH"

W="$(mktemp -d "${TMPDIR:-/tmp}/llvm-dev.XXXXXX")"; trap 'rm -rf "$W"' EXIT
D="$W/llvm22-dev"; mkdir -p "$D/lib" "$D/include" "$D/bin"
for f in "$STAGE"/lib/libLLVM*.a "$STAGE"/lib/libclang*.a "$STAGE"/lib/liblld*.a; do
  case "$f" in */libclang_rt*) continue ;; esac
  [ -f "$f" ] && cp -P "$f" "$D/lib/"
done
mkdir -p "$D/lib/cmake"
for m in llvm clang lld; do
  [ -d "$STAGE/lib/cmake/$m" ] && cp -RP "$STAGE/lib/cmake/$m" "$D/lib/cmake/"
done
for h in llvm llvm-c clang clang-c lld; do
  [ -d "$STAGE/include/$h" ] && cp -RP "$STAGE/include/$h" "$D/include/"
done
[ -f "$STAGE/bin/llvm-config" ] || { echo "package-llvm-dev: no bin/llvm-config in $STAGE" >&2; exit 1; }
cp -P "$STAGE/bin/llvm-config" "$D/bin/"

if [ "$ARCH" = arm64 ]; then
  RT="$(find "$STAGE/lib" -name 'libc++.a' -print | LC_ALL=C sort | head -1)"
  [ -n "$RT" ] || { echo "package-llvm-dev: no libc++.a under $STAGE/lib -- did the runtimes build run?" >&2; exit 1; }
  [ -d "$STAGE/include/c++/v1" ] || { echo "package-llvm-dev: no libc++ headers at $STAGE/include/c++/v1" >&2; exit 1; }
  mkdir -p "$D/lib/x86_64-apple-darwin" "$D/include/c++"
  cp -P "$RT" "$D/lib/x86_64-apple-darwin/libc++.a"
  cp -RP "$STAGE/include/c++/v1" "$D/include/c++/"
fi

printf 'llvm=%s clang22=%s targets=%s arch=%s\n' "$LLVM_VERSION" "$PKG_VERSION" "$TARGETS" "$ARCH" > "$D/BUILD-INFO"

mkdir -p "$OUT"
python3 -I - "$W" "$OUT/$NAME.tar.gz" "$EPOCH" <<'PY'
import gzip, os, sys, tarfile
work, dest, epoch = sys.argv[1], sys.argv[2], int(sys.argv[3])
names = []
for top, dirs, files in os.walk(os.path.join(work, 'llvm22-dev')):
    names.extend(os.path.join(top, n) for n in dirs + files)
names.append(os.path.join(work, 'llvm22-dev'))
tmp = dest + '.part'
with open(tmp, 'wb') as raw, gzip.GzipFile(filename='', fileobj=raw, mode='wb', mtime=epoch) as z, tarfile.open(fileobj=z, mode='w', format=tarfile.PAX_FORMAT) as tar:
    for path in sorted(names, key=lambda p: os.path.relpath(p, work).split(os.sep)):
        info = tar.gettarinfo(path, arcname=os.path.relpath(path, work))
        info.uid = info.gid = 0
        info.uname = info.gname = ''
        info.mtime = epoch
        info.pax_headers = {}
        if not info.issym():
            info.mode = 0o755 if info.isdir() or info.mode & 0o111 else 0o644
        if info.isreg():
            with open(path, 'rb') as f:
                tar.addfile(info, f)
        else:
            tar.addfile(info)
os.replace(tmp, dest)
PY
echo "$OUT/$NAME.tar.gz"
