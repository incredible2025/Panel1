# ULTRAVPN PLAYER 0.6.3

- First release using the permanent Android signing key for consistent future updates.
- Release builds now fail if the signing secret is absent or the APK certificate differs from the expected identity.
- Keeps the built-in update address and simplified update controls from 0.6.2.

Download `ultravpn-player.apk` to install. Moving from a testing build may require a one-time uninstall, which clears saved login, preferences and local history. Later releases signed with this same permanent key can update in place.

For server hosting, extract `remote-update.zip`, upload `ultravpn-player-0.6.3.apk` to `https://ultra-vpn.store/dl/app/` first, then replace `update.json` from the same package. A permanently signed 0.6.3 installation needs a later version with a higher build number to test an update offer.
