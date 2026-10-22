import json
from pathlib import Path
import tempfile
import unittest

from create_update_manifest import create_manifest


class ManifestTest(unittest.TestCase):
    def test_actual_apk_metadata_size_hash_and_unicode_notes(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / 'app.apk'
            apk.write_bytes(b'abc')
            result = create_manifest(apk, "package: name='com.streamline.iptv' versionCode='9' versionName='0.6.1'\nminSdkVersion:'24'\n",
                                     'https://example.com/app.apk', 'Fixes — TV and phones')
            self.assertEqual(result['sizeBytes'], 3)
            self.assertEqual(result['versionCode'], 9)
            self.assertEqual(result['sha256'], 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
            self.assertEqual(json.loads(json.dumps(result))['releaseNotes'], 'Fixes — TV and phones')

    def test_portable_relative_apk_filename(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / 'ultravpn-player-0.6.1.apk'
            apk.write_bytes(b'abc')
            metadata = "package: name='com.streamline.iptv' versionCode='9' versionName='0.6.1'\nminSdkVersion:'24'\n"
            self.assertEqual(create_manifest(apk, metadata, apk.name, 'Notes')['apkUrl'], apk.name)
            for url in ['../app.apk', '//other.example/app.apk', '', 'app.apk#fragment']:
                with self.subTest(url=url), self.assertRaises(ValueError):
                    create_manifest(apk, metadata, url, 'Notes')

    def test_wrong_package_and_insecure_url_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / 'app.apk'
            apk.write_bytes(b'abc')
            valid = "package: name='com.streamline.iptv' versionCode='9' versionName='0.6.1'\nsdkVersion:'24'\n"
            for badging, url in [(valid.replace('com.streamline.iptv', 'other.app'), 'https://example.com/a.apk'),
                                 (valid, 'http://example.com/a.apk'), (valid, 'https://user:pass@example.com/a.apk')]:
                with self.subTest(url=url), self.assertRaises(ValueError):
                    create_manifest(apk, badging, url, 'Notes')


if __name__ == '__main__':
    unittest.main()
