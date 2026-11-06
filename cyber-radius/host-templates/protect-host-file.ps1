# =============================================================================
# protect-host-file.ps1 -- AES-256-CBC + HMAC-SHA256 seal/open for .rsc files
#
# The .rsc cannot be encrypted ON the router (RouterOS only runs plain
# commands) -- but it must never travel or rest in plaintext on a shared
# channel. Seal it here, send the .enc by any channel, and give the
# passphrase verbally. The host opens it with the same script.
#
#   .\protect-host-file.ps1 -Seal   generated\almalla-v6-001.rsc
#   .\protect-host-file.ps1 -Open   generated\almalla-v6-001.rsc.enc
#
# Wire format (base64): CYB1 | salt16 | iv16 | hmac32 | cipher
# Key: PBKDF2-SHA256(passphrase, salt, 100k) -> 48 bytes (32 enc + 16 mac)
# =============================================================================
[CmdletBinding()]
param(
    [switch]$Seal,
    [switch]$Open,
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,
    # Scripted/testing use only — interactive runs must stay prompted.
    [string]$Passphrase
)
$ErrorActionPreference = 'Stop'

function Get-Keys([string]$pass, [byte[]]$salt) {
    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($pass, $salt, 100000)
    $kb = $kdf.GetBytes(48)
    return @{ Enc = $kb[0..31]; Mac = $kb[32..47] }
}
function Read-Pass([string]$prompt) {
    if ($Passphrase) { return $Passphrase }
    $s = Read-Host $prompt -AsSecureString
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
}

if ($Seal -eq $Open) { Write-Host 'Use exactly one of -Seal or -Open' -ForegroundColor Red; exit 1 }

if ($Seal) {
    $plain = [IO.File]::ReadAllBytes((Resolve-Path $Path))
    $pass = Read-Pass 'Seal passphrase'
    $salt = New-Object byte[] 16; $iv = New-Object byte[] 16
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($iv)
    $k = Get-Keys $pass $salt
    $aes = [Security.Cryptography.Aes]::Create(); $aes.Key = $k.Enc; $aes.IV = $iv
    $cipher = $aes.CreateEncryptor().TransformFinalBlock($plain, 0, $plain.Length)
    $mac = (New-Object Security.Cryptography.HMACSHA256(,$k.Mac)).ComputeHash($iv + $cipher)
    $blob = [Text.Encoding]::ASCII.GetBytes('CYB1') + $salt + $iv + $mac + $cipher
    [IO.File]::WriteAllText("$Path.enc", [Convert]::ToBase64String($blob))
    Write-Host "Sealed -> $Path.enc  (send this file; passphrase stays verbal)" -ForegroundColor Green
    exit 0
}

# ---- Open
$b64 = [IO.File]::ReadAllText((Resolve-Path $Path)).Trim()
$blob = [Convert]::FromBase64String($b64)
if ([Text.Encoding]::ASCII.GetString($blob[0..3]) -ne 'CYB1') {
    Write-Host 'Not a sealed file (bad magic)' -ForegroundColor Red; exit 1
}
$salt = $blob[4..19]; $iv = $blob[20..35]; $mac = $blob[36..67]; $cipher = $blob[68..($blob.Length - 1)]
$pass = Read-Pass 'Passphrase'
$k = Get-Keys $pass $salt
$expect = (New-Object Security.Cryptography.HMACSHA256(,$k.Mac)).ComputeHash($iv + $cipher)
if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$mac, [byte[]]$expect)) {
    Write-Host 'INTEGRITY FAIL — wrong passphrase or tampered file. Refusing.' -ForegroundColor Red; exit 1
}
$aes = [Security.Cryptography.Aes]::Create(); $aes.Key = $k.Enc; $aes.IV = $iv
$plain = $aes.CreateDecryptor().TransformFinalBlock($cipher, 0, $cipher.Length)
$out = $Path -replace '\.enc$', ''
[IO.File]::WriteAllBytes($out, $plain)
Write-Host "Opened -> $out  (integrity verified)" -ForegroundColor Green
