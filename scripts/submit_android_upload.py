#!/usr/bin/env python3
"""Submit a locally verified release to the private Android upload queue over SFTP."""
import argparse
import base64
import getpass
import hashlib
import json
from pathlib import Path
import posixpath
import uuid

from publish_uploaded_android import digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verification', required=True, type=Path)
    parser.add_argument('--bundle', required=True, type=Path)
    parser.add_argument('--host', required=True)
    parser.add_argument('--user', required=True)
    parser.add_argument('--port', default=22, type=int)
    parser.add_argument('--fingerprint', required=True, help='Independently verified SHA256 SSH host fingerprint')
    parser.add_argument('--inbox', default='/opt/app-manager/upload-inbox')
    args = parser.parse_args()
    # Paramiko is an operator dependency, not an app or portal dependency.
    import paramiko

    report = json.loads(args.verification.read_text(encoding='utf-8'))
    checksum = digest(args.bundle)
    if (report['bundleSha256'] != checksum or report['bundleBytes'] != args.bundle.stat().st_size
            or report['bundleName'] != args.bundle.name):
        raise ValueError('Bundle does not match the locally verified build report.')

    class Pinned(paramiko.MissingHostKeyPolicy):
        def missing_host_key(self, client, hostname, key):
            actual = 'SHA256:' + base64.b64encode(hashlib.sha256(key.asbytes()).digest()).decode().rstrip('=')
            if actual != args.fingerprint:
                raise paramiko.SSHException('SSH host fingerprint mismatch.')

    token = uuid.uuid4().hex
    remote = posixpath.join(args.inbox, token)
    job = dict(appId=report['appId'], bundle=token + '.zip', sha256=checksum)
    with paramiko.SSHClient() as client:
        client.set_missing_host_key_policy(Pinned())
        client.connect(args.host, port=args.port, username=args.user,
                       password=getpass.getpass('SFTP password: '),
                       look_for_keys=False, allow_agent=False, timeout=20)
        with client.open_sftp() as sftp:
            sftp.put(str(args.bundle), remote + '.upload')
            sftp.chmod(remote + '.upload', 0o600)
            sftp.rename(remote + '.upload', remote + '.zip')
            with sftp.open(remote + '.job-upload', 'w') as stream:
                stream.write(json.dumps(job))
            sftp.chmod(remote + '.job-upload', 0o600)
            # Ready marker is last, so polling can never read a partially uploaded ZIP.
            sftp.rename(remote + '.job-upload', remote + '.ready.json')
    print('Verified release queued. Server cleanup runs after successful publication.')


if __name__ == '__main__':
    main()
