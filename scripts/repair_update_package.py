"""Correct public notes in an existing package without changing either APK."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

from public_release_notes import validate_notes


def repair_package(source, output, notes):
    notes = validate_notes(notes)
    if source.resolve() == output.resolve():
        raise ValueError('Use a separate output file.')
    with zipfile.ZipFile(source) as archive:
        manifest = json.loads(archive.read('update.json'))
        versioned = manifest['apkUrl']
        if '/' in versioned or '\\' in versioned or not versioned.endswith('.apk'):
            raise ValueError('Expected a portable update package.')
        names = ['update.json', versioned, 'Ultravpn-player.apk']
        if sorted(archive.namelist()) != sorted(names):
            raise ValueError('Unexpected update package contents.')
        apk = archive.read(versioned)
        if (apk != archive.read('Ultravpn-player.apk')
                or len(apk) != manifest['sizeBytes']
                or hashlib.sha256(apk).hexdigest() != manifest['sha256']):
            raise ValueError('Existing APK integrity verification failed.')
        manifest['releaseNotes'] = notes
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('update.json', json.dumps(manifest, indent=2) + '\n')
        archive.writestr(versioned, apk)
        archive.writestr('Ultravpn-player.apk', apk)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--notes', type=Path, required=True)
    args = parser.parse_args()
    repair_package(args.source, args.output, args.notes.read_text(encoding='utf-8'))
    print('Public notes corrected; APK bytes and update identity preserved.')


if __name__ == '__main__':
    main()
