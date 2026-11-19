#!/usr/bin/env python3
"""Expose a small read-only operational snapshot, never backup contents or keys."""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import socket
import ssl
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urlsplit


def read_json(path):
    try:
        if path.stat().st_size > 65536:
            return {}
        value = json.loads(path.read_text(encoding='utf-8'))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def probe_download(base, filename):
    """Read a bounded public manifest and compare the stable APK's HEAD size."""
    opener = urllib.request.build_opener(NoRedirect)
    try:
        with opener.open(base.rstrip('/') + '/update.json', timeout=3) as response:
            data = response.read(65537)
            if len(data) > 65536:
                raise ValueError('Manifest too large')
            manifest = json.loads(data)
        expected = manifest['sizeBytes']
        if not isinstance(expected, int) or expected <= 0:
            raise ValueError('Invalid package size')
        request = urllib.request.Request(base.rstrip('/') + '/' + filename, method='HEAD')
        with opener.open(request, timeout=3) as response:
            ok = response.status == 200 and int(response.headers.get('Content-Length', '0')) == expected
        return dict(checked=True, ok=ok, reason='ok' if ok else 'size_or_status')
    except (OSError, ValueError, KeyError, TypeError, urllib.error.URLError):
        return dict(checked=True, ok=False, reason='unavailable')


def probe_certificate(base):
    uri = urlsplit(base)
    try:
        with socket.create_connection((uri.hostname, uri.port or 443), timeout=3) as connection:
            with ssl.create_default_context().wrap_socket(connection, server_hostname=uri.hostname) as secure:
                certificate = secure.getpeercert()
        expires = ssl.cert_time_to_seconds(certificate['notAfter'])
        remaining = int((expires - datetime.now(timezone.utc).timestamp()) // 86400)
        return dict(checked=True, ok=remaining >= 0, daysRemaining=remaining)
    except (OSError, ValueError, KeyError, TypeError):
        return dict(checked=True, ok=False)


def collect(root, active=None, download_probe=probe_download, certificate_probe=probe_certificate):
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
    with ThreadPoolExecutor(max_workers=4) as pool:
        downloads, certificates = {}, {}
        for app_id, app in config.get('apps', {}).items():
            base, filename = app.get('publicBaseUrl', ''), app.get('stableApkName', '')
            uri = urlsplit(base)
            if uri.scheme == 'https' and uri.hostname and not (uri.username or uri.password or uri.query or uri.fragment) and filename.endswith('.apk') and '/' not in filename and '\\' not in filename:
                apps[app_id] = {'downloadUrl': base.rstrip('/') + '/' + filename}
                downloads[app_id] = pool.submit(download_probe, base, filename)
                origin = (uri.hostname, uri.port or 443)
                if origin not in certificates:
                    certificates[origin] = pool.submit(certificate_probe, base)
                apps[app_id]['_origin'] = origin
        for app_id, result in apps.items():
            result['download'] = downloads[app_id].result()
            result['certificate'] = certificates[result.pop('_origin')].result()
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
