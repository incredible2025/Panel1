import json
from pathlib import Path
import tempfile
import unittest

from create_windows_manifest import create_manifest


class WindowsManifestTest(unittest.TestCase):
    def test_separate_platform_feed_from_actual_installer(self):
        with tempfile.TemporaryDirectory() as folder:
            installer = Path(folder) / 'setup.exe'
            installer.write_bytes(b'MZ' + b'\0' * 100)
            result = create_manifest(installer, '0.8.8', 28, '- Added a Windows desktop edition.')
            self.assertEqual(result['applicationId'], 'com.streamline.iptv.windows')
            self.assertEqual(result['platform'], 'windows-x64')
            self.assertEqual(result['sizeBytes'], installer.stat().st_size)
            self.assertEqual(result['installerUrl'], 'Ultravpn-player-Setup-0.8.8.exe')
            self.assertEqual(result['versionCode'], 28)
            self.assertNotIn('apkUrl', result)
            json.dumps(result)

    def test_rejects_invalid_versions_installers_and_private_notes(self):
        with tempfile.TemporaryDirectory() as folder:
            installer = Path(folder) / 'setup.exe'
            installer.write_bytes(b'MZ' + b'\0' * 100)
            for version, code, notes in [('next', 28, 'Fixes'), ('0.8.8', 0, 'Fixes'),
                                         ('0.8.8', 28, 'Use provider.example.com')]:
                with self.assertRaises(ValueError):
                    create_manifest(installer, version, code, notes)
            installer.write_bytes(b'<html>' + b'\0' * 100)
            with self.assertRaises(ValueError):
                create_manifest(installer, '0.8.8', 28, 'Fixes')


if __name__ == '__main__':
    unittest.main()
