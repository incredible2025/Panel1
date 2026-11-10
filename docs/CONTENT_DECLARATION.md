# First-launch content declaration

The shared declaration in `lib/data/content_declaration.dart` explains that the
developer supplies player software, does not supply media content, and that
content/accounts/subscriptions come from the relevant third-party provider.
It also distinguishes buying the app from obtaining permission to view content
and asks users to use only content they are lawfully entitled to access.

The declaration is an acknowledgement of those statements, not a grant of
content rights. It makes no blanket liability waiver or claim that displaying
the declaration establishes whether any particular content is licensed.

On first launch the app requires an unchecked checkbox followed by
Acknowledge and continue. Until acknowledgement is saved, the update gate,
login and catalogue widgets are not created. Existing installations without an
acknowledgement see it once after upgrading, including saved signed-in users.
Cancelling/back cannot open the app without acknowledging; Android TV uses the
existing exit confirmation. Saved sign-in and history are preserved.

SQLite schema 6 adds installation_declarations with declaration_version and a UTC
acknowledged_at timestamp. No account details are recorded in this table, and
acknowledgement is not transmitted to the management portal. It survives
sign-out, preferences reset, ordinary updates and provider-cache clearing. New
app data requires acknowledgement again. Restoring an app-data backup can also
restore its acknowledgement. Increment contentDeclarationVersion only when
substantively changing the declaration, rather than on each app release.

Settings / App & maintenance / Content declaration shows the same version's text
read-only. Branding comes from the current app identity. Mobile uses touch
controls; TV uses a scrollable reading pane and separately reachable actions.

Tests cover required acknowledgement, write barriers and retries, read failures,
TV Back and D-pad navigation at 540p/720p/1080p, portrait/landscape mobile layouts,
read-only review, installation persistence and migration from schema 5.
