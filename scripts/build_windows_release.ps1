$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$taskRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $taskRoot
$taskVersionLine = @((Select-String -LiteralPath pubspec.yaml -Pattern '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$').Matches)
if ($taskVersionLine.Count -ne 1) { throw 'Missing release version.' }
$taskVersion = $taskVersionLine[0].Groups[1].Value
$taskBuild = $taskVersionLine[0].Groups[2].Value
$taskRelease = Join-Path $taskRoot 'build/windows/x64/runner/Release'
$taskOutput = Join-Path $taskRoot 'build/windows-distribution'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null

# sqlite3 v2 needs its x64 native library next to the executable in release mode.
$taskPackageConfig = Get-Content -LiteralPath .dart_tool/package_config.json -Raw | ConvertFrom-Json
$taskFfiPackage = $taskPackageConfig.packages | Where-Object name -EQ 'sqflite_common_ffi'
$taskFfiRoot = [Uri]::new([Uri]::new((Join-Path $taskRoot '.dart_tool/package_config.json')), $taskFfiPackage.rootUri).LocalPath
Copy-Item -LiteralPath (Join-Path $taskFfiRoot 'lib/src/windows/sqlite3.dll') -Destination $taskRelease

# Ship the redistributable runtime DLLs, so a clean PC does not need Visual Studio.
$taskVswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$taskVisualStudio = & $taskVswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$taskRedist = Get-ChildItem -LiteralPath (Join-Path $taskVisualStudio 'VC/Redist/MSVC') -Directory |
    Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'x64/Microsoft.VC143.CRT' } |
    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $taskRedist) { throw 'Visual C++ redistributable DLLs were not found.' }
Copy-Item -Path (Join-Path $taskRedist '*.dll') -Destination $taskRelease
Copy-Item -LiteralPath assets/licenses/native-player.txt -Destination (Join-Path $taskRelease 'THIRD-PARTY-NOTICES.txt')
$taskBinary = Join-Path $taskRelease 'Ultravpn-player.exe'
$taskMetadata = (Get-Item -LiteralPath $taskBinary).VersionInfo
if ($taskMetadata.ProductName -ne 'Ultravpn-player' -or $taskMetadata.FileVersion -ne "$taskVersion+$taskBuild") {
    # Flutter's resource version string is the three-part release plus build.
    if ($taskMetadata.ProductName -ne 'Ultravpn-player' -or $taskMetadata.FileVersion -ne $taskVersion) {
        throw 'Compiled application metadata does not match the release.'
    }
}
$taskIscc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'
if (-not (Test-Path -LiteralPath $taskIscc)) { throw 'Inno Setup 6 is required.' }
& $taskIscc "/DAppVersion=$taskVersion" "/DBuildNumber=$taskBuild" "/DReleaseDir=$taskRelease" "/DOutputDir=$taskOutput" windows/installer.iss
if ($LASTEXITCODE -ne 0) { throw 'Windows installer compilation failed.' }
$taskInstaller = Join-Path $taskOutput 'Ultravpn-player-Setup.exe'
$taskInstallerInfo = (Get-Item -LiteralPath $taskInstaller).VersionInfo
if ($taskInstallerInfo.ProductName -ne 'Ultravpn-player' -or $taskInstallerInfo.FileVersion -ne "$taskVersion.$taskBuild") {
    throw 'Windows installer identity verification failed.'
}
Compress-Archive -Path (Join-Path $taskRelease '*') -DestinationPath (Join-Path $taskOutput 'Ultravpn-player-Windows-x64.zip') -Force
$taskRemote = Join-Path $taskRoot 'build/windows-remote-update'
New-Item -ItemType Directory -Force -Path $taskRemote | Out-Null
Copy-Item -LiteralPath $taskInstaller -Destination (Join-Path $taskRemote 'Ultravpn-player-Setup.exe')
Copy-Item -LiteralPath $taskInstaller -Destination (Join-Path $taskRemote "Ultravpn-player-Setup-$taskVersion.exe")
python scripts/create_windows_manifest.py --installer $taskInstaller --version $taskVersion --code $taskBuild --notes "docs/RELEASE_NOTES_$taskVersion.md" --output (Join-Path $taskRemote 'windows-update.json')
if ($LASTEXITCODE -ne 0) { throw 'Windows update manifest generation failed.' }
Compress-Archive -Path (Join-Path $taskRemote '*') -DestinationPath (Join-Path $taskOutput 'windows-remote-update.zip') -Force
$taskChecksums = Get-ChildItem -LiteralPath $taskOutput -File | Where-Object Name -NE 'windows-checksums.sha256' | ForEach-Object {
    "$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower())  $($_.Name)"
}
$taskChecksums | Set-Content -LiteralPath (Join-Path $taskOutput 'windows-checksums.sha256') -Encoding utf8NoBOM
Write-Output 'Windows installer, portable app and remote update package verified.'
