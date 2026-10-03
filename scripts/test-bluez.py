#!/usr/bin/env python3
"""Hardware-free bulk enumeration, discovery lifecycle and readiness tests."""
import importlib.util
from pathlib import Path
import types
import sys
try:
    import pexpect
except ImportError:
    sys.modules["pexpect"]=types.SimpleNamespace()
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('bt',Path(__file__).with_name('bluetooth-menu.py'))
bt=importlib.util.module_from_spec(spec);spec.loader.exec_module(bt)
class Error(Exception):
    def get_dbus_name(self):return 'org.bluez.Error.NotReady'

class BlueZTest(unittest.TestCase):
    def fixture(self, count=2):
        radio=types.SimpleNamespace(StartDiscovery=lambda **kw:None,StopDiscovery=lambda **kw:None)
        objects={'/org/bluez/hci0':{'org.bluez.Adapter1':{'Powered':True}}}
        for n in range(count):
            objects['/device'+str(n)]={'org.bluez.Device1':{'Address':'AA:BB:CC:DD:EE:%02X'%n,'Alias':'Controller '+str(n),'Paired':n==0,'Connected':n==0,'Trusted':n==0,'ServicesResolved':n==0}}
        c=bt.BlueZ.__new__(bt.BlueZ);c.dbus=types.SimpleNamespace(DBusException=Error);c.scanning=False;c.adapter='/org/bluez/hci0'
        c.objects=lambda:objects;c.prepare=lambda:None;c.interface=lambda *args:radio
        return c,radio,objects
    def test_one_bulk_snapshot_no_command_per_device(self):
        c,_,objects=self.fixture(64)
        with patch.object(c,'objects',return_value=objects) as fetch,patch.object(bt,'ctl',side_effect=AssertionError('CLI should not enumerate')):
            rows=c.rows();self.assertEqual(len(rows),64);fetch.assert_called_once();self.assertTrue(rows[0]['connected'])
    def test_invalid_addresses_and_missing_name(self):
        c,_,objects=self.fixture();objects['/bad']={'org.bluez.Device1':{'Address':'--help'}}
        objects['/device1']['org.bluez.Device1'].pop('Alias');rows=c.rows();self.assertEqual(len(rows),2);self.assertEqual(rows[1]['name'],rows[1]['address'])
    def test_progress_and_owned_discovery_cleanup(self):
        c,radio,_=self.fixture();events=[]
        with patch.object(radio,'StopDiscovery') as stop,patch.object(bt.time,'monotonic',side_effect=[0,0,0,11]),patch.object(bt.time,'sleep'):
            rows=c.scan(lambda rows,status:events.append(rows));self.assertEqual(len(rows),2);self.assertEqual(len(events),1);stop.assert_called_once();self.assertFalse(c.scanning)
    def test_cancel_releases_owned_scan(self):
        c,radio,_=self.fixture()
        def cancel(*args):raise SystemExit()
        with patch.object(radio,'StopDiscovery') as stop,patch.object(bt.time,'monotonic',side_effect=[0,0]):
            with self.assertRaises(SystemExit):c.scan(cancel)
            stop.assert_called_once()
    def test_failed_scan_is_actionable(self):
        c,radio,_=self.fixture()
        with patch.object(radio,'StartDiscovery',side_effect=Error()):
            with self.assertRaisesRegex(RuntimeError,'Discovery failed'):c.scan()
            self.assertFalse(c.scanning)
    def test_foreign_device_rejected(self):
        c,_,_=self.fixture()
        with self.assertRaises(ValueError):c.device('00:11:22:33:44:55')

if __name__=='__main__':unittest.main()
