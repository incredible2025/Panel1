# TV interface and remote controls

Android TV uses a dedicated dashboard; phones keep the touch dashboard. Native device detection selects the layout. The interface uses provider artwork and metadata, with title fallbacks when artwork is unavailable.

## Navigation

- Left/Right on the top bar changes section; Down enters that section.
- In a category list, Up/Down moves between categories and OK applies the category. Right enters channels or posters. Up from the first category returns to the top bar.
- Channel lists and poster grids handle repeated arrow events, including movement to items outside the current viewport. Focus is separate from the selected category.
- In Live TV, highlighting a channel updates its programme information after 250 milliseconds. OK opens full-screen playback. Right enters the programme/preview actions; Left returns to the channel list.
- Search opens a dialog deliberately; normal browsing does not focus an editable field. Sorting opens a remote-accessible choice dialog.
- Back from a dashboard section returns Home. Playback, detail pages and dialogs retain their own Back behaviour.

Home provides a featured title, Continue Watching, recent additions and local recommendations. Movie details reuse the existing account-scoped progress and resume logic. Series presents a season list and an episode list, with existing watched markers and resume handling. My List verifies saved titles against the current accessible catalogue; locked/hidden content is filtered out.

Settings opens grouped playback, audio/subtitle, appearance, library/protection, account and network/app controls. Account details stay behind the parental PIN when configured. Existing user preferences continue to control playback, diagnostics and updates.

## Implementation and checks

`TvDashboardScreen` is the TV entry point. `TvControl`, `TvRemoteList` and `TvPosterBrowser` provide visible focus, explicit panel transitions and lazy content rendering. `TvMovieView` and `TvSeriesView` render the TV details while their existing screens retain playback and data ownership.

UI regression coverage includes category selection, restoration of offscreen categories, held-key movement, sort/search, protection and preserved resume behaviour. CI renders fixture previews at 960×540 and 1280×720. Those previews check layout and navigation without requiring provider credentials. Real hardware verification is still useful for device-specific remote key mappings and video decoder behaviour.
