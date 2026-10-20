#!/usr/bin/env python3
"""Exercise real signed packs through the signed app's production XPC path.

The unsigned independently compiled runtime is used only to generate and reopen
fixtures. App conversions and cancellation must use the installed signed pack.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import struct
import subprocess
import time
import wave


def processes():
    rows = subprocess.check_output(['/bin/ps','-axo','pid=,ppid=,command='], text=True).splitlines()
    return [line.strip().split(None, 2) for line in rows if len(line.strip().split(None, 2)) == 3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--pack', type=Path, required=True)
    parser.add_argument('--update', type=Path)
    parser.add_argument('--download-update', action='store_true', help='Exercise interrupted and successful downloads from the signed app catalog')
    parser.add_argument('--runtime', type=Path, required=True, help='Independently compiled unsigned fixture/probe runtime')
    parser.add_argument('--root', type=Path, required=True, help='New isolated qualification folder')
    args = parser.parse_args()
    import plistlib
    with (args.app / 'Contents/Info.plist').open('rb') as stream:
        if plistlib.load(stream)['CFBundleShortVersionString'] == '0.2.0':
            parser.error('Build the new app first; published 0.2.0 has no real-pack qualification entry point')
    root = args.root.resolve()
    root.mkdir(parents=True, exist_ok=False)
    ffmpeg = args.runtime.resolve() / 'bin/ffmpeg'
    ffprobe = args.runtime.resolve() / 'bin/ffprobe'
    fixture = root / 'Fixtures'
    fixture.mkdir()
    audio = fixture / 'tone.wav'
    with wave.open(str(audio), 'wb') as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(44100)
        stream.writeframes(b''.join(struct.pack('<h', int(8000 * math.sin(2 * math.pi * 440 * i / 44100))) for i in range(88200)))
    image = fixture / 'pattern.ppm'
    image.write_bytes(b'P6\n320 180\n255\n' + bytes(c for y in range(180) for x in range(320) for c in (x % 256, y % 256, (x+y) % 256)))
    video = fixture / 'picture.mp4'
    cancel = fixture / 'long-picture.mp4'
    subprocess.run([str(ffmpeg), '-v','error','-nostdin','-loop','1','-framerate','24','-i',str(image),'-i',str(audio),'-t','2','-c:v','mpeg4','-q:v','5','-c:a','aac',str(video)],check=True)
    subprocess.run([str(ffmpeg), '-v','error','-nostdin','-stream_loop','59','-i',str(video),'-an','-vf','scale=1280:720','-t','120','-c:v','mpeg4','-q:v','8',str(cancel)],check=True)
    incoming = root / 'Incoming'
    incoming.mkdir()
    # Keep all app-selected test data outside privacy-protected project folders.
    # Verification still happens independently in the app and XPC worker.
    initial = incoming / 'Initial.bundle'
    shutil.copytree(args.pack.resolve(), initial)
    config = dict(pack=initial.as_uri(), audio=audio.as_uri(), video=video.as_uri(), cancellation=cancel.as_uri())
    if args.update:
        update = incoming / 'Update.bundle'
        shutil.copytree(args.update.resolve(), update)
        config['update'] = update.as_uri()
    if args.download_update:
        config['downloadUpdate'] = True
    (root / 'configuration.json').write_text(json.dumps(config, indent=2) + '\n')
    subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(args.app.resolve())],check=True)
    # Launch the app bundle itself, not its embedded CLI, with a fresh instance.
    subprocess.run(['/usr/bin/open','-n',str(args.app.resolve()),'--args','--engine-acceptance',str(root)],check=True)
    deadline = time.monotonic() + 180
    observed = None
    report_path = root / 'report.json'
    while time.monotonic() < deadline:
        if report_path.exists() and json.loads(report_path.read_text()).get('error'):
            break
        ready = root / 'cancellation-ready'
        if ready.exists():
            job_id = ready.read_text()
            rows = processes()
            for pid, parent, command in rows:
                if '/Contents/Runtime/bin/ffmpeg ' in command and f'engine-job-{job_id}-' in command:
                    parent_command = next((cmd for p, _, cmd in rows if p == parent), '')
                    if 'ConversionWorker.xpc/Contents/MacOS/' not in parent_command:
                        raise RuntimeError('FFmpeg was not spawned by the production XPC worker')
                    observed = dict(pid=int(pid), parentPID=int(parent), command=command, parentCommand=parent_command)
                    (root / 'observed-child.json').write_text(json.dumps(observed, indent=2) + '\n')
                    (root / 'cancel-now').touch()
                    break
        if observed:
            break
        time.sleep(0.1)
    while time.monotonic() < deadline:
        if report_path.exists():
            report = json.loads(report_path.read_text())
            if report.get('passed') or report.get('error'):
                break
        time.sleep(0.1)
    else:
        raise RuntimeError('Signed-app qualification timed out; inspect worker and report')
    report = json.loads(report_path.read_text())
    if not report.get('passed') or not observed:
        raise RuntimeError(f'Signed-app qualification failed: {report}')
    # XPC cancellation returns before the disconnected service finishes cleanup.
    deadline = time.monotonic() + 10
    while any(pid == str(observed['pid']) for pid, _, _ in processes()) and time.monotonic() < deadline:
        time.sleep(0.1)
    if any(pid == str(observed['pid']) for pid, _, _ in processes()):
        raise RuntimeError('Cancelled FFmpeg child survived XPC cancellation')
    probes = {}
    for name, expected_codec in [('audio','flac'),('video','h264')] + ([('updatedAudio','flac')] if 'updatedAudio' in report else []) + ([('updatedVideo','h264')] if 'updatedVideo' in report else []):
        url = report[name]['outputs'][0]['url']
        from urllib.parse import unquote, urlparse
        path = Path(unquote(urlparse(url).path))
        probe = json.loads(subprocess.check_output([str(ffprobe),'-v','error','-show_streams','-show_format','-of','json',str(path)],text=True))
        if not any(s['codec_name'] == expected_codec for s in probe['streams']):
            raise RuntimeError(f'Unexpected {name} codec')
        if abs(float(probe['format']['duration']) - 2) > 0.3:
            raise RuntimeError(f'Unexpected {name} duration')
        # Decode every frame/sample independently of the app's validation.
        subprocess.run([str(ffmpeg),'-v','error','-xerror','-i',str(path),'-f','null','-'],check=True)
        probes[name] = probe
    result = dict(passed=True, childTerminated=True, observedChild=observed, independentProbes=probes,
                  fixtureHashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (audio,video,cancel)})
    (root / 'qualification.json').write_text(json.dumps(result, indent=2) + '\n')
    print(root / 'qualification.json')


if __name__ == '__main__':
    main()
