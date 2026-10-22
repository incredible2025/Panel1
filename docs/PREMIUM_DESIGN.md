# Streamline visual system · v0.3

Streamline pairs an ink charcoal interface with ivory typography and restrained champagne accents. Provider artwork leads the experience; fine borders, layered gradients and generous spacing keep navigation and playback controls readable on phones and televisions.

## Color and typography

The shared tokens and Material theme live in [`lib/core/design_system.dart`](../lib/core/design_system.dart).

| Role | Token | Color |
| --- | --- | --- |
| App background | `canvas` | `#0B0D10` |
| Cards and panels | `surface` / `surfaceRaised` | `#14171C` / `#1C2026` |
| Fine rules and borders | `border` | `#2C3035` |
| Primary actions and selected states | `accent` | `#DEC48D` |
| Primary text | `text` | `#F5F2EA` |
| Supporting text | `muted` | `#ABB0B8` |
| Live status | `live` | `#E78277` |

Bundled Roboto Condensed gives titles a cinematic display style; Roboto supports forms, controls and metadata. Both load locally, including when the device is offline. Their licenses are included in [`assets/fonts`](../assets/fonts).

`StreamlineMark`, `Eyebrow` and `MetaPill` provide consistent branding, section labels and metadata. Filled buttons identify the main action; outlined and text buttons provide quieter secondary actions.

## Screen composition

- **Login:** an atmospheric brand composition and a compact account form, with a landscape arrangement for television.
- **Live TV:** a channel guide with a selected-channel panel, current/upcoming EPG and a clear Watch action. Favorite and recently played channel shelves provide shortcuts; the star control and Favorites filter expose the saved collection.
- **Movies and series:** a streaming-service-style home of contextual featured artwork and horizontal poster shelves. Up to five provider categories appear as home rows; Browse all opens the full lazy grid. Category/search controls and Newest/A–Z/Z–A sorting remain available. Movies retain Continue Watching and Recently Watched rows.
- **Movie details:** a cinematic backdrop, cover poster, prominent title, provider metadata, synopsis and cast. Saved progress appears as a timeline with watched/remaining time; the resume dialog offers Resume or Start from Beginning.
- **Series details:** a matching cinematic introduction, selectable season rail and image-led episode cards.
- **Player:** readable title and live status, a restrained timeline, clear playback controls and visible remote focus.

Artwork, ratings, years, genres and descriptions come from the user's provider. Recently added shelves use actual `added` timestamps, with `last_modified` as a fallback; titles with unknown dates are never presented as newly added. A missing-date state offers Browse all instead. Missing or failed artwork uses a title-seeded abstract cover. Empty metadata is omitted; Streamline does not invent catalog entries, ratings, trailers or provider claims.

## Touch, remote and motion

Native Android TV detection selects the television rail and remote layout. Phones retain touch navigation, including landscape scrolling. Major content sections scroll so that forms, guide actions, season controls and playback choices remain reachable on shorter screens.

Focusable cards use a bright outline, subtle scale and a soft accent glow. Short transitions respect Android/Flutter reduced-motion settings. D-pad traversal scrolls off-screen targets into view; Select/Enter activates them. The player retains its media-key, seeking, zapping and Back behavior.

## Visual verification

Widget checks cover phone portrait, phone landscape and television layouts, category/search behavior, sorting, favorite controls, resume choices and season selection. Optional screenshot capture writes previews to `build/qa`; see [TESTING.md](TESTING.md) for commands and the v0.3 physical-device acceptance checklist.
