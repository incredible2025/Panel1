import base64
import json
from pathlib import Path
import tempfile
import unittest

from prepare_managed_profile import prepare
from prepare_brand_workspace import stage


def fixture():
    return json.loads((Path(__file__).parents[1] / 'test/fixtures/managed-profile.json').read_text(encoding='utf-8'))


class BrandProfilesTest(unittest.TestCase):
    def branding(self):
        return {'appId': 'fixture-brand', 'packageId': 'com.example.fixture',
                'name': 'Example Player', 'title': 'EXAMPLE', 'subtitle': 'PLAYER',
                'wordmark': 'EXAMPLE PLAYER', 'versionName': '0.9.0', 'versionCode': 43,
                'stableApkName': 'Example-player.apk', 'logo': 'logo.png'}

    def test_brand_defines_keep_own_identity_roots_and_disable_primary_migration(self):
        result = prepare(fixture(), branding=self.branding())
        self.assertEqual(result['ANDROID_APPLICATION_ID'], 'com.example.fixture')
        self.assertEqual(result['APP_BUILD_NUMBER'], '43')
        self.assertEqual(result['APP_BRAND_NAME'], 'Example Player')
        self.assertEqual(result['BRAND_LEGACY_PRIMARY'], 'https://primary.example.test/service')
        self.assertEqual(result['BRAND_LEGACY_FALLBACK'], 'http://backup.example.test/fallback')
        self.assertEqual(result['MANAGED_LEGACY_SERVICE_ID'], '')

    def test_mismatched_bootstrap_and_branding_identities_are_rejected(self):
        profile = fixture()
        with self.assertRaises(ValueError):
            prepare(profile, branding={**self.branding(), 'packageId': 'com.wrong.player'})
        payload = json.loads(base64.urlsafe_b64decode(profile['bootstrap']['payload'] + '==='))
        payload['appId'] = 'another-brand'
        profile['bootstrap']['payload'] = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip('=')
        with self.assertRaises(ValueError):
            prepare(profile, branding=self.branding())

    def test_invalid_native_versions_and_control_characters_are_rejected(self):
        for patch in [{'versionCode': 0}, {'versionCode': True}, {'versionName': 'not-a-version'}, {'name': 'Name\nInjected'}]:
            with self.assertRaises(ValueError):
                prepare(fixture(), branding={**self.branding(), **patch})

    def test_workspace_cannot_overwrite_primary_source_or_an_existing_build(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            brand = source / 'brand.json'
            brand.write_text(json.dumps(self.branding()))
            key = source / 'key.properties'
            key.touch()
            with self.assertRaises(ValueError):
                stage(source, source, fixture(), brand, key)
            workspace = source / '.tooling/brand-workspaces/test'
            workspace.mkdir(parents=True)
            (workspace / 'keep.txt').write_text('existing build')
            with self.assertRaises(ValueError):
                stage(source, workspace, fixture(), brand, key)
            self.assertEqual((workspace / 'keep.txt').read_text(), 'existing build')


if __name__ == '__main__':
    unittest.main()
