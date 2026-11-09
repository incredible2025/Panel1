import importlib.util
import json
from pathlib import Path
import sqlite3
import tarfile
import tempfile
import unittest
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
        result = health.collect(self.root, active=lambda name: name != 'app-manager-backup.timer')
        self.assertEqual(result['apps']['example']['downloadUrl'], 'https://updates.example.test/example/Player.apk')
        self.assertNotIn('must-not-export', json.dumps(result))
        self.assertNotIn('/private/path', json.dumps(result))
        self.assertFalse(result['services']['backups'])
        self.assertTrue(result['services']['uploads'])
        self.assertGreater(result['disk']['totalBytes'], 0)

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


if __name__ == '__main__':
    unittest.main()
