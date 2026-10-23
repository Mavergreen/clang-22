#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; export ROOT
python3 - <<'PY'
import os,pathlib,tempfile,subprocess,tarfile,json
root=pathlib.Path(os.environ['ROOT'])
with tempfile.TemporaryDirectory() as tmp:
 t=pathlib.Path(tmp);p=t/'prefix';(p/'bin').mkdir(parents=True)
 (p/'bin/clang').write_text('compiler');(p/'bin/clang').chmod(0o755)
 (p/'bin/clang++').symlink_to('clang')
 (p/'SDKs').mkdir();(p/'SDKs/MacOSX10.9.sdk').symlink_to('/unshipped/apple/sdk')
 r=subprocess.run(['sh',str(root/'build/target-manifest.sh'),'record',str(p)],capture_output=True,text=True)
 assert r.returncode==0,r.stderr
 (p/'share/clang22').mkdir(parents=True);(p/'.target-identity').rename(p/'share/clang22/identity.json')
 version=json.loads((p/'share/clang22/identity.json').read_text())['version']
 r=subprocess.run(['sh',str(root/'build/package-linux.sh'),str(p),str(t/'dist')],capture_output=True,text=True)
 assert r.returncode==0,(r.stdout,r.stderr)
 archive=t/'dist'/f'clang22-{version}-linux-x86_64.tar.gz'
 with tarfile.open(archive) as a:
  names=a.getnames()
  assert 'opt/mavergreen/clang22/bin/clang' in names
  assert not any('/SDKs' in n for n in names)
  assert a.getmember('opt/mavergreen/clang22/bin/clang++').issym()
 assert list((t/'dist').glob('*.manifest.json'))
print('PASS: Linux release layout, SDK exclusion and manifest')
PY
