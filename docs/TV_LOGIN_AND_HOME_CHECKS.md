# TV login and fixed Home checks

TV login uses selectable credential controls instead of relying on a mobile TextFormField's default remote activation. Each opens TvTextEntryDialog, where the remote activation handler calls the descendant EditableTextState's public requestKeyboard method. This explicitly opens or reopens the platform input connection even when the field already has focus. It does not fake keyboard visibility or send a bare TextInput.show before a client is attached.

Regression journeys cover Select/OK, Enter, numpad Enter and gamepad A. Tests assert native TextInput.show and test input visibility after dismissing the keyboard, send credentials through the connected input client, submit them and verify the saved session. Additional checks cover validation, password masking, keyboard inset clearance, preserving draft input and opening App updates without touch. TV login is captured at 960×540, 1280×720 and 1920×1080.

Home has no vertical Scrollable. TvHomeShelves keeps the hero and collection selector fixed, lays out two complete horizontal shelves and switches additional collections locally. Tests browse beyond the first visible cards, move between rows, hold Down at the bottom and return to navigation while asserting the Home bounds stay fixed. Content and privacy restrictions still come from the existing providers.

These checks exercise Flutter key dispatch and platform text-input requests. Native keyboard appearance and vendor remote mappings still require testing on the target TV.
