# Glass UI route inventory — 0.8.4

All app-owned routes use the Glass brand and Inter typeface. Television surfaces use the approved 1024 × 576 design units, scaled to the display, with bounded remote navigation. Touch surfaces adapt the same visual tokens to phone interaction. The Android installer and optional system keyboard are supplied by Android.

| Surface | Design and interaction |
| --- | --- |
| Native splash and storage failure | Existing operator logo, updated navy background, shared typography and retry action |
| Launch update gate | Branded check before login/Home; fixed TV Update/Retry and Continue controls |
| Login | Glass credentials canvas, visible updates action, built-in TV remote keyboard; masked passwords |
| Home | Fixed TV hero and two shelves with shelf selector; shared Glass branding on mobile |
| Live TV | Compact category/channel/EPG columns, programme details, preview and playback actions |
| Movies / Series / My List | Glass artwork rails and category/grid browsing; sorting and personal history |
| Movie details / resume prompt | Fixed TV actions and progress; bounded synopsis/cast pane; branded resume choice |
| Series details | Fixed season/episode columns, resume action and separate synopsis panel |
| Search / guide filter | Same built-in TV keyboard as login; mobile touch input |
| Full TV guide | Glass utility frame, compact schedule rows, remote-readable programme descriptions |
| Player | Navy overlays, shared Inter controls, existing timed hide/reveal and transport behavior |
| Player options / engine / audio / subtitles / channels | Bounded selectable lists; no inaccessible lazy native list controls |
| Playback diagnostics / programme / series information | Fixed actions around a separately focusable reading pane |
| Settings overview / all six settings groups | Fixed Glass sections/options/description panels and retained option focus |
| Categories / favourites | Remote lists with complete rows and explicit region navigation |
| Parental controls | Branded prompt and built-in masked numeric keypad for create/confirm/unlock |
| Speed test | All four metrics and Start/Stop/Run again/Copy remain visible; separate notes pane |
| Connection diagnosis | Checks beside full evidence, causes and next steps; fixed run/stop/copy actions |
| App updates | Fixed check/download/install actions and release-notes pane; hidden feed address |
| Licences | Bounded reading pane, remote scrolling and Back |
| Loading / empty / error / confirmation states | Shared Glass theme, colors, buttons and typography |

## Startup policy

The launch gate calls `UpdateController.check` directly, bypassing the twelve-hour `autoCheck` throttle. Login and Home are not built before the check resolves. A current version enters the app; available updates and failures require a user action. Checks time out after eight seconds, cancel the transport and suppress late network starts/results. Preference persistence is separately bounded. A cold launch checks again even after a recent launch. Resuming an existing process keeps the background-check throttle.

## Validation

Widget checks cover delayed success, available updates, retries, failure continuation, recent-check bypass, recreated launch checks, network/native-init deadlines and late completions. Startup actions are checked at 960 × 540, 1280 × 720, 1920 × 1080 and portrait/landscape phone sizes. TV captures exercise Settings groups, login/keyboards, speed, diagnosis, updates, licences and new startup/detail/information layouts at three television sizes. Existing playback, EPG, history, security, remote keyboard and focus tests remain part of the release suite.

These are automated widget/render checks. Physical TV, real provider streams and the device's Android installer require installation testing on the target hardware.
