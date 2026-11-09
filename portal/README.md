# App Manager

Private owner/staff portal for independent Android app configurations. It manages service addresses and update-feed locations; it does not upload APKs or build reseller apps.

## How it works

1. The owner registers a brand with its permanent app/package identifiers and saves its initial draft.
2. Owner or staff review and publish the saved draft. Unpublished edits never appear in the configuration API.
3. A build profile exports a signed bootstrap, public verification key and per-app configuration endpoint. An Android build must include the managed-configuration client before it can consume these settings. Existing published APKs do not gain this capability merely by installing the portal.
4. Address moves for the same service retain its UUID. Replacing a provider explicitly creates a new UUID and requires customer sign-in. Rolling back publishes a higher revision, rather than replaying an old revision number.

The public API intentionally supplies app connection settings to clients. Signatures authenticate those settings; they do not encrypt them or make embedded addresses impossible to extract. Customer usernames, passwords and viewing histories are never submitted to this portal.

## Access

Public registration is disabled. Only an owner can register apps or manage staff. Two-factor authentication is optional by default. An operator can require it for all management pages with MANAGEMENT_REQUIRE_2FA=true. Staff can save drafts and publish existing apps. Revoking staff access disables their sessions. Account deletion is disabled to preserve publish history.

Create the first owner with `php artisan management:owner`, or issue a single-use one-hour setup link with `php artisan management:invite-owner`. An owner invitation stops working immediately after the first owner exists. Save authenticator recovery codes privately. Configure SMTP before relying on emailed password recovery or email verification; the default log mailer does not deliver messages.

## Runtime and deployment

PHP 8.3 or newer is required, with Sodium, SQLite/PDO, mbstring, intl, zip and the normal Laravel extensions. This repository includes a Docker deployment using a private PHP-FPM container and Nginx. Only the public directory may be served by the web server. Keep deployment environment, SQLite data, signing key and backups outside the public webroot. Never commit or upload them as release assets.

`deploy/compose.yaml` attaches the web container to an existing reverse-proxy network. Set the external network name for the installation. The supplied Nginx configuration mounts the portal under `/app-manager/` on an existing HTTPS host. The reverse proxy must forward that path unchanged. The SQLite file is stored under `data/database`, and the application/signing keys remain in private deployment data. Do not regenerate them during an upgrade.

Generate production assets with `pnpm install --frozen-lockfile` followed by `pnpm run build`. Create a private deployment environment from `.env.example`, using a unique application key and session cookie. Set APP_URL and ASSET_URL to the actual HTTPS mount path, SESSION_PATH to that mount path, and DB_DATABASE to the private SQLite path. Then build the app container, run migrations with `--force`, initialize configuration signing, and create the first owner. No default administrator password is shipped.

The reference backup service uses SQLite’s online backup API, checks database integrity, and archives the signing key and deployment environment with restricted permissions. Copy private backups off-server; a same-server backup does not protect against server loss. Restore database, signing key and environment together. Test restoration before relying on backups.

## Validation

Run `composer install`, then `php artisan test`, and build the frontend. Tests cover role separation, mandatory 2FA, signed payload verification, app isolation, draft publication, replay-safe rollback revisions, optimistic editing conflicts, service replacement, invalid addresses and first-owner setup.
