# platform: host-agnostic
#   usage: . target-test-lib.sh; target_workspace CASE; ...; target_finish CASE
# spec: TEST_PHASE=build TEST_OUT=DIR preserves a bundle without executing Mach-O
TEST_PHASE=${TEST_PHASE:-all}
case "$TEST_PHASE" in all|build) : ;; *) echo "unsupported TEST_PHASE=$TEST_PHASE" >&2; exit 2 ;; esac
target_workspace() {
  if [ "$TEST_PHASE" = build ]; then
    : "${TEST_OUT:?build phase requires TEST_OUT}"
    mkdir -p "$TEST_OUT"
    TEST_OUT="$(cd "$TEST_OUT" && pwd -P)"
    t="$TEST_OUT/$1"
    mkdir "$t"
  else
    t="$(mktemp -d "${TMPDIR:-/tmp}/$1.XXXXXX")"
    trap 'rm -rf "$t"' EXIT
  fi
}
target_finish() {
  cp "$HERE/target/$1.sh" "$t/run.sh"
  if [ "$TEST_PHASE" = build ]; then
    echo "built target witness: $t"
  else
    [ "$(uname -s)" = Darwin ] || { echo 'target tests require Darwin' >&2; exit 77; }
    sh "$t/run.sh"
  fi
}
