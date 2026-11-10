"""Host-side verified preparation and explicit promotion for dashboard releases."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from publish_uploaded_android import atomic_json, child, cleanup, digest, exclusive, replace_link, validate_bundle
from verify_signing_certificate import verify_certificate


def native_check(apk, manifest, brand, config):
    report = subprocess.run([config['apksigner'], 'verify', '--verbose', '--print-certs', str(apk)],
                            capture_output=True, text=True, check=True).stdout
    verify_certificate(report, brand['certificateSha256'])
    badging = subprocess.run([config['aapt'], 'dump', 'badging', str(apk)],
                             capture_output=True, text=True, check=True).stdout
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging, re.M)
    if (not package or package[1] != brand['packageId']
            or int(package[2]) != manifest['versionCode'] or package[3] != manifest['versionName']):
        raise ValueError('Native APK identity does not match this release.')


def dispatch(config, job):
    ticket = job['ticket']
    if not re.fullmatch(r'[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}', ticket):
        raise ValueError('Invalid release ticket.')
    brand = config['apps'][job['appId']]
    root = Path(brand['directory']).resolve(strict=True)
    inbox = Path(config['inbox']).resolve(strict=True)
    state = Path(config['stateDirectory']).resolve(strict=True)
    receipts = Path(config['receiptDirectory']).resolve(strict=True)
    receipt_path = child(receipts, ticket + '.json')
    with exclusive(child(state, job['appId'] + '.lock')):
        receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else {}
        if receipt and (receipt.get('appId') != job['appId'] or receipt.get('ticket') != ticket):
            raise ValueError('Release belongs to a different app.')
        try:
            operation = job['operation']
            if operation == 'adopt':
                # Operator-only import of the existing native-verified public release.
                manifest = json.loads((root / 'update.json').read_text())
                apk = root / brand['stableApkName']
                if digest(apk) != manifest['sha256'] or manifest['applicationId'] != brand['packageId']:
                    raise ValueError('Existing public release does not match its manifest.')
                native_check(apk, manifest, brand, config)
                remote = {**manifest, 'apkUrl': brand['publicBaseUrl'].rstrip('/') + '/' + manifest['apkUrl']}
                receipt = dict(ticket=ticket, appId=job['appId'], status='published', manifest=remote)
                atomic_json(receipt_path, receipt, mode=0o640)
            elif operation == 'prepare':
                bundle = child(inbox, job['bundle'])
                if receipt.get('status') in ('ready', 'published') and not bundle.exists():
                    directory = child(root, receipt['directory'])
                    if digest(directory / brand['stableApkName']) != receipt['sourceManifest']['sha256']:
                        raise ValueError('Prepared release failed verification.')
                    return
                if not bundle.name.endswith('.zip'):
                    raise ValueError('A release ZIP is required.')
                stage = Path(tempfile.mkdtemp(prefix='release-', dir=inbox))
                manifest = validate_bundle(bundle, job['sha256'], brand, stage)
                native_check(stage / brand['stableApkName'], manifest, brand, config)
                feed = root / 'update.json'
                previous = json.loads(feed.read_text()) if feed.exists() else None
                if previous and (manifest['versionCode'] <= previous['versionCode'] or manifest['apkUrl'] == previous['apkUrl']):
                    raise ValueError('Use a new Android build number and versioned filename.')
                directory = f"{manifest['versionName']}-{manifest['versionCode']}"
                destination = child(root, directory)
                if destination.exists():
                    # Two uploads cannot share a native build: each ticket owns its immutable folder.
                    if not receipt or receipt.get('directory') != directory or receipt.get('sourceManifest') != manifest:
                        raise ValueError('This native build has already been prepared.')
                else:
                    hidden = root / ('.' + ticket + '.staging')
                    if hidden.exists() or hidden.is_symlink():
                        raise ValueError('Incomplete public staging requires inspection.')
                    shutil.copytree(stage, hidden)
                    (hidden / manifest['apkUrl']).unlink()
                    os.link(hidden / brand['stableApkName'], hidden / manifest['apkUrl'])
                    for file in hidden.iterdir():
                        file.chmod(0o644)
                    hidden.chmod(0o755)
                    hidden.rename(destination)
                remote_manifest = {**manifest, 'apkUrl': brand['publicBaseUrl'].rstrip('/') + '/' + directory + '/' + manifest['apkUrl']}
                receipt = dict(ticket=ticket, appId=job['appId'], directory=directory,
                               status='ready', sourceManifest=manifest, manifest=remote_manifest)
                atomic_json(receipt_path, receipt, mode=0o640)
                shutil.rmtree(stage)
                bundle.unlink()
            elif operation in ('promote', 'retire'):
                if operation == 'retire' and receipt.get('status') == 'withdrawn':
                    return
                if not receipt.get('sourceManifest') or receipt.get('status') == 'withdrawn':
                    raise ValueError('A verified candidate is required.')
                manifest = receipt['sourceManifest']
                directory = child(root, receipt['directory'])
                if operation == 'promote':
                    for filename in (brand['stableApkName'], manifest['apkUrl']):
                        path = child(directory, filename)
                        if digest(path) != manifest['sha256']:
                            raise ValueError('Prepared APK integrity verification failed.')
                    native_check(directory / brand['stableApkName'], manifest, brand, config)
                    _promote(config, brand, root, state, receipts, receipt, manifest)
                    receipt['status'] = 'published'
                else:
                    records_file = child(state, job['appId'] + '.json')
                    records = json.loads(records_file.read_text()) if records_file.exists() else []
                    protected = [Path(p).resolve() for p in config.get('protectedArtifacts', [])]
                    registered = any(r['directory'] == directory.name for r in records)
                    pinned = any(p == directory or directory in p.parents for p in protected)
                    stable = root / brand['stableApkName']
                    active = stable.is_symlink() and stable.resolve().parent == directory
                    # Never remove a public/retained release, a protected download, or another ticket's folder.
                    if directory.exists() and not registered and not pinned and not active:
                        shutil.rmtree(directory)
                    receipt['status'] = 'withdrawn'
                atomic_json(receipt_path, receipt, mode=0o640)
            else:
                raise ValueError('Unknown release operation.')
        except Exception:
            # No untrusted archive/command output is copied into the portal or journal.
            receipt.update(ticket=ticket, appId=job['appId'], status='failed')
            atomic_json(receipt_path, receipt, mode=0o640)
            raise


def _promote(config, brand, root, state, receipts, receipt, manifest):
    feed = root / 'update.json'
    previous = json.loads(feed.read_text()) if feed.exists() else None
    if previous and (previous['applicationId'] != brand['packageId'] or previous['versionCode'] > manifest['versionCode']):
        raise ValueError('Public release cannot be downgraded or reassigned.')
    if previous and previous['versionCode'] == manifest['versionCode'] and previous != manifest:
        raise ValueError('Published build cannot be replaced.')
    state_file = child(state, receipt['appId'] + '.json')
    records = json.loads(state_file.read_text()) if state_file.exists() else []
    stable = root / brand['stableApkName']
    if previous and stable.is_symlink():
        old = stable.resolve(strict=True).parent
        if old.parent == root and not any(r['directory'] == old.name for r in records):
            records.append(dict(directory=old.name, versionCode=previous['versionCode'], apkName=Path(previous['apkUrl']).name))
    directory = receipt['directory']
    aliases = {name: f'{directory}/{name}' for name in (brand['stableApkName'], manifest['apkUrl'])}
    old_links = {}
    for name in aliases:
        path = root / name
        if (path.exists() or path.is_symlink()) and not path.is_symlink():
            raise ValueError('Unmanaged public file cannot be replaced.')
        old_links[name] = os.readlink(path) if path.is_symlink() else None
    try:
        for name, target in aliases.items():
            replace_link(root, name, target)
        if previous != manifest:
            atomic_json(feed, manifest, mode=0o644)
    except Exception:
        for name, target in old_links.items():
            if target is None:
                (root / name).unlink(missing_ok=True)
            else:
                replace_link(root, name, target)
        raise
    if not any(r['directory'] == directory for r in records):
        records.append(dict(directory=directory, versionCode=manifest['versionCode'], apkName=manifest['apkUrl']))
    try:
        atomic_json(state_file, records)
        protected = [Path(p).resolve() for p in config.get('protectedArtifacts', [])]
        for path in receipts.glob('*.json'):
            item = json.loads(path.read_text())
            if item.get('appId') == receipt['appId'] and item.get('status') == 'ready' and item.get('directory'):
                protected.append(child(root, item['directory']))
        atomic_json(state_file, cleanup(root, records, protected))
    except (OSError, ValueError):
        # Publication has committed. Retention trouble must not label it unpublished.
        receipt['cleanupPending'] = True
