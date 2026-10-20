#!/usr/bin/env python3
"""Assemble an independently built local runtime into a verifiable engine bundle.

No downloading, installed-app harvesting, or license inference happens here.
The producer supplies a complete relocatable runtime and its notices.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--config', required=True, type=Path)
parser.add_argument('--payload', required=True, type=Path, help='Directory whose files become Contents/Runtime')
parser.add_argument('--output', required=True, type=Path, help='New .bundle path')
parser.add_argument('--identity', help='Developer ID Application identity; omit only for an unusable unsigned fixture')
parser.add_argument('--notary-profile', help='Optional stored notarytool profile for the resulting ZIP')
parser.add_argument('--notary-keychain', help='Keychain holding the existing notary profile, if not the default')
args = parser.parse_args()
config = json.loads(args.config.read_text())
if config.get('id') not in {'media', 'documents', 'ebooks', 'transcription', 'pdf'}:
    parser.error('Unknown engine id')
if not re.fullmatch(r'\d+(?:\.\d+){1,3}', config.get('version', '')):
    parser.error('Use a numeric engine pack version')
if args.output.exists() or args.output.suffix != '.bundle':
    parser.error('Choose a new .bundle output path')
if args.notary_profile and not args.identity:
    parser.error('Notarization requires a Developer ID identity')
if not config.get('licenses') or not config.get('tools') or not config.get('engineVersions'):
    parser.error('Declare tool paths, versions, and license/source notices')

def safe_path(relative):
    if not isinstance(relative, str) or '\\' in relative or ':' in relative or relative.startswith('/') or any(x in {'', '.', '..'} for x in relative.split('/')):
        parser.error('Unsafe payload path')
    path = args.payload / relative
    if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(args.payload.resolve()):
        parser.error('Every declared payload path must be a regular file inside the payload')
    return path

for name in list(config['tools'].values()) + config['licenses'] + list(config.get('models', {}).values()):
    safe_path(name)
for entry in args.payload.rglob('*'):
    if entry.is_symlink() or not (entry.is_dir() or entry.is_file()):
        parser.error('Supply regular files and directories only; construct a relocatable runtime without symbolic links')

args.output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='converter-pack-', dir=args.output.parent) as temporary:
    bundle = Path(temporary) / args.output.name
    runtime = bundle / 'Contents/Runtime'
    shutil.copytree(args.payload, runtime)
    resources = bundle / 'Contents/Resources'
    resources.mkdir()
    macos = bundle / 'Contents/MacOS'
    macos.mkdir()
    # A bundle anchor supplies a normal, inspectable code-signing identity.
    anchor_source = Path(temporary) / 'anchor.c'
    anchor_source.write_text('int main(void) { return 0; }\n')
    subprocess.run(['xcrun', 'clang', '-arch', 'arm64', '-mmacosx-version-min=13.0', str(anchor_source), '-o', str(macos / 'pack-anchor')], check=True)
    prefix = 'Contents/Runtime/'
    tools = {key: prefix + value for key, value in config['tools'].items()}
    for relative in tools.values():
        (bundle / relative).chmod(0o755)
    macho_magic = {bytes.fromhex(value) for value in ['feedface', 'feedfacf', 'cefaedfe', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca']}
    binaries = []
    for file in bundle.rglob('*'):
        if file.is_file():
            with file.open('rb') as stream:
                if stream.read(4) in macho_magic:
                    binaries.append(file)
    if args.identity:
        inherited_entitlements = Path(temporary) / 'inherited.plist'
        with inherited_entitlements.open('wb') as stream:
            plistlib.dump({'com.apple.security.app-sandbox': True, 'com.apple.security.inherit': True}, stream)
        for file in sorted(binaries, key=lambda x: len(x.parts), reverse=True):
            if file == macos / 'pack-anchor':
                continue  # Signed once with the outer bundle after its manifest exists.
            signing = ['codesign', '--force', '--options', 'runtime', '--timestamp', '--sign', args.identity]
            # Child executables inherit the worker's sandbox, with no extra grants.
            # Dylibs do not carry process sandbox entitlements.
            if config.get('sandboxInheritance') and str(file.relative_to(bundle)) in tools.values():
                signing += ['--entitlements', str(inherited_entitlements)]
            subprocess.run(signing + [str(file)], check=True)
    hashes = {}
    for file in sorted(bundle.rglob('*')):
        if file.is_file() and file != macos / 'pack-anchor':
            digest = hashlib.sha256()
            with file.open('rb') as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(chunk)
            hashes[str(file.relative_to(bundle))] = digest.hexdigest()
    manifest = dict(schemaVersion=1, id=config['id'], version=config['version'], minimumAppVersion=config.get('minimumAppVersion', '0.2.0'), minimumOSVersion=config.get('minimumOSVersion', '13.0'), architectures=['arm64'], tools=tools, files=hashes, licenses=[prefix+x for x in config['licenses']], installedBytes=sum(x.stat().st_size for x in bundle.rglob('*') if x.is_file()), engineVersions=config['engineVersions'], models={key: prefix+value for key,value in config.get('models', {}).items()})
    (resources / 'engine.json').write_text(json.dumps(manifest, indent=2, sort_keys=True)+'\n')
    with (bundle / 'Contents/Info.plist').open('wb') as stream:
        plistlib.dump(dict(CFBundleIdentifier='io.local.file-converter.engine.'+config['id'], CFBundleName=config['id'].title()+' Engine', CFBundleExecutable='pack-anchor', CFBundlePackageType='BNDL', CFBundleVersion=config['version'], CFBundleShortVersionString=config['version']), stream)
    if args.identity:
        subprocess.run(['codesign', '--force', '--options', 'runtime', '--timestamp', '--sign', args.identity, str(bundle)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
    # Include the manifest, Info.plist, signed anchor and seal in logical installed
    # bytes. The anchor is not payload-hashed, so adjusting this signed metadata
    # does not introduce a manifest/anchor hash cycle.
    for attempt in range(4):
        total = sum(file.stat().st_size for file in bundle.rglob('*') if file.is_file())
        if manifest['installedBytes'] == total:
            break
        manifest['installedBytes'] = total
        (resources / 'engine.json').write_text(json.dumps(manifest, indent=2, sort_keys=True)+'\n')
        if args.identity:
            subprocess.run(['codesign', '--force', '--options', 'runtime', '--timestamp', '--sign', args.identity, str(bundle)], check=True)
    else:
        raise SystemExit('Installed size did not stabilize; bundle retained only in temporary assembly')
    if args.identity:
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
    shutil.move(bundle, args.output)
archive = args.output.with_suffix('.zip')
if archive.exists():
    parser.error('ZIP output already exists; the assembled bundle was retained')
subprocess.run(['ditto', '-c', '-k', '--keepParent', '--norsrc', '--noextattr', str(args.output), str(archive)], check=True)
if args.notary_profile:
    notarize = ['xcrun', 'notarytool', 'submit', str(archive), '--keychain-profile', args.notary_profile, '--wait', '--output-format', 'json']
    if args.notary_keychain:
        notarize += ['--keychain', args.notary_keychain]
    result = subprocess.run(notarize, check=True, capture_output=True, text=True)
    record = json.loads(result.stdout)
    args.output.with_suffix('.notary.json').write_text(json.dumps(record, indent=2) + '\n')
    if record.get('status') != 'Accepted':
        raise SystemExit('Pack notarization was not accepted; inspect the saved notary record')
    # Bundles carry notarization through the submitted archive; app releases are
    # separately stapled and assessed by release-app.sh.
archive_digest = hashlib.sha256()
with archive.open('rb') as stream:
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        archive_digest.update(chunk)
entry = dict(id=config['id'], version=config['version'], downloadBytes=archive.stat().st_size, sha256=archive_digest.hexdigest())
print(json.dumps(entry, indent=2))
if not args.identity:
    print('Unsigned development fixture only. Production pack verification will reject this bundle.')
