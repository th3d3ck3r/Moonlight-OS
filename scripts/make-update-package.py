#!/usr/bin/env python3
"""Create a signed update from prebuilt files; never compile a frontend or OS image."""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tarfile

spec = importlib.util.spec_from_file_location('update', Path(__file__).with_name('eclipseos-update.py'))
update = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--id', required=True)
    parser.add_argument('--sequence', required=True, type=int)
    parser.add_argument('--channel', choices=['stable', 'testing'], required=True)
    parser.add_argument('--source', required=True, help='40-character Moonlight-OS source commit')
    parser.add_argument('--notes', required=True, type=Path)
    parser.add_argument('--baseline', required=True, type=Path, help='JSON exported from the target USB')
    parser.add_argument('--key', required=True, type=Path, help='Offline Ed25519 private key; never commit it')
    parser.add_argument('--url', required=True, help='Future GitHub release payload.tar.gz URL')
    parser.add_argument('--file', action='append', required=True, help='Allowlisted target=/absolute/prebuilt/file')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Output directory already exists')
    baseline = update.decode(args.baseline.read_bytes())
    if baseline['base'] != update.BASE_ID or baseline['kernel'] != update.KERNEL:
        parser.error('Incompatible baseline')
    entries, payloads = [], {}
    for value in args.file:
        name, separator, path = value.partition('=')
        if not separator or name not in update.TARGETS or name in payloads:
            parser.error('Unknown or duplicate target')
        data = update.read_regular(Path(path), update.MAX_EXPANDED)
        payloads[name] = data
        entries.append(dict(target=name, size=len(data), sha256=update.digest(data), before_sha256=None if name == 'frontend' else baseline['files'][name]))
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w:gz') as archive:
        for name, data in payloads.items():
            item = tarfile.TarInfo(name)
            item.size, item.mode, item.mtime = len(data), 0o600, 0
            archive.addfile(item, io.BytesIO(data))
    bundle = buffer.getvalue()
    manifest = dict(schema=1, base=update.BASE_ID, id=args.id, sequence=args.sequence, channel=args.channel, source=args.source, notes=args.notes.read_text(), files=entries, archive=dict(size=len(bundle), sha256=update.digest(bundle), url=args.url))
    update.manifest_validate(manifest)
    args.output.mkdir(parents=True, mode=0o700)
    (args.output / 'payload.tar.gz').write_bytes(bundle)
    (args.output / 'manifest.json').write_text(json.dumps(manifest, sort_keys=True, separators=(',', ':')))
    subprocess.run(['/usr/bin/openssl', 'pkeyutl', '-sign', '-rawin', '-inkey', str(args.key), '-in', str(args.output / 'manifest.json'), '-out', str(args.output / 'manifest.sig')], check=True)
    if (args.output / 'manifest.sig').stat().st_size != 64:
        raise ValueError('Signing key must be Ed25519')
    print('Signed package prepared:', args.output)

if __name__ == '__main__':
    main()
