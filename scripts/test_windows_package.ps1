$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $taskRoot
$taskFixtures = Join-Path $taskRoot 'build/windows-smoke/media'
New-Item -ItemType Directory -Force -Path $taskFixtures | Out-Null
& ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc=size=320x180:rate=25' -f lavfi -i 'sine=frequency=440:sample_rate=48000' -t 4 -c:v libx264 -pix_fmt yuv420p -g 25 -c:a aac (Join-Path $taskFixtures 'fixture.mp4')
if ($LASTEXITCODE -ne 0) { throw 'Test video generation failed.' }
& ffmpeg -hide_banner -loglevel error -y -i (Join-Path $taskFixtures 'fixture.mp4') -c copy -f mpegts (Join-Path $taskFixtures 'fixture.ts')
if ($LASTEXITCODE -ne 0) { throw 'Transport stream fixture failed.' }
& ffmpeg -hide_banner -loglevel error -y -i (Join-Path $taskFixtures 'fixture.mp4') -c copy -hls_time 1 -hls_list_size 0 -hls_segment_filename (Join-Path $taskFixtures 'segment-%02d.ts') (Join-Path $taskFixtures 'fixture.m3u8')
if ($LASTEXITCODE -ne 0) { throw 'HLS fixture failed.' }

function Invoke-DesktopSmoke([string]$Executable, [string]$Name) {
    $taskReport = Join-Path $taskRoot "build/windows-smoke/$Name.json"
    $taskArguments = @('--smoke-test', "`"$taskReport`"", '--media-fixtures', "`"$taskFixtures`"",
        '--installer', "`"$(Join-Path $taskRoot 'build/windows-distribution/Ultravpn-player-Setup.exe')`"",
        '--manifest', "`"$(Join-Path $taskRoot 'build/windows-remote-update/windows-update.json')`"")
    $taskProcess = Start-Process -FilePath $Executable -WorkingDirectory (Split-Path -Parent $Executable) -ArgumentList $taskArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $taskRoot "build/windows-smoke/$Name.stdout.log") -RedirectStandardError (Join-Path $taskRoot "build/windows-smoke/$Name.stderr.log")
    if (-not $taskProcess.WaitForExit(150000)) {
        Stop-Process -Id $taskProcess.Id -Force
        throw "Desktop smoke timed out: $Name"
    }
    $taskProcess.Refresh()
    if (-not (Test-Path -LiteralPath $taskReport)) { throw "Desktop did not produce its verification report: $Name" }
    $taskResult = Get-Content -LiteralPath $taskReport -Raw | ConvertFrom-Json
    $taskResult | ConvertTo-Json -Depth 5 | Write-Output
    if ($taskProcess.ExitCode -ne 0 -or -not $taskResult.passed) { throw "Desktop smoke failed: $Name" }
}

$taskTemp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$taskPortable = Join-Path $taskTemp 'Ultravpn-player-smoke/portable'
Expand-Archive -LiteralPath build/windows-distribution/Ultravpn-player-Windows-x64.zip -DestinationPath $taskPortable -Force
Invoke-DesktopSmoke (Join-Path $taskPortable 'Ultravpn-player.exe') 'portable'
$taskInstall = Join-Path $taskTemp 'Ultravpn-player-smoke/installed'
$taskSetup = Start-Process -FilePath (Join-Path $taskRoot 'build/windows-distribution/Ultravpn-player-Setup.exe') -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOICONS', "/DIR=`"$taskInstall`"") -WindowStyle Hidden -Wait -PassThru
if ($taskSetup.ExitCode -ne 0) { throw 'Silent test installation failed.' }
Invoke-DesktopSmoke (Join-Path $taskInstall 'Ultravpn-player.exe') 'installed'
$taskUninstall = Start-Process -FilePath (Join-Path $taskInstall 'unins000.exe') -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -WindowStyle Hidden -Wait -PassThru
if ($taskUninstall.ExitCode -ne 0) { throw 'Test uninstall failed.' }
Write-Output 'Portable launch, installation, native playback, storage and uninstall passed.'
