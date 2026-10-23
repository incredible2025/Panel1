# Ultravpn-player 0.6.8

Fixes TV category navigation in Live TV, Movies and Series. The TV toolbar now retains one layout while the sidebar expands/collapses and remains mounted above scrolling library content. Sidebar Right enters the selected category directly, avoiding the search-field cursor trap. Non-interactive sidebar containers no longer receive focus.

Category Left/Right follows adjacent entries, scrolls to categories beyond the visible edge and handles held D-pad keys. Select/Enter/remote A activate a category without losing its focus. Up reaches search, search Down returns to the selected category, and Left from All returns to the active sidebar destination. Live Favorites remains reachable beyond the category row. Saved categories beyond the initial viewport are restored into view when entering the row.

The row uses fixed-extent lazy items and stable category IDs/focus nodes rather than building every provider category at once. Mobile category controls retain their touch layout. Regression coverage exercises all three libraries at a width where sidebar expansion previously changed the toolbar structure, plus restored/offscreen categories, held keys and boundary movement.

Speed test, embedded portal sign-in, no-expiry labels, permanent signing identity and the stable `Ultravpn-player.apk` download filename remain included. Upload both APKs from the server ZIP before replacing `update.json`.
