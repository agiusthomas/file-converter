#!/usr/bin/env python3
"""Generate the capability reference from the same registry as the app and CLI."""
import argparse
import datetime
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--binary', default='.build/debug/convert-file')
parser.add_argument('--output', type=Path, default=Path('docs/CAPABILITIES.md'))
args = parser.parse_args()
report = json.loads(subprocess.check_output([args.binary, 'capabilities']))
lines = ['# Capability reference', '', f'Generated {datetime.date.today().isoformat()} from `convert-file capabilities` (schema {report["schemaVersion"]}).', '', 'This is the registry on the generation Mac. Use `convert-file actions FILE...` for the content-probed intersection for your selection. Native encoders vary by OS; optional media profiles are further filtered against the installed binary’s encoders and muxers. A format name does not guarantee every codec, track, animation, or embedded feature.', '', f'Archive engine: {report["archiveEngine"]}.', '', '| Action | Inputs | Output profiles | Availability |', '| --- | --- | --- | --- |']
for action in report['actions']:
    availability = 'Included' if action['available'] else 'Requires '+action.get('requiredPack', 'compatible engine')+' pack'
    lines.append('| `'+action['id']+'` | '+', '.join(action['families'])+' | '+', '.join('`'+x['id']+'`' for x in action['profiles'])+' | '+availability+' |')
lines += ['', 'Optional adapters are development implementations until signed packs and their release corpora pass. See [implementation status](../IMPLEMENTATION.md) for validation and outstanding gates.', '']
args.output.write_text('\n'.join(lines))
