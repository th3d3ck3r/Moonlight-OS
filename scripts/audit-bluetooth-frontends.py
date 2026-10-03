#!/usr/bin/env python3
"""Exercise agent confirmations and failures through a real PTY, without radios."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch

root = Path(__file__).resolve().parents[1]
subprocess.run(['python3', str(root/'scripts/sync-frontend-payloads.py'), '--check'], check=True)
spec = importlib.util.spec_from_file_location('bt', root/'scripts/bluetooth-menu.py')
bt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bt)
compile((root/'scripts/bluetooth-menu.py').read_text(), 'bluetooth-menu.py', 'exec')
address = 'AA:BB:CC:DD:EE:01'
assert bt.devices(f'Device {address} Wireless Controller\nDevice AA:BB:CC:DD:EE:FF AirPods ✨') == [(address, 'Wireless Controller'), ('AA:BB:CC:DD:EE:FF', 'AirPods ✨')]
assert bt.select_device([], lambda _: '1') is None
assert bt.select_device([(address, 'Switch Pro')], lambda _: '1') == address
assert bt.select_device([(address, 'Xbox')], lambda _: '99') is None
for bad in [';reboot', '00:11:22', address + ' reboot']:
    try:
        bt.valid_mac(bad)
        raise AssertionError('unsafe address accepted')
    except ValueError:
        pass
with tempfile.TemporaryDirectory() as task:
    task = Path(task)
    fake = task/'bluetoothctl'
    fake.write_text('''#!/usr/bin/env python3
import os, sys
print('Agent registered', flush=True)
for line in sys.stdin:
    command=line.strip()
    if command=='default-agent': print('Default agent request successful', flush=True)
    elif command.startswith('pair '):
        if os.environ.get('PAIR_FAIL'): print('Failed to pair: org.bluez.Error.AuthenticationFailed', flush=True)
        else:
            print('[agent] Confirm passkey 123456 (yes/no):', flush=True)
            response=sys.stdin.readline().strip()
            print('Pairing successful' if response=='yes' else 'Failed to pair: org.bluez.Error.AuthenticationRejected', flush=True)
    elif command=='quit': break
''')
    fake.chmod(0o755)
    for answer, expected in [('yes', True), ('no', False)]:
        agent = bt.Agent(str(fake))
        try:
            assert agent.pair(address, lambda _: answer) is expected
        finally:
            agent.close()
        assert not agent.child.isalive()
    with patch.dict(os.environ, {'PAIR_FAIL':'1'}):
        agent = bt.Agent(str(fake))
        try:
            assert agent.pair(address) is False
        finally:
            agent.close()
    # Readiness must be actual BlueZ state, never a successful command string.
    from types import SimpleNamespace
    state={'Connected':True,'Trusted':True,'ServicesResolved':True}
    backend=SimpleNamespace(device=lambda _:('/fixture',state),operate=lambda *args:None)
    with patch.object(bt,'backend',return_value=backend), patch.object(bt,'properties',return_value={'Connected':'yes'}):
        assert bt.connect(address) is True
    state={'Connected':False,'Trusted':True,'ServicesResolved':False}
    with patch.object(bt,'backend',return_value=backend), patch.object(bt,'properties',return_value={'Connected':'no'}), patch.object(bt.time,'monotonic',side_effect=[0,0,9]), patch.object(bt.time,'sleep'):
        assert bt.connect(address) is False
    # Verify selector persistence and the launcher's exact argv/environment.
    base=task/'runtime'
    targets={'vibemis':'frontends/vibemis/AppRun', 'artemis':'frontends/artemis', 'pegasus':'frontends/pegasus/pegasus-fe', 'moonlight':'moonlight', 'cocoos':'cocoos'}
    for client, rel in targets.items():
        binary=base/rel
        binary.parent.mkdir(parents=True, exist_ok=True)
        binary.write_text('#!/usr/bin/env python3\nimport os,sys\nassert not any(k in os.environ for k in ["LD_LIBRARY_PATH","QT_PLUGIN_PATH","QML2_IMPORT_PATH","QML_IMPORT_PATH"])\nassert os.environ["LANG"]=="en_US.UTF-8"\nassert sys.argv[1:]==["argument with spaces"]\n')
        binary.chmod(0o755)
        env=dict(os.environ, MOONLIGHT_FRONTEND_BASE=str(base), QT_PLUGIN_PATH='/wrong', QML2_IMPORT_PATH='/wrong')
        subprocess.run(['bash',str(root/'scripts/frontend-launch.sh'),client,'argument with spaces'], env=env, check=True)
    assert subprocess.run(['bash',str(root/'scripts/frontend-launch.sh'),'bad']).returncode == 2
    conf=task/'client.conf'
    setter=task/'setter'
    setter.write_text('#!/bin/sh\nprintf "CLIENT=%s\\n" "$1" > "$MOONLIGHT_CLIENT_CONF"\n')
    setter.chmod(0o755)
    sudo=task/'sudo'
    sudo.write_text('#!/bin/sh\nexec "$@"\n'); sudo.chmod(0o755)
    env=dict(os.environ, PATH=str(task)+':'+os.environ['PATH'], MOONLIGHT_CLIENT_CONF=str(conf), MOONLIGHT_CLIENT_SETTER=str(setter))
    for n, client in enumerate(['vibemis','artemis','pegasus','moonlight','cocoos'],1):
        subprocess.run(['bash',str(root/'scripts/frontend-select.sh')], input=str(n)+'\n', text=True, env=env, check=True, stdout=subprocess.DEVNULL)
        assert conf.read_text()==f'CLIENT={client}\n'
    subprocess.run(['bash',str(root/'scripts/frontend-select.sh')], input='\n', text=True, env=env, check=True, stdout=subprocess.DEVNULL)
    assert conf.read_text()=='CLIENT=cocoos\n'
print('Bluetooth confirmation/rejection/connection and five frontend selection/launch fixtures passed.')
