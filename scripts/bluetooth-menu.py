#!/usr/bin/env python3
"""Guided BlueZ pairing with one live agent; never filter by controller brand."""
import argparse
import re
import subprocess
import time
import pexpect
from pathlib import Path

ANSI = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')
MAC = r'(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'


def clean(text):
    return ANSI.sub('', text).replace('\r', '')


def ctl(*args):
    result = subprocess.run(['bluetoothctl', '--timeout', '12', *args],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=16)
    return clean(result.stdout)


def valid_mac(address):
    if not re.fullmatch(MAC, address):
        raise ValueError('Invalid Bluetooth address')
    return address.upper()


def properties(address):
    props = backend().device(address)[1]
    return {key: 'yes' if props.get(key) else 'no' for key in ('Paired', 'Trusted', 'Connected')}


class BlueZ:
    """One system-bus connection and one bulk snapshot, never N CLI timeouts."""
    def __init__(self, bus=None):
        import dbus
        self.dbus = dbus
        self.bus = bus or dbus.SystemBus(private=True)
        self.scanning = False
        self.adapter = None

    def interface(self, path, name):
        return self.dbus.Interface(self.bus.get_object('org.bluez', path, introspect=False), name)

    def objects(self):
        try:
            return self.interface('/', 'org.freedesktop.DBus.ObjectManager').GetManagedObjects(timeout=5)
        except self.dbus.DBusException as error:
            raise RuntimeError('Bluetooth service unavailable: ' + error.get_dbus_name()) from None

    def rows(self):
        result = []
        objects=self.objects()
        adapters=[interfaces['org.bluez.Adapter1'] for interfaces in objects.values() if 'org.bluez.Adapter1' in interfaces]
        if not adapters:
            raise RuntimeError('No Bluetooth adapter found. Check Adapter status in the recovery console.')
        self.powered=any(p.get('Powered') for p in adapters)
        for path, interfaces in objects.items():
            p = interfaces.get('org.bluez.Device1')
            if not p or not re.fullmatch(MAC, str(p.get('Address', ''))):
                continue
            result.append(dict(id=str(p['Address']).upper(), address=str(p['Address']).upper(),
                               name=str(p.get('Alias') or p.get('Name') or p['Address'])[:80],
                               detail='Paired' if p.get('Paired') else 'Not paired',
                               paired=bool(p.get('Paired')), trusted=bool(p.get('Trusted')),
                               connected=bool(p.get('Connected')), ready=bool(p.get('ServicesResolved'))))
        return sorted(result, key=lambda item: (not item['connected'], not item['paired'], item['name']))[:64]

    def device(self, address):
        address = valid_mac(address)
        for path, interfaces in self.objects().items():
            props = interfaces.get('org.bluez.Device1', {})
            if str(props.get('Address', '')).upper() == address:
                return str(path), props
        raise ValueError('Device is no longer available. Scan again.')

    def prepare(self):
        subprocess.run(['sudo', '-n', 'systemctl', 'start', 'bluetooth.service'], check=True, timeout=8)
        subprocess.run(['sudo', '-n', 'rfkill', 'unblock', 'bluetooth'], check=True, timeout=5)
        adapters = [(str(path), p['org.bluez.Adapter1']) for path, p in self.objects().items() if 'org.bluez.Adapter1' in p]
        if not adapters:
            raise RuntimeError('No Bluetooth adapter found. Check Adapter status in the recovery console.')
        self.adapter = next((path for path, p in adapters if p.get('Powered')), adapters[0][0])
        # introspect=False means dbus-python cannot infer Properties.Set's ssv.
        # Explicitly wrap the Boolean in a variant, otherwise it sends ssb.
        props = self.interface(self.adapter, 'org.freedesktop.DBus.Properties')
        try:
            for key in ('Powered', 'Pairable'):
                props.Set('org.bluez.Adapter1', key, self.dbus.Boolean(True, variant_level=1), timeout=5)
        except self.dbus.DBusException as error:
            raise RuntimeError('Bluetooth radio unavailable: '+error.get_dbus_name()) from None

    def scan(self, progress=None, seconds=10):
        self.prepare()
        adapter = self.interface(self.adapter, 'org.bluez.Adapter1')
        try:
            adapter.StartDiscovery(timeout=5); self.scanning = True
        except self.dbus.DBusException as error:
            raise RuntimeError('Discovery failed: '+error.get_dbus_name()) from None
        try:
            deadline = time.monotonic() + seconds
            while time.monotonic() < deadline:
                rows = self.rows()
                if progress:
                    progress(rows, 'Scanning Bluetooth… %d device(s)' % len(rows))
                time.sleep(min(1, max(0, deadline-time.monotonic())))
            return self.rows()
        finally:
            self.stop_scan()

    def stop_scan(self):
        if self.scanning:
            self.scanning = False
            try:
                self.interface(self.adapter, 'org.bluez.Adapter1').StopDiscovery(timeout=3)
            except self.dbus.DBusException:
                pass

    def operate(self, address, action):
        path, _ = self.device(address)
        try:
            if action == 'forget':
                adapter = str(self.objects()[path]['org.bluez.Device1']['Adapter'])
                self.interface(adapter, 'org.bluez.Adapter1').RemoveDevice(self.dbus.ObjectPath(path), timeout=5)
            else:
                if action == 'connect':
                    self.interface(path, 'org.freedesktop.DBus.Properties').Set('org.bluez.Device1', 'Trusted', self.dbus.Boolean(True, variant_level=1), timeout=5)
                if action != 'connect' or not self.device(address)[1].get('Connected'):
                    getattr(self.interface(path, 'org.bluez.Device1'), 'Connect' if action == 'connect' else 'Disconnect')(timeout=20 if action == 'connect' else 5)
        except self.dbus.DBusException as error:
            raise RuntimeError('Bluetooth %s failed: %s. Wake the device and retry.' % (action, error.get_dbus_name())) from None

    def close(self):
        self.stop_scan()
        self.bus.close()


