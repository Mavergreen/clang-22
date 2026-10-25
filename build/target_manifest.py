#!/usr/bin/env python3
# platform: host-agnostic
"""Export target data without copying host libraries or Apple SDK bytes."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def identity():
    root = Path(os.environ['REPO_ROOT'])
    revision = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    return dict(format=1, revision=revision, version=os.environ['PKG_VERSION'],
                llvm=os.environ['LLVM_VERSION'], recaulk=os.environ['RECAULK_VERSION'],
                sdk=os.environ['SDK_PIN'],
                sdk_settings=json.loads(os.environ.get('SDK_SETTINGS_JSON') or 'null'),
                patches={p.name: digest(p) for p in sorted((root/'patches').glob('*.patch'))})


def inventory(root):
    result = []
    for p in sorted(root.rglob('*')):
        name = p.relative_to(root).as_posix()
        mode = p.lstat().st_mode
        if stat.S_ISLNK(mode):
            target = os.readlink(p)
            if Path(target).is_absolute() or not p.resolve().is_relative_to(root.resolve()) or not p.exists():
                raise ValueError(f'unsafe or dangling symlink: {name} -> {target}')
            result.append(dict(path=name, kind='link', target=target))
        elif stat.S_ISREG(mode):
            result.append(dict(path=name, kind='file', mode=stat.S_IMODE(mode), sha256=digest(p)))
        elif not stat.S_ISDIR(mode):
            raise ValueError(f'unsupported file: {name}')
    return result


def write_json(path, value):
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n')


def export(stage, out):
    if json.loads((stage/'.target-identity').read_text()) != identity():
        raise ValueError('stage was built from different source/version/pins')
    if out.exists():
        raise ValueError(f'output already exists: {out}')
    for forbidden in ('libc++abi.a', 'libunwind.a'):
        if list((stage/'lib').rglob(forbidden)):
            raise ValueError(f'private runtime forbidden: {forbidden}')
    runtimes = list((stage/'lib').rglob('libc++.a'))
    if len(runtimes) != 1:
        raise ValueError('expected exactly one target libc++.a')
    major = os.environ['LLVM_VERSION'].split('.')[0]
    selected = ['bin/clang.cfg', 'bin/clang++.cfg', 'bin/portable-ld',
                'include/c++/v1', 'include/recaulk',
                'lib/librecaulk.a', runtimes[0].relative_to(stage).as_posix(),
                f'lib/clang/{major}/include', f'lib/clang/{major}/lib/darwin']
    for required in (f'lib/clang/{major}/lib/darwin/libclang_rt.osx.a',
                     f'lib/clang/{major}/lib/darwin/libclang_rt.profile_osx.a'):
        if not (stage/required).is_file():
            raise ValueError(f'missing target runtime: {required}')
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=out.name+'.tmp.', dir=out.parent) as temporary:
        temp = Path(temporary)
        payload = temp/'payload'
        for name in selected:
            src, dst = stage/name, payload/name
            if not src.exists():
                raise ValueError(f'missing target file: {name}')
            dst.parent.mkdir(parents=True, exist_ok=True)
            if src.is_dir() and not src.is_symlink():
                shutil.copytree(src, dst, symlinks=True)
            else:
                shutil.copy2(src, dst, follow_symlinks=False)
        records = inventory(payload)
        write_json(temp/'identity', identity())
        write_json(temp/'manifest.json', records)
        (temp/'files.sha256').write_text(''.join(f"{r['sha256']}  {r['path']}\n" for r in records if r['kind']=='file'))
        # platform: rename a child so TemporaryDirectory retains its own cleanup path
        packaged = temp/'export'
        packaged.mkdir()
        for name in ('payload', 'identity', 'manifest.json', 'files.sha256'):
            (temp/name).rename(packaged/name)
        packaged.rename(out)


def verify(out):
    if json.loads((out/'identity').read_text()) != identity():
        raise ValueError('target identity differs from this checkout/version/pins')
    actual = inventory(out/'payload')
    if actual != json.loads((out/'manifest.json').read_text()):
        raise ValueError('target payload differs from its manifest')
    expected = ''.join(f"{r['sha256']}  {r['path']}\n" for r in actual if r['kind']=='file')
    if (out/'files.sha256').read_text() != expected:
        raise ValueError('target checksum list differs from manifest')


if __name__ == '__main__':
    try:
        if sys.argv[1] == 'export':
            export(Path(sys.argv[2]).resolve(), Path(sys.argv[3]).absolute())
        elif sys.argv[1] == 'record':
            write_json(Path(sys.argv[2])/'.target-identity', identity())
        elif sys.argv[1] == 'verify':
            verify(Path(sys.argv[2]).absolute())
        else:
            raise ValueError('expected export or verify')
    except (ValueError, OSError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(f'target-manifest: {error}')
