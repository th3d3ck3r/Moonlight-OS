#!/usr/bin/env python3
"""Hardware-free checks for Eclipse's local controls and power safeguards."""
import importlib.util
import json
import stat
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
spec = importlib.util.spec_from_file_location('center', Path(__file__).with_name('control-center.py'))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
class CenterTest(unittest.TestCase):
    def test_audio_sinks_parser(self):
        value = 'Audio\n ├─ Sinks:\n │ * 42. Speakers [vol: 0.50]\n │ 57. AirPods [vol: 0.70]\n ├─ Sources:\n │ 70. Mic [vol: 1.00]\nVideo\n ├─ Sinks:\n │ 99. Camera output\n'
        self.assertEqual(m.sinks(value), [dict(id='42',name='Speakers',default=True),dict(id='57',name='AirPods',default=False)])
    def test_brightness_fixture(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name,current,maximum in [('backlight/intel_backlight',100,200),('leds/spi::kbd_backlight',0,255)]:
                device=root/name;device.mkdir(parents=True)
                (device/'brightness').write_text(str(current));(device/'max_brightness').write_text(str(maximum))
            value=m.brightness_devices(root)
            self.assertEqual(value['screen']['percent'],50);self.assertEqual(value['keyboard']['percent'],0)
    def test_volume_bounds(self):
        for value in ['-1','101','1;reboot','nan',10,None]:
            with self.assertRaises(ValueError): m.percent(value)
    def test_power_requires_boolean_confirmation(self):
        for value in [False,None,1,'true']:
            with patch.object(m,'command') as command:
                with self.assertRaises(ValueError):m.execute(dict(action='center-poweroff',confirm=value),{})
                command.assert_not_called()
    def test_audio_output_must_be_available(self):
        with patch.object(m,'command') as command:
            with self.assertRaises(ValueError):m.execute(dict(action='center-output',id='999'),dict(sinks=[dict(id='42')]))
            command.assert_not_called()
    def test_commands_have_fixed_arguments(self):
        with patch.object(m,'command') as command,patch.object(m,'snapshot',return_value={}):
            m.execute(dict(action='center-volume',id='75'),{})
            command.assert_called_once_with(['wpctl','set-volume','-l','1','@DEFAULT_AUDIO_SINK@','75%'])
    def test_unavailable_brightness_is_not_mutated(self):
        with patch.object(m,'command') as command:
            with self.assertRaises(ValueError):m.execute(dict(action='center-screen',id='50'),{})
            command.assert_not_called()
    def test_screen_floor_and_keyboard_off(self):
        state = dict(brightness=dict(screen=dict(device='acpi_video0'), keyboard=dict(device='spi::kbd_backlight')))
        with patch.object(m,'command') as command,patch.object(m,'snapshot',return_value={}):
            m.execute(dict(action='center-screen',id='0'),state)
            command.assert_called_with(['sudo','brightnessctl','-d','acpi_video0','set','5%'])
            m.execute(dict(action='center-keyboard',id='0'),state)
            command.assert_called_with(['sudo','brightnessctl','-d','spi::kbd_backlight','set','0%'])
    def test_suspend_stays_unavailable(self):
        with patch.object(m,'command') as command:
            with self.assertRaises(ValueError):m.execute(dict(action='center-suspend',confirm=True),{})
            command.assert_not_called()
    def test_confirmed_power_arguments(self):
        with patch.object(m,'command') as command,patch.object(m,'snapshot',return_value={}):
            for action in ('reboot','poweroff'):
                m.execute(dict(action='center-'+action,confirm=True),{})
                command.assert_called_with(['sudo','systemctl',action])
    def test_report_is_private_and_redacted(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(m.Path,'home',return_value=Path(folder)),patch.object(m,'snapshot',return_value={}),patch.object(m,'brightness_devices',return_value=dict(screen=dict(device='private-device-name'))):
            m.execute(dict(action='center-report'),dict(volume=50,sinks=[dict(name='private-headphones')]))
            target=Path(folder)/'.local/state/moonlight-os/eclipse-diagnostics.json'
            data=json.loads(target.read_text())
            self.assertEqual(stat.S_IMODE(target.stat().st_mode),0o600)
            self.assertEqual(data['brightness_devices'],['screen'])
            self.assertNotIn('private-',target.read_text())
            self.assertEqual(set(data),{'kernel','brightness_devices','render_nodes','audio_available'})
    def test_report_rejects_symlink(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(m.Path,'home',return_value=Path(folder)):
            outside=Path(folder)/'keep';outside.write_text('unchanged')
            directory=Path(folder)/'.local/state/moonlight-os';directory.mkdir(parents=True)
            (directory/'eclipse-diagnostics.json').symlink_to(outside)
            with self.assertRaises(OSError):m.execute(dict(action='center-report'),{})
            self.assertEqual(outside.read_text(),'unchanged')
if __name__=='__main__':unittest.main()
