# Streamline visual system · v0.5

The current design and interaction specification is [V0.5_DESIGN.md](V0.5_DESIGN.md).

## Visual foundations

Midnight-blue canvas (#060E1B), layered navy surfaces (#101D30 / #172840), cool-white typography (#F4F8FF) and cyan interaction accents (#64D9F5) create the shared mobile/TV palette. Cinema mode uses neutral black and ivory for the main theme surfaces and controls.

Bundled Roboto and Roboto Condensed keep typography predictable without a network font dependency. Large editorial titles, clear metadata and restrained uppercase labels establish hierarchy. Provider artwork receives directional gradients so titles and actions remain readable. Missing artwork uses a title-seeded abstract cover rather than invented media.

## Composed screens

- Home: a large provider-backed featured title, Continue Watching, explained local recommendations, recently added movies, saved titles and favourite channels.
- Movies and Series: cinematic introductions, horizontally scrolling artwork shelves, category/saved filters and a full poster grid. Detail screens retain synopsis, metadata, resume actions and episode progress.
- Live TV: channel navigation beside a large programme/preview panel. Preview is optional and muted; full-screen playback releases it first.
- Settings: grouped cards for playback, audio/subtitles, appearance, library/parental controls, account and maintenance. Wide screens use two columns.
- Player: chrome disappears during playback, including the dark scrim and branding. Subtitles remain visible. Menus, pause, errors and countdowns retain reachable controls.

## Focus, density and motion

TV uses a navigation rail which expands on focus. The selected control has a bright outline, subtle background and restrained scale. Mobile has five bottom destinations. Large-poster, compact-layout and reduced-motion preferences affect the actual components.

Account/category protection applies before fetching protected details or opening playback. It also filters Home, recommendations and guide content. Expiry notices use provider data and never invent account dates.

## Verification

Flutter widget checks exercise phone portrait/landscape and television layouts, including Settings, Home, recommendations, category filtering and remote navigation. Reviewable previews are written to build/qa using the real widgets. See [TESTING.md](TESTING.md) for capture commands and physical-device acceptance checks.
