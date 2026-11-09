#!/usr/bin/env python3
"""Run as the deployment owner; keep backups private and copy them off-server."""
from datetime import datetime, timezone
from pathlib import Path
import os
import sqlite3
import tarfile
import tempfile

root = Path(__file__).resolve().parents[1]
database = root / 'data/database/management.sqlite'
key = root / 'data/storage/app/private/config-signing.key'
environment = root / 'deploy/.env'
if not all(path.is_file() for path in (database, key, environment)):
    raise SystemExit('Private application data is incomplete; backup stopped.')
os.umask(0o077)
destination = root / 'backups'
destination.mkdir(mode=0o700, exist_ok=True)
timestamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
archive = destination / f'management-{timestamp}.tar.gz'
with tempfile.TemporaryDirectory(dir=destination) as temporary:
    snapshot = Path(temporary) / 'management.sqlite'
    with sqlite3.connect(f'file:{database}?mode=ro', uri=True) as source:
        with sqlite3.connect(snapshot) as output:
            source.backup(output)
            if output.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                raise SystemExit('Database integrity check failed.')
    with tarfile.open(archive, 'x:gz') as tar:
        tar.add(snapshot, arcname='management.sqlite')
        tar.add(key, arcname='config-signing.key')
        tar.add(environment, arcname='deployment.env')
        for name in ['release-tools/uploads.json', 'release-state', 'release-receipts']:
            path = root / name
            if path.exists():
                tar.add(path, arcname=name)
archive.chmod(0o600)
print('Private management backup created.')
