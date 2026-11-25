#!/usr/bin/env python3
"""Run as the deployment owner; keep backups private and copy them off-server."""
from datetime import datetime, timezone
from contextlib import closing
from pathlib import Path
import os
import sqlite3
import tarfile
import tempfile

import json
import sys


def status(root, values):
    folder = root / 'release-state'
    folder.mkdir(mode=0o700, exist_ok=True)
    target = folder / 'backup-status.json'
    temporary = folder / '.backup-status.next'
    temporary.write_text(json.dumps(values), encoding='utf-8')
    temporary.chmod(0o600)
    os.replace(temporary, target)


def perform_backup(root):
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
        with closing(sqlite3.connect(f'file:{database}?mode=ro', uri=True)) as source:
            with closing(sqlite3.connect(snapshot)) as output:
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
    return archive


def main(root=None):
    root = Path(root) if root is not None else Path(__file__).resolve().parents[1]
    now = datetime.now(timezone.utc).isoformat()
    previous = {}
    try:
        marker = root / 'release-state/backup-status.json'
        if marker.is_file():
            previous = json.loads(marker.read_text())
        perform_backup(root)
        status(root, dict(success=True, integrityVerified=True, completedAt=now, lastAttemptAt=now))
        print('Private management backup created.')
        return 0
    except (Exception, SystemExit):
        status(root, {**previous, 'success': False, 'lastAttemptAt': now})
        print('Management backup failed; operator inspection required.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
