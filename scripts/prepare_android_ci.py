#!/usr/bin/env python3
"""Prepare checksum-pinned Android build tooling for GitHub runners."""
import hashlib
import os
from pathlib import Path
import tempfile
import urllib.request


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
    print('Verified Android build tooling is ready.')


if __name__ == '__main__':
    main()
