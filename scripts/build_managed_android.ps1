param(
    [Parameter(Mandatory = $true)][string]$Profile,
    [string]$LegacyServiceId = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$resolvedProfile = (Resolve-Path -LiteralPath $Profile).Path
$profileData = Get-Content -LiteralPath $resolvedProfile -Raw | ConvertFrom-Json
$definesPath = Join-Path $projectRoot '.tooling/managed-build/defines.json'
$pythonPath = (Get-Command python -ErrorAction Stop).Source
$flutterPath = Join-Path $projectRoot '.tooling/flutter/bin/flutter.bat'
if (-not (Test-Path -LiteralPath $flutterPath)) { $flutterPath = (Get-Command flutter -ErrorAction Stop).Source }
$prepareArgs = @((Join-Path $projectRoot 'scripts/prepare_managed_profile.py'), '--profile', $resolvedProfile, '--output', $definesPath)
if ($LegacyServiceId) { $prepareArgs += @('--legacy-service-id', $LegacyServiceId) }
& $pythonPath @prepareArgs
if ($LASTEXITCODE -ne 0) { throw 'Build profile preparation failed.' }
$previousIdentity = $env:MANAGED_ANDROID_APPLICATION_ID
try {
    $env:MANAGED_ANDROID_APPLICATION_ID = $profileData.packageId
    Push-Location $projectRoot
    try {
        & $flutterPath build apk --release --target-platform android-arm,android-arm64 "--dart-define-from-file=$definesPath"
        if ($LASTEXITCODE -ne 0) { throw 'Android build failed.' }
    } finally { Pop-Location }
} finally {
    $env:MANAGED_ANDROID_APPLICATION_ID = $previousIdentity
}
