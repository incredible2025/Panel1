# Ultravpn-player 0.8.5

TV Search now stays in the section you selected. Moving right from Movies or Series to Search no longer opens the intervening tabs or My List. Header focus and section selection are separate: press OK to open a tab, or Down to open it and enter its content. Moving focus alone preserves the current section, query, category and saved destination.

Search captures its target before opening the remote keyboard. Live TV searches channels, Movies searches movies, and Series searches series. Cancelling returns to Search without switching section. Search opened explicitly from Home, My List or Settings opens the movie catalogue on submission, so a query cannot be silently ignored by My List.

Remote regression checks cross the actual header controls and type a query using the built-in keypad at 540p, 720p and 1080p. They verify that unsaved catalogue titles remain searchable, results come from the correct media type, cancellation preserves Series, and both OK and Down still open tabs.

Version 0.8.5, Android build 25. Existing Glass layouts, startup update checks, package identity and permanent signing certificate remain compatible. Upload both APKs from remote-update.zip before replacing update.json. Ultravpn-player.apk remains the stable Downloader filename.
