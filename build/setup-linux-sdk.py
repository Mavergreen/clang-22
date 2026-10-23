#!/usr/bin/env python3
# platform: host-agnostic
"""Wire a separately fetched Mavericks SDK into this user-owned toolchain."""
from pathlib import Path
import os
import plistlib
import sys


def setup(sdk):
    sdk=sdk.resolve(strict=True)
    with (sdk/'SDKSettings.plist').open('rb') as stream:
        version=plistlib.load(stream).get('Version')
    if str(version)!='10.9' or not (sdk/'usr/lib/libSystem.dylib').is_file():
        raise ValueError('expected the pinned MacOSX10.9.sdk from shipyard fetch_sdk.sh')
    prefix=Path(__file__).resolve().parent.parent
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
    except (OSError,ValueError,plistlib.InvalidFileException) as error:
        sys.exit(f'setup-sdk: {error}')
