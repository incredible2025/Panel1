#!/usr/bin/env python3
"""Stage a branded build without modifying the primary app's working files."""
import argparse
import json
import re
import shutil
import subprocess
from pathlib import Path

from prepare_managed_profile import prepare


def stage(source, workspace, profile, branding_path, signing_properties):
    source, workspace = source.resolve(), workspace.resolve()
    allowed = (source / '.tooling/brand-workspaces').resolve()
    if not workspace.is_relative_to(allowed) or workspace == allowed:
        raise ValueError('Use a dedicated directory inside .tooling/brand-workspaces.')
    if workspace.exists() and any(workspace.iterdir()):
        raise ValueError('Select a new empty workspace; existing builds are preserved.')
    branding = json.loads(branding_path.read_text(encoding='utf-8'))
    definitions = prepare(profile, branding=branding)
    logo = (branding_path.parent / branding['logo']).resolve()
    if not logo.is_relative_to(branding_path.parent.resolve()) or not logo.is_file():
        raise ValueError('A project-local brand logo is required.')
    signing_properties = signing_properties.resolve(strict=True)
    stable_name = branding.get('stableApkName', '')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*\.apk', stable_name):
        raise ValueError('A stable APK filename is required.')
    workspace.mkdir(parents=True, exist_ok=True)
    tracked = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=source)
    copied = set()
    for name in tracked.decode('utf-8').split('\0'):
        if not name or name in copied:
            continue
        relative = Path(name)
        if relative.parts[0] not in {'lib', 'android', 'assets', 'packages', 'test', 'scripts'} and name not in {'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'}:
            continue
        origin = source / relative
        if not origin.is_file():
            continue
        target = workspace / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(origin, target)
        copied.add(name)
    # Flutter generates these locally; Android's standard ignore file excludes
    # them from Git, but an isolated native build still needs its wrapper.
    for name in ['android/gradlew', 'android/gradlew.bat', 'android/gradle/wrapper/gradle-wrapper.jar', 'android/gradle/wrapper/gradle-wrapper.properties']:
        origin = source / name
        if origin.is_file():
            target = workspace / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(origin, target)
    for destination in ['assets/branding/ultravpn-shield.png', 'android/app/src/main/res/drawable-nodpi/ultravpn_shield.png']:
        shutil.copy2(logo, workspace / destination)
    # This is a generated copy, never the primary workspace's artwork.
    obsolete = workspace / 'assets/branding/ultravpn-player.jpg'
    if obsolete.is_file():
        obsolete.unlink()
    definitions.update(EXPORT_BRAND_ASSETS='true', BRAND_ASSET_OUTPUT=str(workspace / '.brand-build/artwork'))
    private = workspace / '.brand-build'
    private.mkdir()
    (private / 'defines.json').write_text(json.dumps(definitions, indent=2), encoding='utf-8')
    native = dict(line.split('=', 1) for line in (source / 'android/local.properties').read_text(encoding='utf-8').splitlines() if '=' in line)
    native.update({'flutter.versionName': branding['versionName'], 'flutter.versionCode': str(branding['versionCode'])})
    (workspace / 'android/local.properties').write_text(''.join(f'{k}={v}\n' for k, v in native.items()), encoding='utf-8')
    (private / 'build.json').write_text(json.dumps({'appId': branding['appId'], 'packageId': branding['packageId'],
        'name': branding['name'], 'versionName': branding['versionName'], 'versionCode': branding['versionCode'],
        'stableApkName': stable_name, 'signingProperties': str(signing_properties)}, indent=2), encoding='utf-8')
    return workspace


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--branding', type=Path, required=True)
    parser.add_argument('--signing-properties', type=Path, required=True)
    args = parser.parse_args()
    stage(args.source, args.workspace, json.loads(args.profile.read_text(encoding='utf-8-sig')), args.branding, args.signing_properties)
    print('Isolated brand workspace prepared; primary app files preserved.')


if __name__ == '__main__':
    main()
