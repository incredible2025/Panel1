#!/usr/bin/env python3
"""Publish verified Android bundles from a private inbox, then reclaim upload space.

Linux server only. Submit an atomic *.ready.json job after uploading its ZIP.
Jobs and the allowlist belong outside the web root and must be owner-writable only.
"""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import tempfile
import zipfile

from public_release_notes import validate_notes


def digest(path):
    with path.open('rb') as stream:
        value = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
        return value.hexdigest()


def child(root, name):
    if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', name):
        raise ValueError('Invalid file name.')
    path = root / name
    if path.is_symlink():
        raise ValueError('Private work files cannot be symbolic links.')
    return path


def atomic_json(path, value, mode=None):
    temp = path.with_name(path.name + '.tmp')
    with temp.open('w', encoding='utf-8') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    if mode is not None:
        temp.chmod(mode)
    os.replace(temp, path)


@contextmanager
def exclusive(path):
    import fcntl
    with path.open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def validate_bundle(bundle, expected_sha, brand, stage):
    if not re.fullmatch(r'[a-f0-9]{64}', expected_sha) or digest(bundle) != expected_sha:
        raise ValueError('Upload checksum verification failed.')
    stable = brand['stableApkName']
    with zipfile.ZipFile(bundle) as archive:
        entries = archive.infolist()
        if len(entries) != 3 or len({i.filename for i in entries}) != 3:
            raise ValueError('Expected exactly three release files.')
        for entry in entries:
            child(stage, entry.filename)
            mode = entry.external_attr >> 16
            if entry.is_dir() or stat.S_ISLNK(mode) or entry.flag_bits & 1:
                raise ValueError('Unsupported archive entry.')
            limit = 65536 if entry.filename == 'update.json' else 200_000_000
            if not 0 < entry.file_size <= limit:
                raise ValueError('Release file exceeds its size limit.')
        manifest = json.loads(archive.read('update.json'))
        versioned = manifest['apkUrl']
        if not isinstance(versioned, str) or not versioned.endswith('.apk'):
            raise ValueError('Expected a relative APK filename.')
        child(stage, versioned)
        if set(archive.namelist()) != {stable, versioned, 'update.json'} or stable == versioned:
            raise ValueError('Unexpected bundle contents.')
        if manifest['schemaVersion'] != 1 or manifest['applicationId'] != brand['packageId']:
            raise ValueError('Release belongs to a different app.')
        if type(manifest['versionCode']) is not int or manifest['versionCode'] <= 0:
            raise ValueError('Invalid Android build number.')
        if not re.fullmatch(r'\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?', manifest['versionName']):
            raise ValueError('Invalid release version.')
        if not re.fullmatch(r'[a-f0-9]{64}', manifest['sha256']):
            raise ValueError('Invalid APK checksum.')
        if type(manifest['sizeBytes']) is not int or manifest['sizeBytes'] <= 0:
            raise ValueError('Invalid APK size.')
        if validate_notes(manifest['releaseNotes']) != manifest['releaseNotes']:
            raise ValueError('Release notes must already be validated public copy.')
        for name in (stable, versioned):
            with archive.open(name) as source, (stage / name).open('wb') as target:
                shutil.copyfileobj(source, target)
            apk = stage / name
            if apk.stat().st_size != manifest['sizeBytes'] or digest(apk) != manifest['sha256']:
                raise ValueError('APK integrity verification failed.')
            with zipfile.ZipFile(apk) as contents:
                if 'AndroidManifest.xml' not in contents.namelist() or contents.testzip() is not None:
                    raise ValueError('Invalid APK archive.')
    # Store just one APK's bytes; the two published names share its inode.
    (stage / versioned).unlink()
    os.link(stage / stable, stage / versioned)
    atomic_json(stage / 'update.json', manifest)
    return manifest


def replace_link(root, name, target):
    link = root / name
    if link.exists() and not link.is_symlink():
        raise ValueError('Refusing to overwrite an unmanaged public file.')
    temporary = root / ('.' + name + '.next')
    if temporary.exists() or temporary.is_symlink():
        temporary.unlink()
    temporary.symlink_to(target)
    os.replace(temporary, link)


def cleanup(root, records, protected):
    """Only registered releases can be removed. Unknown files are never swept."""
    keep = sorted(records, key=lambda r: r['versionCode'], reverse=True)[:2]
    retained = []
    for record in records:
        directory = child(root, record['directory'])
        preserve = record in keep or any(
            path == directory or directory in path.parents for path in protected)
        if preserve:
            retained.append(record)
            continue
        # Unlink only the obsolete versioned alias, never a permanent download name.
        alias = root / record['apkName']
        if alias.is_symlink() and alias.resolve().parent == directory:
            alias.unlink()
        if directory.exists():
            # child() rejects symlinks, and the parent is the exact allowlisted app folder.
            shutil.rmtree(directory)
    return retained


