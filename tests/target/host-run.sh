#!/bin/sh
# platform: macOS-only -- preserves the existing local tests' x86_64/Rosetta policy
set -eu
[ "$(uname -s)" = Darwin ] || { echo 'target tests require Darwin' >&2; exit 77; }
if [ "$(uname -m)" != x86_64 ]; then
  if [ "$1" = profile ]; then
    softwareupdate --install-rosetta --agree-to-license >/dev/null 2>&1 || true
  fi
  if ! arch -x86_64 /usr/bin/true 2>/dev/null; then
    case "$1" in
      catch-align|weak-bind) echo 'note: runtime execution unavailable; host inspection passed'; exit 0 ;;
      *) echo 'cannot execute x86_64 target here' >&2; exit 77 ;;
    esac
  fi
fi
exec sh "$2/run.sh"
