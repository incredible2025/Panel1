# Release communication

- Keep customer-facing release notes brief: two to four plain-text points about user-visible improvements. Follow docs/RELEASE_NOTES_POLICY.md.
- Never disclose provider IPs, domains, portal or stream URLs, credentials, diagnostic connection details, signing information or deployment instructions in release notes, public change summaries, PR titles/bodies or commit messages.
- Refer to connection changes generically, for example "Improved service connectivity." Keep necessary configuration in its existing source location; do not copy it into announcements or logs.
- Validate the current notes with scripts/public_release_notes.py. Both the update manifest and GitHub release must use the same validated public copy. Preserve the app's display filter for legacy or manually edited feeds.
- Keep the stable APK filename, application identity and permanent release signing compatible with existing installations. Increase the actual Android build number for a new APK release.
- Keep Windows and Android update manifests and packages separate. Preserve the Windows installer name and installation identity across releases. Run the native Windows smoke checks before publishing its installer or portable app.
