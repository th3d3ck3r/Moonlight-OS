#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import os
import subprocess

spec = importlib.util.spec_from_file_location('signing', Path(__file__).with_name('github-sign-update.py'))
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)

class SigningPlanTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'scripts').mkdir()
        (self.root / 'scripts/system-controls.py').write_text('print("reviewed")\n')
        baseline = {'base': signing.update.BASE_ID, 'kernel': signing.update.KERNEL, 'files': {'system-controls': '0' * 64}}
        (self.root / 'baseline.json').write_text(json.dumps(baseline))
        (self.root / 'notes.md').write_text('Fix connection selection.')
        self.plan = dict(id='eclipse-testing-001', sequence=1, channel='testing', baseline='baseline.json', notes='notes.md', targets=['system-controls'])

    def check(self):
        (self.root / 'plan.json').write_text(json.dumps(self.plan))
        return signing.validate_plan('plan.json', self.root)

    def test_valid_receiving_baseline(self):
        self.assertEqual(self.check(), self.plan)

    def test_reject_frontend_without_native_pipeline(self):
        self.plan['targets'] = ['frontend']
        with self.assertRaises(ValueError): self.check()

    def test_reject_duplicates(self):
        self.plan['targets'] *= 2
        with self.assertRaises(ValueError): self.check()

    def test_reject_path_escape(self):
        self.plan['notes'] = '../notes.md'
        with self.assertRaises(ValueError): self.check()

    def test_reject_symlink_payload(self):
        file = self.root / 'scripts/system-controls.py'
        file.unlink()
        file.symlink_to(self.root / 'notes.md')
        with self.assertRaises(ValueError): self.check()

    def test_reject_different_kernel(self):
        data = json.loads((self.root / 'baseline.json').read_text())
        data['kernel'] = 'other'
        (self.root / 'baseline.json').write_text(json.dumps(data))
        with self.assertRaises(ValueError): self.check()

    def test_reject_unchanged_helper(self):
        data = json.loads((self.root / 'baseline.json').read_text())
        data['files']['system-controls'] = signing.update.digest((self.root / 'scripts/system-controls.py').read_bytes())
        (self.root / 'baseline.json').write_text(json.dumps(data))
        with self.assertRaises(ValueError): self.check()

    def test_reject_invalid_python(self):
        (self.root / 'scripts/system-controls.py').write_text('def broken(')
        with self.assertRaises(SyntaxError): self.check()

    def test_sign_verify_publish_order_and_private_key_cleanup(self):
        for name in ('make-update-package.py', 'eclipseos-update.py'):
            (self.root / 'scripts' / name).write_bytes((signing.ROOT / 'scripts' / name).read_bytes())
        self.check()
        key = self.root / 'test-only.pem'
        subprocess.run(['openssl', 'genpkey', '-algorithm', 'ED25519', '-out', str(key)], check=True)
        calls = []
        def fake_gh(*args):
            calls.append(args)
            if args[:2] == ('release', 'upload') and args[2] == self.plan['id']:
                public = Path(args[-1])
                self.assertFalse((public.parent / 'private.pem').exists())
                self.assertEqual(Path(args[-2]).stat().st_size, 64)
                self.assertNotIn('ECLIPSEOS_SIGNING_KEY', os.environ)
        environment = dict(UPDATE_PLAN='plan.json', GITHUB_REF='refs/heads/main', GITHUB_REPOSITORY=signing.REPO, GITHUB_SHA='a'*40, ECLIPSEOS_SIGNING_KEY=key.read_text(), RUNNER_TEMP=str(self.root))
        original_repo_file = signing.repo_file
        def local_file(value, root=None):
            return original_repo_file(value, self.root)
        original_validate = signing.validate_plan
        with patch.dict(os.environ, environment), patch.object(signing, 'ROOT', self.root), patch.object(signing, 'repo_file', local_file), patch.object(signing, 'validate_plan', lambda path: original_validate(path, self.root)), patch.object(signing, 'release', return_value=None), patch.object(signing, 'gh', fake_gh), patch('sys.argv', ['github-sign-update.py']):
            signing.main()
        self.assertEqual([c[:2] for c in calls], [('release','create'), ('release','upload'), ('release','edit'), ('release','create'), ('release','upload')])
        self.assertEqual(list(self.root.glob('eclipse-sign-*')), [])

if __name__ == '__main__': unittest.main()
