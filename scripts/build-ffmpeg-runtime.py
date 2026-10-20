#!/usr/bin/env python3
"""Build an independent, pinned arm64/macOS 13 FFmpeg runtime, never Homebrew binaries.

Downloads are explicit. Sources, configuration, licenses and a build record travel
with the payload. This initial LGPL build has no third-party codec libraries;
the complete Media milestone still requires LAME, Opus and VP9 qualification.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile

PINS = {
    '8.1.1': 'b6863adde98898f42602017462871b5f6333e65aec803fdd7a6308639c52edf3',
    '8.1.2': '464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c',
}


def run(*args, **kwargs):
    return subprocess.run(list(map(str, args)), check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', choices=PINS, default='8.1.2')
    parser.add_argument('--pack-version', required=True)
    parser.add_argument('--work', type=Path, default=Path('build/ffmpeg'))
    parser.add_argument('--sources', type=Path, default=Path('build/engine-sources'))
    parser.add_argument('--jobs', type=int, default=min(os.cpu_count() or 2, 8))
    args = parser.parse_args()
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        parser.error('Build on an Apple-silicon Mac with the Xcode command line tools')
    work = args.work.resolve() / args.version
    payload = work / 'payload'
    if payload.exists():
        parser.error('Payload already exists; retain immutable build evidence or choose a new work folder')
    sources = args.sources.resolve()
    sources.mkdir(parents=True, exist_ok=True)
    archive = sources / f'ffmpeg-{args.version}.tar.xz'
    url = f'https://ffmpeg.org/releases/{archive.name}'
    if not archive.exists():
        pending = archive.with_suffix('.download')
        run('/usr/bin/curl', '--fail', '--location', '--proto', '=https', '--tlsv1.2', url, '-o', pending)
        pending.rename(archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != PINS[args.version]:
        parser.error('Source archive does not match the pinned SHA-256')
    work.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as source:
        # Upstream source symlinks are not shipped. Refuse archives that escape.
        source.extractall(work, filter='data')
    source = work / f'ffmpeg-{args.version}'
    build = work / 'compile'
    build.mkdir()
    prefix = work / 'install'
    flags = [
        '--arch=arm64', '--target-os=darwin', '--cc=/usr/bin/clang',
        f'--prefix={prefix}', '--disable-autodetect', '--disable-network',
        '--disable-doc', '--disable-debug', '--disable-ffplay', '--disable-avdevice',
        '--disable-static', '--enable-shared', '--enable-pthreads',
        '--enable-videotoolbox', '--enable-audiotoolbox', '--install-name-dir=@rpath',
        '--extra-cflags=-mmacosx-version-min=13.0',
        '--extra-ldflags=-mmacosx-version-min=13.0 -Wl,-rpath,@executable_path/../lib',
    ]
    environment = dict(os.environ, PATH='/usr/bin:/bin:/usr/sbin:/sbin', MACOSX_DEPLOYMENT_TARGET='13.0')
    environment.pop('SDKROOT', None)
    with (work / 'build.log').open('w') as log:
        run(source / 'configure', *flags, cwd=build, env=environment, stdout=log, stderr=subprocess.STDOUT)
        run('/usr/bin/make', f'-j{args.jobs}', cwd=build, env=environment, stdout=log, stderr=subprocess.STDOUT)
        run('/usr/bin/make', 'install', cwd=build, env=environment, stdout=log, stderr=subprocess.STDOUT)
    (payload / 'bin').mkdir(parents=True)
    (payload / 'lib').mkdir()
    for name in ('ffmpeg', 'ffprobe'):
        shutil.copy2(prefix / 'bin' / name, payload / 'bin' / name)
    # Flatten SONAME links without shipping duplicate libraries or any symlink.
    for library in (prefix / 'lib').glob('*.dylib'):
        if not library.is_symlink():
            soname = run('/usr/bin/otool', '-D', library, capture_output=True, text=True).stdout.splitlines()[1].strip()
            shutil.copy2(library, payload / 'lib' / Path(soname).name)
    notices = payload / 'notices'
    notices.mkdir()
    for name in ('COPYING.LGPLv2.1', 'LICENSE.md', 'CREDITS'):
        shutil.copy2(source / name, notices / name)
    (payload / 'sources').mkdir()
    shutil.copy2(archive, payload / 'sources' / archive.name)
    shutil.copy2(Path(__file__).resolve(), payload / 'sources' / Path(__file__).name)
    record = dict(ffmpeg=args.version, sourceURL=url, sourceSHA256=PINS[args.version],
                  sourceChanges='none', configuration=flags, deploymentTarget='13.0', architecture='arm64',
                  xcode=run('/usr/bin/xcodebuild', '-version', capture_output=True, text=True).stdout,
                  compiler=run('/usr/bin/clang', '--version', capture_output=True, text=True).stdout)
    (notices / 'BUILD.json').write_text(json.dumps(record, indent=2) + '\n')
    (notices / 'BUILD-AND-SOURCE.txt').write_text(
        f'FFmpeg {args.version}, LGPL-2.1-or-later. Copyright the FFmpeg contributors.\n'
        'Full unmodified corresponding source is included in sources/. Exact configuration and toolchain: BUILD.json.\n'
        'Rebuild with the included build-ffmpeg-runtime.py; source SHA-256 is pinned there.\n'
        'GPL, nonfree and version3 options are disabled. No external codec libraries are linked.\n'
        'Networking and device capture are disabled. Only local file/pipe protocols are used by the app.\n'
        'Apple system frameworks are provided by macOS. FFmpeg libraries use relative @rpath linkage.\n'
        'You may modify and rebuild this LGPL runtime, including its shared libraries, under the included license.\n'
        'Modified executables require your own signature; publisher verification does not accept modified packs.\n')
    config = dict(id='media', version=args.pack_version, minimumAppVersion='0.2.1', minimumOSVersion='13.0',
                  tools={'ffmpeg':'bin/ffmpeg', 'ffprobe':'bin/ffprobe'}, sandboxInheritance=True,
                  licenses=['notices/COPYING.LGPLv2.1', 'notices/LICENSE.md', 'notices/BUILD-AND-SOURCE.txt'],
                  engineVersions={'ffmpeg':args.version, 'configuration':' '.join(flags), 'license':'LGPL-2.1-or-later'})
    (work / 'pack.json').write_text(json.dumps(config, indent=2) + '\n')
    print(payload)


if __name__ == '__main__':
    main()
