#!/usr/bin/env python3
"""Reject non-arm64, post-macOS-13 and build-machine-linked Mach-O payloads."""
import argparse
import json
from pathlib import Path
import re
import subprocess

MAGIC = {bytes.fromhex(x) for x in ('feedface','feedfacf','cefaedfe','cffaedfe','cafebabe','bebafeca','cafebabf','bfbafeca')}


def output(*args):
    return subprocess.check_output(args, text=True)


def validate(root):
    root = root.resolve()
    records = []
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise ValueError(f'Symlink in payload: {path}')
        if not path.is_file():
            continue
        with path.open('rb') as stream:
            if stream.read(4) not in MAGIC:
                continue
        arches = output('/usr/bin/lipo', '-archs', str(path)).split()
        if arches != ['arm64']:
            raise ValueError(f'Expected only arm64: {path}: {arches}')
        commands = output('/usr/bin/otool', '-l', str(path))
        targets = re.findall(r'\bminos\s+([\d.]+)', commands) + re.findall(r'\bversion\s+([\d.]+)\s*\n\s+sdk', commands)
        if not targets or any(tuple(map(int, v.split('.'))) > (13, 0, 0) for v in targets):
            raise ValueError(f'Unsupported deployment target: {path}: {targets}')
        dependencies = [line.strip().split(' (')[0] for line in output('/usr/bin/otool', '-L', str(path)).splitlines()[1:]]
        dylib = path.suffix == '.dylib'
        for dependency in dependencies:
            if dependency.startswith(('/usr/lib/', '/System/Library/')):
                continue
            if dependency.startswith('@rpath/'):
                resolved = root / 'lib' / dependency.removeprefix('@rpath/')
            elif dependency.startswith('@loader_path/'):
                resolved = path.parent / dependency.removeprefix('@loader_path/')
            elif dependency.startswith('@executable_path/'):
                resolved = root / 'bin' / dependency.removeprefix('@executable_path/')
            else:
                raise ValueError(f'Nonrelocatable dependency: {path}: {dependency}')
            if not resolved.resolve().is_relative_to(root) or not resolved.is_file():
                raise ValueError(f'Missing/escaping dependency: {path}: {dependency}')
        rpaths = re.findall(r'\bpath\s+(\S+)\s+\(offset', commands)
        for rpath in rpaths:
            if not rpath.startswith(('@loader_path/', '@executable_path/')):
                raise ValueError(f'Absolute/unsupported run path: {path}: {rpath}')
        if not dylib and any(d.startswith('@rpath/') for d in dependencies) and '@executable_path/../lib' not in rpaths:
            raise ValueError(f'Executable cannot resolve libraries: {path}')
        records.append(dict(path=str(path.relative_to(root)), architectures=arches, minimumOS=targets, dependencies=dependencies, rpaths=rpaths))
    if not records:
        raise ValueError('No native runtime code found')
    return records


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('payload', type=Path)
    args = parser.parse_args()
    print(json.dumps(validate(args.payload), indent=2))
