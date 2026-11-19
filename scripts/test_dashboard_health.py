import importlib.util
import json
from pathlib import Path
import sqlite3
import tarfile
import tempfile
import unittest
from unittest.mock import patch
from io import BytesIO
from contextlib import closing


def module(name):
    spec = importlib.util.spec_from_file_location('dashboard_' + name, Path(__file__).parents[1] / 'portal/deploy' / (name + '.py'))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


backup = module('backup')
health = module('health')


class DashboardHealthTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ['public/downloads', 'release-tools', 'release-state', 'data/database', 'data/storage/app/private', 'deploy']:
            (self.root / name).mkdir(parents=True, exist_ok=True)

    def test_snapshot_exposes_only_public_download_fields_and_operational_status(self):
        (self.root / 'release-tools/uploads.json').write_text(json.dumps({'apps': {'example': {
            'publicBaseUrl': 'https://updates.example.test/example', 'stableApkName': 'Player.apk',
            'certificateSha256': 'must-not-export', 'directory': '/private/path'}}}))
        result = health.collect(self.root, active=lambda name: name != 'app-manager-backup.timer',
                                download_probe=lambda *_: dict(checked=True, ok=False, reason='unavailable'),
                                certificate_probe=lambda *_: dict(checked=True, ok=True, daysRemaining=12))
        self.assertEqual(result['apps']['example']['downloadUrl'], 'https://updates.example.test/example/Player.apk')
        self.assertNotIn('must-not-export', json.dumps(result))
        self.assertNotIn('/private/path', json.dumps(result))
        self.assertFalse(result['services']['backups'])
        self.assertTrue(result['services']['uploads'])
        self.assertGreater(result['disk']['totalBytes'], 0)
        self.assertFalse(result['apps']['example']['download']['ok'])
        self.assertEqual(result['apps']['example']['certificate']['daysRemaining'], 12)

    def test_backup_records_integrity_checked_success_and_preserves_failure_history(self):
        with closing(sqlite3.connect(self.root / 'data/database/management.sqlite')) as db:
            db.execute('create table sample (id integer)')
            db.execute('insert into sample values (1)')
            db.commit()
        (self.root / 'data/storage/app/private/config-signing.key').write_bytes(b'fixture-only')
        env = self.root / 'deploy/.env'
        env.write_text('APP_KEY=fixture-only')
        self.assertEqual(backup.main(self.root), 0)
        marker = self.root / 'release-state/backup-status.json'
        before = json.loads(marker.read_text())
        self.assertTrue(before['success'])
        self.assertTrue(before['integrityVerified'])
        archive = next((self.root / 'backups').glob('*.tar.gz'))
        with tarfile.open(archive) as source:
            self.assertIn('management.sqlite', source.getnames())
            self.assertIn('config-signing.key', source.getnames())
        env.unlink()
        self.assertEqual(backup.main(self.root), 1)
        after = json.loads(marker.read_text())
        self.assertFalse(after['success'])
        self.assertEqual(after['completedAt'], before['completedAt'])

    def test_download_probe_rejects_mismatched_package_and_keeps_failures_generic(self):
        class Reply(BytesIO):
            status = 200
            headers = {'Content-Length': '99'}

        class Opener:
            def open(self, target, timeout):
                return Reply(b'{"sizeBytes":100}') if isinstance(target, str) else Reply()

        with patch.object(health.urllib.request, 'build_opener', return_value=Opener()):
            result = health.probe_download('https://updates.example.test/app', 'Player.apk')
        self.assertTrue(result['checked'])
        self.assertFalse(result['ok'])
        opener = Opener()
        with patch.object(opener, 'open', side_effect=OSError('private-data')), patch.object(health.urllib.request, 'build_opener', return_value=opener):
            result = health.probe_download('https://updates.example.test/app', 'Player.apk')
        self.assertEqual(result, {'checked': True, 'ok': False, 'reason': 'unavailable'})
        self.assertNotIn('private-data', json.dumps(result))

    def test_certificate_probe_reports_failure_without_exception_details(self):
        with patch.object(health.socket, 'create_connection', side_effect=OSError('private-data')):
            result = health.probe_certificate('https://updates.example.test/app')
        self.assertEqual(result, {'checked': True, 'ok': False})

    def test_short_lived_certificates_use_a_short_warning_window(self):
        with patch.object(health.socket, 'create_connection'), patch.object(health.ssl, 'create_default_context') as context:
            context.return_value.wrap_socket.return_value.__enter__.return_value.getpeercert.return_value = {
                'notBefore': 'Nov 19 00:00:00 2030 GMT', 'notAfter': 'Nov 26 00:00:00 2030 GMT'}
            result = health.probe_certificate('https://updates.example.test/app')
        self.assertTrue(result['ok'])
        self.assertEqual(result['warningDays'], 2)


if __name__ == '__main__':
    unittest.main()
