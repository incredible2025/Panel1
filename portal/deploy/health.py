#!/usr/bin/env python3
"""Expose a small read-only operational snapshot, never backup contents or keys."""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
from urllib.parse import urlsplit


def read_json(path):
    try:
        if path.stat().st_size > 65536:
            return {}
        value = json.loads(path.read_text(encoding='utf-8'))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def collect(root, active=None):
    def service(name):
        if active:
            return active(name)
        try:
            return subprocess.run(['systemctl', 'is-active', '--quiet', name], timeout=5, capture_output=True).returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            return False

    disk_path = root / 'public/downloads'
    usage = shutil.disk_usage(disk_path if disk_path.exists() else root / 'public')
    config = read_json(root / 'release-tools/uploads.json')
    apps = {}
    for app_id, app in config.get('apps', {}).items():
        base, filename = app.get('publicBaseUrl', ''), app.get('stableApkName', '')
        uri = urlsplit(base)
        if uri.scheme == 'https' and uri.hostname and not (uri.username or uri.password or uri.query or uri.fragment) and filename.endswith('.apk') and '/' not in filename and '\\' not in filename:
            apps[app_id] = {'downloadUrl': base.rstrip('/') + '/' + filename}
    return dict(schemaVersion=1, capturedAt=datetime.now(timezone.utc).isoformat(),
                disk=dict(freeBytes=usage.free, totalBytes=usage.total),
                backup=read_json(root / 'release-state/backup-status.json'),
                services={key: service(unit) for key, unit in dict(uploads='app-manager-uploads.timer', scheduler='app-manager-schedule.timer', backups='app-manager-backup.timer').items()},
                apps=apps)


def main():
    root = Path(__file__).resolve().parents[1]
    destination = root / 'release-receipts'
    temporary = destination / '.health.next'
    temporary.write_text(json.dumps(collect(root)), encoding='utf-8')
    temporary.chmod(0o640)
    os.replace(temporary, destination / 'health.json')


if __name__ == '__main__':
    main()
