# Windows desktop edition

The Windows x64 edition shares the Glass interface, catalogue, playback history,
recommendations, parental settings and account behaviour with Android. Windows
uses mouse/keyboard input, the desktop media engine and its own encrypted session
storage and SQLite database. History is local to each device; this release does
not add cross-device sync. F11 toggles fullscreen. Space pauses/resumes playback;
Escape returns from the player. Search and PIN entry accept physical keyboards.

## Installation and testing

Install `Ultravpn-player-Setup.exe` for a per-user Start menu installation, or
extract **all** files from `Ultravpn-player-Windows-x64.zip` into a folder and run
`Ultravpn-player.exe`. The portable app requires the adjacent DLLs and data folder.
Windows 10 build 19041 or newer, x64, is required. The initial Windows installer is
unsigned: Windows may display an unknown-publisher or SmartScreen prompt. Android
continues using its existing permanent release certificate.

The installer updates the existing app directory and preserves the user's
application-data directory. Uninstall removes program files; user data is retained.
Portable users can replace their extracted program files while the app is closed,
or switch to the installer. Program files and per-user data are stored separately.

## Remote updates

Windows reads `windows-update.json` next to the existing embedded Android update
manifest. Android continues reading `update.json`. The separate application and
platform identifiers prevent either app from accepting the other platform's file.
Windows checks the installer size, SHA-256, executable header, product identity
and file version before opening it. The user controls download and installation.
Initial Windows releases do not yet have Authenticode publisher signing; HTTPS
hosting and manifest/file integrity checks are not a substitute for that signature.

For self-hosting, extract `windows-remote-update.zip` into the existing update
folder. Upload both supplied installer copies first, then `windows-update.json`
last. Keep previous versioned installers available. The permanent Windows
download filename is `Ultravpn-player-Setup.exe`; the Android APK name stays the
same. Public release notes remain concise and exclude connection details.

## Build and verification

GitHub builds on Windows with Flutter 3.35.7, Visual Studio C++, Inno Setup 6 and
FFmpeg. Native SQLite and Visual C++ runtime DLLs accompany the executable.
`scripts/build_windows_release.ps1` generates the installer, portable archive,
separate update package and checksums. `scripts/test_windows_package.ps1` tests
both extracted and installed applications, then uninstalls the test copy.

The native smoke command runs only when explicitly requested by CI. It checks
application directories, a temporary SQLite database, encrypted storage, native
fullscreen/awake controls and actual playback of locally generated MP4, MPEG-TS
and HLS media. CI uses a null speaker output because the runner has no speakers.
It never signs in to the TV service or accesses customer accounts. These checks
do not establish playback quality on every GPU, audio device or provider stream.
