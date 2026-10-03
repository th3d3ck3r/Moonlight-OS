#!/usr/bin/python3
"""Signed, fixed-base updates. No package-supplied commands or arbitrary destinations."""
import argparse
import contextlib
import fcntl
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
import urllib.parse

BASE_ID = 'eclipseos-f44-mbp14-1-v1'
KERNEL = '6.19.10-300.fc44.x86_64'
HELPER = '/usr/local/libexec/moonlight-os/eclipseos-update.py'
STATE = '/var/lib/eclipseos-updates'
RELEASES = '/usr/local/libexec/eclipseos/releases'
KEY = '/etc/eclipseos-update/public.pem'
MAX_ARCHIVE = 256 * 1024 * 1024
MAX_EXPANDED = 384 * 1024 * 1024
TARGETS = {
    'frontend': (None, 0o755, None),
    'system-controls': ('/usr/local/libexec/moonlight-os/system-controls.py', 0o755, None),
    'control-center': ('/usr/local/libexec/moonlight-os/control-center.py', 0o755, None),
    'bluetooth-menu': ('/usr/local/bin/moonlight-bluetooth', 0o755, None),
    'streaming-tune': ('/usr/local/bin/eclipseos-streaming', 0o755, None),
    'wifi-menu': ('/usr/local/bin/moonlight-wifi', 0o755, None),
    'wifi-config': ('/etc/NetworkManager/conf.d/99-moonlight-wifi.conf', 0o644, 'NetworkManager.service'),
    'bluetooth-config': ('/etc/bluetooth/main.conf', 0o644, 'bluetooth.service'),
}

def digest(data):
    return hashlib.sha256(data).hexdigest()

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate JSON key')
        result[key] = value
    return result

def decode(data):
    return json.loads(data, object_pairs_hook=unique_object)

def atomic(path, data, mode=0o600):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.update-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as out:
            os.fchmod(out.fileno(), mode)
            out.write(data)
            out.flush()
            os.fsync(out.fileno())
        os.replace(tmp, path)
        sync_dir(path.parent)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def sync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)

def read_regular(path, limit):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        import stat
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_size > limit:
            raise ValueError('Invalid or oversized file')
        with os.fdopen(fd, 'rb', closefd=False) as src:
            data = src.read(limit + 1)
        if len(data) > limit:
            raise ValueError('Oversized file')
        return data
    finally:
        os.close(fd)

def manifest_validate(m):
    if set(m) != {'schema', 'base', 'id', 'sequence', 'channel', 'source', 'notes', 'files', 'archive'}:
        raise ValueError('Unsupported manifest fields')
    if m['schema'] != 1 or m['base'] != BASE_ID:
        raise ValueError('Update targets a different base OS')
    if not isinstance(m['id'], str) or not re.fullmatch(r'[a-z0-9][a-z0-9.-]{0,63}', m['id']):
        raise ValueError('Invalid update ID')
    if type(m['sequence']) is not int or m['sequence'] < 1 or m['channel'] not in ('stable', 'testing'):
        raise ValueError('Invalid update channel or sequence')
    if not isinstance(m['source'], str) or not re.fullmatch(r'[0-9a-f]{40}', m['source']):
        raise ValueError('Missing source commit')
    if not isinstance(m['notes'], str) or len(m['notes']) > 4096:
        raise ValueError('Invalid release notes')
    if not isinstance(m['files'], list) or not 1 <= len(m['files']) <= len(TARGETS):
        raise ValueError('Invalid file count')
    seen = set()
    for item in m['files']:
        if set(item) != {'target', 'sha256', 'size', 'before_sha256'}:
            raise ValueError('Invalid file fields')
        name = item['target']
        if name not in TARGETS or name in seen:
            raise ValueError('Unsupported or duplicate target')
        seen.add(name)
        if not isinstance(item['sha256'], str) or not re.fullmatch(r'[0-9a-f]{64}', item['sha256']):
            raise ValueError('Invalid file checksum')
        if type(item['size']) is not int or not 0 < item['size'] <= MAX_EXPANDED:
            raise ValueError('Invalid file size')
        before = item['before_sha256']
        if name == 'frontend':
            if before is not None:
                raise ValueError('Frontend baseline must be null')
        elif not isinstance(before, str) or not re.fullmatch(r'[0-9a-f]{64}', before):
            raise ValueError('System files require a matching baseline checksum')
    archive = m['archive']
    if set(archive) != {'sha256', 'size', 'url'} or not re.fullmatch(r'[0-9a-f]{64}', archive['sha256']):
        raise ValueError('Invalid archive checksum')
    if type(archive['size']) is not int or not 0 < archive['size'] <= MAX_ARCHIVE:
        raise ValueError('Invalid archive size')
    if sum(i['size'] for i in m['files']) > MAX_EXPANDED:
        raise ValueError('Expanded package too large')
    validate_url(archive['url'], initial=True)
    return m