_backend = None
def backend():
    global _backend
    if _backend is None:
        _backend = BlueZ()
    return _backend


def devices(text):
    # Names are presentation only; commands always use the separately validated MAC.
    return [(m.group(1).upper(), m.group(2).strip()) for m in
            re.finditer(r'^Device (' + MAC + r') (.+)$', clean(text), re.M)]


class Agent:
    def __init__(self, executable='bluetoothctl'):
        self.child = pexpect.spawn(executable, ['--agent', 'KeyboardDisplay'], encoding='utf-8',
                                   codec_errors='replace', timeout=12, echo=False)
        try:
            self.child.expect(r'Agent registered|Agent is already registered')
            self.child.sendline('default-agent')
            self.child.expect('Default agent request successful')
        except pexpect.ExceptionPexpect:
            self.child.terminate(force=True)
            raise

    def pair(self, address, answer=input):
        self.child.sendline('pair ' + valid_mac(address))
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            event = self.child.expect([
                'Pairing successful', r'Failed to pair:[^\r\n]*',
                r'\[agent\][^\r\n]*[:?]', pexpect.EOF, pexpect.TIMEOUT,
            ], timeout=max(1, deadline - time.monotonic()))
            if event == 0:
                return True
            if event == 1:
                print(clean(self.child.after))
                return False
            if event == 2:
                prompt = clean(self.child.after)
                response = answer(prompt + ' ').strip()
                # BlueZ validates PIN/passkey format; never log input or cache it.
                self.child.sendline(response)
                continue
            print('Pairing timed out or the Bluetooth agent stopped. Put the device back in pairing mode.')
            return False
        return False

    def close(self):
        if self.child.isalive():
            self.child.sendline('quit')
            try:
                self.child.expect(pexpect.EOF, timeout=3)
            except pexpect.TIMEOUT:
                self.child.terminate(force=True)


def select_device(items, ask=input):
    if not items:
        print('No devices found. Check pairing mode, then scan again.')
        return None
    for i, (address, name) in enumerate(items, 1):
        print(f'  {i}) {name} [{address}]')
    value = ask('Device number (Enter cancels): ').strip()
    if value.isdecimal() and 1 <= int(value) <= len(items):
        return items[int(value) - 1][0]
    return None


