#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; export ROOT
python3 - <<'PY'
import os,pathlib,re
text=(pathlib.Path(os.environ['ROOT'])/'.github/workflows/release.yml').read_text()
jobs={};current=None
for line in text.splitlines():
 m=re.fullmatch(r'  ([a-zA-Z0-9_-]+):',line)
 if m:current=m[1];jobs[current]=[]
 elif current:jobs[current].append(line)
def closure(name):
 block='\n'.join(jobs[name]);m=re.search(r'^    needs: \[([^]]+)\]',block,re.M)
 direct=[] if not m else [n.strip() for n in m[1].split(',')]
 return set(direct).union(*(closure(n) for n in direct))
assert {'build-linux','on-linux-mavericks','verify-linux'} <= closure('publish'),'publish can bypass Linux correctness gates'
assert 'build-linux' in closure('collect'),'collection can omit the Linux product'
collect='\n'.join(jobs['collect'])
assert 'dist/clang22-*-linux-x86_64.tar.gz' in collect,'Linux archive excluded from release handoff'
assert 'dist/clang22-*-linux-x86_64.manifest.json' in collect,'Linux manifest excluded from release handoff'
print('PASS: publication and collection depend on Linux target verification and assets')
PY
