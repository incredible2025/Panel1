# ULTRAVPN PLAYER branding

Prepared for the next release; not yet published as an APK.

## Assets and use

- `assets/branding/ultravpn-player.jpg`: the user's supplied full artwork, copied unchanged. Displayed in the Settings branding card.
- `assets/branding/ultravpn-shield.png`: transparent shield/play mark derived from that artwork with the built-in image generation tool. Used for small in-app marks and the launcher.
- `lib/core/app_brand.dart`: the public display name and asset paths.
- `StreamlineMark`: the existing internal widget name is retained; it now displays the supplied brand's shield and a two-line ULTRAVPN / PLAYER wordmark.
- `android/app/src/main/res/drawable-nodpi/ultravpn_shield.png`: native copy for launcher and splash resources.
- `android/app/src/main/res/drawable-xhdpi/ultravpn_tv_banner.png`: 320 × 180 banner rendered from the real Flutter `UltraVpnBanner` widget.
- Launcher resources include a legacy Android 7 icon, adaptive Android 8+ icon and Android 13+ themed icon layer. The foreground is inset to protect the shield under launcher masks.
- Native launch backgrounds use the same midnight blue as the app and display the shield. Android 12+ splash resources are also updated.

The display name, licence-page heading, player title, diagnostic-report heading and visible app branding use ULTRAVPN PLAYER. Internal Dart/font names, package ID `com.streamline.iptv`, MethodChannels and account/database identities remain stable so existing installations and local collections can be updated.

The brand name does not change the application's functionality: it remains a player with connection diagnosis; no VPN tunnel or DNS configuration feature has been added by this rebrand.

## Regenerate the TV banner / review sheet

Run `flutter test tool/render_brand_assets.dart`. This renders the actual brand widget, producing the native TV PNG and `build/qa/ultravpn-brand-preview.png`. Keep the font assets and wordmark widget in sync with the export. The original full JPG is never rewritten.

References: [Android adaptive icons](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive), [Android TV launcher icon and banner guidance](https://developer.android.com/design/ui/tv/guides/system/tv-app-icon-guidelines).

## Image preparation record

Mode: built-in `image_gen`, edit of the user-supplied logo, transparent background. No CLI/API fallback was used.

Prompt:

> Edit target: the attached ULTRAVPN PLAYER logo. Create one square transparent PNG production asset containing ONLY the existing central cyan/blue/teal U-shaped shield and its embedded triangular play symbol. Faithfully preserve the exact shield silhouette, open U top, beveled 3D edges, cyan-to-blue/teal gradients, proportions and play triangle from the supplied image. Remove ALL words, surrounding rounded-square frame, circuit lines, background, cast shadows outside the symbol and atmospheric glow. Do not invent, redesign, simplify into a different shield, or add details. Crisp clean alpha edges, no fake checkerboard or opaque backdrop. Center the complete symbol tightly in the square canvas, with about 6% transparent margin on each edge; it will be inset separately for Android launcher safe areas. No text at all. Output a single square asset.

## Suggested additions, awaiting scope selection

1. **Automatic player fallback:** an optional switch to the alternate playback engine after a genuine playback failure, preserving the movie/episode position and avoiding fallback loops for account, network or subscription errors.
2. **Backup and restore:** portable favourites, My List, category preferences and watch history, with clear handling of credentials and parental protection rather than silently exporting them.
3. **Provider profiles:** save more than one provider/account securely and switch without re-entering credentials, retaining the existing account isolation.
4. **EPG time adjustment:** an account-specific guide offset and preview for providers whose schedules are shifted, separate from the device clock.

These are proposals, not features implemented in this branding change. Global search and permanent signing remain outside the accepted scope from earlier releases.
