param(
    [string]$Keytool = 'keytool',
    [string]$OutputDirectory = '.signing'
)

$ErrorActionPreference = 'Stop'
$taskDirectory = [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputDirectory))
$taskKeystore = Join-Path $taskDirectory 'streamline-release.p12'
$taskSecretFile = Join-Path $taskDirectory 'android-signing.json'
if ((Test-Path -LiteralPath $taskKeystore) -or (Test-Path -LiteralPath $taskSecretFile)) {
    if ((Test-Path -LiteralPath $taskKeystore) -and (Test-Path -LiteralPath $taskSecretFile)) {
        Write-Output 'Existing release signing material retained. No new key was generated.'
        exit 0
    }
    throw 'Incomplete signing backup. Restore the missing file before creating another key.'
}

New-Item -ItemType Directory -Path $taskDirectory -Force | Out-Null
if ($IsWindows) {
    $taskIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $taskAcl = [Security.AccessControl.DirectorySecurity]::new()
    $taskAcl.SetOwner($taskIdentity)
    $taskAcl.SetAccessRuleProtection($true, $false)
    $taskRule = [Security.AccessControl.FileSystemAccessRule]::new(
        $taskIdentity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'
    )
    $taskAcl.AddAccessRule($taskRule)
    Set-Acl -LiteralPath $taskDirectory -AclObject $taskAcl
}
$taskPasswordBytes = [byte[]]::new(36)
[Security.Cryptography.RandomNumberGenerator]::Fill($taskPasswordBytes)
$taskPassword = [Convert]::ToBase64String($taskPasswordBytes)
$env:STREAMLINE_KEY_PASSWORD = $taskPassword
try {
    & $Keytool -genkeypair -noprompt -keystore $taskKeystore -storetype PKCS12 `
        -alias streamline -keyalg RSA -keysize 3072 -sigalg SHA256withRSA `
        -validity 10000 -dname 'CN=Streamline Release, OU=Android, O=Streamline' `
        -storepass:env STREAMLINE_KEY_PASSWORD -keypass:env STREAMLINE_KEY_PASSWORD
    if ($LASTEXITCODE -ne 0) { throw 'Key generation failed. No GitHub secret was created.' }
    $taskSecret = [ordered]@{
        keystore = [Convert]::ToBase64String([IO.File]::ReadAllBytes($taskKeystore))
        storePassword = $taskPassword
        keyAlias = 'streamline'
        keyPassword = $taskPassword
    } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText($taskSecretFile, $taskSecret, [Text.UTF8Encoding]::new($false))
    & $Keytool -exportcert -rfc -keystore $taskKeystore -alias streamline `
        -storepass:env STREAMLINE_KEY_PASSWORD -file (Join-Path $taskDirectory 'release-certificate.pem')
    if ($LASTEXITCODE -ne 0) { throw 'The key was created, but exporting its public certificate failed.' }
    Write-Output 'Release key created. Back up the private .signing folder securely; never commit it.'
} finally {
    Remove-Item Env:STREAMLINE_KEY_PASSWORD -ErrorAction SilentlyContinue
    [Array]::Clear($taskPasswordBytes)
    $taskPassword = $null
    $taskSecret = $null
}
