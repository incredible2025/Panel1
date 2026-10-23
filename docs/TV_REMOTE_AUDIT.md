# TV remote regression coverage

The 0.7.0 checks validated rendered layouts and individual button activation but did not exercise the complete update journey with long release notes. This allowed an offscreen action to be missed. The new checks navigate using remote key events from the initial focus; they do not tap, drag, call ensureVisible or assign focus to bypass navigation.

## Required checks before release

- Settings navigation: enter from the dashboard, reach the offscreen App updates shortcut, return with Back, open Speed test, return to the category column and enter App & maintenance.
- Maintenance: reach Speed test, Connection diagnosis and App updates in order, including restoration after returning from a route.
- Every Settings group: traverse to its final actionable control and verify focus does not wrap away before reaching it.
- Updater: Check → available → Download → ready → Install → permission → Install; preserve the primary focus through state changes.
- Long descriptions: independently scroll release notes with held arrows while Download/Install remains visible. Repeat at 960×540 and 1280×720, with 100% and 130% text scaling.
- Download cancellation: cancel with Select, retain focus and successfully retry.
- Management: navigate well beyond the visible category list and use its OK menu; preserve focus when the record changes. Favourite ordering uses the same virtualized remote list and menu controls.
- Existing coverage: Live TV/movie/series categories, offscreen restoration, held-key grids, sort/search, movie/episode resume, player controls, track/engine choices, guide, parental protection, diagnostics, speed tests and mobile layouts.

`TvPageNavigation` gives utility forms a bounded vertical focus order and reveals the focused control. Utility forms build their finite controls eagerly; provider catalogues remain virtualized. `TvScrollPane` gives read-only content its own focus target and scroll controller. The updater keeps actions outside that scroll area.

CI runs formatting, analysis and the full suite before compiling Android. Rendered previews supplement the remote journeys. Real-device remote mappings and the system installation/permission screens require hardware verification; those external screens are represented by a fake platform in widget tests.
