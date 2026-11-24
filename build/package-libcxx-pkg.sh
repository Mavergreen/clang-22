#!/bin/sh
# platform: macOS-only -- pkgbuild and productbuild (via build_component_pkg.sh and set_install_floor.sh) build the installer archive
# Package the staged libc++ runtime (libcxx<line>): a flat component pkg wrapped in a product archive
# that enforces the 10.9.5 install floor. The runtime loads on any 10.9 box on its own (its only
# dependencies are libSystem and the system's libc++abi), so there are no hooks and no --requires.
# Emits build-info-libcxx.txt.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/versions.sh"
: "${SHIPYARD_SCRIPTS:?need shipyard}"
export COPYFILE_DISABLE=1
STAGE="$LIBCXX_STAGE"
[ -f "$STAGE/lib/libc++.1.dylib" ] && [ -f "$STAGE/lib/libc++abi.1.dylib" ] \
  || { echo "FATAL: run build-libcxx.sh first" >&2; exit 1; }
VER="$(sh "$SHIPYARD_SCRIPTS/resolve-version.sh" "$(sh "$SHIPYARD_SCRIPTS/release-mode.sh")")"
DIST="${DIST:-$HERE/../dist}"; mkdir -p "$DIST"
# The payload root is the stage minus the install prefix, so the guard above and the payload always
# name the same tree, wherever LIBCXX_STAGE points.
PAYLOAD="${STAGE%"$LIBCXX_PREFIX"}"
[ "$PAYLOAD$LIBCXX_PREFIX" = "$STAGE" ] || { echo "FATAL: LIBCXX_STAGE '$STAGE' does not end in $LIBCXX_PREFIX" >&2; exit 1; }
NAME="libcxx${CLANG_LINE}-$VER.pkg"
# Assemble on LOCAL disk and move the finished artifact into dist/ (see package-native-pkg.sh).
OUTDIR="$WORK/out"; mkdir -p "$OUTDIR"

# Archive first: the standalone archive is the pkg's tree unchanged (no SDK, nothing bundled, no
# pkg-only path), and the pkg's root is derived from it. libc++abi.1.dylib keeps its absolute install
# name there too, a declared standalone deviation (INGREDIENTS.md).
rm -rf "$PAYLOAD/Library" "$PAYLOAD/Applications" "$STAGE/mavergreen.plist"
sh "$SHIPYARD_SCRIPTS/stage_standalone.sh" "$PAYLOAD" "libcxx${CLANG_LINE}" "$VER" x86_64 "$DIST/libcxx${CLANG_LINE}-$VER-macos-x86_64.tar.gz"
PKGROOT="$WORK/pkgroot-libcxx"; rm -rf "$PKGROOT"
sh "$SHIPYARD_SCRIPTS/stage_pkg_from_archive.sh" --repo "$HERE/.." \
  "$DIST/libcxx${CLANG_LINE}-$VER-macos-x86_64.tar.gz" "$HERE/../packaging/libcxx${CLANG_LINE}.standalone-bundled" "$PKGROOT"

UPD_APP="${UPD_APP:-}"
UPD_DIR="/Library/Application Support/Mavergreen"
UPD_LABEL="$(sh "$SHIPYARD_SCRIPTS/product-name.sh" agent-label "libcxx${CLANG_LINE}")"
scr="$OUTDIR/pkg-scripts-libcxx"; rm -rf "$scr"
set -- --stage "$PKGROOT" --product "libcxx${CLANG_LINE}" --name "libc++ ${CLANG_LINE} for Mavericks" \
  --group libcxx --line "$CLANG_LINE" --version "$VER" --scripts-out "$scr"
if [ -n "$UPD_APP" ] && [ -d "$UPD_APP" ]; then
  set -- "$@" --updater-app "$UPD_APP"
else
  echo ">> WARNING: no updater at '$UPD_APP'; packaging the runtime alone (build it: shipyard-cmake --build \"\$MAVERICKS_BUILD_ROOT/clang-updater-libcxx\" --target libcxx${CLANG_LINE}-updater)" >&2
  rm -rf "$PKGROOT$UPD_DIR" "$PKGROOT/Library/LaunchAgents/$UPD_LABEL.plist"
fi
sh "$SHIPYARD_SCRIPTS/stage_product.sh" "$@"

comp="$OUTDIR/libcxx${CLANG_LINE}-component.pkg"
sh "$SHIPYARD_SCRIPTS/build_component_pkg.sh" \
  --root "$PKGROOT" \
  --identifier "$LIBCXX_IDENTIFIER" \
  --version "$VER" \
  --install-location "/" \
  --scripts "$scr" \
  --out "$comp" >/dev/null

sh "$SHIPYARD_SCRIPTS/set_install_floor.sh" \
  --identifier "$LIBCXX_IDENTIFIER" \
  --title "libc++ ${CLANG_LINE} for Mavericks — the LLVM ${LLVM_VERSION} C++ runtime for OS X 10.9" \
  --component "$comp" --out "$OUTDIR/$NAME" --host-arch x86_64 --require-scripts
rm -f "$comp" "$OUTDIR/libcxx${CLANG_LINE}-component-components.plist"
mv "$OUTDIR/$NAME" "$DIST/$NAME"
echo "built $DIST/$NAME"

# llvm/recaulk/target must agree with the toolchains' records (conformance compares shared keys).
sh "$SHIPYARD_SCRIPTS/build-info.sh" "$DIST/build-info-libcxx.txt" \
  variant=libcxx arch=x86_64 prefix="$LIBCXX_PREFIX" pkg="$NAME" identifier="$LIBCXX_IDENTIFIER" \
  llvm="$LLVM_VERSION" recaulk="$RECAULK_VERSION" target="$TARGET_TRIPLE"
cat "$DIST/build-info-libcxx.txt"
