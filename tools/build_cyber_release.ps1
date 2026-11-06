# CYB-14 — hardened release build for cyber_client_app.
#
# Reads signing secrets from %USERPROFILE%\.cyber-build-secrets.psd1
# (OUTSIDE the repo, never committed). The file holds plain
# key=value pairs:
#
#   CYBER_API_URL      = https://api.yourdomain.tld/api
#   CYBER_HMAC_KEY     = <64-hex-char random key, same as server env>
#   CYBER_SIGN_SHA256  = <SHA-256 of the release keystore cert>
#   CYBER_TLS_PIN      = <SHA-256 DER of the API leaf cert, optional>
#
# Usage:
#   powershell -File tools\build_cyber_release.ps1            # AAB
#   powershell -File tools\build_cyber_release.ps1 -Apk       # APK
param([switch]$Apk)

$ErrorActionPreference = 'Stop'
$secretsFile = "$env:USERPROFILE\.cyber-build-secrets.psd1"

if (-not (Test-Path $secretsFile)) {
    Write-Host "Missing secrets file: $secretsFile" -ForegroundColor Red
    Write-Host "Create it with keys: CYBER_API_URL, CYBER_HMAC_KEY, CYBER_SIGN_SHA256, CYBER_TLS_PIN"
    exit 1
}

$defines = @{}
Get-Content $secretsFile | ForEach-Object {
    if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.+?)\s*$') { $defines[$Matches[1]] = $Matches[2] }
}

if (-not $defines.CYBER_HMAC_KEY) {
    Write-Host 'CYBER_HMAC_KEY missing from secrets file — refusing release build' -ForegroundColor Red
    exit 1
}

$symbolsDir = "build\symbols\$(Get-Date -Format yyyyMMdd-HHmmss)"
$dartDefines = @(
    "--dart-define=CYBER_API_URL=$($defines.CYBER_API_URL)",
    '--dart-define=CYBER_STRICT_TAMPER=true',
    "--dart-define=CYBER_HMAC_KEY=$($defines.CYBER_HMAC_KEY)",
    "--dart-define=CYBER_SIGN_SHA256=$($defines.CYBER_SIGN_SHA256)",
    "--dart-define=CYBER_TLS_PIN=$($defines.CYBER_TLS_PIN)"
)

Push-Location (Join-Path $PSScriptRoot '..\cyber_client_app')
try {
    $target = if ($Apk) { 'apk' } else { 'appbundle' }
    Write-Host "Building $target with obfuscation -> $symbolsDir"
    & flutter build $target --release --obfuscate "--split-debug-info=$symbolsDir" @dartDefines
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "`nSymbols archived at: cyber_client_app\$symbolsDir" -ForegroundColor Green
    Write-Host 'Keep the symbols dir PRIVATE — it is required to decode crash stacks.' -ForegroundColor Yellow
} finally {
    Pop-Location
}
