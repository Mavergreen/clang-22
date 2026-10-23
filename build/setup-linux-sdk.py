#!/usr/bin/env python3
# platform: host-agnostic
"""Wire a separately fetched Mavericks SDK into this user-owned toolchain."""
from pathlib import Path, PurePosixPath
import os
import hashlib
import json
import tarfile
import plistlib
import sys


def checksum(stream):
    value=hashlib.sha256()
    for block in iter(lambda:stream.read(1024*1024),b''):
        value.update(block)
    return value.hexdigest()


def verify_sdk(sdk, prefix):
    identity=json.loads((prefix/'share/clang22/identity.json').read_text())
    _, expected, filename, sdk_name=identity['sdk'].split()
    if Path(filename).name!=filename or PurePosixPath(sdk_name).name!=sdk_name:
        raise ValueError('invalid SDK pin in toolchain identity')
    archive=sdk.parent/filename
    with archive.open('rb') as stream:
        if checksum(stream)!=expected:
            raise ValueError('SDK archive differs from the toolchain pin')
        stream.seek(0)
        with tarfile.open(fileobj=stream,mode='r:*') as source:
            expected_paths=set()
            for member in source.getmembers():
                name=PurePosixPath(member.name)
                if name.is_absolute() or '..' in name.parts:
                    raise ValueError('unsafe SDK archive member')
                relative=name.relative_to(sdk_name)
                if str(relative)=='.':continue
                if str(relative) in expected_paths:
                    raise ValueError('duplicate SDK archive member')
                expected_paths.add(str(relative))
                actual=sdk/str(relative)
                if member.issym():
                    if not actual.is_symlink() or os.readlink(actual)!=member.linkname:
                        raise ValueError(f'SDK link changed: {relative}')
                elif member.isdir():
                    if actual.is_symlink() or not actual.is_dir():
                        raise ValueError(f'SDK directory changed: {relative}')
                elif member.isfile():
                    if actual.is_symlink() or not actual.is_file():
                        raise ValueError(f'SDK file missing or replaced: {relative}')
                    with source.extractfile(member) as wanted, actual.open('rb') as found:
                        if checksum(wanted)!=checksum(found):
                            raise ValueError(f'SDK contents changed: {relative}')
                else:
                    raise ValueError(f'unsupported SDK member: {relative}')
            actual_paths={p.relative_to(sdk).as_posix() for p in sdk.rglob('*')}
            if actual_paths!=expected_paths:
                raise ValueError('SDK contains files not present in the pinned archive')


def setup(sdk):
    sdk=sdk.resolve(strict=True)
    with (sdk/'SDKSettings.plist').open('rb') as stream:
        version=plistlib.load(stream).get('Version')
    if str(version)!='10.9' or not (sdk/'usr/lib/libSystem.dylib').is_file():
        raise ValueError('expected the pinned MacOSX10.9.sdk from shipyard fetch_sdk.sh')
    prefix=Path(__file__).resolve().parent.parent
    verify_sdk(sdk,prefix)
    directory=prefix/'SDKs';directory.mkdir(exist_ok=True)
    link=directory/'MacOSX10.9.sdk'
    if link.is_symlink() and link.resolve()==sdk:
        return
    if link.exists() and not link.is_symlink():
        raise ValueError(f'refusing to replace SDK directory {link}')
    temporary=directory/f'.sdk-{os.getpid()}'
    try:
        temporary.symlink_to(sdk)
        temporary.replace(link)
    finally:
        if temporary.is_symlink(): temporary.unlink()
    print(link)


if __name__=='__main__':
    if len(sys.argv)!=2:
        sys.exit('usage: setup-sdk SDK_PATH (from shipyard fetch_sdk.sh)')
    try:
        setup(Path(sys.argv[1]))
    except (OSError,ValueError,KeyError,tarfile.TarError,plistlib.InvalidFileException) as error:
        sys.exit(f'setup-sdk: {error}')
