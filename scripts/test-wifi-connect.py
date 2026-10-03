#!/usr/bin/env python3
"""Exercise the real PTY/authentication lifecycle against disposable fake nmcli."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
try:
    import pexpect
except ImportError:
    if '--require-pty' in sys.argv:raise SystemExit('Install python3-pexpect for required PTY regression tests')
    raise SystemExit('PTY tests skipped: pexpect unavailable (source CI runs them explicitly)')
if '--require-pty' in sys.argv:sys.argv.remove('--require-pty')
spec=importlib.util.spec_from_file_location('controls',Path(__file__).with_name('system-controls.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class WifiConnectTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.fixture=self.root/'nmcli.py';self.log=self.root/'argv.json'
        self.fixture.write_text('''import json,os,sys
with open(os.environ['ARGS_FILE'],'w') as f:json.dump(sys.argv[1:],f)
mode=os.environ['CASE']
if mode=='authorization':
 print('Error: Not authorized to control networking.',flush=True);sys.exit(1)
print('Password (802-11-wireless-security.psk):',end='',flush=True)
secret=input()
if mode=='wrong':
 print('Error: rejected secret '+secret,flush=True);sys.exit(1)
print("Device 'wlp2s0' successfully activated",flush=True)
sys.exit(3 if mode=='false-success' else 0)
''')
        self.c=m.Controls.__new__(m.Controls);self.c.wifi_child=None
        self.item=dict(name='Shared router',address='AA:BB:CC:DD:EE:FF',device='wlp2s0')
        self.commands=[];self.children=[]
        self.original=pexpect.spawn
    def spawn(self,cmd,args,**kwargs):
        self.commands.append([cmd,*args])
        kwargs['env']=dict(kwargs['env'],CASE=self.case,ARGS_FILE=str(self.log))
        child=self.original(sys.executable,[str(self.fixture),*args],**kwargs)
        self.children.append(child);return child
    def connect(self,case='success',answer='PRIVATE_PASSWORD'):
        self.case=case
        with patch.object(m.pexpect,'spawn',self.spawn),patch.object(m,'answer',return_value=answer):self.c.wifi_connect(self.item)
    def test_password_stays_in_private_pty_and_connection_is_verified(self):
        self.connect()
        self.assertEqual(self.commands[0][:4],['/usr/bin/sudo','-n','/usr/bin/nmcli','--ask'])
        self.assertNotIn('PRIVATE_PASSWORD',self.log.read_text())
        self.assertIsNone(self.c.wifi_child)
        self.assertFalse(self.children[0].isalive())
    def test_secret_is_never_forwarded_in_error(self):
        with self.assertRaises(RuntimeError) as error:self.connect('wrong')
        self.assertNotIn('PRIVATE_PASSWORD',str(error.exception));self.assertIsNone(self.c.wifi_child)
    def test_authorization_error_is_not_mistaken_for_password_prompt(self):
        with self.assertRaises(RuntimeError),patch.object(m,'answer',side_effect=AssertionError('must not ask for Wi-Fi password')):
            self.case='authorization'
            with patch.object(m.pexpect,'spawn',self.spawn):self.c.wifi_connect(self.item)
        self.assertFalse(self.children[0].isalive())
    def test_success_text_with_nonzero_exit_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError,'did not complete'):self.connect('false-success')
    def test_cancel_terminates_network_child(self):
        self.case='success'
        with patch.object(m.pexpect,'spawn',self.spawn),patch.object(m,'answer',side_effect=EOFError):
            with self.assertRaises(EOFError):self.c.wifi_connect(self.item)
        self.assertIsNone(self.c.wifi_child);self.assertFalse(self.children[0].isalive())

if __name__=='__main__':unittest.main()
