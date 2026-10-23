# Ultravpn-player 0.7.1

Fixes TV update controls becoming unreachable when release notes extend beyond the screen. The TV updater keeps Check, Download, Cancel and Install in a fixed action column. Release notes and errors have a separate remote-scrollable panel. Left reads the details; Right returns to the primary update action. Focus remains on that action through download, permission and installation states.

TV utility pages now use a predictable Up/Down order and reveal focused controls, including those below the initial viewport. Settings shortcuts, grouped Settings, speed tests and diagnosis are included. Category and favourite management use lazy remote lists with OK menus for ordering and visibility/protection actions. Long movie descriptions can be read with the remote.

Regression checks exercise the dashboard-to-updater journey using only remote events, every Settings group, long notes, larger text, download cancellation/retry and installer permission handling. Existing playback, guide, resume, PIN, account isolation and phone tests run before Android compilation. Automated checks do not replace testing device-specific remote firmware or Android's external installer on real hardware.

Version 0.7.1, Android build 18. The permanent signing identity and stable filename `Ultravpn-player.apk` are unchanged. Upload both APKs from `remote-update.zip` before replacing `update.json`.
