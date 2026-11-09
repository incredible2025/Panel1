# Managing Android apps

The portal manages connection settings for each Android app independently. It does not collect customers’ usernames, passwords or viewing history. Branding, icons, application identity and the Android release key remain part of each app build.

## First installation

Existing APKs need one compatible app update before they can receive portal settings. Install the managed Android release over the existing app. Keep the same application identity and release certificate; do not uninstall it to perform this upgrade. The primary app preserves its existing account storage, favourites, watch progress, preferences and parental PIN.

The primary brand’s public verification key and signed offline bootstrap live alongside its existing connection configuration in source. Normal primary builds retain that configuration automatically. The private portal signing key never enters an APK or this repository.

## Change an address for the same service

1. Sign in and open the app card.
2. Edit its primary address, optional fallback and/or HTTPS update manifest address.
3. Choose **Save draft**. Review the saved settings beside the form.
4. Choose **Publish saved draft**.

Managed apps check at launch, on returning to the foreground, and every five minutes while active. An existing healthy stream continues; subsequent API and playback requests use the new addresses. A network configuration check has a three-second deadline. During an outage the app keeps its newest verified local configuration, with a signed build bootstrap available for first offline launch.

Only transport reachability failures allow fallback. Certificate errors, DNS failures, rejected account requests and malformed API responses do not cause an insecure retry. Publishing settings is separate from publishing a new APK.

## Replace a provider

Use **Replace with a different service** only when the backend service itself changes. Enter the new settings and type the confirmation shown in the portal. This creates a new service identity, closes active app navigation and requires a fresh sign-in. Stored credentials from the old service are never silently forwarded to the replacement. Historical account data stays isolated and is not deleted.

Use publish history to restore previous settings. A restore creates a higher configuration revision. Staff may restore settings for the current service; only the owner can restore a different service identity.

## Add another brand

The owner registers its name, a permanent app identifier, a unique Android package identifier, service addresses and an HTTPS update manifest address. Publish the first configuration, then choose **Download build profile**.

The developer uses the same codebase, the exported profile and the brand’s own assets and Android release key to build that app. `scripts/prepare_managed_profile.py` prepares private Flutter defines. `scripts/build_branded_android.ps1` combines that profile with a branding manifest and private release credentials. It stages an isolated workspace, renders launcher artwork, and builds the combined ARM APK without changing the primary app. `scripts/package_branded_android.py` verifies the actual native identity and produces the three-file update ZIP. Reseller builds disable legacy primary-account migration by default. Keep build profiles outside public release assets.

Portal settings cannot overwrite compiled branding. Each branded APK must retain its own application identity and release key across later updates. Shared code improvements still need a new APK for each branded variant. The release centre uploads and publishes built packages; building them remains a separate developer operation.

## Publish an APK update

Keep each brand’s APKs and update manifest in its own hosting folder. Upload the APK files first, then replace that brand’s update manifest last. The manifest must describe the exact APK bytes, actual Android build number and matching package identity. Keep the stable APK filename for initial-download links. Android still asks the customer to approve installation.

### Automatic upload cleanup

Use `scripts/submit_android_upload.py` with the packaged ZIP and its local `verification.json`, SSH host/user and independently verified host fingerprint. It prompts for the password without saving it. Install Paramiko in the operator's Python environment. This submits to the private upload inbox; uploading files directly to the public download folder does not invoke the processor. The dashboard release centre is an alternative upload path; APK building remains separate.

The server's `app-manager-uploads.timer` checks completed jobs every minute. A ZIP is uploaded with a temporary name, then a small ready marker is renamed into place last. `scripts/publish_uploaded_android.py` checks the pinned bundle checksum, expected app identity, exact archive contents, both APK checksums and public release notes before publishing. Native identity and release-certificate verification remain mandatory in the preceding packaging step; a checksum is not a substitute for signing verification.

The operator SFTP processor publishes into an immutable version/build folder and replaces the permanent download links, with `update.json` last. Dashboard uploads instead prepare a verified candidate and wait for an owner release action. Increment both the Android build number and the versioned APK filename for a new release. Retrying an identical operator upload is safe. The two APK names share their bytes through a hard link. On successful processing the uploaded ZIP, private extraction folder and ready marker are removed. Local build files are not deleted.

## Dashboard release workflow

1. Open the brand and upload its three-file update ZIP in **Release centre**. The browser shows upload progress; verification then runs in the background. Refresh to see Ready or Failed.
2. Native verification compares the actual Android package, version, APK integrity and permanent certificate against the operator's allowlist. A ZIP/report supplied by the uploader cannot select its own trusted certificate. Failed packages stay private for operator inspection.
3. In an updated Android app, choose **Settings → App & maintenance → Management & support → Link test device**. The owner enters the six-digit code and a device label on that brand's dashboard. Codes last ten minutes and work once.
4. The owner chooses **Offer to testers**. Paired installations receive the candidate through their updater. Existing public APK links and ordinary devices keep the public release.
5. After testing, choose **Publish to everyone**. The worker promotes the same verified bytes and permanent download links. No new Downloader code is needed. Removing a tester or withdrawing a candidate never downgrades an installed APK.

