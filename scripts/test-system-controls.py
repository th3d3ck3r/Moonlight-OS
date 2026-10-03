#!/usr/bin/env python3
"""Deterministic helper safety fixtures; never touch live radios."""
import importlib.util
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch
# Parsing and command-selection tests do not need a live PTY dependency.
sys.modules.setdefault('pexpect', types.SimpleNamespace(ExceptionPexpect=type('PexpectError', (Exception,), {})))
spec = importlib.util.spec_from_file_location('controls', Path(__file__).with_name('system-controls.py'))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

class ControlsTests(unittest.TestCase):
    def fixture(self):
        c = m.Controls.__new__(m.Controls)
        c.mode = 'bt'; c.items = [dict(id='AA:BB:CC:DD:EE:FF', address='AA:BB:CC:DD:EE:FF')]
        c.bt = types.SimpleNamespace(ctl=lambda *args: self.fail('Unexpected Bluetooth mutation'))
        return c
    def test_escaped_ssid_and_address(self):
        text = r'*:Cafe\:Space:AA\:BB\:CC\:DD\:EE\:FF:90:WPA2:wlan0'
        rows = m.wifi_rows(text)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['name'], 'Cafe:Space')
        self.assertTrue(rows[0]['connected'])
        self.assertEqual(m.wifi_rows(text+'\n'+text), rows)
    def test_shared_ssid_access_points_show_their_band(self):
        text=r'*:Shared:AA\:BB\:CC\:DD\:EE\:01:95:WPA2:wlan0:2412'+'\n'+r':Shared:AA\:BB\:CC\:DD\:EE\:02:90:WPA2:wlan0:5180'
        rows=m.wifi_rows(text)
        self.assertEqual(len(rows),2)
        self.assertIn('2.4 GHz',rows[0]['detail']);self.assertIn('5 GHz',rows[1]['detail'])
        self.assertNotEqual(rows[0]['id'],rows[1]['id'])
    def test_invalid_device_and_hidden_network(self):
        for line in [r'*:name:AA\:BB\:CC\:DD\:EE\:FF:50:WPA2:--help', r'*::AA\:BB\:CC\:DD\:EE\:FF:50:WPA2:wlan0']:
            self.assertEqual(m.wifi_rows(line), [])
    def test_foreign_and_unknown_selection_rejected(self):
        c = self.fixture()
        for request in [dict(action='wifi-connect', id=c.items[0]['id']), dict(action='bt-connect', id='unknown')]:
            with self.assertRaises(ValueError): c.execute(request)
    def test_forget_requires_explicit_confirmation(self):
        c = self.fixture()
        for confirm in [False, None, 'true', 1]:
            with self.assertRaises(ValueError): c.execute(dict(action='bt-forget', id=c.items[0]['id'], confirm=confirm))
    def test_disconnect_uses_cached_interface_without_shell(self):
        c = self.fixture(); c.mode = 'wifi'; c.items = [dict(id='listed', device='wlan0')]
        c.wifi_list = lambda: []
        with patch.object(m, 'run', return_value='') as run:
            c.execute(dict(action='wifi-disconnect', id='listed'))
            run.assert_called_once_with(['nmcli', 'device', 'disconnect', 'wlan0'])
    def test_credentials_reject_newline(self):
        with patch.object(m, 'emit'), patch.object(m, 'read', return_value=dict(action='answer', value='bad\ninput')):
            with self.assertRaises(ValueError): m.answer('Password')

if __name__ == '__main__': unittest.main()
