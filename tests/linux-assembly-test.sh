#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; export ROOT
python3 - <<'PY'
import os, pathlib, tempfile, subprocess, json, plistlib, tarfile, hashlib
root=pathlib.Path(os.environ['ROOT'])
with tempfile.TemporaryDirectory(prefix='linux assembly ') as t:
    t=pathlib.Path(t); host=t/'host'; export=t/'export'; out=t/'relocated compiler'
    host.mkdir(); (host/'bin').mkdir()
    def call(script,*args,good=True):
        r=subprocess.run(['sh',str(root/'build'/script),*map(str,args)],text=True,capture_output=True)
        assert (r.returncode==0)==good,(r.returncode,r.stdout,r.stderr)
    call('target-manifest.sh','record',host)
    for name in ['clang','clang++','ld64.lld']:
        p=host/'bin'/name;p.write_text('#!/bin/sh\nexit 0\n');p.chmod(0o755)
    stage=t/'target'; stage.mkdir()
    for name in ['bin/clang.cfg','bin/clang++.cfg','bin/portable-ld','include/c++/v1/vector','include/recaulk/time.h','include/mavericks-compat/pthread/qos.h','lib/librecaulk.a','lib/x86_64-apple-darwin/libc++.a','lib/clang/22/include/stddef.h','lib/clang/22/lib/darwin/libclang_rt.osx.a','lib/clang/22/lib/darwin/libclang_rt.profile_osx.a']:
        p=stage/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('--target=x86_64-apple-macos10.9\n' if name.endswith('.cfg') else 'target')
    call('target-manifest.sh','record',stage)
    call('export-target.sh',stage,export)
    call('assemble-linux.sh',host,export,out)
    assert (out/'lib/librecaulk.a').read_text()=='target'
    assert '--ld-path=<CFGDIR>/ld64.lld' in (out/'bin/clang.cfg').read_text()
    assert not (out/'SDKs').exists()
    ident=host/'.target-identity';d=json.loads(ident.read_text());d['revision']='wrong';ident.write_text(json.dumps(d))
    call('assemble-linux.sh',host,export,t/'bad',good=False)
    real_sdk=t/'real-sdk';real_sdk.mkdir()
    sdk=t/'sdk';sdk.symlink_to(real_sdk,target_is_directory=True)
    run=lambda good: subprocess.run([str(out/'bin/setup-sdk'),str(sdk)],capture_output=True).returncode==0
    assert not run(False)
    (sdk/'SDKSettings.plist').write_bytes(plistlib.dumps({'Version':'11.3'}))
    (sdk/'usr/lib').mkdir(parents=True);(sdk/'usr/lib/libSystem.dylib').write_text('stub')
    assert not run(False)
    (sdk/'SDKSettings.plist').write_bytes(plistlib.dumps({'Version':'10.9'}))
    assert not run(False), 'unverified SDK directory accepted'
    header=sdk/'usr/include/test.h';header.parent.mkdir();header.write_text('pinned header')
    archive=t/'MacOSX10.9.sdk.tar.xz'
    with tarfile.open(archive,'w:xz') as a:a.add(real_sdk,arcname='MacOSX10.9.sdk')
    identity_file=out/'share/clang22/identity.json'
    identity=json.loads(identity_file.read_text())
    identity['sdk']='https://example.invalid/sdk '+hashlib.sha256(archive.read_bytes()).hexdigest()+' MacOSX10.9.sdk.tar.xz MacOSX10.9.sdk'
    identity_file.write_text(json.dumps(identity))
    assert run(True)
    assert (out/'SDKs/MacOSX10.9.sdk').resolve()==sdk.resolve()
    header.write_text('corrupted header')
    assert not run(False), 'reused SDK header corruption accepted'

print('PASS: assembly identity, target contents, linker and SDK setup')
PY
