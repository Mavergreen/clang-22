# platform: host-agnostic
#   usage: . build/clang-manifest-args.sh -- with VER and CLANG_LINE set, sets "$@" to the native
#          toolchain's mavergreen.plist arguments for shipyard's stage_product.sh/render-manifest.sh.
#          package-native-pkg.sh and render-linux-manifest.sh both take them from here, so the native
#          pkg's mavergreen.plist and the Linux archive's are the same bytes (collect cmp's them).
set -- --product "clang${CLANG_LINE}" --name "Clang ${CLANG_LINE} for Mavericks" \
  --group clang --line "$CLANG_LINE" --version "$VER" \
  --exclude "bin/clang-${CLANG_LINE}" --exclude bin/clang.cfg --exclude bin/clang++.cfg --exclude bin/portable-ld --exclude bin/strip --exclude bin/lipo \
  --requires sdk109
