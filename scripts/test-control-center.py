#!/usr/bin/env python3
"""Hardware-free checks for Eclipse's local controls and power safeguards."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
spec = importlib.util.spec_from_file_location('center', Path(__file__).with_name('control-center.py'))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
class CenterTest(unittest.TestCase):
    def test_audio_sinks_parser(self):
        value = 'Audio\n ├─ Sinks:\n │ * 42. Speakers [vol: 0.50]\n │ 57. AirPods [vol: 0.70]\n ├─ Sources:\n │ 70. Mic [vol: 1.00]\nVideo\n ├─ Sinks:\n'
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
if __name__=='__main__':unittest.main()
