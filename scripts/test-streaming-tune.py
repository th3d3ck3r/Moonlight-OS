#!/usr/bin/env python3
import importlib.util
import json
import os
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
        self.assertEqual(t.settings_parse(result),{'fps':'60','eclipse/accent':'7'})
        with self.assertRaises(ValueError):t.settings_parse('[General]\nfps=30\nfps=60\n')
    def test_comparison_presets_disable_both_overlays_and_restore_local_overlay(self):
        _,config,state=self.fixture()
        config.write_text(config.read_text()+'localOverlay=true\nbackgroundPath=KEEP_BACKGROUND\n')
        with patch.object(t,'idle'):
            t.tune(config,state,'balanced')
            settings=t.settings_parse(config.read_text())
            self.assertEqual(settings['showperfoverlay'],'false')
            self.assertEqual(settings['eclipse/localOverlay'],'false')
            self.assertEqual(settings['eclipse/backgroundPath'],'KEEP_BACKGROUND')
            t.tune(config,state,'restore')
        self.assertEqual(t.settings_parse(config.read_text())['eclipse/localOverlay'],'true')
        self.assertNotIn('showperfoverlay',t.settings_parse(config.read_text()))
    def test_renderer_comparison_preserves_stream_settings_and_local_overlay(self):
        _,config,state=self.fixture()
        config.write_text(config.read_text()+'localOverlay=true\n')
        with patch.object(t,'idle'):t.tune(config,state,'vulkan-test')
        settings=t.settings_parse(config.read_text())
        self.assertEqual(settings['fps'],'59')
        self.assertEqual(settings['eclipse/localOverlay'],'true')
        self.assertEqual(settings['rendererbackend'],'1')
        self.assertNotIn('showperfoverlay',settings)
    def test_group_editor_without_trailing_newline_and_duplicate_group(self):
        result=t.settings_edit('[General]\nfps=60\n[eclipse]\naccent=7',{'eclipse/localOverlay':'false'})
        self.assertIn('accent=7\nlocalOverlay=false\n',result)
        with self.assertRaises(ValueError):t.settings_parse('[eclipse]\nlocalOverlay=true\nlocalOverlay=false\n')
    def pipeline_line(self, recv=60, dec=60, pres=57, drop=3, total=60):
        return f'[BL-2546] pipeline +1000ms: recv +{recv} dec +{dec} pres +{pres} drop +{drop} queue 3 | totals recv {total} dec {total} pres {total} drop {total} | mode none'
    def test_pipeline_rates_and_egl_identity_without_raw_log_content(self):
        text="SECRET_PASSWORD=never-export\nEGLRenderer: Presentation: swap-vsync; reported swap interval: 0; fence wait: enabled\nRenderer 'EGL/GLES' with 'VAAPI' backend chosen\n"+self.pipeline_line()+'\n'+self.pipeline_line(total=120)
        result=t.pipeline_evidence(text)
        self.assertEqual(result['rates_fps'],{'received':60,'decoded':60,'presented':57})
        self.assertEqual(result['drop_percent'],5)
        self.assertEqual(result['identity']['renderer'],'EGL/GLES')
        self.assertEqual(result['identity']['reported_swap_interval'],0)
        self.assertNotIn('SECRET_PASSWORD',json.dumps(result))
    def test_pipeline_counter_reset_uses_latest_segment_and_is_bounded(self):
        text='\n'.join(self.pipeline_line(total=(i+1)*60) for i in range(130))
        self.assertEqual(len(t.pipeline_evidence(text)['samples']),120)
        result=t.pipeline_evidence(text+'\n'+self.pipeline_line(recv=30,dec=30,pres=30,drop=0,total=30))
        self.assertEqual(len(result['samples']),1)
        self.assertEqual(result['rates_fps']['presented'],30)
    def test_pipeline_reinitialization_and_invalid_lines(self):
        text="EGLRenderer: Presentation: swap-vsync; reported swap interval: 1; fence wait: enabled\nRenderer 'EGL/GLES' chosen\n"+self.pipeline_line()+"\nRenderer 'Vulkan (libplacebo)' with 'VAAPI' backend chosen\n"+self.pipeline_line(total=1)+'\n'+self.pipeline_line().replace('+1000ms','+0ms')
        result=t.pipeline_evidence(text)
        self.assertEqual(result['identity'],{'renderer':'Vulkan (libplacebo)','backend':'VAAPI'})
        self.assertEqual(len(result['samples']),1)
        self.assertEqual(t.pipeline_evidence("Renderer 'SECRET_HOST' chosen")['identity'],{})
    def test_recent_log_excludes_symlinks_and_stale_files(self):
        root,_,_=self.fixture();target=root/'secret';target.write_text('TOKEN_SECRET')
        (root/'Vibemis-1.log').symlink_to(target)
        old=root/'Vibemis-2.log';old.write_text(self.pipeline_line());os.utime(old,(100,100))
        self.assertIn('unavailable',t.recent_pipeline(root,now=1000)['status'])
        fresh=root/'Vibemis-3.log';fresh.write_text(self.pipeline_line());os.utime(fresh,(999,999))
        result=t.recent_pipeline(root,now=1000)
        self.assertEqual(result['log_age_seconds'],1)
        self.assertEqual(result['rates_fps']['presented'],57)
        self.assertNotIn('TOKEN_SECRET',json.dumps(result))
    def test_capture_excludes_prior_stream_samples_and_preserves_renderer_identity(self):
        root,_,_=self.fixture();log=root/'Vibemis-4.log'
        log.write_text("Renderer 'EGL/GLES' with 'VAAPI' backend chosen\n"+self.pipeline_line()+'\n')
        positions=t.pipeline_log_positions(root)
        self.assertEqual(t.recent_pipeline(root,positions=positions)['samples'],[])
        with log.open('a') as out:out.write(self.pipeline_line(pres=59,drop=1,total=120)+'\n')
        result=t.recent_pipeline(root,positions=positions)
        self.assertEqual(len(result['samples']),1)
        self.assertEqual(result['rates_fps']['presented'],59)
        self.assertEqual(result['identity']['renderer'],'EGL/GLES')
    def test_diagnostic_launch_is_child_only_and_uses_existing_preflight_launcher(self):
        before=dict(os.environ)
        with patch.object(t,'idle'),patch.object(t.subprocess,'call',return_value=7) as call:
            self.assertEqual(t.launch_diagnostic(),7)
        args,kwargs=call.call_args
        self.assertEqual(args[0],['/usr/local/bin/moonlight-launch','vibemis'])
        self.assertEqual(kwargs['env']['VIBEMIS_PIPELINE_SAMPLER'],'1')
        self.assertEqual(dict(os.environ),before)
    def test_driver_report_filters_failed_package_errors_and_marks_missing(self):
        root,_,_=self.fixture()
        def command(args):
            if args[0]=='rpm':return 1,'mesa-libEGL 26.1-1.fc44.x86_64\npackage intel-media-driver is not installed\nSECRET_HOST TOKEN\n'
            return 1,'Unavailable'
        with patch.object(t,'command',command),patch.object(t,'recent_pipeline',return_value={'status':'fixture'}):
            report=t.diagnose(2,root,sleeper=lambda _:None)
        self.assertEqual(report['driver_packages'],{'mesa-libEGL':'26.1-1.fc44.x86_64'})
        self.assertIn('intel-media-driver',report['driver_packages_unavailable'])
        self.assertNotIn('SECRET_HOST',json.dumps(report))
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
        with patch.object(t,'command',command),patch.object(t,'recent_pipeline',return_value={'status':'fixture'}):
            report=t.diagnose(2,root,sleeper=lambda _:None)
        self.assertEqual(len(report['samples']),2)
        self.assertTrue(any('--rescan' in c and 'no' in c for c in calls))
        self.assertFalse(any('restart' in c or 'modify' in c for c in calls))
        self.assertNotIn('KEEP_UNCHANGED',json.dumps(report))

if __name__=='__main__':unittest.main()
