#!/usr/bin/env python3
"""Configure Android release signing from one GitHub Actions JSON secret.

ANDROID_SIGNING_JSON must contain exactly these string fields: keystore
(standard, unwrapped base64 PKCS#12), storePassword, keyAlias, keyPassword.
The Android toolchain verifies the passwords and private key during signing;
this script performs structural PKCS#12 checks before writing any files.
"""

from __future__ import annotations

import base64
import binascii
import contextlib
import json
import os
from pathlib import Path
import sys
import tempfile


SECRET_NAME = "ANDROID_SIGNING_JSON"
MAX_SECRET_BYTES = 48 * 1024
MIN_KEYSTORE_BYTES = 100
MAX_KEYSTORE_BYTES = 20 * 1024
FIELDS = frozenset({"keystore", "storePassword", "keyAlias", "keyPassword"})


class SigningConfigurationError(Exception):
    """An actionable configuration error whose message contains no secret."""


def _unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise SigningConfigurationError("The signing secret contains duplicate JSON fields.")
        result[key] = value
    return result


def _der_value(data: bytes, offset: int, expected_tag: int) -> tuple[int, int]:
    """Return the content bounds of one canonical, definite-length DER value."""
    invalid = SigningConfigurationError(
        "The keystore must be a DER-encoded PKCS#12 file (PFX version 3)."
    )
    if offset + 2 > len(data) or data[offset] != expected_tag:
        raise invalid
    length_byte = data[offset + 1]
    start = offset + 2
    if length_byte < 0x80:
        length = length_byte
    else:
        length_bytes = length_byte & 0x7F
        if not 1 <= length_bytes <= 4 or start + length_bytes > len(data):
            raise invalid
        encoded_length = data[start : start + length_bytes]
        if encoded_length[0] == 0:
            raise invalid
        length = int.from_bytes(encoded_length, "big")
        if length < 0x80:
            raise invalid
        start += length_bytes
    end = start + length
    if end > len(data):
        raise invalid
    return start, end


def _validate_pkcs12(data: bytes) -> None:
    if not MIN_KEYSTORE_BYTES <= len(data) <= MAX_KEYSTORE_BYTES:
        raise SigningConfigurationError("The decoded PKCS#12 keystore must be 100 bytes to 20 KiB.")
    start, end = _der_value(data, 0, 0x30)
    if end != len(data):
        raise SigningConfigurationError("The PKCS#12 keystore contains unexpected trailing bytes.")
    version_start, version_end = _der_value(data, start, 0x02)
    if data[version_start:version_end] != b"\x03":
        raise SigningConfigurationError("The keystore must use PKCS#12 PFX version 3.")
    auth_start, auth_end = _der_value(data, version_end, 0x30)
    if auth_end > end:
        raise SigningConfigurationError("The PKCS#12 keystore structure is invalid.")
    oid_start, oid_end = _der_value(data, auth_start, 0x06)
    allowed_content_types = {
        b"\x2a\x86\x48\x86\xf7\x0d\x01\x07\x01",  # PKCS#7 data
        b"\x2a\x86\x48\x86\xf7\x0d\x01\x07\x02",  # PKCS#7 signedData
    }
    if oid_end > auth_end or data[oid_start:oid_end] not in allowed_content_types:
        raise SigningConfigurationError("The PKCS#12 keystore has an invalid authenticated content type.")
    if auth_end < end:
        _, mac_end = _der_value(data, auth_end, 0x30)
        if mac_end != end:
            raise SigningConfigurationError("The PKCS#12 keystore structure is invalid.")


def _property_value(value: str) -> str:
    """Escape a value for Java Properties.load, preserving exact passwords."""
    escaped: list[str] = []
    for char in value:
        codepoint = ord(char)
        if char == "\\":
            escaped.append("\\\\")
        elif char == "\t":
            escaped.append("\\t")
        elif char == "\f":
            escaped.append("\\f")
        elif char in " =:#!":
            escaped.append("\\" + char)
        elif codepoint < 0x20 or codepoint > 0x7E:
            encoded = char.encode("utf-16-be")
            for offset in range(0, len(encoded), 2):
                unit = int.from_bytes(encoded[offset : offset + 2], "big")
                escaped.append(f"\\u{unit:04x}")
        else:
            escaped.append(char)
    return "".join(escaped)


