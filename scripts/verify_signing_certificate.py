#!/usr/bin/env python3
"""Check certificate identity after a successful apksigner verify command."""

from __future__ import annotations

from pathlib import Path
import re
import sys


CERTIFICATE = re.compile(
    r"^(?:Signer #[0-9]+|V[0-9]+(?:\.[0-9]+)? Signer(?: #[0-9]+)?:) "
    r"certificate SHA-256 digest: ([0-9a-fA-F]{64})$",
    re.MULTILINE,
)


def verify_certificate(report: str, expected: str) -> None:
    fingerprint = re.sub(r"[\s:]", "", expected).lower()
    if re.fullmatch(r"[0-9a-f]{64}", fingerprint) is None:
        raise ValueError("The expected certificate fingerprint is invalid.")
    fingerprints = {value.lower() for value in CERTIFICATE.findall(report.replace("\r\n", "\n"))}
    if not fingerprints:
        raise ValueError("No supported APK signer certificate was found in the verification report.")
    if fingerprints != {fingerprint}:
        raise ValueError("The APK signing certificate does not match the permanent release identity.")


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: verify_signing_certificate.py REPORT EXPECTED_FINGERPRINT", file=sys.stderr)
        return 2
    try:
        verify_certificate(
            Path(sys.argv[1]).read_text(encoding="utf-8"),
            Path(sys.argv[2]).read_text(encoding="utf-8"),
        )
    except (OSError, ValueError) as error:
        print(f"Signing certificate verification failed: {error}", file=sys.stderr)
        return 1
    print("APK signing certificate matches the permanent release identity.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
