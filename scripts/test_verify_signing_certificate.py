import unittest

from verify_signing_certificate import verify_certificate


class SigningCertificateTest(unittest.TestCase):
    fingerprint = "72c1e7d6d35aa7e68f9467603aa54e5b78d674da4b0ea015ab1911a2eea31512"

    def test_original_apksigner_output(self):
        verify_certificate(f"Signer #1 certificate SHA-256 digest: {self.fingerprint}\n", self.fingerprint)

    def test_new_apksigner_output_and_repeated_schemes(self):
        report = "\r\n".join(
            f"{label}: certificate SHA-256 digest: {self.fingerprint.upper()}"
            for label in ("V2 Signer", "V3 Signer", "V3.1 Signer #1")
        )
        expected = ":".join(self.fingerprint[i:i + 2] for i in range(0, 64, 2)) + "\n"
        verify_certificate(report, expected)

    def test_wrong_or_additional_signer_is_rejected(self):
        wrong = "0" * 64
        for report in (
            f"V2 Signer: certificate SHA-256 digest: {wrong}\n",
            f"Signer #1 certificate SHA-256 digest: {self.fingerprint}\n"
            f"Signer #2 certificate SHA-256 digest: {wrong}\n",
        ):
            with self.subTest(report=report), self.assertRaises(ValueError):
                verify_certificate(report, self.fingerprint)

    def test_missing_malformed_or_source_stamp_only_report_is_rejected(self):
        for report in ("", "Verifies\n", "V2 Signer: certificate SHA-256 digest: abc\n",
                       f"Source Stamp Signer certificate SHA-256 digest: {self.fingerprint}\n"):
            with self.subTest(report=report), self.assertRaises(ValueError):
                verify_certificate(report, self.fingerprint)

    def test_invalid_expected_fingerprint_is_rejected(self):
        with self.assertRaises(ValueError):
            verify_certificate(f"V2 Signer: certificate SHA-256 digest: {self.fingerprint}\n", "abc")


if __name__ == "__main__":
    unittest.main()
