# Streamline 0.5.0

## A new place to watch

- Midnight-blue and cyan interface with a cinematic Home destination, large featured artwork, Continue Watching, My List, recently added films and favourite channels. Optional Cinema theme, larger posters, compact spacing and reduced motion.
- Five mobile destinations and a TV navigation rail that expands on focus: Home, Live TV, Movies, Series and Settings.
- Live TV pairs channel navigation with programme information and an optional muted preview. A preview is stopped before full-screen playback opens.

## A player that gets out of the way

- Controls, title, logo and gradient hide after five seconds of playback. Choose three, five, eight seconds or Never in Settings. Tap or press OK to reveal them. Pause, errors, open menus and episode countdowns remain actionable.
- Remote Back first hides visible controls during playback, then exits. The on-screen Back button exits directly.
- Now/Next programme information, a quick channel switcher and diagnostics for reported resolution, codecs, audio channels and playback state.
- ExoPlayer remains the default. A built-in media_kit compatibility engine can be selected globally or overridden per channel/title. Both share resume/history, episode transitions, remote controls and recovery handling.
- Saved picture, audio-language, stereo-track preference and subtitle defaults, language, size and text-background settings. Device/stream support determines available tracks and audio output.

## Recommendations from your own viewing

Movie shelves explain their source: **Because you watched …** and **Picked for you**. They use meaningful movie playback, provider categories, recency, progress and supplied ratings. Opening a detail page alone is not a viewing signal. Already-watched films, duplicate editions, unavailable titles, hidden categories and locked content are excluded.

Recommendations run on this device, are separate for each account and can be disabled. No viewing history is uploaded to a recommendation service. The interface shows an honest starter message when there is insufficient viewing history or similar content.

## Settings, account and parental controls

- Refresh account status, provider, username, expiry, days remaining and connection counts. Missing provider fields show **Not supplied**. Home/library notices highlight expiry within seven days.
- Hide, reorder or PIN-protect categories and reorder favourite channels with touch or remote controls.
- Parental PINs use salted PBKDF2 in encrypted secure storage, with throttling after repeated failures. Protected browsing/settings access lasts five minutes and relocks on backgrounding. An already-authorized playing title continues; returning from the background requires unlocking before protected playback resumes.
- Restore the last section/category/channel selection. Refresh the library/guide, clear provider cache, reset preferences, view open-source licences or sign out. History and My List are retained.
- SQLite v4 upgrades preserve existing movie/series history and saved collections.

Download **streamline.apk** for Android mobile or Android TV (Android 7.0+). The universal APK is larger because it includes both playback engines.

Permanent signing remains deferred; this is a testing-key APK. Global search remains excluded. Real-provider codecs, alternate-engine playback, audio output and device-specific remotes still need testing on the intended phone/TV.
