#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('tune',Path(__file__).with_name('streaming-tune.py'))
t=importlib.util.module_from_spec(spec);spec.loader.exec_module(t)

class TuningTest(unittest.TestCase):
    def fixture(self):
        temp=tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup)
        root=Path(temp.name);config=root/'Vibemis.conf';state=root/'state'
        config.write_text('[General]\nfps=59\nwidth=1280\npairedHost=@ByteArray(unchanged)\n[hoststats]\ntoken=KEEP_UNCHANGED\n[eclipse]\naccent=14\n')
        return root,config,state
    def test_presets_preserve_other_sections_and_host_data(self):
        _,config,state=self.fixture()
        with patch.object(t,'idle'):t.tune(config,state,'latency')
        text=config.read_text()
        self.assertIn('pairedHost=@ByteArray(unchanged)',text);self.assertIn('token=KEEP_UNCHANGED',text);self.assertIn('accent=14',text)
        self.assertEqual(t.settings_parse(text)['videodec'],'1');self.assertEqual(t.settings_parse(text)['fps'],'60')
    def test_restore_removes_new_keys_and_keeps_unrelated_edits(self):
        _,config,state=self.fixture()
        with patch.object(t,'idle'):
            t.tune(config,state,'balanced')
            config.write_text(config.read_text().replace('accent=14','accent=3'))
            t.tune(config,state,'restore')
        data=t.settings_parse(config.read_text())
        self.assertEqual(data['fps'],'59');self.assertNotIn('vsync',data);self.assertIn('accent=3',config.read_text())
    def test_external_owned_setting_changes_are_protected(self):
        _,config,state=self.fixture()
        with patch.object(t,'idle'):
            t.tune(config,state,'latency');config.write_text(config.read_text().replace('fps=60','fps=30'))
            with self.assertRaisesRegex(ValueError,'Settings changed'):t.tune(config,state,'restore')
    def test_multiple_profiles_keep_original_snapshot(self):
        _,config,state=self.fixture()
        with patch.object(t,'idle'):
            t.tune(config,state,'balanced');t.tune(config,state,'latency');t.tune(config,state,'opengl-test');t.tune(config,state,'restore')
        self.assertEqual(t.settings_parse(config.read_text())['fps'],'59');self.assertNotIn('rendererbackend',t.settings_parse(config.read_text()))
    def test_active_frontend_rejects_tuning(self):
        _,config,state=self.fixture();old=config.read_bytes()
        with patch.object(t,'idle',side_effect=ValueError('close frontend')):
            with self.assertRaises(ValueError):t.tune(config,state,'latency')
        self.assertEqual(config.read_bytes(),old)
    def test_atomic_config_failure_can_be_retried(self):
        _,config,state=self.fixture();original=t.atomic
        def fail(path,data):
            if path==config:raise OSError('injected')
            return original(path,data)
        with patch.object(t,'idle'),patch.object(t,'atomic',fail):
            with self.assertRaises(OSError):t.tune(config,state,'latency')
        with patch.object(t,'idle'):t.tune(config,state,'balanced');t.tune(config,state,'restore')
        self.assertEqual(t.settings_parse(config.read_text())['fps'],'59')
    def test_interruption_after_config_write_preserves_restore(self):
        _,config,state=self.fixture();original=t.atomic;count=[0]
        def interrupt(path,data):
            count[0]+=1
            if count[0]==3:raise KeyboardInterrupt()
            return original(path,data)
        with patch.object(t,'idle'),patch.object(t,'atomic',interrupt):
            with self.assertRaises(KeyboardInterrupt):t.tune(config,state,'latency')
        with patch.object(t,'idle'):t.tune(config,state,'restore')
        self.assertEqual(t.settings_parse(config.read_text())['fps'],'59')
    def test_settings_editor_no_general_section_and_duplicates(self):
        result=t.settings_edit('[eclipse]\naccent=7\n',{'fps':'60'})
        self.assertEqual(t.settings_parse(result),{'fps':'60'})
        with self.assertRaises(ValueError):t.settings_parse('[General]\nfps=30\nfps=60\n')
    def test_hardware_snapshot_and_throttle_delta(self):
        root,_,_=self.fixture()
        for relative,value in {'sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq':'2300000',
            'sys/devices/system/cpu/cpu0/thermal_throttle/core_throttle_count':'3',
            'sys/class/hwmon/hwmon0/name':'coretemp','sys/class/hwmon/hwmon0/temp1_input':'92000',
            'sys/class/power_supply/BAT0/type':'Battery','sys/class/power_supply/BAT0/status':'Discharging',
            'proc/stat':'cpu  10 0 20 100 0 0 0 0\ncpu0 10 0 20 100 0 0 0 0\n'}.items():
            path=root/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(value)
        first=t.snapshot(root)
        (root/'sys/devices/system/cpu/cpu0/thermal_throttle/core_throttle_count').write_text('4')
        last=t.snapshot(root);findings=t.assess([first,last])
        self.assertTrue(any('counters increased' in x for x in findings));self.assertTrue(any('90 C' in x for x in findings));self.assertTrue(any('Battery discharging' in x for x in findings))
    def test_missing_hardware_data_never_claims_power_is_good(self):
        root,_,_=self.fixture();samples=[t.snapshot(root),t.snapshot(root)]
        findings=t.assess(samples)
        self.assertTrue(any('throttling has not been ruled out' in x for x in findings));self.assertTrue(any('unconfirmed' in x for x in findings))
    def test_diagnostics_are_bounded_and_do_not_scan_or_change_services(self):
        root,_,_=self.fixture();calls=[]
        def command(args):calls.append(args);return 1,'Unavailable'
        with patch.object(t,'command',command):
            report=t.diagnose(2,root,sleeper=lambda _:None)
        self.assertEqual(len(report['samples']),2)
        self.assertTrue(any('--rescan' in c and 'no' in c for c in calls))
        self.assertFalse(any('restart' in c or 'modify' in c for c in calls))
        self.assertNotIn('KEEP_UNCHANGED',json.dumps(report))

if __name__=='__main__':unittest.main()
