#!/usr/bin/env python3
"""Mock nmcli commands; never change host networking or prompt for real secrets."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

UUID='11111111-2222-3333-4444-555555555555'
MENU=Path(__file__).with_name('wifi-menu.sh').resolve()
class WifiMenuTest(unittest.TestCase):
    def run_menu(self,inputs,fail=False,active=True):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);log=root/'calls.jsonl'
            (root/'nmcli').write_text('''#!/usr/bin/env python3
import json,os,sys
with open(os.environ['CALL_LOG'],'a') as f:f.write(json.dumps(sys.argv[1:])+'\\n')
a=sys.argv[1:]
if 'modify' in a and os.environ.get('FAIL_MODIFY')=='1':sys.exit(1)
if '-g' in a:print('Shared router: name')
elif '--active' in a:
 if os.environ.get('HAS_ACTIVE')=='1':print('11111111-2222-3333-4444-555555555555:802-11-wireless')
elif 'TYPE' in ','.join(a):print('11111111-2222-3333-4444-555555555555:802-11-wireless')
''')
            (root/'sudo').write_text('#!/bin/sh\n[ "$1" = -n ] && shift\nexec "$@"\n')
            (root/'clear').write_text('#!/bin/sh\nexit 0\n')
            for f in root.iterdir():f.chmod(0o755)
            env=dict(os.environ,PATH=str(root)+os.pathsep+os.environ['PATH'],CALL_LOG=str(log),FAIL_MODIFY='1' if fail else '0',HAS_ACTIVE='1' if active else '0')
            result=subprocess.run(['bash',str(MENU)],input=inputs,text=True,capture_output=True,env=env,timeout=5)
            return result.stdout,[json.loads(line) for line in log.read_text().splitlines()]
    def test_automatic_band_keeps_live_connection(self):
        output,calls=self.run_menu('3\n\n0\n')
        modify=next(c for c in calls if 'modify' in c)
        self.assertIn('uuid',modify);self.assertIn(UUID,modify)
        self.assertEqual(modify[-4:],['802-11-wireless.band','','802-11-wireless.bssid',''])
        self.assertFalse(any('down' in c or 'up' in c for c in calls))
        self.assertIn('current connection was left running',output)
    def test_failed_save_does_not_report_success_or_disconnect(self):
        output,calls=self.run_menu('3\n\n0\n',fail=True)
        self.assertNotIn('selection saved',output)
        self.assertIn('Could not save',output)
        self.assertFalse(any('down' in c for c in calls))
    def test_5ghz_only_requires_confirmation(self):
        output,calls=self.run_menu('2\nno\n\n0\n')
        self.assertFalse(any('modify' in c for c in calls))
        _,calls=self.run_menu('2\nyes\n\n0\n')
        self.assertEqual(next(c for c in calls if 'modify' in c)[-3],'a')
    def test_saved_disconnected_profile_can_be_recovered(self):
        output,calls=self.run_menu('3\n1\n\n0\n',active=False)
        self.assertIn('No active Wi-Fi',output)
        self.assertTrue(any('modify' in c and UUID in c for c in calls))
    def test_reconnect_prompts_and_never_explicitly_takes_link_down(self):
        _,calls=self.run_menu('5\n\n0\n')
        activation=next(c for c in calls if 'up' in c)
        self.assertIn('--ask',activation);self.assertIn(UUID,activation)
        self.assertFalse(any('down' in c for c in calls))

if __name__=='__main__':unittest.main()
