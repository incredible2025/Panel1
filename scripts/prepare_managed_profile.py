#!/usr/bin/env python3
"""Prepare private Flutter build defines from an exported app profile."""
import argparse
import base64
import json
from pathlib import Path
import re
from urllib.parse import urlsplit


def prepare(profile, legacy_service_id=None):
    app_id = profile.get('appId', '')
    package_id = profile.get('packageId', '')
    address = urlsplit(profile.get('configUrl', ''))
    if (not re.fullmatch(r'[a-z][a-z0-9-]{2,63}', app_id)
            or not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+', package_id)
            or address.scheme != 'https' or not address.hostname or address.username
            or address.password or address.query or address.fragment):
        raise ValueError('Invalid app profile identity or HTTPS configuration address.')
    key = profile.get('verificationKey', '')
    if not re.fullmatch(r'[A-Za-z0-9_-]{43}', key) or len(base64.urlsafe_b64decode(key + '=')) != 32:
        raise ValueError('Invalid public verification key.')
    envelope = profile.get('bootstrap', {})
    if not all(isinstance(envelope.get(k), str) and re.fullmatch(r'[A-Za-z0-9_-]+', envelope[k])
               for k in ('payload', 'signature')):
        raise ValueError('Missing signed bootstrap.')
    # The compiled client verifies the signature, app identity and revision before use.
    result = {'ANDROID_APPLICATION_ID': package_id,
              'MANAGED_PROFILE': json.dumps(profile, separators=(',', ':')),
              'MANAGED_LEGACY_SERVICE_ID': ''}
    if legacy_service_id:
        if not re.fullmatch(r'[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}', legacy_service_id):
            raise ValueError('Invalid legacy service identity.')
        result['MANAGED_LEGACY_SERVICE_ID'] = legacy_service_id
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--legacy-service-id', help='Only this original service may inherit historical account storage.')
    args = parser.parse_args()
    profile = json.loads(args.profile.read_text(encoding='utf-8-sig'))
    defines = prepare(profile, args.legacy_service_id)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(defines, indent=2) + '\n', encoding='utf-8')
    print('Private managed build profile prepared. Keep it out of public release assets.')


if __name__ == '__main__':
    main()
