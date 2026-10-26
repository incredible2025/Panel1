"""Generate a separate Windows update feed from the finished installer."""
import argparse
import hashlib
import json
from pathlib import Path
import re

from public_release_notes import validate_notes


def create_manifest(installer, version, code, notes):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or code <= 0:
        raise ValueError('Use the built version and a positive build number.')
    if not 64 < installer.stat().st_size <= 512 * 1024 * 1024:
        raise ValueError('Installer size is invalid.')
    with installer.open('rb') as source:
        if source.read(2) != b'MZ':
            raise ValueError('Expected a Windows executable installer.')
        source.seek(0)
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    return dict(schemaVersion=1, platform='windows-x64', applicationId='com.streamline.iptv.windows',
                versionName=version, versionCode=code, minWindowsBuild=19041,
                installerUrl=f'Ultravpn-player-Setup-{version}.exe',
                sizeBytes=installer.stat().st_size, sha256=digest,
                releaseNotes=validate_notes(notes))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--installer', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--code', type=int, required=True)
    parser.add_argument('--notes', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = create_manifest(args.installer, args.version, args.code, args.notes.read_text(encoding='utf-8'))
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('Windows update manifest verified.')


if __name__ == '__main__':
    main()
