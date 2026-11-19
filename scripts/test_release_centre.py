import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch
import uuid

from manage_android_releases import dispatch
import test_uploaded_android as fixtures


@unittest.skipIf(os.name == 'nt', 'Host worker requires Linux filesystem semantics')
class ReleaseCentreTest(unittest.TestCase):
    job = fixtures.UploadedAndroidTest.job

    def setUp(self):
        fixtures.UploadedAndroidTest.setUp(self)
        (self.base / 'receipts').mkdir()
        self.config['receiptDirectory'] = str(self.base / 'receipts')
        self.config['apps']['fixture']['publicBaseUrl'] = 'https://downloads.example.test/fixture'
        self.mock_native = patch('manage_android_releases.native_check')
        self.native = self.mock_native.start()
        self.addCleanup(self.mock_native.stop)

    def prepare(self, code):
        job = {**self.job(code), 'ticket': str(uuid.uuid4()), 'operation': 'prepare'}
        dispatch(self.config, job)
        return job

    def test_upload_is_verified_but_does_not_change_public_links_until_promoted(self):
        job = self.prepare(1)
        self.native.assert_called_once()
        self.assertFalse((self.root / 'Player.apk').exists())
        self.assertFalse((self.root / 'update.json').exists())
        self.assertFalse((self.base / 'inbox' / job['bundle']).exists())
        self.assertTrue((self.root / '1.0.1-1/Player.apk').is_file())
        dispatch(self.config, {**job, 'operation': 'promote'})
        self.assertEqual(json.loads((self.root / 'update.json').read_text())['versionCode'], 1)
        receipt = json.loads((self.base / 'receipts' / (job['ticket']+'.json')).read_text())
        self.assertEqual(receipt['status'], 'published')
        self.assertTrue(receipt['manifest']['apkUrl'].startswith('https://downloads.example.test/fixture/1.0.1-1/'))

    def test_native_verification_failure_retains_upload_without_publication(self):
        self.native.side_effect = ValueError('invalid certificate')
        job = {**self.job(1), 'ticket': str(uuid.uuid4()), 'operation': 'prepare'}
        with self.assertRaises(ValueError):
            dispatch(self.config, job)
        self.assertTrue((self.base / 'inbox' / job['bundle']).exists())
        self.assertFalse((self.root / '1.0.1-1').exists())

    def test_candidate_withdrawal_and_prepare_retries_are_idempotent(self):
        job = self.prepare(1)
        dispatch(self.config, job)
        dispatch(self.config, {**job, 'operation': 'retire'})
        dispatch(self.config, {**job, 'operation': 'retire'})
        self.assertFalse((self.root / '1.0.1-1').exists())

    def test_an_old_candidate_cannot_downgrade_a_new_public_release(self):
        old = self.prepare(1)
        new = self.prepare(2)
        dispatch(self.config, {**new, 'operation': 'promote'})
        with self.assertRaises(ValueError):
            dispatch(self.config, {**old, 'operation': 'promote'})
        self.assertEqual(json.loads((self.root / 'update.json').read_text())['versionCode'], 2)

    def test_withdrawal_cannot_remove_the_active_release_if_retention_state_is_lost(self):
        job = self.prepare(1)
        dispatch(self.config, {**job, 'operation': 'promote'})
        (self.base / 'state/fixture.json').unlink()
        dispatch(self.config, {**job, 'operation': 'retire'})
        self.assertTrue((self.root / 'Player.apk').is_file())

    def test_operator_uploads_cannot_bypass_required_server_native_verification(self):
        from publish_uploaded_android import publish
        self.config['requireNativeVerification'] = True
        self.native.side_effect = ValueError('invalid native identity')
        job = self.job(1)
        with self.assertRaises(ValueError):
            publish(self.config, job)
        self.native.assert_called_once()
        self.assertFalse((self.root / 'Player.apk').exists())
        self.assertTrue((self.base / 'inbox' / job['bundle']).exists())
