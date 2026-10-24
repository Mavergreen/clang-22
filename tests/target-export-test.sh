#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; export ROOT
python3 - <<'PY'
import os, pathlib, subprocess, tempfile
root = pathlib.Path(os.environ['ROOT'])
with tempfile.TemporaryDirectory(prefix='target export ') as tmp:
    stage = pathlib.Path(tmp) / 'stage'
    out = pathlib.Path(tmp) / 'out'
    files = ['bin/clang.cfg', 'bin/clang++.cfg', 'bin/portable-ld',
             'include/c++/v1/vector', 'include/recaulk/time.h',
             'lib/librecaulk.a',
             'lib/x86_64-apple-darwin/libc++.a',
             'lib/clang/22/include/stddef.h',
             'lib/clang/22/lib/darwin/libclang_rt.osx.a',
             'lib/clang/22/lib/darwin/libclang_rt.profile_osx.a',
             'lib/libLLVM.dylib', 'SDKs/MacOSX10.9.sdk/Apple bytes']
    for name in files:
        p = stage / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(name)
    (stage/'bin/portable-ld').chmod(0o755)
    (stage/'include/c++/v1/header alias').symlink_to('vector')
    def call(script, *args, good=True):
        r = subprocess.run(['sh', str(root/'build'/script), *map(str,args)], capture_output=True, text=True)
        assert (r.returncode == 0) == good, (script, r.returncode, r.stdout, r.stderr)
        return r
    call('export-target.sh', stage, out, good=False)
    call('target-manifest.sh', 'record', stage)
    call('export-target.sh', stage, out)
    assert (out/'payload/lib/x86_64-apple-darwin/libc++.a').read_bytes() == (stage/'lib/x86_64-apple-darwin/libc++.a').read_bytes()
    assert not (out/'payload/lib/libLLVM.dylib').exists()
    assert not (out/'payload/SDKs').exists()
    assert (out/'payload/include/c++/v1/header alias').is_symlink()
    assert (out/'payload/bin/portable-ld').stat().st_mode & 0o111
    call('target-manifest.sh', 'verify', out)
    import json
    ident = out/'identity'; original = ident.read_text()
    changed = json.loads(original); changed['llvm'] = '0.0.0'
    ident.write_text(json.dumps(changed))
    call('target-manifest.sh', 'verify', out, good=False)
    ident.write_text(original)
    victim=out/'payload/include/c++/v1/vector'
    victim.write_text('corrupted'); call('target-manifest.sh', 'verify', out, good=False)
    victim.unlink(); call('target-manifest.sh', 'verify', out, good=False)
    bad=stage/'lib/x86_64-apple-darwin/libc++abi.a'; bad.write_text('forbidden')
    call('export-target.sh', stage, pathlib.Path(tmp)/'bad', good=False); bad.unlink()
    (stage/'include/c++/v1/escape').symlink_to('/etc/passwd')
    call('export-target.sh', stage, pathlib.Path(tmp)/'escape', good=False)
print('PASS: target export inventory, integrity, modes and links')
PY
