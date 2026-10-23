#!/bin/sh
# platform: macOS-only -- executes the saved cross-image C++ ABI matrix
set -eu
t="$(cd "$(dirname "$0")" && pwd)"
shapes="$(cat "$t/shapes")"
fail=0
PASSING="one-abi control-new-new control-sys-sys sys-runtime-as-runtime_error sys-runtime-as-exception sys-custom
  sys-any new-runtime-caught-by-sys new-custom-caught-by-sys new-through-sys-frame uncaught-count-across objc-catch-cxx
  objc-raise-through-cxx cxx-catch-objc-any cxx-catch-objc-typed objc-raise-through-sys exception_ptr-across
  make_exception_ptr promise-set-exception uncaught_exceptions bad_array_new_length char8_t const-char8_t-pointer"
TERMINATING="terminate-ours-through-sys terminate-sys terminate-noexcept"
for s in $shapes; do
  run_case() {
    if [ "$s" = dylib ]; then env DYLD_FALLBACK_LIBRARY_PATH="$t/libcxx" "$@"
    else "$@"; fi
  }
  for c in $PASSING; do
    out="$(run_case "$t/interop-$s" "$c" 2>&1)" && rc=0 || rc=$?
    if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q "^PASS $c:" && ! printf '%s\n' "$out" | grep -q 'pointer being freed'; then echo "ok $s $c"
    else echo "FAIL $s $c (exit $rc): $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"; fail=1; fi
  done
  # Meant to call std::terminate, which reports the exception once and aborts: the system's libc++abi's
  # message, the one runtime's ("libc++abi.dylib: terminating ..." on 10.9, "libc++abi: terminating due
  # to ..." on current macOS). A crash elsewhere, or a second message, is a failure.
  for c in $TERMINATING; do
    out="$(run_case "$t/interop-$s" "$c" 2>&1)" && rc=0 || rc=$?
    if [ "$rc" = 134 ] && [ "$(printf '%s\n' "$out" | grep -c 'terminating')" = 1 ] \
       && printf '%s\n' "$out" | grep -Eq '^libc\+\+abi(\.dylib)?: terminating' && ! printf '%s\n' "$out" | grep -q 'pointer being freed'; then
      echo "ok $s $c (terminated)"
    else echo "FAIL $s $c (exit $rc, want std::terminate's abort): $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"; fail=1; fi
  done
done
[ "$fail" = 0 ] && echo "PASS: one C++ ABI ($shapes)"
exit "$fail"
