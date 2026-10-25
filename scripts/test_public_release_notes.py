import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from create_update_manifest import create_manifest
from public_release_notes import validate_notes
from repair_update_package import repair_package

ROOT = Path(__file__).resolve().parents[1]
VECTORS = json.loads((ROOT / 'test/fixtures/public_release_notes.json').read_text(encoding='utf-8'))


class PublicNotesTest(unittest.TestCase):
    def test_safe_customer_notes_and_heading_cleanup(self):
        for value in VECTORS['safe']:
            self.assertTrue(validate_notes(value))
        self.assertEqual(validate_notes(VECTORS['safe'][-1]), '- Improved browsing.')

    def test_unsafe_and_verbose_notes_fail_without_echoing_content(self):
        for value in VECTORS['unsafe'] + ['', '# Version', 'x' * 161, 'x\n' * 301]:
            with self.subTest(index=len(value)):
                with self.assertRaises(ValueError) as result:
                    validate_notes(value)
                if value:
                    self.assertNotIn(value, str(result.exception))

    def test_current_and_corrected_release_notes_follow_policy(self):
        for version in ['0.8.6', '0.8.7']:
            validate_notes((ROOT / f'docs/RELEASE_NOTES_{version}.md').read_text(encoding='utf-8'))

    def test_manifest_generation_refuses_sensitive_notes(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / 'app.apk'
            apk.write_bytes(b'abc')
            metadata = "package: name='com.streamline.iptv' versionCode='27' versionName='0.8.7'\nsdkVersion:'24'\n"
            for value in VECTORS['unsafe']:
                with self.assertRaises(ValueError):
                    create_manifest(apk, metadata, 'app.apk', value)

    def test_notes_only_repair_preserves_all_metadata_and_apk_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'old.zip'
            target = Path(directory) / 'corrected.zip'
            apk = b'original signed APK bytes'
            manifest = dict(apkUrl='version.apk', sizeBytes=len(apk),
                            sha256=hashlib.sha256(apk).hexdigest(), versionCode=26,
                            versionName='0.8.6', releaseNotes=VECTORS['unsafe'][0])
            with zipfile.ZipFile(source, 'w') as archive:
                archive.writestr('update.json', json.dumps(manifest))
                archive.writestr('version.apk', apk)
                archive.writestr('Ultravpn-player.apk', apk)
            repaired = repair_package(source, target, '- Improved connectivity.')
            self.assertEqual({**manifest, 'releaseNotes': '- Improved connectivity.'}, repaired)
            with zipfile.ZipFile(target) as archive:
                self.assertEqual(archive.read('version.apk'), apk)
                self.assertEqual(archive.read('Ultravpn-player.apk'), apk)
            # A corrupted package must never be republished.
            with zipfile.ZipFile(source, 'w') as archive:
                archive.writestr('update.json', json.dumps(manifest))
                archive.writestr('version.apk', b'changed')
                archive.writestr('Ultravpn-player.apk', apk)
            with self.assertRaises(ValueError):
                repair_package(source, target, '- Improved connectivity.')


if __name__ == '__main__':
    unittest.main()
