# TV login and fixed Home checks

TV login uses selectable credential controls instead of relying on a mobile TextFormField's default remote activation. Each opens TvTextEntryDialog, an app-rendered keyboard with explicit D-pad paths between keys, editing actions and Done. The default flow creates no TextField or native input connection and sends no TextInput.show. This avoids depending on the TV's IME, which was still failing on a real device despite the earlier platform-channel tests passing.

New regression journeys use only D-pad and four activation-key variants to select individual username and password characters, toggle capitals and symbols, complete both fields and authenticate. They do not inject text through testTextInput. Additional checks cover every printable ASCII credential character, masking/reveal, Unicode-aware physical backspace, space, delete, clear, held OK, draft retention and keyboard layouts at 960×540, 1280×720 and 1920×1080.

Use system keyboard opens the separate TvSystemTextEntryDialog only when explicitly selected. Its remote activation calls the descendant EditableTextState's public requestKeyboard method. Optional native-input regression journeys still assert TextInput.show, reopen after hiding, submit through the connected input client and verify the saved session. Other checks cover validation, password masking, keyboard inset clearance, preserving draft input and opening App updates without touch.

A native TextInputClient.onConnectionClosed callback is tested separately from simply hiding the keyboard. If Android leaves focus on the dialog scope after closing the input connection, the optional system dialog returns to the built-in keyboard with the draft intact. Intentional focus moves to password visibility or Done remain inside the system dialog. The parent waits for entry route transitions before advancing login focus.

Home has no vertical Scrollable. TvHomeShelves keeps the hero and collection selector fixed, lays out two complete horizontal shelves and switches additional collections locally. Tests browse beyond the first visible cards, move between rows, hold Down at the bottom and return to navigation while asserting the Home bounds stay fixed. Content and privacy restrictions still come from the existing providers.

These checks exercise Flutter key dispatch, actual on-screen character selection and optional platform text-input requests. Vendor remote mappings and native keyboard appearance still require testing on the target TV; the built-in keyboard no longer requires native keyboard appearance.
