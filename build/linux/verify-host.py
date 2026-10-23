#!/usr/bin/env python3
# platform: host-agnostic
"""Fail closed on ELF requirements beyond the declared Linux host baseline."""
from pathlib import Path
import re
import subprocess
import sys


def inspect(prefix):
    count = 0
    allowed = {'libc.so.6', 'libm.so.6', 'libpthread.so.0', 'libdl.so.2',
               'librt.so.1', 'ld-linux-x86-64.so.2'}
    for path in sorted(prefix.rglob('*')):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open('rb') as stream:
            if stream.read(4) != b'\x7fELF':
                continue
        count += 1
        text = subprocess.check_output(['readelf', '-W', '-h', '-d', '-V', str(path)],
                                       text=True, env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'})
        if not re.search(r'Class:\s+ELF64', text) or not re.search(r'Machine:\s+Advanced Micro Devices X86-64', text):
            raise ValueError(f'{path}: not x86_64 ELF64')
        for version in re.findall(r'\bGLIBC_(\d+(?:\.\d+)+)', text):
            if tuple(map(int, version.split('.'))) > (2, 35):
                raise ValueError(f'{path}: requires GLIBC_{version}, floor is 2.35')
        if 'GLIBC_PRIVATE' in text or re.search(r'\b(?:GLIBCXX|CXXABI)_', text):
            raise ValueError(f'{path}: private libc or external C++ runtime dependency')
        for library in re.findall(r'\(NEEDED\).*?\[([^]]+)\]', text):
            if library not in allowed:
                raise ValueError(f'{path}: unsupported host dependency {library}')
        for paths in re.findall(r'\((?:RPATH|RUNPATH)\).*?\[([^]]*)\]', text):
            if any(p not in ('$ORIGIN', '$ORIGIN/../lib') for p in paths.split(':')):
                raise ValueError(f'{path}: non-relocatable runtime path {paths}')
    if not count:
        raise ValueError('no ELF files measured')
    print(f'PASS: {count} x86_64 ELF files, glibc <=2.35, system dependencies only')


if __name__ == '__main__':
    try:
        inspect(Path(sys.argv[1]))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f'verify-linux-host: {error}')
