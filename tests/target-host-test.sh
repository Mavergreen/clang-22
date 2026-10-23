#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d "${TMPDIR:-/tmp}/linux-host.XXXXXX")"; trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin" "$t/case"
cat > "$t/bin/uname" <<'SH'
#!/bin/sh
case "$1" in -s) echo Darwin ;; -m) echo arm64 ;; esac
SH
cat > "$t/bin/arch" <<'SH'
#!/bin/sh
[ -f "$PRIMED" ]
SH
printf '#!/bin/sh\ntouch "$PRIMED"\n' > "$t/bin/softwareupdate"
printf '#!/bin/sh\ntouch "$EXECUTED"\n' > "$t/case/run.sh"
chmod +x "$t/bin/"*
export PATH="$t/bin:$PATH" PRIMED="$t/primed" EXECUTED="$t/executed"
sh "$ROOT/tests/target/host-run.sh" catch-align "$t/case"
[ ! -e "$EXECUTED" ] && [ ! -e "$PRIMED" ]
rc=0; sh "$ROOT/tests/target/host-run.sh" cxxabi "$t/case" || rc=$?
[ "$rc" = 77 ]
sh "$ROOT/tests/target/host-run.sh" profile "$t/case"
[ -f "$EXECUTED" ] && [ -f "$PRIMED" ]
echo 'PASS: existing Mac execution/skip behavior retained'
