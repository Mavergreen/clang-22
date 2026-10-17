#!/bin/sh
# platform: macOS-only -- otool reads the staged Mach-O load commands
# Flag any Mach-O load command (dependency / install-name / rpath) that names an absolute path the
# INSTALLED toolchain will not have.
#
# The obvious offender is the build scratch dir ($WORK): a dylib whose install_name still points into
# ~/.cache builds fine and dies on the first machine that is not this one. But the subtler and more
# likely one is a BUILD-HOST PACKAGE MANAGER: CMake happily finds /opt/pkg (pkgsrc) or /opt/homebrew
# (a GHA runner) while probing for zstd/zlib/libedit and bakes that path into clang's load commands.
# The result ships, installs, and fails at first launch on a user's machine with a missing dylib --
# which a $WORK-only grep would never have caught. So the rule is a WHITELIST, not a blacklist:
#
#   allowed: @rpath/@loader_path/@executable_path (relative by construction)
#            /usr/lib/**, /System/**             (present on every macOS)
#            $NATIVE_PREFIX/**, $CROSS_PREFIX/**, $LIBCXX_PREFIX/**
#                                                (our own install locations -- the pkgs put us there)
#   flagged: every other absolute path
#
# ALL THREE prefixes are allowed whichever product is audited. The alternative -- passing
# in the one prefix that applies -- buys nothing (a native binary cannot legitimately reference the
# cross prefix anyway, and the prefixes are distinct paths) and costs a class of silent failure: a
# caller that forgets to set it leaves the pattern empty, "" /* matches every absolute path, and the
# gate passes everything while appearing to run.
#
#   usage: verify-relocatable.sh <prefix>
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/versions.sh"
P="${1:?usage: verify-relocatable.sh <prefix>}"
OTOOL="${OTOOL:-otool}"
n=0; bad=0
tmp="$(mktemp "${TMPDIR:-/tmp}/verify-relocatable.XXXXXX")"   # template: 10.9 BSD mktemp requires one
# `|| true`: find exits non-zero when one of these dirs is absent, which under set -e would abort the
# audit before it printed a thing -- a silent pass is the one outcome a gate must never have.
find "$P/bin" "$P/lib" "$P/libexec" -type f 2>/dev/null > "$tmp" || true
[ -s "$tmp" ] || { echo "FATAL: no files under $P/{bin,lib,libexec} -- nothing audited" >&2; exit 1; }
# Each otool read is checked: an otool that cannot run would otherwise yield no paths for every image,
# and the gate would pass everything while appearing to audit. (deps/id/lc: distinct on a
# case-insensitive volume, where .L and .l are one file.)
rd() { "$OTOOL" "$1" "$f" > "$tmp.$2" 2>&1 || { echo "FATAL: $OTOOL $1 failed on ${f#"$P"/}:" >&2; cat "$tmp.$2" >&2; rm -f "$tmp" "$tmp.deps" "$tmp.id" "$tmp.lc"; exit 1; }; }
# Read from a FILE, not a pipeline: a `while … | read` runs in a subshell and would lose n/bad.
while IFS= read -r f; do
  # Audit LINKED IMAGES only. A static archive must be excluded explicitly, not by accident: `file`
  # calls a fat one "Mach-O universal binary ... [x86_64:current ar archive]", so a bare Mach-O match
  # lets it through, and `otool -L` on an archive prints a header line per MEMBER --
  # "/path/libclang_rt.osx.a(divtc3.c.o):" -- which reads exactly like an absolute dependency and
  # fails the gate forever. Archives carry no load commands that ship anyway; their members' symbols
  # are resolved at the final link, which is what tests/smoke-target.sh actually checks.
  desc="$(file "$f" 2>/dev/null)"
  case "$desc" in
    *"ar archive"*) continue ;;
    *Mach-O*executable*|*Mach-O*"shared library"*|*Mach-O*bundle*) : ;;
    *) continue ;;
  esac
  n=$((n+1))
  rd -L deps; rd -D id; rd -l lc
  paths="$(tail -n +2 "$tmp.deps" | awk '{print $1}'; tail -n +2 "$tmp.id"; awk '/LC_RPATH/{r=1} r&&/ path /{print $2; r=0}' "$tmp.lc")"
  hits=""
  for p in $paths; do
    case "$p" in
      @*|"") continue ;;                       # @rpath &c -- relative by construction
      /usr/lib/*|/System/*) continue ;;        # on every macOS
      "$NATIVE_PREFIX"/*|"$CROSS_PREFIX"/*|"$LIBCXX_PREFIX"/*) continue ;;   # where the pkgs actually install us
      /*) hits="$hits$p
" ;;
    esac
  done
  if [ -n "$hits" ]; then
    bad=$((bad+1))
    echo "FAIL ${f#"$P"/}"
    printf '%s' "$hits" | sed "s#$WORK#<WORK>#g;s/^/    /"
  fi
done < "$tmp"
rm -f "$tmp" "$tmp.deps" "$tmp.id" "$tmp.lc"
echo "checked $n Mach-O under $P: $bad with unshippable absolute paths"
[ "$bad" -eq 0 ]
