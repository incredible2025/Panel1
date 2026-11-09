param(
    [Parameter(Mandatory = $true)][string]$Profile,
    [Parameter(Mandatory = $true)][string]$Branding,
    [Parameter(Mandatory = $true)][string]$SigningProperties,
    [string]$Workspace = '',
    [string]$Python = '',
    [string]$JavaHome = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$profilePath = (Resolve-Path -LiteralPath $Profile).Path
$brandPath = (Resolve-Path -LiteralPath $Branding).Path
$signingPath = (Resolve-Path -LiteralPath $SigningProperties).Path
$brand = Get-Content -LiteralPath $brandPath -Raw | ConvertFrom-Json
if (-not $Python) {
    $bundledPython = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    $Python = if (Test-Path -LiteralPath $bundledPython) { $bundledPython } else { (Get-Command python -ErrorAction Stop).Source }
}
if (-not $JavaHome) {
    $bundledJava = Join-Path $projectRoot '.tooling/jdk17/jdk-17.0.20.1+1'
    $JavaHome = if (Test-Path -LiteralPath $bundledJava) { $bundledJava } else { $env:JAVA_HOME }
}
if (-not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin/java.exe'))) { throw 'A Java 17 installation is required.' }
if (-not $Workspace) { $Workspace = Join-Path $projectRoot ".tooling/brand-workspaces/$($brand.appId)-$($brand.versionCode)-$(Get-Date -Format yyyyMMddHHmmss)" }
$Workspace = [IO.Path]::GetFullPath($Workspace)
& $Python (Join-Path $PSScriptRoot 'prepare_brand_workspace.py') --source $projectRoot --workspace $Workspace --profile $profilePath --branding $brandPath --signing-properties $signingPath
if ($LASTEXITCODE -ne 0) { throw 'Brand workspace preparation failed.' }
$definesPath = Join-Path $Workspace '.brand-build/defines.json'
$definitions = Get-Content -LiteralPath $definesPath -Raw | ConvertFrom-Json -AsHashtable
$encoded = ($definitions.GetEnumerator() | ForEach-Object { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($_.Key)=$($_.Value)")) }) -join ','
$variables = @{
    JAVA_HOME = $JavaHome
    PUB_CACHE = (Join-Path $projectRoot '.pub-cache')
    MANAGED_ANDROID_APPLICATION_ID = $brand.packageId
    MANAGED_ANDROID_APP_NAME = $brand.name
    MANAGED_ANDROID_SIGNING_PROPERTIES = $signingPath
    'ORG_GRADLE_PROJECT_dart-defines' = $encoded
    CI = 'true'
}
$previous = @{}
try {
    foreach ($name in $variables.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $variables[$name], 'Process')
    }
    Push-Location $Workspace
    try {
        $flutterPath = Join-Path $projectRoot '.tooling/flutter/bin/flutter.bat'
        & $flutterPath pub get --enforce-lockfile
        if ($LASTEXITCODE -ne 0) { throw 'Locked dependency resolution failed.' }
        & $flutterPath test --no-pub "--dart-define-from-file=$definesPath" test/branding_assets_test.dart
        if ($LASTEXITCODE -ne 0) { throw 'Brand asset rendering failed.' }
        $artwork = Join-Path $Workspace '.brand-build/artwork'
        foreach ($name in @('icon.png', 'artwork.png', 'tv-banner.png')) {
            if ((Get-Item -LiteralPath (Join-Path $artwork $name)).Length -lt 5000) { throw 'An exported brand image is empty.' }
        }
        Copy-Item -LiteralPath (Join-Path $artwork 'icon.png') -Destination 'assets/branding/ultravpn-shield.png'
        Copy-Item -LiteralPath (Join-Path $artwork 'icon.png') -Destination 'android/app/src/main/res/drawable-nodpi/ultravpn_shield.png'
        Copy-Item -LiteralPath (Join-Path $artwork 'artwork.png') -Destination 'assets/branding/brand-artwork.png'
        Copy-Item -LiteralPath (Join-Path $artwork 'tv-banner.png') -Destination 'android/app/src/main/res/drawable-xhdpi/ultravpn_tv_banner.png'
        & ./android/gradlew.bat -p android "-Dorg.gradle.java.home=$JavaHome" :app:testReleaseUnitTest :app:assembleRelease '-Ptarget-platform=android-arm,android-arm64'
        if ($LASTEXITCODE -ne 0) { throw 'Branded Android build failed.' }
    } finally { Pop-Location }
    $output = Join-Path $projectRoot "build/brand-releases/$($brand.appId)/$($brand.versionCode)"
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $Workspace 'build/app/outputs/flutter-apk/app-release.apk') -Destination (Join-Path $output $brand.stableApkName)
    Write-Output "Branded APK built: $($brand.stableApkName)"
} finally {
    foreach ($name in $previous.Keys) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') }
}
