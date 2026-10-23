#!/usr/bin/env python3
# platform: host-agnostic
"""Package the portable compiler without its locally configured Apple SDK."""
import gzip
import json
from pathlib import Path
import shutil
import sys
import tarfile
import tempfile
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from target_manifest import inventory


def package(prefix, dist):
    identity = json.loads((prefix/'share/clang22/identity.json').read_text())
    version = identity['version']
    if not version or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_' for c in version):
        raise ValueError('invalid product version')
    name = f'clang22-{version}-linux-x86_64'
    dist.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=dist) as temporary:
        root = Path(temporary)
        tree = root/'opt/mavergreen/clang22'
        shutil.copytree(prefix, tree, symlinks=True, ignore=lambda directory, names: ['SDKs'] if Path(directory)==prefix else [])
        records = inventory(tree)
        manifest = root/(name+'.manifest.json')
        manifest.write_text(json.dumps(dict(identity=identity,files=records), sort_keys=True, indent=2)+'\n')
        archive = root/(name+'.tar.gz')
        with archive.open('wb') as raw, gzip.GzipFile(filename='',fileobj=raw,mode='wb',mtime=0) as zipped, tarfile.open(fileobj=zipped,mode='w') as tar:
            for p in [tree, *sorted(tree.rglob('*'))]:
                info=tar.gettarinfo(str(p),arcname=p.relative_to(root).as_posix())
                info.uid=info.gid=0;info.uname=info.gname='';info.mtime=0
                if info.isfile():
                    with p.open('rb') as content: tar.addfile(info,content)
                else: tar.addfile(info)
        archive.replace(dist/archive.name)
        manifest.replace(dist/manifest.name)
    print(dist/(name+'.tar.gz'))


if __name__=='__main__':
    try:
        package(Path(sys.argv[1]).absolute(),Path(sys.argv[2]).absolute())
    except (OSError,ValueError,KeyError) as error:
        sys.exit(f'package-linux: {error}')
