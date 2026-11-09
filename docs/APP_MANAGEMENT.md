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

The developer uses the same codebase, the exported profile and the brand’s own assets and Android release key to build that app. `scripts/prepare_managed_profile.py` prepares private Flutter defines. `scripts/build_managed_android.ps1` sets the matching native package identifier and builds the combined ARM APK. Reseller builds disable legacy primary-account migration by default. Keep build profiles outside public release assets.

Portal settings cannot overwrite compiled branding. Each branded APK must retain its own application identity and release key across later updates. Shared code improvements still need a new APK for each branded variant; this version of the portal does not build or upload APKs.

## Publish an APK update

Keep each brand’s APKs and update manifest in its own hosting folder. Upload the APK files first, then replace that brand’s update manifest last. The manifest must describe the exact APK bytes, actual Android build number and matching package identity. Keep the stable APK filename for initial-download links. Android still asks the customer to approve installation.

## Owner and staff

Public registration is disabled. The owner registers apps and manages staff. Staff can edit and publish existing apps. Two-factor authentication is optional and remains available under Account security. An installation can require it by enabling its management setting.

Save private portal backups off-server as well as locally. Configure outgoing email before relying on password-reset or email-verification messages. Public configuration is signed for authenticity; addresses supplied to an installed client cannot be made impossible to extract.

Windows management is not enabled in this release. Its existing updater and installer identity remain separate.