def publish(config, job, *, after_links=None):
    app_id = job['appId']
    brand = config['apps'][app_id]
    root = Path(brand['directory']).resolve(strict=True)
    inbox = Path(config['inbox']).resolve(strict=True)
    state_root = Path(config['stateDirectory']).resolve(strict=True)
    stable = brand['stableApkName']
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*\.apk', stable):
        raise ValueError('Invalid permanent APK filename.')
    bundle = child(inbox, job['bundle'])
    if not bundle.name.endswith('.zip') or not bundle.is_file():
        raise ValueError('A completed ZIP upload is required.')
    state_file = child(state_root, app_id + '.json')
    # Resolve protection before changing any links. A protected ZIP can pin an old folder.
    protected = [Path(p).resolve() for p in config.get('protectedArtifacts', [])]
    with exclusive(child(state_root, app_id + '.lock')):
        stage = Path(tempfile.mkdtemp(prefix=app_id + '-', dir=inbox))
        committed = False
        try:
            manifest = validate_bundle(bundle, job['sha256'], brand, stage)
            if config.get('requireNativeVerification') or brand.get('certificateSha256'):
                from manage_android_releases import native_check
                native_check(stage / stable, manifest, brand, config)
            feed = root / 'update.json'
            previous = json.loads(feed.read_text()) if feed.exists() else None
            if previous and previous['applicationId'] != brand['packageId']:
                raise ValueError('Existing feed belongs to a different app.')
            if previous and manifest['versionCode'] < previous['versionCode']:
                raise ValueError('Android build number cannot decrease.')
            if previous and manifest['versionCode'] == previous['versionCode'] and manifest != previous:
                raise ValueError('An existing build cannot be replaced with different content.')
            if previous and manifest['versionCode'] > previous['versionCode'] and manifest['apkUrl'] == previous['apkUrl']:
                raise ValueError('A new release needs a new versioned APK filename.')
            records = json.loads(state_file.read_text()) if state_file.exists() else []
            # Adopt the current legacy release only when its stable link proves its location.
            link = root / stable
            if previous and link.is_symlink():
                old = link.resolve(strict=True).parent
                if old.parent == root and not any(r['directory'] == old.name for r in records):
                    child(root, old.name)
                    records.append(dict(directory=old.name, versionCode=previous['versionCode'],
                                        apkName=Path(previous['apkUrl']).name))
            name = f"{manifest['versionName']}-{manifest['versionCode']}"
            destination = child(root, name)
            if destination.exists():
                if (json.loads((destination / 'update.json').read_text()) != manifest
                        or any(digest(destination / n) != manifest['sha256']
                               for n in (stable, manifest['apkUrl']))):
                    raise ValueError('Existing release directory does not match the upload.')
            else:
                # Copy to the same filesystem before promotion, even when inbox is on another disk.
                public_stage = root / ('.' + name + '.staging')
                if public_stage.exists() or public_stage.is_symlink():
                    raise ValueError('A previous incomplete staging directory requires inspection.')
                shutil.copytree(stage, public_stage, copy_function=shutil.copy2)
                (public_stage / manifest['apkUrl']).unlink()
                os.link(public_stage / stable, public_stage / manifest['apkUrl'])
                for file in public_stage.iterdir():
                    file.chmod(0o644)
                public_stage.chmod(0o755)
                public_stage.rename(destination)
            aliases = {stable: f'{name}/{stable}', manifest['apkUrl']: f"{name}/{manifest['apkUrl']}"}
            old_links = {}
            for alias in aliases:
                path = root / alias
                if (path.exists() or path.is_symlink()) and not path.is_symlink():
                    raise ValueError('Refusing to replace an unmanaged public APK.')
                old_links[alias] = os.readlink(path) if path.is_symlink() else None
            if not any(r['directory'] == name for r in records):
                records.append(dict(directory=name, versionCode=manifest['versionCode'], apkName=manifest['apkUrl']))
            try:
                for alias, target in aliases.items():
                    replace_link(root, alias, target)
                if after_links:
                    after_links()
                # Feed last: until this succeeds, clients keep the old advertised build.
                if previous != manifest:
                    atomic_json(feed, manifest, mode=0o644)
                committed = True
            finally:
                if not committed:
                    for alias, target in old_links.items():
                        if target is None:
                            (root / alias).unlink(missing_ok=True)
                        else:
                            replace_link(root, alias, target)
            # Never register an uncommitted release for retention decisions.
            atomic_json(state_file, records)
            records = cleanup(root, records, protected)
            atomic_json(state_file, records)
            shutil.rmtree(stage)
            bundle.unlink()
        except Exception:
            # Failed upload and private extraction remain for troubleshooting. No secrets logged.
            raise


def process_queue(config):
    inbox = Path(config['inbox']).resolve(strict=True)
    state = Path(config['stateDirectory']).resolve(strict=True)
    with exclusive(state / 'queue.lock'):
        for path in sorted(inbox.glob('*.ready.json')):
            try:
                if path.is_symlink() or path.stat().st_size > 65536:
                    raise ValueError('Invalid upload job.')
                job = json.loads(path.read_text(encoding='utf-8'))
                if 'operation' in job:
                    from manage_android_releases import dispatch
                    dispatch(config, job)
                else:
                    publish(config, job)
            except Exception as error:
                # Do not retry failed work every minute or log supplied configuration.
                path.rename(path.with_suffix('.failed'))
                print('Upload requires inspection (' + type(error).__name__ + '); existing release remains available.', flush=True)
            else:
                path.unlink()
                print('Release job completed successfully.', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True, type=Path)
    args = parser.parse_args()
    process_queue(json.loads(args.config.read_text(encoding='utf-8')))


if __name__ == '__main__':
    main()
