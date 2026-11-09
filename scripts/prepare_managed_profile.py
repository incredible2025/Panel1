#!/usr/bin/env python3
"""Prepare private Flutter build defines from an exported app profile."""
import argparse
import base64
import json
from pathlib import Path
import re
from urllib.parse import urlsplit


def prepare(profile, legacy_service_id=None, branding=None):
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
    payload = json.loads(base64.urlsafe_b64decode(envelope['payload'] + '==='))
    if payload.get('appId') != app_id or payload.get('packageId') != package_id:
        raise ValueError('Bootstrap identity does not match the build profile.')
    endpoints = payload.get('endpoints', [])
    if not isinstance(endpoints, list) or not 1 <= len(endpoints) <= 2:
        raise ValueError('Invalid bootstrap connection settings.')
    for value in endpoints:
        uri = urlsplit(value)
        if uri.scheme not in ('http', 'https') or not uri.hostname or uri.username or uri.password or uri.query or uri.fragment:
            raise ValueError('Invalid bootstrap connection settings.')
    if package_id != 'com.streamline.iptv':
        result.update(BRAND_LEGACY_PRIMARY=endpoints[0], BRAND_LEGACY_FALLBACK=endpoints[-1],
                      APP_UPDATE_MANIFEST_URL=payload['updateManifestUrl'])
    if branding is not None:
        if branding.get('appId') != app_id or branding.get('packageId') != package_id:
            raise ValueError('Branding identity does not match the build profile.')
        for field in ('name', 'title', 'subtitle', 'wordmark'):
            if not isinstance(branding.get(field), str) or not branding[field].strip() or len(branding[field]) > 48 or any(ord(c) < 32 for c in branding[field]):
                raise ValueError('Invalid branding text.')
        if not re.fullmatch(r'\d+\.\d+\.\d+', str(branding.get('versionName', ''))) or type(branding.get('versionCode')) is not int or branding['versionCode'] < 1:
            raise ValueError('Invalid brand version.')
        result.update(APP_BRAND_NAME=branding['name'], APP_BRAND_TITLE=branding['title'],
                      APP_BRAND_SUBTITLE=branding['subtitle'], APP_BRAND_WORDMARK=branding['wordmark'],
                      APP_BRAND_ARTWORK='assets/branding/brand-artwork.png',
                      APP_VERSION_NAME=branding['versionName'], APP_BUILD_NUMBER=str(branding['versionCode']))
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
    parser.add_argument('--branding', type=Path)
    args = parser.parse_args()
    profile = json.loads(args.profile.read_text(encoding='utf-8-sig'))
    branding = json.loads(args.branding.read_text(encoding='utf-8')) if args.branding else None
    defines = prepare(profile, args.legacy_service_id, branding)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(defines, indent=2) + '\n', encoding='utf-8')
    print('Private managed build profile prepared. Keep it out of public release assets.')


if __name__ == '__main__':
    main()
