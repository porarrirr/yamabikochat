#!/usr/bin/env python3
"""Exercise the real bootstrap with local release archives and a fake transport."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

SCRIPTS = Path(__file__).resolve().parent


class NodeMobileBootstrapTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.ios = self.root / 'ios'
        (self.ios / 'scripts').mkdir(parents=True)
        for name in ('bootstrap-node-mobile.sh', 'build-cache.py'):
            shutil.copy2(SCRIPTS / name, self.ios / 'scripts' / name)
        self.license = self.root / 'third_party/nodejs-mobile/LICENSE'
        self.license.parent.mkdir(parents=True)
        self.license.write_text('test composite license\n')
        self.archive = self.root / 'release.zip'
        self.calls = self.root / 'downloads'
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        curl = self.bin / 'curl'
        curl.write_text('''#!/bin/bash
set -eu
printf 'download\\n' >> "$TEST_DOWNLOADS"
while [[ "$1" != --output ]]; do shift; done
cp "$TEST_ARCHIVE" "$2"
''')
        curl.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                        TEST_ARCHIVE=str(self.archive), TEST_DOWNLOADS=str(self.calls))
        self.framework = self.ios / 'Vendor/NodeMobile.xcframework'
        self.binary = self.framework / 'ios-arm64/NodeMobile.framework/NodeMobile'
        self.release()

    def release(self, version='24.22.1', simulator=True):
        with zipfile.ZipFile(self.archive, 'w') as archive:
            for arch in (['ios-arm64', 'ios-arm64-simulator'] if simulator else ['ios-arm64']):
                archive.writestr(f'NodeMobile.xcframework/{arch}/NodeMobile.framework/NodeMobile',
                                 f'fixture binary\nv{version}\n')
            archive.writestr('LICENSE', self.license.read_text())
        self.manifest = dict(nodeVersion='24.22.1',
                             archiveURL='https://github.com/porarrirr/nodejs-mobile/releases/download/test/runtime.zip',
                             archiveSHA256=hashlib.sha256(self.archive.read_bytes()).hexdigest())
        self.save_manifest()

    def save_manifest(self):
        (self.ios / 'node-mobile-release.json').write_text(json.dumps(self.manifest))

    def run_bootstrap(self, success=True):
        result = subprocess.run(['bash', str(self.ios / 'scripts/bootstrap-node-mobile.sh')],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def test_upgrade_reuse_and_modified_binary_repair(self):
        self.binary.parent.mkdir(parents=True)
        self.binary.write_text('v24.18.0\n')
        self.run_bootstrap()
        self.assertIn('v24.22.1', self.binary.read_text())
        self.run_bootstrap()
        self.assertEqual(self.calls.read_text().count('download'), 1)
        original = self.binary.stat()
        self.binary.write_text(self.binary.read_text().replace('24.22.1', '24.18.0'))
        os.utime(self.binary, ns=(original.st_atime_ns, original.st_mtime_ns))
        self.run_bootstrap()
        self.assertEqual(self.calls.read_text().count('download'), 2)
        self.assertIn('v24.22.1', self.binary.read_text())

    def test_checksum_failure_preserves_previous_framework(self):
        self.binary.parent.mkdir(parents=True)
        self.binary.write_text('old runtime')
        self.manifest['archiveSHA256'] = '0' * 64
        self.save_manifest()
        result = self.run_bootstrap(False)
        self.assertIn('checksum mismatch', result.stderr)
        self.assertEqual(self.binary.read_text(), 'old runtime')
        self.assertFalse((self.ios / 'Vendor/node-mobile-cache.json').exists())

    def test_wrong_runtime_version_rejected(self):
        self.release(version='24.18.0')
        self.run_bootstrap(False)
        self.assertFalse(self.framework.exists())

    def test_missing_simulator_slice_rejected(self):
        self.release(simulator=False)
        self.run_bootstrap(False)
        self.assertFalse(self.framework.exists())

    def test_updated_release_identity_invalidates_cache(self):
        self.run_bootstrap()
        self.manifest['archiveURL'] = self.manifest['archiveURL'].replace('/test/', '/new-release/')
        self.save_manifest()
        self.run_bootstrap()
        self.assertEqual(self.calls.read_text().count('download'), 2)

    def test_license_mismatch_rejected(self):
        self.license.write_text('outdated license')
        self.run_bootstrap(False)
        self.assertFalse(self.framework.exists())


if __name__ == '__main__':
    unittest.main()
