#!/usr/bin/env python3
"""Prepare checksum-pinned Android build tooling for GitHub runners."""
import hashlib
import os
from pathlib import Path
import tempfile
import urllib.request


def prepare_player_dependencies():
    # These digests pin the same upstream binaries already verified in released builds.
    dependencies = [
        ('default-arm64-v8a.jar', 300465119, '4363dfa5d3d415b91c1f16f6fb90c3fe59a77dfd3f9b824d2b24b492d6b09df9'),
        ('default-armeabi-v7a.jar', 300465118, '8ead114fc5a43348d89dc0eb8f41823e549b15115c29f73ee26973f973620995'),
        ('default-x86_64.jar', 300465116, '90268cd15f0766e07fb8e427388c621161177c9eb343c544f327bd63232bb236'),
        ('default-x86.jar', 300465120, '94c13cb6188b774710e5e487afff6e500c4af504df74b2494d7b12cf9be8a66a'),
    ]
    root = Path('build/media_kit_libs_android_video/v1.1.7')
    root.mkdir(parents=True, exist_ok=True)
    for name, asset_id, expected in dependencies:
        destination = root / name
        if destination.exists() and hashlib.sha256(destination.read_bytes()).hexdigest() == expected:
            continue
        request = urllib.request.Request(
            f'https://api.github.com/repos/media-kit/libmpv-android-video-build/releases/assets/{asset_id}',
            headers={'Accept': 'application/octet-stream', 'User-Agent': 'Android-release-build'},
        )
        digest = hashlib.sha256()
        with urllib.request.urlopen(request, timeout=60) as response, destination.open('wb') as output:
            while chunk := response.read(1024 * 1024):
                digest.update(chunk)
                output.write(chunk)
        if digest.hexdigest() != expected:
            destination.unlink(missing_ok=True)
            raise ValueError('A player dependency does not match its pinned checksum.')
    print('Player build dependencies verified.')


def main():
    wrapper = Path('android/gradle/wrapper/gradle-wrapper.properties')
    properties = wrapper.read_text(encoding='utf-8')
    expected_url = 'distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-bin.zip'
    if expected_url not in properties:
        raise ValueError('Update the pinned Gradle bootstrap when changing the wrapper version.')
    expected_digest = '20f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78'
    destination = Path(os.environ.get('RUNNER_TEMP', tempfile.gettempdir())) / 'android-gradle-8.13-bin.zip'
    sources = [
        'https://downloads.gradle.org/distributions/gradle-8.13-bin.zip',
        'https://mirrors.huaweicloud.com/gradle/gradle-8.13-bin.zip',
    ]
    for index, source in enumerate(sources):
        if destination.exists() and hashlib.sha256(destination.read_bytes()).hexdigest() == expected_digest:
            break
        try:
            digest = hashlib.sha256()
            with urllib.request.urlopen(source, timeout=60) as response, destination.open('wb') as output:
                while chunk := response.read(1024 * 1024):
                    digest.update(chunk)
                    output.write(chunk)
            if digest.hexdigest() != expected_digest:
                raise ValueError('The Gradle archive does not match the official checksum.')
            break
        except Exception:
            destination.unlink(missing_ok=True)
            if index == len(sources) - 1:
                raise RuntimeError('Unable to obtain a verified Gradle distribution.') from None
            print('Primary build-tool download unavailable; trying checksum-verified fallback.')
    wrapper.write_text(properties.replace(expected_url, 'distributionUrl=' + destination.resolve().as_uri()), encoding='utf-8')
    init_dir = Path(os.environ.get('GRADLE_USER_HOME', str(Path.home() / '.gradle'))) / 'init.d'
    init_dir.mkdir(parents=True, exist_ok=True)
    (init_dir / 'android-plugin-repositories.gradle').write_text('''
beforeSettings { settings ->
    settings.pluginManagement.repositories {
        mavenCentral()
        google()
        gradlePluginPortal()
    }
}
''', encoding='utf-8')
    prepare_player_dependencies()
    print('Verified Android build tooling is ready.')


if __name__ == '__main__':
    main()
