#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef BuildNumber
  #error BuildNumber is required
#endif
#ifndef ReleaseDir
  #error ReleaseDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif

[Setup]
AppId={{0C752AC9-C4A8-42DF-9850-B064D09A60CE}
AppName=Ultravpn-player
AppVersion={#AppVersion}
AppPublisher=Ultravpn-player
DefaultDirName={localappdata}\Programs\Ultravpn-player
DefaultGroupName=Ultravpn-player
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
OutputDir={#OutputDir}
OutputBaseFilename=Ultravpn-player-Setup
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Ultravpn-player.exe
VersionInfoProductName=Ultravpn-player
VersionInfoVersion={#AppVersion}.{#BuildNumber}
VersionInfoTextVersion={#AppVersion}.{#BuildNumber}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
Uninstallable=yes

[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Ultravpn-player"; Filename: "{app}\Ultravpn-player.exe"
Name: "{autodesktop}\Ultravpn-player"; Filename: "{app}\Ultravpn-player.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Ultravpn-player.exe"; Description: "Open Ultravpn-player"; Flags: nowait postinstall skipifsilent
