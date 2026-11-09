import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from publish_uploaded_android import publish, process_queue


@unittest.skipIf(__import__('os').name == 'nt', 'Server publication uses Linux flock and symlinks')
class UploadedAndroidTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        for name in ('inbox', 'state', 'app', 'other'):
            (self.base / name).mkdir()
        self.config = dict(inbox=str(self.base / 'inbox'), stateDirectory=str(self.base / 'state'),
                           apps={'fixture': dict(directory=str(self.base / 'app'),
                                                 packageId='com.example.fixture', stableApkName='Player.apk')})
        (self.base / 'other' / 'keep.zip').write_bytes(b'other brand')
        self.root = self.base / 'app'

    def job(self, code, *, package='com.example.fixture', extra=None):
        apk = self.base / 'sample.apk'
        with zipfile.ZipFile(apk, 'w') as archive:
            archive.writestr('AndroidManifest.xml', b'test binary manifest')
            archive.writestr('classes.dex', str(code))
        content = apk.read_bytes()
        version = f'1.0.{code}'
        manifest = dict(schemaVersion=1, applicationId=package, versionName=version, versionCode=code,
                        apkUrl=f'player-{version}.apk', sha256=hashlib.sha256(content).hexdigest(),
                        sizeBytes=len(content), releaseNotes='- Improved playback.\n- Improved navigation.')
        bundle = self.base / 'inbox' / f'upload-{code}.zip'
        with zipfile.ZipFile(bundle, 'w') as archive:
            archive.writestr('Player.apk', content)
            archive.writestr(manifest['apkUrl'], content)
            archive.writestr('update.json', json.dumps(manifest))
            if extra:
                archive.writestr(extra, b'bad')
        return dict(appId='fixture', bundle=bundle.name, sha256=hashlib.sha256(bundle.read_bytes()).hexdigest())

    def test_success_cleans_upload_and_keeps_two_releases_and_stable_link(self):
        for code in (1, 2, 3):
            publish(self.config, self.job(code))
        self.assertFalse((self.root / '1.0.1-1').exists())
        self.assertFalse((self.root / 'player-1.0.1.apk').exists())
        self.assertTrue((self.root / '1.0.2-2').exists())
        self.assertTrue((self.root / '1.0.3-3').exists())
        self.assertEqual((self.root / 'Player.apk').resolve().parent.name, '1.0.3-3')
        self.assertEqual(json.loads((self.root / 'update.json').read_text())['versionCode'], 3)
        self.assertEqual((self.root / 'update.json').stat().st_mode & 0o777, 0o644)
        self.assertEqual(list((self.base / 'inbox').iterdir()), [])
        self.assertEqual((self.base / 'other/keep.zip').read_bytes(), b'other brand')

    def test_invalid_and_cross_brand_uploads_retain_upload_and_active_release(self):
        publish(self.config, self.job(1))
        for job in (self.job(2, package='com.wrong.brand'), self.job(3, extra='../escape'),
                    {**self.job(4), 'sha256': '0' * 64}):
            with self.assertRaises(ValueError):
                publish(self.config, job)
            self.assertTrue((self.base / 'inbox' / job['bundle']).exists())
        self.assertEqual(json.loads((self.root / 'update.json').read_text())['versionCode'], 1)
        self.assertFalse((self.base / 'escape').exists())

    def test_promotion_failure_restores_links_and_feed_and_keeps_upload(self):
        publish(self.config, self.job(1))
        job = self.job(2)
        def fail():
            raise OSError('simulated feed failure')
        with self.assertRaises(OSError):
            publish(self.config, job, after_links=fail)
        self.assertEqual((self.root / 'Player.apk').resolve().parent.name, '1.0.1-1')
        self.assertEqual(json.loads((self.root / 'update.json').read_text())['versionCode'], 1)
        self.assertTrue((self.base / 'inbox' / job['bundle']).exists())
        # Retry the exact completed upload without rebuilding or replacing native bytes.
        publish(self.config, job)
        self.assertEqual(json.loads((self.root / 'update.json').read_text())['versionCode'], 2)

    def test_public_zip_protects_old_release_and_unknown_files_are_untouched(self):
        publish(self.config, self.job(1))
        zip_file = self.root / '1.0.1-1' / 'public-download.zip'
        zip_file.write_bytes(b'existing published zip')
        public_link = self.root / 'public-download.zip'
        public_link.symlink_to('1.0.1-1/public-download.zip')
        self.config['protectedArtifacts'] = [str(public_link)]
        (self.root / 'unknown').mkdir()
        for code in (2, 3):
            publish(self.config, self.job(code))
        self.assertEqual(public_link.read_bytes(), b'existing published zip')
        self.assertTrue((self.root / 'unknown').exists())

    def test_queue_waits_for_ready_marker_and_retains_failed_upload(self):
        good = self.job(1)
        process_queue(self.config)
        self.assertFalse((self.root / 'update.json').exists())
        marker = self.base / 'inbox' / 'release.ready.json'
        marker.write_text(json.dumps(good))
        process_queue(self.config)
        self.assertFalse(marker.exists())
        self.assertFalse((self.base / 'inbox' / good['bundle']).exists())
        bad = self.job(2, package='com.wrong.brand')
        marker.write_text(json.dumps(bad))
        process_queue(self.config)
        self.assertTrue(marker.with_suffix('.failed').exists())
        self.assertTrue((self.base / 'inbox' / bad['bundle']).exists())

    def test_downgrades_and_same_build_replacements_are_rejected(self):
        publish(self.config, self.job(2))
        with self.assertRaises(ValueError):
            publish(self.config, self.job(1))
        feed = self.root / 'update.json'
        # Old uploads can have Windows line endings. An identical retry preserves bytes.
        feed.write_bytes(feed.read_bytes().replace(b'\n', b'\r\n'))
        before = feed.read_bytes()
        job = self.job(2)
        publish(self.config, job)  # Identical uploads are safe to retry.
        self.assertEqual(feed.read_bytes(), before)
        job = self.job(2)
        path = self.base / 'inbox' / job['bundle']
        with zipfile.ZipFile(path) as archive:
            files = {name: archive.read(name) for name in archive.namelist()}
        manifest = json.loads(files['update.json'])
        manifest['releaseNotes'] = '- Improved navigation.\n- Improved playback.'
        files['update.json'] = json.dumps(manifest).encode()
        with zipfile.ZipFile(path, 'w') as archive:
            for name, content in files.items():
                archive.writestr(name, content)
        job['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        with self.assertRaises(ValueError):
            publish(self.config, job)

    def test_retiring_release_does_not_interrupt_an_already_open_download(self):
        publish(self.config, self.job(1))
        with (self.root / 'Player.apk').open('rb') as downloading:
            expected = downloading.read()
            downloading.seek(0)
            for code in (2, 3):
                publish(self.config, self.job(code))
            self.assertEqual(downloading.read(), expected)

    def test_unmanaged_public_files_cannot_be_overwritten(self):
        original = self.root / 'Player.apk'
        original.write_bytes(b'keep unmanaged download')
        job = self.job(1)
        with self.assertRaises(ValueError):
            publish(self.config, job)
        self.assertEqual(original.read_bytes(), b'keep unmanaged download')
        self.assertFalse((self.root / 'update.json').exists())
        self.assertTrue((self.base / 'inbox' / job['bundle']).exists())


if __name__ == '__main__':
    unittest.main()