def _read_configuration(raw: str | None) -> tuple[bytes, bytes]:
    if raw is None or not raw.strip():
        raise SigningConfigurationError(
            "Missing ANDROID_SIGNING_JSON. Configure the repository's ANDROID_SIGNING secret as JSON with "
            "keystore (base64 PKCS#12), storePassword, keyAlias, and keyPassword. "
            "Release signing cannot fall back to a debug key."
        )
    try:
        encoded_size = len(raw.encode("utf-8"))
    except UnicodeError as error:
        raise SigningConfigurationError("The signing secret must contain valid Unicode text.") from error
    if encoded_size > MAX_SECRET_BYTES:
        raise SigningConfigurationError("ANDROID_SIGNING_JSON exceeds GitHub's 48 KiB secret limit.")
    try:
        values = json.loads(raw, object_pairs_hook=_unique_object)
    except (json.JSONDecodeError, RecursionError) as error:
        raise SigningConfigurationError("ANDROID_SIGNING_JSON must be a valid JSON object.") from error
    if not isinstance(values, dict) or set(values) != FIELDS:
        raise SigningConfigurationError(
            "The signing secret must contain exactly keystore, storePassword, keyAlias, and keyPassword."
        )
    for field in FIELDS:
        value = values[field]
        if not isinstance(value, str) or not value.strip():
            raise SigningConfigurationError(f"The signing field {field} must be a nonempty string.")
        if any(char in value for char in ("\r", "\n", "\x00")):
            raise SigningConfigurationError(f"The signing field {field} cannot contain line breaks or NUL characters.")
        try:
            value.encode("utf-16-be")
        except UnicodeError as error:
            raise SigningConfigurationError(f"The signing field {field} contains invalid Unicode.") from error
    try:
        keystore = base64.b64decode(values["keystore"], validate=True)
    except (ValueError, binascii.Error) as error:
        raise SigningConfigurationError("The keystore field must be standard, unwrapped base64.") from error
    if base64.b64encode(keystore).decode("ascii") != values["keystore"]:
        raise SigningConfigurationError("The keystore field must use canonical base64 encoding.")
    _validate_pkcs12(keystore)
    properties = (
        "# Generated from ANDROID_SIGNING_JSON. Never commit this file.\n"
        "storeFile=signing/streamline-release.p12\n"
        f"storePassword={_property_value(values['storePassword'])}\n"
        f"keyAlias={_property_value(values['keyAlias'])}\n"
        f"keyPassword={_property_value(values['keyPassword'])}\n"
    ).encode("ascii")
    return keystore, properties


def _private_mode(path: Path, mode: int) -> None:
    if os.name == "posix":
        path.chmod(mode)


def _check_existing_keystore(path: Path, expected: bytes) -> bool:
    if path.is_symlink():
        raise SigningConfigurationError("The release keystore path cannot be a symbolic link.")
    if not path.exists():
        return False
    if not path.is_file() or path.read_bytes() != expected:
        raise SigningConfigurationError(
            "An existing release keystore differs from the configured secret. "
            "Use the original signing secret or an intentionally prepared clean workspace; "
            "the existing keystore was not replaced."
        )
    return True


def _stage_file(directory: Path, content: bytes) -> Path:
    descriptor, name = tempfile.mkstemp(prefix=".streamline-signing-", suffix=".tmp", dir=directory)
    staged = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as output:
            if os.name == "posix":
                os.fchmod(output.fileno(), 0o600)
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
    except BaseException:
        with contextlib.suppress(OSError):
            staged.unlink()
        raise
    return staged


def _write_configuration(android_root: Path, keystore: bytes, properties: bytes) -> None:
    if not android_root.is_dir() or android_root.is_symlink():
        raise SigningConfigurationError("The repository must contain a real android/ project directory.")
    signing_directory = android_root / "signing"
    if signing_directory.is_symlink():
        raise SigningConfigurationError("android/signing cannot be a symbolic link.")
    signing_directory.mkdir(mode=0o700, exist_ok=True)
    _private_mode(signing_directory, 0o700)
    keystore_path = signing_directory / "streamline-release.p12"
    properties_path = android_root / "key.properties"
    existing_keystore = _check_existing_keystore(keystore_path, keystore)
    if properties_path.is_symlink() or (properties_path.exists() and not properties_path.is_file()):
        raise SigningConfigurationError("android/key.properties must be a regular file, not a symbolic link.")

    staged: list[Path] = []
    try:
        staged_key = _stage_file(signing_directory, keystore)
        staged.append(staged_key)
        staged_properties = _stage_file(android_root, properties)
        staged.append(staged_properties)
        if not existing_keystore:
            try:
                # An atomic exclusive install also refuses a concurrent writer's
                # different keystore rather than replacing it with os.replace.
                os.link(staged_key, keystore_path)
            except FileExistsError:
                _check_existing_keystore(keystore_path, keystore)
        _private_mode(keystore_path, 0o600)
        os.replace(staged_properties, properties_path)
        _private_mode(properties_path, 0o600)
    finally:
        for temporary in staged:
            with contextlib.suppress(OSError):
                temporary.unlink()


def main() -> int:
    try:
        keystore, properties = _read_configuration(os.environ.get(SECRET_NAME))
        android_root = Path(__file__).resolve().parent.parent / "android"
        _write_configuration(android_root, keystore, properties)
    except SigningConfigurationError as error:
        print(f"Release signing configuration failed: {error}", file=sys.stderr)
        return 1
    except OSError:
        print(
            "Release signing configuration failed: could not write the private signing files. "
            "Check repository permissions and filesystem support for atomic file installation.",
            file=sys.stderr,
        )
        return 1
    print("Android release signing configured.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
