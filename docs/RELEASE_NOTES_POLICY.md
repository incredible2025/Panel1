# Public release notes

Write two to four short points describing improvements customers will notice.
Keep notes under 600 characters, five non-empty lines and 160 characters per line.
Use plain text bullets without a version heading; the app already shows the version.

Never include provider addresses, domains, IP addresses, credentials, connection
configuration, diagnostic evidence, signing details, hashes or deployment instructions.
Keep engineering and hosting instructions separate from public release notes.
Do not copy a commit message, PR description or test report into the public notes.

The release workflow validates notes before building, and uses the same validated
copy for the update manifest and GitHub release. Missing or unsafe notes fail the
release rather than falling back to technical copy. Validation errors never echo
the rejected text. The app also substitutes a short generic summary for unsafe
or excessively long notes from older or manually edited feeds. Updates remain
available even when their description is withheld.

Remote hosting is managed separately. Replace its manifest to correct notes for
users with older installed apps; publishing a GitHub release cannot change that
server automatically. A notes-only correction must preserve all APK metadata.
