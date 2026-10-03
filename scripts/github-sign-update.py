#!/usr/bin/env python3
"""Publish reviewed helper updates; key exists only in a private temporary directory."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
REPO = 'th3d3ck3r/Moonlight-OS'
HELPERS = {
    'system-controls': 'scripts/system-controls.py',
    'control-center': 'scripts/control-center.py',
    'bluetooth-menu': 'scripts/bluetooth-menu.py',
    'wifi-menu': 'scripts/wifi-menu.sh',
    'streaming-tune': 'scripts/streaming-tune.py',
}
spec = importlib.util.spec_from_file_location('update', ROOT / 'scripts/eclipseos-update.py')
update = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update)

def repo_file(value, root=ROOT):
    if not isinstance(value, str) or not value or Path(value).is_absolute():
        raise ValueError('Expected a repository-relative file')
    path = root / value
    if '..' in Path(value).parts or any(p.is_symlink() for p in [path, *path.parents]):
        raise ValueError('Unsafe repository path')
    path.resolve().relative_to(root.resolve())
    if not path.is_file():
        raise ValueError('Missing reviewed repository file')
    return path

def validate_plan(path, root=ROOT):
    plan = update.decode(update.read_regular(repo_file(path, root), 16384))
    if set(plan) != {'id', 'sequence', 'channel', 'baseline', 'notes', 'targets'}:
        raise ValueError('Unexpected release-plan fields')
    if not isinstance(plan['id'], str) or not re.fullmatch(r'eclipse-[a-z0-9][a-z0-9.-]{0,55}', plan['id']):
        raise ValueError('Use a unique eclipse- release ID')
    if type(plan['sequence']) is not int or plan['sequence'] < 1 or plan['channel'] not in ('stable', 'testing'):
        raise ValueError('Invalid channel/sequence')
    targets = plan['targets']
    if not isinstance(targets, list) or not targets or any(not isinstance(t, str) or t not in HELPERS for t in targets) or len(set(targets)) != len(targets):
        raise ValueError('Select distinct supported helpers; frontend needs a native build pipeline')
    baseline = update.decode(update.read_regular(repo_file(plan['baseline'], root), 16384))
    if baseline.get('base') != update.BASE_ID or baseline.get('kernel') != update.KERNEL:
        raise ValueError('Incompatible receiving installation')
    notes = update.read_regular(repo_file(plan['notes'], root), 16384).decode()
    if not notes.strip() or len(notes) > 4096:
        raise ValueError('Release notes must contain 1..4096 characters')
    for target in targets:
        before = baseline.get('files', {}).get(target)
        if not isinstance(before, str) or not re.fullmatch(r'[0-9a-f]{64}', before):
            raise ValueError('Missing receiving helper checksum')
        file = repo_file(HELPERS[target], root)
        data = update.read_regular(file, update.MAX_EXPANDED)
        if update.digest(data) == before:
            raise ValueError('Selected helper is unchanged')
        if target == 'wifi-menu':
            subprocess.run(['bash', '-n', str(file)], check=True)
        else:
            compile(data, target, 'exec')
    return plan

def release(tag):
    request = urllib.request.Request(f'https://api.github.com/repos/{REPO}/releases/tags/{tag}', headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'Accept': 'application/vnd.github+json'})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise

def gh(*args):
    subprocess.run(['gh', *args], check=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--validate-only', action='store_true')
    args = parser.parse_args()
    plan = validate_plan(os.environ.get('UPDATE_PLAN', ''))
    if args.validate_only:
        print('Release plan and helper payloads validated')
        return
    if os.environ.get('GITHUB_REF') != 'refs/heads/main' or os.environ.get('GITHUB_REPOSITORY') != REPO:
        raise ValueError('Signing is restricted to the owner repository main branch')
    source = os.environ['GITHUB_SHA']
    if not re.fullmatch(r'[0-9a-f]{40}', source):
        raise ValueError('Invalid source identity')
    key = os.environ.pop('ECLIPSEOS_SIGNING_KEY', '')
    if not key.strip():
        raise ValueError('Configure environment secret ECLIPSEOS_SIGNING_KEY first')
    feed = 'eclipseos-updates-' + plan['channel']
    if release(plan['id']) is not None:
        raise ValueError('Release ID already exists; never overwrite a payload')
    previous = release(feed)
    with tempfile.TemporaryDirectory(prefix='eclipse-sign-', dir=os.environ.get('RUNNER_TEMP')) as folder:
        work = Path(folder)
        private = work / 'private.pem'
        private.touch(mode=0o600)
        private.write_text(key)
        del key
        public = work / 'public.pem'
        subprocess.run(['openssl', 'pkey', '-in', str(private), '-pubout', '-out', str(public)], check=True)
        if previous:
            old = work / 'old'
            old.mkdir()
            gh('release', 'download', feed, '--pattern', 'manifest.*', '--dir', str(old))
            subprocess.run(['openssl', 'pkeyutl', '-verify', '-rawin', '-pubin', '-inkey', str(public), '-in', str(old / 'manifest.json'), '-sigfile', str(old / 'manifest.sig')], check=True)
            manifest = update.manifest_validate(update.decode((old / 'manifest.json').read_bytes()))
            if manifest['channel'] != plan['channel'] or plan['sequence'] <= manifest['sequence']:
                raise ValueError('Sequence must increase within the channel')
        output = work / 'package'
        command = ['python3', str(ROOT / 'scripts/make-update-package.py'), '--id', plan['id'], '--sequence', str(plan['sequence']), '--channel', plan['channel'], '--source', source, '--notes', str(repo_file(plan['notes'])), '--baseline', str(repo_file(plan['baseline'])), '--key', str(private), '--url', f'https://github.com/{REPO}/releases/download/{plan["id"]}/payload.tar.gz', '--output', str(output)]
        for target in plan['targets']:
            command.extend(['--file', target + '=' + str(repo_file(HELPERS[target]))])
        subprocess.run(command, check=True)
        subprocess.run(['openssl', 'pkeyutl', '-verify', '-rawin', '-pubin', '-inkey', str(public), '-in', str(output / 'manifest.json'), '-sigfile', str(output / 'manifest.sig')], check=True)
        private.unlink()
        # Public enrollment key only; no private key or workspace artifact upload.
        gh('release', 'create', plan['id'], '--target', source, '--draft', '--title', plan['id'], '--notes-file', str(repo_file(plan['notes'])), '--latest=false')
        gh('release', 'upload', plan['id'], *[str(output / name) for name in ('payload.tar.gz', 'manifest.json', 'manifest.sig')], str(public))
        gh('release', 'edit', plan['id'], '--draft=false')
        if previous is None:
            gh('release', 'create', feed, '--target', source, '--title', feed, '--notes', 'Signed EclipseOS update feed', '--latest=false', '--prerelease')
        gh('release', 'upload', feed, str(output / 'manifest.json'), str(output / 'manifest.sig'), '--clobber')
        print('Published signed helper update:', plan['id'])

if __name__ == '__main__':
    main()
