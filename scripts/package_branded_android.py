#!/usr/bin/env python3
"""Validate and package one branded APK using its actual native metadata."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile

from create_update_manifest import create_manifest
from verify_signing_certificate import verify_certificate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('apk', 'branding', 'notes', 'output', 'expected-certificate'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--aapt', required=True)
    parser.add_argument('--apksigner', required=True)
    args = parser.parse_args()
    brand = json.loads(args.branding.read_text(encoding='utf-8'))
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*\.apk', brand.get('stableApkName', '')) or not re.fullmatch(r'[a-z][a-z0-9-]{2,63}', brand.get('appId', '')):
        raise ValueError('Invalid brand output filename.')
    badging = subprocess.check_output([args.aapt, 'dump', 'badging', str(args.apk)], text=True, encoding='utf-8')
    versioned_name = f"{brand['appId']}-{brand['versionName']}.apk"
    manifest = create_manifest(args.apk, badging, versioned_name, args.notes.read_text(encoding='utf-8'), brand['packageId'])
    if manifest['versionCode'] != brand['versionCode'] or manifest['versionName'] != brand['versionName']:
        raise ValueError('Native and displayed brand versions must agree.')
    label = re.search(r"^application-label:'([^']+)'", badging, re.M)
    if not label or label[1] != brand['name']:
        raise ValueError('Native launcher name does not match the selected brand.')
    if args.apk.stat().st_size >= 200_000_000:
        raise ValueError('The combined ARM APK exceeds the download target.')
    report = subprocess.check_output([args.apksigner, 'verify', '--verbose', '--print-certs', str(args.apk)], text=True)
    verify_certificate(report, args.expected_certificate.read_text(encoding='utf-8').strip())
    with zipfile.ZipFile(args.apk) as apk:
        names = set(apk.namelist())
        if {n.split('/')[1] for n in names if n.startswith('lib/')} != {'armeabi-v7a', 'arm64-v8a'}:
            raise ValueError('Both ARM architectures are required.')
        for abi in ('armeabi-v7a', 'arm64-v8a'):
            for library in ('libapp.so', 'libflutter.so', 'libmpv.so', 'libvlc.so', 'libvlcjni.so'):
                if f'lib/{abi}/{library}' not in names:
                    raise ValueError('A playback library is missing.')
            if brand['name'].encode() not in apk.read(f'lib/{abi}/libapp.so'):
                raise ValueError('The compiled app name does not match its launcher identity.')
    subprocess.check_call([sys.executable, str(Path(__file__).with_name('verify_vlc_jni.py')), str(args.apk)])
    args.output.mkdir(parents=True, exist_ok=True)
    stable = args.output / brand['stableApkName']
    versioned = args.output / versioned_name
    shutil.copy2(args.apk, stable)
    shutil.copy2(args.apk, versioned)
    manifest_file = args.output / 'update.json'
    manifest_file.write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    bundle = args.output / f"{stable.stem}-{brand['versionName']}-remote-update.zip"
    with zipfile.ZipFile(bundle, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for file in (stable, versioned, manifest_file):
            archive.write(file, file.name)
    with zipfile.ZipFile(bundle) as archive:
        if archive.testzip() is not None:
            raise ValueError('Update bundle failed its integrity check.')
    verification = {'appId': brand['appId'], 'packageId': brand['packageId'],
                    'versionName': manifest['versionName'], 'versionCode': manifest['versionCode'],
                    'stableApkName': stable.name, 'versionedApkName': versioned.name, 'bundleName': bundle.name,
                    'apkBytes': manifest['sizeBytes'], 'apkSha256': manifest['sha256'],
                    'bundleBytes': bundle.stat().st_size, 'bundleSha256': hashlib.file_digest(bundle.open('rb'), 'sha256').hexdigest()}
    (args.output / 'verification.json').write_text(json.dumps(verification, indent=2), encoding='utf-8')
    print('Branded APK identity, runtime name, playback libraries and update bundle verified.')


if __name__ == '__main__':
    main()
