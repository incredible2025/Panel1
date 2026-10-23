# Ultravpn-player 0.8.4

The Glass design now extends through movie and series details, full TV guide, search, player menus, programme information, startup and error states. Shared Inter typography, blue glass surfaces and cyan accents replace the older condensed text and grey/gold treatments. Both appearance choices use the new design, with a darker Midnight option. Touch layouts use the same branding.

TV movie details keep Play/Resume, My List and refresh visible beside a separately scrollable synopsis and cast. Series details use compact season and episode columns with a separate information panel. Search and guide filtering use the built-in remote keyboard. Player, audio, subtitle and channel menus use bounded lists with explicit D-pad movement; long information uses a remote-readable panel.

Every cold launch checks the embedded update feed before opening login or Home, even when an earlier check was recent. An up-to-date app proceeds automatically. A newer version offers Update now or Continue to app; Android still asks the user to approve installation. Failed checks offer Retry or Continue and never claim the app is up to date. Startup requests have an eight-second deadline and can be retried. Returning from the installer does not trigger another launch gate. Background/resume checks retain their existing throttle.

Version 0.8.4, Android build 24. The package identity, permanent signing certificate, hidden portal/update feed, account data and watch history remain compatible. Upload both APKs from remote-update.zip first, then replace update.json. Ultravpn-player.apk remains the stable Downloader filename.
