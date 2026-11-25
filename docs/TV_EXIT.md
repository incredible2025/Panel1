# TV app exit

Android TV users can select Exit app from the TV Settings overview, or press Back
from Home. Back from a library still returns Home first. The TV sign-in screen
also offers the exit confirmation when Back is pressed. Nested detail, player,
keyboard and utility routes retain their existing Back behaviour.

Stay in app has initial remote focus. Cancelling does not stop playback or erase
anything. Confirming prevents new players opening, cancels pending previews,
waits for all tracked native player disposals (including players whose view has
already been removed), drains queued preference writes, suspends management
reporting and invokes Flutter's SystemNavigator.pop. Android finishes the app
activity and returns to the previous activity, normally the TV launcher. This
does not force-kill an Android process or sign the user out. Android owns process
memory reclamation. Watch progress is saved by the existing player exit path
before returning to the dashboard.

The closing dialog cannot be dismissed while cleanup is running. If cleanup or
the platform exit fails, a generic retry message is shown and playback/reporting
can resume. Mobile and Windows do not get the TV exit controls.

Validation covers cancellation by remote OK, native teardown and settings-write
barriers, platform failure/retry, already-closing players, Home/library Back,
sign-in Back and the Settings action at 960x540, 1280x720 and 1920x1080.
Physical-device confirmation of launcher return remains required on the release
APK; widget tests intercept the Android exit call.
