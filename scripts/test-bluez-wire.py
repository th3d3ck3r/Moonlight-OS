#!/usr/bin/env python3
"""Real dbus-python message serialization; no bus/radio access or daemon needed."""
import importlib.util
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch
try:
    import dbus
    import dbus.lowlevel
except ImportError:
    if '--require-dbus' in sys.argv:
        raise SystemExit('Install python3-dbus to run the required wire tests')
    raise SystemExit('Wire tests skipped: python3-dbus unavailable (source CI runs them explicitly)')
if '--require-dbus' in sys.argv:
    sys.argv.remove('--require-dbus')
try:
    import pexpect
except ImportError:
    sys.modules['pexpect']=types.SimpleNamespace()
spec=importlib.util.spec_from_file_location('bt',Path(__file__).with_name('bluetooth-menu.py'))
bt=importlib.util.module_from_spec(spec);spec.loader.exec_module(bt)

class WireTest(unittest.TestCase):
    def fixture(self):
        bluez=bt.BlueZ.__new__(bt.BlueZ)
        bluez.dbus=dbus;bluez.scanning=False;bluez.adapter=None
        self.messages=[]
        objects={'/org/bluez/hci0':{'org.bluez.Adapter1':{'Powered':False}},
                 '/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF':{'org.bluez.Device1':{'Address':'AA:BB:CC:DD:EE:FF','Adapter':'/org/bluez/hci0','Connected':False}}}
        bluez.objects=lambda:objects
        def interface(path,name):
            def method(method_name):
                def send(*args,**kwargs):
                    message=dbus.lowlevel.MethodCallMessage('org.bluez',path,name,method_name)
                    message.append(*args)  # Same signature inference as introspect=False proxies.
                    self.messages.append((method_name,str(message.get_signature()),message.get_args_list()))
                    expected={'Set':'ssv','Connect':'','Disconnect':'','RemoveDevice':'o'}[method_name]
                    if message.get_signature()!=expected:
                        raise dbus.DBusException('Wrong method signature',name='org.freedesktop.DBus.Error.UnknownMethod')
                return send
            return types.SimpleNamespace(**{key:method(key) for key in ('Set','Connect','Disconnect','RemoveDevice')})
        bluez.interface=interface
        return bluez
    def test_negative_control_reproduces_wrong_properties_signature(self):
        c=self.fixture()
        with self.assertRaises(dbus.DBusException):
            c.interface('/org/bluez/hci0','org.freedesktop.DBus.Properties').Set('org.bluez.Adapter1','Powered',dbus.Boolean(True))
        self.assertEqual(self.messages[0][1],'ssb')
    def test_radio_power_and_pairable_use_variants(self):
        c=self.fixture()
        with patch.object(bt.subprocess,'run'):c.prepare()
        self.assertEqual([(name,sig) for name,sig,_ in self.messages],[('Set','ssv'),('Set','ssv')])
        self.assertEqual([args[1] for _,_,args in self.messages],['Powered','Pairable'])
    def test_trust_uses_variant_before_connect(self):
        c=self.fixture();c.operate('AA:BB:CC:DD:EE:FF','connect')
        self.assertEqual([(n,s) for n,s,_ in self.messages],[('Set','ssv'),('Connect','')])
    def test_forget_uses_object_path_not_string(self):
        c=self.fixture();c.operate('AA:BB:CC:DD:EE:FF','forget')
        self.assertEqual(self.messages[0][1],'o')

if __name__=='__main__':unittest.main()