def ready():
    backend().prepare()


def connect(address):
    backend().operate(address, 'connect')
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        _, state = backend().device(address)
        if state.get('Connected') and state.get('Trusted') and state.get('ServicesResolved'):
            controller=state.get('Icon')=='input-gaming'
            nodes=[] if controller else [True]
            if controller:
                for path in Path('/sys/class/input').glob('event*/device/uniq'):
                    try:
                        if path.read_text(errors='replace').strip().upper()==address.upper(): nodes.append(path)
                    except OSError:
                        continue
            if nodes:
                print('Connected, trusted and services ready'+('; controller input present.' if controller else '.')); return True
        time.sleep(.5)
    print('Pairing is saved, but connection/services are not ready. Wake the device and use Reconnect.')
    return False


def pair_device(airpods=False):
    ready()
    print('Put the device in pairing mode. Examples:')
    print('  PS4: SHARE + PS; PS5: CREATE + PS; Xbox: pairing button; Switch Pro: SYNC.')
    print('  AirPods: open the case and activate its setup control until the light flashes white.')
    print('Controllers, headphones, keyboards and mice all appear in the same list.')
    agent = Agent()
    try:
        print('Scanning for 10 seconds…')
        rows = backend().scan(lambda rows, status: print(status, flush=True))
        address = select_device([(item['address'], item['name']) for item in rows])
        if not address:
            return False
        if properties(address).get('Paired') != 'yes':
            if not agent.pair(address) or properties(address).get('Paired') != 'yes':
                print('Pairing was not completed. No bond was removed automatically.')
                return False
        if not connect(address):
            return False
        if airpods:
            subprocess.run(['airpods-mode', 'low-latency'], check=True)
        print('Pairing saved. Test input/audio; connection alone does not prove every device feature.')
        return True
    finally:
        backend().stop_scan()
        agent.close()


def saved():
    return [(item['address'], item['name']) for item in backend().rows() if item['paired']]


def status():
    print(ctl('show'))
    subprocess.run(['rfkill'])
    subprocess.run(['sudo', 'journalctl', '-u', 'bluetooth.service', '-n', '15', '--no-pager'])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pair', action='store_true')
    parser.add_argument('--airpods', action='store_true')
    args = parser.parse_args()
    if args.pair:
        return 0 if pair_device(args.airpods) else 1
    while True:
        print('\033[40m\033[1;31m\nBLUETOOTH • CONTROLLERS & AUDIO\033[0;31m')
        print('1) Scan & pair any device\n2) Reconnect saved device\n3) Disconnect device\n4) Forget device\n5) AirPods audio mode\n6) Adapter status & errors\n0) Back')
        choice = input('Choose: ').strip()
        try:
            if choice == '0':
                return 0
            if choice == '1':
                pair_device()
            elif choice in ('2', '3', '4'):
                ready()
                address = select_device(saved())
                if address:
                    if choice == '2':
                        agent = Agent()
                        try:
                            connect(address)
                        finally:
                            agent.close()
                    elif choice == '3':
                        backend().operate(address, 'disconnect')
                    elif input('Forget this device and its saved pairing? Type yes: ').strip().lower() == 'yes':
                        backend().operate(address, 'forget')
            elif choice == '5':
                mode = input('1) Low latency  2) Quality: ').strip()
                if mode in ('1', '2'):
                    subprocess.run(['airpods-mode', 'low-latency' if mode == '1' else 'quality'], check=True)
            elif choice == '6':
                status()
        except (RuntimeError, subprocess.SubprocessError, pexpect.ExceptionPexpect) as error:
            print(f'Bluetooth error: {error}')
        input('Press Enter to continue...')


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (KeyboardInterrupt, EOFError):
        print('\nCancelled.')
        raise SystemExit(130)
    except (RuntimeError, subprocess.SubprocessError, pexpect.ExceptionPexpect) as error:
        print(f'Bluetooth error: {error}')
        raise SystemExit(1)
