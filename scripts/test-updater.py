#!/usr/bin/env python3
"""Source-level updater tests using disposable roots and ephemeral signing keys only."""
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('updater', Path(__file__).with_name('eclipseos-update.py'))
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)

class UpdateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.calls = []
        self.engine = u.Updater(self.root, self.runner)
        self.private = self.root / 'private.pem'
        subprocess.run(['openssl', 'genpkey', '-algorithm', 'ED25519', '-out', str(self.private)], check=True, capture_output=True)
        key = self.engine.path(u.KEY)
        key.parent.mkdir(parents=True)
        subprocess.run(['openssl', 'pkey', '-in', str(self.private), '-pubout', '-out', str(key)], check=True, capture_output=True)
        self.engine.path('/etc/eclipseos-update/base.json').write_text(json.dumps({'base':u.BASE_ID,'kernel':u.KERNEL,'arch':'x86_64'}))
        for name, (path, mode, _) in u.TARGETS.items():
            if path:
                target = self.engine.path(path)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b'# baseline\n')
                target.chmod(mode)

    def runner(self, args):
        self.calls.append(args)
        if args[0].endswith('systemctl'):
            return b''
        return u.Updater.run(args)

    def package(self, files=None, mutation=None, archive_mutation=None, sequence=1, identifier='trial-1'):
        files = files or {'system-controls':b'print("new helper")\n'}
        entries=[]
        for name,data in files.items():
            path=u.TARGETS[name][0]
            entries.append(dict(target=name,size=len(data),sha256=u.digest(data),before_sha256=u.digest(self.engine.path(path).read_bytes()) if path else None))
        buffer=io.BytesIO()
        with tarfile.open(fileobj=buffer,mode='w:gz',format=tarfile.USTAR_FORMAT) as archive:
            for name,data in files.items():
                info=tarfile.TarInfo(name);info.size=len(data)
                if archive_mutation: archive_mutation(info)
                archive.addfile(info,io.BytesIO(data))
        bundle=buffer.getvalue()
        m=dict(schema=1,base=u.BASE_ID,id=identifier,sequence=sequence,channel='testing',source='a'*40,notes='Test only',files=entries,archive=dict(size=len(bundle),sha256=u.digest(bundle),url='https://github.com/th3d3ck3r/Moonlight-OS/releases/download/test/payload.tar.gz'))
        if mutation: mutation(m)
        raw=json.dumps(m).encode()
        manifest=self.root/'sign-input';manifest.write_bytes(raw)
        signature=self.root/'signature'
        subprocess.run(['openssl','pkeyutl','-sign','-rawin','-inkey',str(self.private),'-in',str(manifest),'-out',str(signature)],check=True,capture_output=True)
        return raw,signature.read_bytes(),bundle

    def test_stage_does_not_change_live_files_or_services(self):
        self.engine.stage(*self.package())
        self.assertEqual(self.engine.path(u.TARGETS['system-controls'][0]).read_bytes(),b'# baseline\n')
        self.assertFalse(any('systemctl' in c[0] for c in self.calls))
        self.assertEqual(self.engine.load()['pending'],'trial-1')

    def test_trial_next_launch_rolls_back(self):
        self.engine.stage(*self.package());self.engine.apply()
        self.assertTrue(self.engine.load()['trial'])
        self.engine.apply()
        self.assertEqual(self.engine.path(u.TARGETS['system-controls'][0]).read_bytes(),b'# baseline\n')
        self.assertFalse(self.engine.load()['trial'])

    def test_confirm_is_durable_and_boot_does_not_revert(self):
        self.engine.stage(*self.package());self.engine.apply();self.engine.confirm()
        self.engine.rollback(boot=True)
        self.assertIn(b'new helper',self.engine.path(u.TARGETS['system-controls'][0]).read_bytes())
        self.assertEqual(self.engine.load()['accepted']['testing'],1)
        self.assertTrue((self.engine.state_dir/'confirmed-journal.json').exists())

    def test_power_loss_after_mutation_recovers_without_network(self):
        self.engine.stage(*self.package())
        with patch.object(self.engine,'save',side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):self.engine.apply()
        self.assertTrue((self.engine.state_dir/'journal.json').exists())
        self.engine.rollback(boot=True)
        self.assertEqual(self.engine.path(u.TARGETS['system-controls'][0]).read_bytes(),b'# baseline\n')

    def test_power_loss_after_confirmation_before_journal_delete(self):
        self.engine.stage(*self.package());self.engine.apply()
        original=Path.unlink
        def fail(path,*a,**k):
            if path.name=='journal.json':raise KeyboardInterrupt()
            return original(path,*a,**k)
        with patch.object(Path,'unlink',fail):
            with self.assertRaises(KeyboardInterrupt):self.engine.confirm()
        self.engine.rollback(boot=True)
        self.assertIn(b'new helper',self.engine.path(u.TARGETS['system-controls'][0]).read_bytes())

    def test_partial_multi_file_failure_restores_every_file(self):
        self.engine.stage(*self.package({'system-controls':b'print(1)\n','control-center':b'print(2)\n'}))
        original=u.atomic
        once=[False]
        def fail(path,data,mode=0o600):
            if Path(path)==self.engine.path(u.TARGETS['control-center'][0]) and not once[0]:
                once[0]=True;raise OSError('injected disk failure')
            return original(path,data,mode)
        with patch.object(u,'atomic',fail):
            with self.assertRaises(OSError):self.engine.apply()
        for name in ('system-controls','control-center'):
            self.assertEqual(self.engine.path(u.TARGETS[name][0]).read_bytes(),b'# baseline\n')

    def test_service_restart_failure_restores_original_config(self):
        self.engine.stage(*self.package({'wifi-config':b'[connection]\nwifi.powersave=3\n'}))
        once=[False]
        original=self.engine.runner
        def fail(args):
            if 'restart' in args and not once[0]:
                once[0]=True;raise subprocess.CalledProcessError(1,args)
            return original(args)
        self.engine.runner=fail
        with self.assertRaises(subprocess.CalledProcessError):self.engine.apply()
        self.assertEqual(self.engine.path(u.TARGETS['wifi-config'][0]).read_bytes(),b'# baseline\n')

    def test_boot_recovery_never_restarts_network_services(self):
        self.engine.stage(*self.package({'wifi-config':b'[connection]\nwifi.powersave=2\n'}));self.engine.apply()
        self.calls=[];self.engine.rollback(boot=True)
        self.assertFalse(any('systemctl' in c[0] for c in self.calls))

    def test_confirmed_update_can_be_explicitly_rolled_back(self):
        self.engine.stage(*self.package());self.engine.apply();self.engine.confirm()
        self.engine.explicit_rollback()
        self.assertEqual(self.engine.path(u.TARGETS['system-controls'][0]).read_bytes(),b'# baseline\n')
        self.assertFalse(self.engine.load()['trial'])
        self.assertEqual(self.engine.load()['accepted']['testing'],1)

    def test_failed_validation_preserves_previous_rollback_snapshot(self):
        self.engine.stage(*self.package());self.engine.apply();self.engine.confirm()
        self.engine.stage(*self.package({'control-center':b'def broken(\n'},sequence=2,identifier='trial-2'))
        with self.assertRaises(SyntaxError):self.engine.apply()
        self.engine.explicit_rollback()
        self.assertEqual(self.engine.path(u.TARGETS['system-controls'][0]).read_bytes(),b'# baseline\n')

    def test_real_packager_and_signature_roundtrip(self):
        baseline=self.root/'baseline.json';baseline.write_text(json.dumps(self.engine.baseline()))
        notes=self.root/'notes.txt';notes.write_text('Fixture update')
        source=self.root/'new-helper.py';source.write_text('print(42)\n')
        output=self.root/'fixture-output'
        subprocess.run(['python3',str(Path(__file__).with_name('make-update-package.py')),
            '--id','package-roundtrip','--sequence','7','--channel','testing','--source','b'*40,
            '--notes',str(notes),'--baseline',str(baseline),'--key',str(self.private),
            '--url','https://github.com/th3d3ck3r/Moonlight-OS/releases/download/test/payload.tar.gz',
            '--file','system-controls='+str(source),'--output',str(output)],check=True,capture_output=True)
        self.engine.stage(*( (output/name).read_bytes() for name in ('manifest.json','manifest.sig','payload.tar.gz')))
        self.engine.apply();self.engine.confirm()
        self.assertEqual(self.engine.load()['accepted']['testing'],7)

    def test_apply_refuses_active_frontend_before_mutation(self):
        self.engine.stage(*self.package())
        with patch.object(self.engine,'idle',side_effect=ValueError('Close frontends')):
            with self.assertRaises(ValueError):self.engine.apply()
        self.assertFalse((self.engine.state_dir/'journal.json').exists())

    def test_no_pending_update_preserves_nested_pegasus_launch(self):
        with patch.object(self.engine,'idle',side_effect=u.FrontendBusy('Pegasus running')):
            self.assertEqual(self.engine.preflight()['message'],'No pending update.')

    def test_launch_defers_update_while_parent_frontend_runs(self):
        self.engine.stage(*self.package())
        with patch.object(self.engine,'idle',side_effect=u.FrontendBusy('Pegasus running')):
            self.assertIn('deferred',self.engine.preflight()['message'])
        self.assertEqual(self.engine.load()['pending'],'trial-1')
        self.assertFalse((self.engine.state_dir/'journal.json').exists())

    def test_exclusive_updater_lock(self):
        with self.engine.lock():
            with self.assertRaises(BlockingIOError):
                with u.Updater(self.root,self.runner).lock():pass

    def test_bad_signature(self):
        raw,sig,bundle=self.package()
        with self.assertRaises(subprocess.CalledProcessError):self.engine.stage(raw+b' ',sig,bundle)
        self.assertIsNone(self.engine.load()['pending'])

    def test_no_trusted_key_fails_closed(self):
        package=self.package();self.engine.path(u.KEY).unlink()
        with self.assertRaisesRegex(ValueError,'trusted public key'):self.engine.stage(*package)

    def test_archive_checksum_mismatch(self):
        raw,sig,bundle=self.package()
        with self.assertRaisesRegex(ValueError,'checksum'):self.engine.stage(raw,sig,bundle+b'x')

    def test_archive_traversal_link_and_duplicate_targets_rejected(self):
        for transform in (lambda i:setattr(i,'name','../outside'), lambda i:setattr(i,'type',tarfile.SYMTYPE)):
            with self.subTest(transform=transform),self.assertRaises(ValueError):self.engine.stage(*self.package(archive_mutation=transform))
        with self.assertRaises(ValueError):self.engine.stage(*self.package(mutation=lambda m:m['files'].append(m['files'][0])))

    def test_arbitrary_targets_and_kernel_rejected(self):
        for target in ('/etc/shadow','kernel','firmware','updater','../wifi-menu'):
            with self.subTest(target=target),self.assertRaises(ValueError):
                self.engine.stage(*self.package(mutation=lambda m:m['files'][0].update(target=target)))

    def test_wrong_base_rejected(self):
        with self.assertRaises(ValueError):self.engine.stage(*self.package(mutation=lambda m:m.update(base='other-os')))

    def test_local_changes_protected(self):
        package=self.package();target=self.engine.path(u.TARGETS['system-controls'][0]);target.write_bytes(b'# local changes\n')
        self.engine.stage(*package)
        with self.assertRaisesRegex(ValueError,'baseline'):self.engine.apply()
        self.assertEqual(target.read_bytes(),b'# local changes\n')

    def test_invalid_helper_syntax_does_not_mutate(self):
        self.engine.stage(*self.package({'system-controls':b'def broken(\n'}))
        with self.assertRaises(SyntaxError):self.engine.apply()
        self.assertFalse((self.engine.state_dir/'journal.json').exists())

    def test_config_scope_restricted(self):
        self.engine.stage(*self.package({'wifi-config':b'[connection]\nwifi.powersave=2\n[other]\npassword=secret\n'}))
        with self.assertRaises(ValueError):self.engine.apply()

    def test_frontend_slot_and_baseline_preserved(self):
        elf=b'\x7fELF\x02\x01'+b'\x00'*12+b'\x3e\x00'+b'fixture'
        self.engine.stage(*self.package({'frontend':elf}));self.engine.apply()
        self.assertEqual(self.engine.path('/usr/local/libexec/eclipseos/current/vibemis').read_bytes(),elf)
        self.engine.rollback(boot=True)
        self.assertFalse(self.engine.path('/usr/local/libexec/eclipseos/current').exists())

    def test_downgrade_rejected_after_confirmation(self):
        self.engine.stage(*self.package());self.engine.apply();self.engine.confirm()
        with self.assertRaisesRegex(ValueError,'sequence'):self.engine.stage(*self.package(identifier='old-sequence'))

    def test_download_destinations_restricted(self):
        for url in ('http://github.com/x','https://localhost/x','https://github.com/other/repo/releases/download/x/y','https://github.com/th3d3ck3r/Moonlight-OS/releases/download/x/y?redirect=x'):
            with self.subTest(url=url),self.assertRaises(ValueError):u.validate_url(url,initial=True)

    def test_duplicate_json_key_rejected(self):
        with self.assertRaises(ValueError):u.decode(b'{"schema":1,"schema":2}')

    def test_baseline_exports_only_hashes(self):
        baseline=self.engine.baseline()
        self.assertEqual(len(baseline['files']),len(u.TARGETS)-1)
        self.assertTrue(all(len(x)==64 for x in baseline['files'].values()))
        self.assertNotIn('private',json.dumps(baseline))

    def test_corrupt_recovery_backup_keeps_journal(self):
        self.engine.stage(*self.package());self.engine.apply()
        (self.engine.state_dir/'backup'/'system-controls').write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError,'backup checksum'):self.engine.rollback(boot=True)
        self.assertTrue((self.engine.state_dir/'journal.json').exists())

    def test_repeated_service_failure_is_recoverable_at_boot(self):
        self.engine.stage(*self.package({'wifi-config':b'[connection]\nwifi.powersave=2\n'}))
        original=self.engine.runner
        def fail(args):
            if 'restart' in args:raise subprocess.CalledProcessError(1,args)
            return original(args)
        self.engine.runner=fail
        with self.assertRaises(subprocess.CalledProcessError):self.engine.apply()
        self.assertTrue((self.engine.state_dir/'journal.json').exists())
        self.engine.rollback(boot=True)
        self.assertFalse((self.engine.state_dir/'journal.json').exists())

    def test_wrong_kernel_receipt_blocks_staging_but_not_recovery(self):
        self.engine.stage(*self.package());self.engine.apply()
        self.engine.path('/etc/eclipseos-update/base.json').write_text('{}')
        with self.assertRaises(ValueError):self.engine.compatible()
        self.engine.rollback(boot=True)
        self.assertFalse(self.engine.load()['trial'])

    def test_invalid_frontend_architecture_is_rejected(self):
        self.engine.stage(*self.package({'frontend':b'not a native executable'}))
        with self.assertRaisesRegex(ValueError,'x86_64'):self.engine.apply()
        self.assertFalse(self.engine.path('/usr/local/libexec/eclipseos/current').exists())

    def test_launcher_preserves_all_five_clients_and_arguments(self):
        for relative in ('moonlight','cocoos','frontends/artemis','frontends/vibemis/AppRun','frontends/pegasus/pegasus-fe'):
            target=self.root/relative;target.parent.mkdir(parents=True,exist_ok=True)
            target.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n');target.chmod(0o755)
        launcher=Path(__file__).with_name('frontend-launch.sh')
        env=dict(os.environ,MOONLIGHT_FRONTEND_BASE=str(self.root))
        for name in ('moonlight','cocoos','artemis','vibemis','pegasus'):
            result=subprocess.run(['bash',str(launcher),name,'two words','--flag'],env=env,capture_output=True,check=True)
            self.assertEqual(result.stdout,b'two words\n--flag\n')
        result=subprocess.run(['bash',str(launcher),'invalid'],env=env,capture_output=True)
        self.assertEqual(result.returncode,2)

    def test_symlink_input_rejected(self):
        link=self.root/'link';link.symlink_to(self.private)
        with self.assertRaises(OSError):u.read_regular(link,65536)

if __name__=='__main__':unittest.main()
