#!/usr/bin/env python3
# platform: host-agnostic
"""Compose only matching compiler and target builds; preserve relative paths."""
import json
from pathlib import Path
import shutil
import sys
import tempfile


def assemble(host, export, destination):
    if json.loads((host/'.target-identity').read_text()) != json.loads((export/'identity').read_text()):
        raise ValueError('Linux host and target build identities differ')
    if destination.exists():
        raise ValueError(f'destination already exists: {destination}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as scratch:
        result=Path(scratch)/'prefix'
        shutil.copytree(host,result,symlinks=True)
        (result/'.target-identity').unlink()
        shutil.copytree(export/'payload',result,symlinks=True,dirs_exist_ok=True)
        with (result/'bin/clang.cfg').open('a') as cfg:
            cfg.write('\n--ld-path=<CFGDIR>/ld64.lld\n')
        source=Path(__file__).resolve().parents[1]
        shutil.copy2(source/'setup-linux-sdk.py',result/'bin/setup-sdk')
        (result/'bin/setup-sdk').chmod(0o755)
        info=result/'share/clang22';info.mkdir(parents=True,exist_ok=True)
        shutil.copy2(export/'identity',info/'identity.json')
        for name in ('LICENSE','NOTICE'):
            shutil.copy2(source.parent/name,info/name)
        result.rename(destination)


if __name__=='__main__':
    try:
        assemble(*(Path(x).absolute() for x in sys.argv[1:]))
    except (OSError,ValueError) as error:
        sys.exit(f'assemble-linux: {error}')