def validate_url(url, initial=False):
    p = urllib.parse.urlsplit(url)
    hosts = {'github.com', 'release-assets.githubusercontent.com', 'objects.githubusercontent.com'}
    if p.scheme != 'https' or p.hostname not in hosts or p.username or p.password or p.port not in (None, 443):
        raise ValueError('Untrusted download destination')
    if initial and (p.hostname != 'github.com' or not p.path.startswith('/th3d3ck3r/Moonlight-OS/releases/download/') or p.query or p.fragment or '..' in p.path):
        raise ValueError('Package must be published by Moonlight-OS')

class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        validate_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)

def download(url, limit):
    validate_url(url, initial=True)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), SafeRedirect())
    with opener.open(url, timeout=30) as response:
        started = time.monotonic()
        chunks, received = [], 0
        while received <= limit:
            if time.monotonic() - started > 600:
                raise ValueError('Download deadline exceeded')
            chunk = response.read(min(65536, limit + 1 - received))
            if not chunk:
                break
            chunks.append(chunk)
            received += len(chunk)
        data = b''.join(chunks)
    if len(data) > limit:
        raise ValueError('Download exceeds limit')
    return data

class FrontendBusy(ValueError):
    pass

class Updater:
    # root/runner injection is only a Python test API, never a CLI option/environment variable.
    def __init__(self, root=Path('/'), runner=None):
        self.root = Path(root)
        self.runner = runner or self.run
        self.state_dir = self.path(STATE)
        self.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(self.state_dir, 0o700)

    def path(self, path):
        return self.root / path.lstrip('/')

    @staticmethod
    def run(args):
        return subprocess.run(args, check=True, capture_output=True, timeout=60,
                              env={'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LANG': 'C'}).stdout

    @contextlib.contextmanager
    def lock(self):
        with open(self.state_dir / 'lock', 'a') as fd:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            yield

    def load(self):
        p = self.state_dir / 'state.json'
        return decode(read_regular(p, 65536)) if p.exists() else {'accepted': {}, 'active': None, 'pending': None, 'trial': False, 'rollback_requested': False}

    def save(self, state):
        atomic(self.state_dir / 'state.json', json.dumps(state).encode())

    def compatible(self):
        receipt = decode(read_regular(self.path('/etc/eclipseos-update/base.json'), 4096))
        if receipt != {'base': BASE_ID, 'kernel': KERNEL, 'arch': 'x86_64'}:
            raise ValueError('Unsupported base receipt')
        if self.root == Path('/') and (os.uname().release != KERNEL or os.uname().machine != 'x86_64'):
            raise ValueError('Kernel/base differs; use a separately validated OS release')

    def verify(self, raw, signature):
        if len(raw) > 65536 or len(signature) != 64:
            raise ValueError('Invalid signed manifest size')
        key = self.path(KEY)
        if not key.is_file():
            raise ValueError('Updates disabled: trusted public key has not been provisioned')
        with tempfile.TemporaryDirectory(dir=self.state_dir) as td:
            m, s = Path(td) / 'manifest', Path(td) / 'signature'
            m.write_bytes(raw)
            s.write_bytes(signature)
            self.runner(['/usr/bin/openssl', 'pkeyutl', '-verify', '-rawin', '-pubin', '-inkey', str(key), '-in', str(m), '-sigfile', str(s)])
        return manifest_validate(decode(raw))

    def offer(self, channel):
        self.compatible()
        if not self.path(KEY).is_file():
            raise ValueError('Updates disabled: trusted public key has not been provisioned')
        url = 'https://github.com/th3d3ck3r/Moonlight-OS/releases/download/eclipseos-updates-' + channel + '/'
        raw = download(url + 'manifest.json', 65536)
        signature = download(url + 'manifest.sig', 64)
        manifest = self.verify(raw, signature)
        if manifest['channel'] != channel:
            raise ValueError('Feed channel mismatch')
        return raw, signature, manifest

    def baseline(self):
        self.compatible()
        return {'base': BASE_ID, 'kernel': KERNEL, 'files': {name: digest(read_regular(self.path(path), MAX_EXPANDED)) for name, (path, _, _) in TARGETS.items() if path}}

    def stage(self, raw, signature, bundle):
        self.compatible()
        m = self.verify(raw, signature)
        state = self.load()
        if state['trial'] or state['pending'] or (self.state_dir / 'journal.json').exists():
            raise ValueError('Confirm, roll back or cancel the pending update first')
        if m['sequence'] <= state['accepted'].get(m['channel'], 0):
            raise ValueError('Old or already accepted update sequence')
        if len(bundle) != m['archive']['size'] or digest(bundle) != m['archive']['sha256']:
            raise ValueError('Archive checksum/size mismatch')
        if shutil.disk_usage(self.state_dir).free < 2 * MAX_EXPANDED:
            raise ValueError('Need at least 768 MiB free for staging and recovery')
        destination = self.state_dir / 'packages' / m['id']
        if destination.exists():
            raise ValueError('Update ID already staged; use a new unique ID')
        destination.parent.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=destination.parent) as td:
            folder = Path(td)
            wanted = {i['target']: i for i in m['files']}
            found = set()
            with gzip.GzipFile(fileobj=io.BytesIO(bundle)) as compressed:
                expanded = compressed.read(MAX_EXPANDED + 1024 * 1024 + 1)
            if len(expanded) > MAX_EXPANDED + 1024 * 1024:
                raise ValueError('Archive expansion exceeds limit')
            with tarfile.open(fileobj=io.BytesIO(expanded), mode='r:') as archive:
                for member in archive:
                    if member.name not in wanted or member.name in found or not member.isfile() or member.sparse or member.pax_headers or member.size != wanted[member.name]['size']:
                        raise ValueError('Archive has extra, duplicate, linked or malformed entries')
                    # No extract()/extractall(): archive paths, ownership and permissions are never trusted.
                    data = archive.extractfile(member).read(member.size + 1)
                    if len(data) != member.size or digest(data) != wanted[member.name]['sha256']:
                        raise ValueError('Payload checksum mismatch')
                    atomic(folder / member.name, data)
                    found.add(member.name)
            if found != set(wanted):
                raise ValueError('Missing payload')
            atomic(folder / 'manifest.json', raw)
            atomic(folder / 'manifest.sig', signature)
            os.rename(folder, destination)
            sync_dir(destination.parent)
            # TemporaryDirectory tolerates the renamed directory at cleanup.
        state['pending'] = m['id']
        self.save(state)
        return {'message': 'Verified and staged. End the frontend, then relaunch. Wi-Fi/Bluetooth configuration changes can interrupt connectivity.', 'id': m['id'], 'notes': m['notes']}

    def idle(self):
        if self.root != Path('/'):
            return
        names = {'vibemis', 'moonlight', 'cocoos', 'artemis', 'pegasus-fe', 'Moonlight', 'CocoOS', 'Artemis', 'Eclipse'}
        for proc in Path('/proc').glob('[0-9]*/exe'):
            try:
                executable = os.readlink(proc).removesuffix(' (deleted)')
                if Path(executable).name in names or executable.startswith(('/usr/local/libexec/moonlight-os/', '/usr/local/libexec/eclipseos/releases/')):
                    raise FrontendBusy('Close all frontends/streams before applying or rolling back')
            except (FileNotFoundError, ProcessLookupError):
                pass

    def validate_payload(self, name, data, staged):
        if name in ('system-controls', 'control-center', 'bluetooth-menu', 'streaming-tune'):
            compile(data, name, 'exec')
        elif name == 'wifi-menu':
            self.runner(['/usr/bin/bash', '-n', str(staged)])
        elif name.endswith('-config'):
            import configparser
            parser = configparser.ConfigParser(interpolation=None, strict=True)
            parser.read_string(data.decode())
            allowed = {'wifi-config': {'connection': {'wifi.powersave'}}, 'bluetooth-config': {'General': {'AutoEnable'}}}[name]
            # Vendor BlueZ baseline can contain comments; update payload is deliberately narrow.
            if set(parser.sections()) != set(allowed) or parser.defaults():
                raise ValueError('Configuration sections outside permitted scope')
            for section in allowed:
                if set(parser[section]) != {k.lower() for k in allowed[section]}:
                    raise ValueError('Configuration options outside permitted scope')
            if name == 'wifi-config' and parser['connection']['wifi.powersave'] not in ('2', '3'):
                raise ValueError('Invalid Wi-Fi powersave setting')
            if name == 'bluetooth-config' and parser['General']['AutoEnable'].lower() not in ('true', 'false'):
                raise ValueError('Invalid Bluetooth setting')
        elif name == 'frontend':
            if len(data) < 20 or data[:6] != b'\x7fELF\x02\x01' or data[18:20] != b'\x3e\x00':
                raise ValueError('Frontend must be a native x86_64 ELF executable')
            if self.root == Path('/'):
                os.chmod(staged, 0o755)
                output = self.runner(['/usr/bin/ldd', str(staged)])
                if b'not found' in output:
                    raise ValueError('Missing frontend dependency; full base update required')

    def switch(self, update_id):
        link = self.path('/usr/local/libexec/eclipseos/current')
        link.parent.mkdir(parents=True, exist_ok=True)
        if update_id is None:
            link.unlink(missing_ok=True)
        else:
            temporary = link.with_name('.current-next')
            temporary.unlink(missing_ok=True)
            temporary.symlink_to('releases/' + update_id)
            os.replace(temporary, link)
        sync_dir(link.parent)

    def restart(self, services, boot=False):
        if boot:
            return
        for service in services:
            self.runner(['/usr/bin/systemctl', 'restart', service])

    def rollback(self, boot=False):
        journal_path = self.state_dir / 'journal.json'
        if not journal_path.exists():
            return
        journal = decode(read_regular(journal_path, 65536))
        state = self.load()
        if state.get('confirmed') == journal['id'] and not journal.get('force'):
            journal_path.unlink()
            sync_dir(self.state_dir)
            return
        for item in journal['backups']:
            name = item['target']
            path, _, _ = TARGETS[name]
            data = read_regular(self.state_dir / 'backup' / name, MAX_EXPANDED)
            if digest(data) != item['sha256']:
                raise ValueError('Recovery backup checksum mismatch; use tty2/manual recovery')
            atomic(self.path(path), data, item['mode'])
        self.switch(journal['previous'])
        self.restart(journal['services'], boot)
        state.pop('confirmed', None)
        state.update(active=journal['previous'], trial=False, rollback_requested=False, pending=None)
        self.save(state)
        journal_path.unlink()
        sync_dir(self.state_dir)

    def preflight(self):
        try:
            return self.apply()
        except FrontendBusy:
            return {'message': 'Update deferred: an existing frontend is running. Close all clients to activate/recover on the next launch.'}

    def apply(self):
        state = self.load()
        if not (state['trial'] or state['rollback_requested'] or state['pending'] or (self.state_dir / 'journal.json').exists()):
            return {'message': 'No pending update.'}
        self.idle()
        if state['trial'] or state['rollback_requested'] or (self.state_dir / 'journal.json').exists():
            self.rollback()
            return {'message': 'Previous update restored. Recovery did not need networking.'}
        if not state['pending']:
            return {'message': 'No pending update.'}
        self.compatible()
        folder = self.state_dir / 'packages' / state['pending']
        m = self.verify(read_regular(folder / 'manifest.json', 65536), read_regular(folder / 'manifest.sig', 64))
        if m['id'] != state['pending'] or m['sequence'] <= state['accepted'].get(m['channel'], 0):
            raise ValueError('Pending update identity/sequence mismatch')
        backup = self.state_dir / 'backup'
        backups, services, payloads, originals = [], [], {}, {}
        for item in m['files']:
            name = item['target']
            path, mode, service = TARGETS[name]
            data = read_regular(folder / name, MAX_EXPANDED)
            if len(data) != item['size'] or digest(data) != item['sha256']:
                raise ValueError('Staged payload changed')
            self.validate_payload(name, data, folder / name)
            payloads[name] = data
            if path:
                target = self.path(path)
                previous = read_regular(target, MAX_EXPANDED)
                if digest(previous) != item['before_sha256']:
                    raise ValueError('Local configuration/helper differs from package baseline: ' + name)
                originals[name] = previous
                backups.append({'target': name, 'sha256': digest(previous), 'mode': target.stat().st_mode & 0o777})
                if service and service not in services:
                    try:
                        self.runner(['/usr/bin/systemctl', 'is-active', '--quiet', service])
                        services.append(service)
                    except subprocess.CalledProcessError:
                        pass
        required = sum(map(len, originals.values())) + len(payloads.get('frontend', b'')) + 16 * 1024 * 1024
        if shutil.disk_usage(self.state_dir).free < required:
            raise ValueError('Insufficient space for recovery snapshot')
        (self.state_dir / 'confirmed-journal.json').unlink(missing_ok=True)
        if backup.exists():
            shutil.rmtree(backup)
        backup.mkdir(mode=0o700)
        for name, previous in originals.items():
            atomic(backup / name, previous)
        if 'frontend' in payloads:
            releases = self.path(RELEASES)
            releases.mkdir(parents=True, exist_ok=True, mode=0o755)
            os.chmod(releases, 0o755)
            slot = releases / m['id']
            slot.mkdir(parents=True, exist_ok=True, mode=0o755)
            os.chmod(slot, 0o755)
            atomic(slot / 'vibemis', payloads['frontend'], 0o755)
            sync_dir(slot.parent)
        journal = {'id': m['id'], 'previous': state['active'], 'backups': backups, 'services': services}
        atomic(self.state_dir / 'journal.json', json.dumps(journal).encode())
        try:
            for name, data in payloads.items():
                path, mode, _ = TARGETS[name]
                if path:
                    atomic(self.path(path), data, mode)
            if 'frontend' in payloads:
                self.switch(m['id'])
            self.restart(services)
            state.update(active=m['id'] if 'frontend' in payloads else state['active'], pending=None, trial=True, trial_id=m['id'])
            self.save(state)
        except Exception:
            self.rollback()
            raise
        return {'message': 'Trial active. Test the frontend, Wi-Fi and Bluetooth, then confirm from tty2. Next launch/boot rolls back an unconfirmed trial.', 'id': m['id']}

    def confirm(self):
        state = self.load()
        if not state['trial'] or state['rollback_requested']:
            raise ValueError('No confirmable trial')
        folder = self.state_dir / 'packages' / state['trial_id']
        m = self.verify(read_regular(folder / 'manifest.json', 65536), read_regular(folder / 'manifest.sig', 64))
        atomic(self.state_dir / 'confirmed-journal.json', read_regular(self.state_dir / 'journal.json', 65536))
        state['accepted'][m['channel']] = m['sequence']
        state.update(trial=False, confirmed=m['id'])
        self.save(state)  # Durable confirmation precedes journal removal.
        (self.state_dir / 'journal.json').unlink()
        sync_dir(self.state_dir)
        return {'message': 'Update confirmed. Explicit rollback remains available until the next update.'}

    def explicit_rollback(self):
        self.idle()
        state = self.load()
        if not (self.state_dir / 'journal.json').exists():
            recovery = self.state_dir / 'confirmed-journal.json'
            if not state.get('confirmed') or not recovery.exists():
                raise ValueError('No rollback snapshot available')
            journal = decode(read_regular(recovery, 65536))
            journal['force'] = True
            atomic(self.state_dir / 'journal.json', json.dumps(journal).encode())
            state.pop('confirmed', None)
            self.save(state)
        self.rollback()
        return {'message': 'Update rolled back'}

    def status(self):
        state = self.load()
        return dict(state, provisioned=self.path(KEY).is_file(), base=BASE_ID, kernel=KERNEL,
                    message='Stage only while using Eclipse; apply/rollback after closing all frontends. Confirm each trial from tty2.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['status', 'baseline', 'check', 'stage', 'stage-offline', 'apply', 'launch-preflight', 'recover-boot', 'confirm', 'rollback', 'cancel'])
    parser.add_argument('argument', nargs='?')
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('Run through sudo; installed updater and state must be root-owned')
    updater = Updater()
    with updater.lock():
        if args.command in ('status', 'baseline'):
            result = updater.status() if args.command == 'status' else updater.baseline()
        elif args.command in ('check', 'stage'):
            if args.argument not in ('stable', 'testing'):
                raise ValueError('Choose stable or testing')
            raw, sig, m = updater.offer(args.argument)
            result = {'id': m['id'], 'notes': m['notes'], 'channel': m['channel']}
            if args.command == 'stage':
                result = updater.stage(raw, sig, download(m['archive']['url'], m['archive']['size']))
        elif args.command == 'stage-offline':
            if not args.argument or not Path(args.argument).is_absolute():
                raise ValueError('Use an absolute package-directory path')
            directory = Path(args.argument)
            result = updater.stage(read_regular(directory / 'manifest.json', 65536), read_regular(directory / 'manifest.sig', 64), read_regular(directory / 'payload.tar.gz', MAX_ARCHIVE))
        elif args.command == 'launch-preflight':
            result = updater.preflight()
        elif args.command == 'apply':
            result = updater.apply()
        elif args.command == 'recover-boot':
            updater.idle()
            updater.rollback(boot=True)
            result = {'message': 'Boot recovery complete'}
        elif args.command == 'confirm':
            result = updater.confirm()
        elif args.command == 'rollback':
            result = updater.explicit_rollback()
        else:
            state = updater.load()
            state['pending'] = None
            updater.save(state)
            result = {'message': 'Pending update cancelled'}
        print(json.dumps(result))

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps({'error': str(error)[:512]}))
        sys.exit(1)
