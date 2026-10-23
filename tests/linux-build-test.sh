#!/bin/sh
# platform: host-agnostic
set -eu
[ "$(uname -s)" = Linux ] || { echo 'SKIP: ELF audit fixture requires Linux'; exit 77; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/prefix/bin"
printf 'int main(void) { return 0; }\n' > "$T/main.c"
cc "$T/main.c" -o "$T/prefix/bin/tool"
sh "$ROOT/build/verify-linux-host.sh" "$T/prefix"
cc "$T/main.c" -Wl,-rpath,/tmp/build-only -o "$T/prefix/bin/tool"
if sh "$ROOT/build/verify-linux-host.sh" "$T/prefix"; then echo 'FAIL: accepted absolute build RPATH'; exit 1; fi
cc "$T/main.c" -o "$T/prefix/bin/tool"
python3 - "$T/prefix/bin/tool" <<'PY'
import pathlib, sys
p=pathlib.Path(sys.argv[1]); data=bytearray(p.read_bytes()); data[18:20]=(183).to_bytes(2,'little'); p.write_bytes(data)
PY
if sh "$ROOT/build/verify-linux-host.sh" "$T/prefix"; then echo 'FAIL: accepted arm64 ELF'; exit 1; fi
printf 'extern unsigned arc4random(void); int main(void) { return arc4random() == 0; }\n' > "$T/new.c"
if cc "$T/new.c" -o "$T/prefix/bin/tool" 2>/dev/null; then
  if sh "$ROOT/build/verify-linux-host.sh" "$T/prefix"; then echo 'FAIL: accepted GLIBC_2.36'; exit 1; fi
else
  echo 'SKIP case: baseline libc cannot create GLIBC_2.36 fixture'
fi
printf 'int special(void) { return 1; }\n' > "$T/lib.c"
cc -shared -fPIC "$T/lib.c" -o "$T/libspecial.so"
printf 'extern int special(void); int main(void) { return special(); }\n' > "$T/main.c"
cc "$T/main.c" -L"$T" -lspecial -o "$T/prefix/bin/tool"
if sh "$ROOT/build/verify-linux-host.sh" "$T/prefix"; then echo 'FAIL: accepted host-only dependency'; exit 1; fi
echo 'PASS: Linux ELF baseline and dependency audit'
