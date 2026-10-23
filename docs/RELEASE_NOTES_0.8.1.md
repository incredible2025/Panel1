# Ultravpn-player 0.8.1

Fixes TV login remote activation. Username and password are explicit remote targets; OK opens a focused text-entry dialog and the platform keyboard. OK can reopen the keyboard after dismissal. Select, Enter, numpad Enter and gamepad A are supported. Native keyboard connection closure returns cleanly to login with the draft intact. Completed input advances focus to the next login control, and passwords stay masked unless explicitly revealed. Repeated activation cannot stack entry dialogs.

TV login uses a fixed Glass layout with a permanently visible App updates action in the header. Connection diagnosis, validation errors and sign-in stay reachable without scrolling. Mobile keeps its existing text-field sign-in flow.

TV Home is a fixed canvas with a compact hero and two complete horizontal content rows. Additional recommendations, continue-watching and history collections are selected using the collection row; the page itself never scrolls vertically. Explicit remote paths connect the hero, collections, both rows and main navigation. Existing Movies and Series browsing pages retain their library controls.

Version 0.8.1, Android build 21. App identity, signing certificate, stable Ultravpn-player.apk filename and embedded update endpoint are unchanged. Upload both APKs from remote-update.zip before replacing update.json.