Staff may prepare uploads and retain their existing settings permissions. Only the owner can manage testers, release packages or inspect the staff activity log. The activity log stores action summaries, not connection addresses or credentials. Two-factor authentication remains optional.

Candidate URLs are immutable download locations, not access-controlled content. Tester selection controls which update is offered automatically; somebody given an APK can still share it. Retention preserves the two newest registered public releases, protected downloads and pending candidates. Withdraw unused candidates to reclaim their package space.

## Activity and remote app information

Compatible Android installations report once a minute while foregrounded, including on the login screen. Online now means seen within three minutes. Active today counts distinct installations using the displayed portal timezone. A person using two installations counts twice; reinstalling/clearing app data may create a new identity. Older versions, offline devices and interrupted reporting are absent, so these are estimates, unsuitable for billing or account enforcement.

Each report contains only an anonymous installation credential, app version/build and applied signed-configuration revision. The server stores its hash and last-seen time; reports do not contain IPTV credentials, watched content, hardware identifiers or customer IP fields. Dashboard pages show version distribution and configuration acknowledgement for devices seen within thirty days. Inactive rows are removed after thirty days. Runtime reporting failure never blocks app use.

Expand **Maintenance notice & support** in the draft settings to edit the optional plain-text notice, required UTC expiry, support email, HTTPS website and help message. Save and publish normally. Notices appear on login/home, can be dismissed and expire without interrupting a stream. Support and pairing use the existing TV remote-friendly settings layout. Old configuration revisions without these fields remain valid.

The managed update endpoint serves the existing public manifest shape to old clients without installation credentials, and selects a higher test build only for a paired reporting installation. Responses are private/no-store. Updater credentials are restricted to the exact management feed endpoint and are not forwarded to APK hosts or other redirect destinations. Windows feeds/installers remain separate.

## Release worker setup

The private worker allowlist additionally requires each brand's `certificateSha256` and `publicBaseUrl`, plus host `aapt`, `apksigner` and `receiptDirectory` settings. Set `requireNativeVerification` to true so operator uploads cannot bypass the same checks. Trust fingerprints must come from the established release keys. The web container gets write access only to the private inbox and read-only access to worker receipts; it gets no APK signing key or worker allowlist. Create the host group `app-manager-web` with the container web-service GID (82 for the supplied image); the worker uses this group to read uploaded files while keeping its private state protected. Exclude inboxes, receipts, state, deployment backups and release tools from Docker build contexts.

Use the provided uploads timer for native processing and scheduler timer for receipt reconciliation and daily housekeeping. Import existing public releases only after independent native verification, using a worker `adopt` receipt and `management:import-release`. Activate each app's managed update feed only after its public release has been imported. Worker operations are prepare/promote/retire, with durable statuses and idempotent recovery. The private backup includes the database, signing configuration and small release metadata; APK archives still need independent distribution/storage protection.

Keep the two newest successfully published releases per app for rollback. Only releases registered by the processor (including the prior release adopted through its existing stable APK link) are eligible for removal. Unknown files, other apps and signing credentials are never swept. Existing published ZIPs and workflow dependencies must be listed as protected artifacts; protecting a file also preserves its enclosing release folder. New uploaded ZIPs are temporary, not public downloads. A failure keeps the ZIP/extraction for inspection, renames the job to `.ready.failed`, and leaves the active release available. A cleanup failure after publication does not undo the successfully published release. Inspect the failed job and resubmit after correcting it; there is no unattended retry loop for failed uploads.

Server installation uses the included systemd service/timer and a private `uploads.json` beside the release scripts. The configuration contains `inbox`, `stateDirectory`, `protectedArtifacts` (absolute paths), and an `apps` map keyed by app identifier. Each app entry specifies its exact public `directory`, `packageId`, and `stableApkName`. Keep this allowlist, upload inbox and state directory outside the web root and writable only by the deployment operator. Copy `public_release_notes.py` alongside the publisher. Add new brands to this allowlist before submitting their first release. The worker has no access to signing keys and never changes app configuration in the portal. Windows packages/manifests are outside this process.

## Owner and staff

Public registration is disabled. The owner registers apps and manages staff. Staff can edit and publish existing apps. Two-factor authentication is optional and remains available under Account security. An installation can require it by enabling its management setting.

Save private portal backups off-server as well as locally. Configure outgoing email before relying on password-reset or email-verification messages. Public configuration is signed for authenticity; addresses supplied to an installed client cannot be made impossible to extract.

Windows management is not enabled in this release. Its existing updater and installer identity remain separate.

## Repeat a branded build

Keep the non-secret branding manifest and source logo under `brands/<app-id>/`. Keep exported portal profiles and release credentials in ignored private storage. Increase that brand’s versionCode before publishing another release, keeping its package identifier and stable APK filename unchanged. The build script sets the Flutter display version and Android version together. The test brand starts at version 0.9.0, build 43.

Primary publication runs only when the primary version has a new release tag to create. Building a test brand does not replace the primary APK or its update feed. Branded packages are hosted in their own folders and do not become the primary GitHub release.
