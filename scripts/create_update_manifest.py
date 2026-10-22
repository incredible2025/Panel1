#!/usr/bin/env python3
"""Generate an update feed from the built APK, never from guessed metadata."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import urlparse


def create_manifest(apk, badging, apk_url, notes):
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging, re.M)
    sdk = re.search(r"^(?:minSdkVersion|sdkVersion):'(\d+)'", badging, re.M)
    url = urlparse(apk_url)
    if not package or not sdk or package[1] != 'com.streamline.iptv':
        raise ValueError('APK metadata must identify ULTRAVPN PLAYER with a minimum SDK.')
    if url.scheme != 'https' or not url.hostname or url.username or url.password or url.fragment:
        raise ValueError('The APK address must use HTTPS without credentials or a fragment.')
    if not 0 < apk.stat().st_size <= 512 * 1024 * 1024:
        raise ValueError('APK size must be between 1 byte and 512 MB.')
    if len(notes) > 20000:
        raise ValueError('Release notes exceed the app limit.')
    with apk.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    return dict(schemaVersion=1, applicationId=package[1], versionCode=int(package[2]),
                versionName=package[3], minSdk=int(sdk[1]), apkUrl=apk_url,
                sizeBytes=apk.stat().st_size, sha256=digest, releaseNotes=notes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--aapt', required=True)
    parser.add_argument('--apk-url', required=True)
    parser.add_argument('--notes', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    badging = subprocess.check_output([args.aapt, 'dump', 'badging', str(args.apk)], text=True)
    manifest = create_manifest(args.apk, badging, args.apk_url, args.notes.read_text(encoding='utf-8'))
    encoded = json.dumps(manifest, indent=2, ensure_ascii=False) + '\n'
    if len(encoded.encode('utf-8')) > 65536:
        raise ValueError('The complete update manifest exceeds 64 KiB.')
    args.output.write_text(encoded, encoding='utf-8')
    print(f"Update manifest verified for {manifest['versionName']} ({manifest['versionCode']}).")


if __name__ == '__main__':
    main()
