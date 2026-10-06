#!/bin/sh
# platform: host-agnostic
# libcxx22 ships with clang22: release.yml's build-cross job relinks it, tests it, builds its updater and
# packages it (in that order, after the cross build and its smoke), and uploads variant-libcxx; the
# collect job downloads it, signs it into libcxx22.xml, checks that feed upgradeable and carries it in
# the combined artifact. This parses release.yml's text, so it runs anywhere.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$HERE/.."
W="$ROOT/.github/workflows/release.yml"

res="$(awk '
  function mark(k) { if (!(k in at)) at[k] = NR }
  /^  [a-z][a-z-]*:$/ { job = $1; sub(/:$/, "", job); up = 0; next }
  /^      - / { up = 0 }
  job == "build-cross" {
    if ($0 ~ /^ *run: sh build\/build-cross\.sh$/) mark("cross")
    if ($0 ~ /^ *run: sh tests\/smoke-target\.sh$/) mark("smoke")
    if ($0 ~ /^ *(run: )?sh build\/build-libcxx\.sh$/) mark("relink")
    if ($0 ~ /^ *(run: )?sh tests\/libcxx-shape-test\.sh$/) mark("shape")
    if ($0 ~ /^ *(run: )?sh tests\/libcxx-runtime-test\.sh$/) mark("runtime")
    if ($0 ~ /shipyard-cmake .*-DCLANG_VARIANT=libcxx/) mark("configure")
    if ($0 ~ /shipyard-cmake --build .*--target libcxx22-updater/) mark("target")
    if (("target" in at) && $0 ~ /otool -L .*libcxx22-updater/) mark("otool")
    if (("otool" in at) && $0 ~ /sed 1d /) mark("sed1d")
    if (("sed1d" in at) && $0 ~ /grep .*usr\/local\/mavergreen\//) mark("grep")
    if ($0 ~ /UPD_APP="\$MAVERICKS_BUILD_ROOT\/clang-updater-libcxx\/libcxx22-updater\.app" sh build\/package-libcxx-pkg\.sh/) mark("package")
    if ($0 ~ /^ *uses: actions\/upload-artifact@/) uploading = NR
    if ($0 ~ /^ *name: variant-libcxx$/ && uploading && NR - uploading < 3) { up = 1; mark("upload") }
    if (up && $0 ~ /^ *dist\/libcxx\*\.pkg$/) mark("uppkg")
    if (up && $0 ~ /^ *dist\/build-info-libcxx\.txt$/) mark("upinfo")
  }
  job == "collect" {
    if ($0 ~ /name: variant-libcxx/ && $0 ~ /download|path: dist/) mark("download")
    if ($0 ~ /--product libcxx22( |$)/) mark("sign")
    if ($0 ~ /for a in .*libcxx22\.xml/) mark("loop")
    if ($0 ~ /^ *dist\/libcxx22\*\.xml$/) mark("combined")
  }
  END {
    n = split("cross smoke relink shape runtime configure target otool sed1d grep package upload uppkg upinfo", seq, " ")
    for (i = 1; i <= n; i++) if (!(seq[i] in at)) { print "missing build-cross piece: " seq[i]; exit }
    m = split("cross smoke relink shape runtime configure target otool sed1d grep package upload", ord, " ")
    for (i = 2; i <= m; i++) if (at[ord[i]] <= at[ord[i-1]]) { print "out of order: " ord[i] " must follow " ord[i-1]; exit }
    k = split("download sign loop combined", cs, " ")
    for (i = 1; i <= k; i++) if (!(cs[i] in at)) { print "missing collect piece: " cs[i]; exit }
    print "ok"
  }' "$W")"
[ "$res" = ok ] || { echo "FAIL: release.yml libcxx22 wiring: $res"; exit 1; }

# The libcxx22 sign call, the whole continued command: its floor, title, pkg and feed dir.
call="$(awk '
  /sign_and_appcast\.sh" \\$/ { on = 1; c = "" }
  on { c = c $0 "\n"; if ($0 !~ /\\$/) { if (c ~ /--product libcxx22( |\n)/) printf "%s", c; on = 0 } }' "$W")"
[ -n "$call" ] || { echo "FAIL: release.yml has no sign_and_appcast.sh call for --product libcxx22"; exit 1; }
for f in '--min-os 10.9.5' '--channel-title "libc++ 22 for Mavericks"' '--pkg "$LPKG"' '--feed-dir dist'; do
  printf '%s' "$call" | grep -qF -- "$f" \
    || { echo "FAIL: release.yml's libcxx22 sign_and_appcast.sh call lacks $f"; exit 1; }
done
grep -qF 'LPKG="$(ls dist/libcxx*.pkg | head -1)"' "$W" \
  || { echo "FAIL: release.yml does not take the libcxx pkg from ls dist/libcxx*.pkg"; exit 1; }
echo "OK release-libcxx-test"
