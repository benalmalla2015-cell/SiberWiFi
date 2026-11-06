# =============================================================================
# generate-host-v6.ps1 -- hardened RouterOS v6 host files (CYB-02/CYB-14)
#
# Emits TWO artifacts so the structural file never carries a secret:
#   generated/<id>.rsc        -- black-box config, paste first (no secrets)
#   secure/<id>-key.rsc       -- 2-line upstream key, paste second, deliver
#                               on a separate channel (gitignored dir)
#
# Registry hosts-v6.json keeps only a secret HINT (first4...last4) plus
# the server IP, so re-running does not re-emit secrets and -Force
# performs a clean rotation.
#
#   .\generate-host-v6.ps1 -HostId almalla-v6-001 -ServerIP 203.0.113.10
#   .\generate-host-v6.ps1 -HostId almalla-v6-001 -Force   # rotate secret
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$HostId,
    [string]$ServerIP,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Here      = Split-Path -Parent $MyInvocation.MyCommand.Path
$TmplMain  = Join-Path $Here 'host.v6.secure.tmpl'
$TmplKey   = Join-Path $Here 'key.v6.rsc.tmpl'
$Registry  = Join-Path $Here 'hosts-v6.json'
$OutDir    = Join-Path $Here 'generated'
$SecureDir = Join-Path $Here 'secure'

function New-Secret([int]$len = 40) {
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    -join (1..$len | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

# ---- registry
$reg = if (Test-Path $Registry) { Get-Content $Registry -Raw | ConvertFrom-Json } else { [pscustomobject]@{ hosts = @{} } }
if (-not $reg.PSObject.Properties['hosts']) { $reg | Add-Member hosts ([pscustomobject]@{}) }
$hostsProp = $reg.hosts

$existing = $hostsProp.PSObject.Properties[$HostId]
if ($existing -and -not $Force) {
    Write-Host "Host '$HostId' already exists (created $($existing.Value.created)). Use -Force to rotate the secret." -ForegroundColor Yellow
    Write-Host "Secret hint: $($existing.Value.secret_hint)  ServerIP: $($existing.Value.server_ip)"
    exit 1
}
if ($existing -and $Force) { $ServerIP = if ($ServerIP) { $ServerIP } else { $existing.Value.server_ip } }
if (-not $ServerIP) { Write-Host '-ServerIP is required for a new host' -ForegroundColor Red; exit 1 }

# ---- render
$secret = New-Secret
foreach ($d in @($OutDir, $SecureDir)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

(Get-Content $TmplMain -Raw).Replace('{{RADIUS_IP}}', $ServerIP) |
    Set-Content (Join-Path $OutDir "$HostId.rsc") -NoNewline -Encoding ASCII

(Get-Content $TmplKey -Raw).Replace('{{RADIUS_IP}}', $ServerIP).Replace('{{HOST_SECRET}}', $secret) |
    Set-Content (Join-Path $SecureDir "$HostId-key.rsc") -NoNewline -Encoding ASCII

# ---- registry update (hint only, never the secret)
$entry = [pscustomobject]@{
    server_ip    = $ServerIP
    secret_hint  = $secret.Substring(0, 4) + '...' + $secret.Substring($secret.Length - 4)
    created      = if ($existing) { $existing.Value.created } else { (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC' }
    rotated      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC'
}
if ($existing) {
    $hostsProp.$HostId = $entry
} else {
    $hostsProp | Add-Member -MemberType NoteProperty -Name $HostId -Value $entry
}
$reg | ConvertTo-Json -Depth 5 | Set-Content $Registry -Encoding UTF8

Write-Host "Generated:" -ForegroundColor Green
Write-Host "  $OutDir\$HostId.rsc          (structural - safe to share with host)"
Write-Host "  $SecureDir\$HostId-key.rsc   (KEY - separate channel only)"
Write-Host "Secret hint: $($entry.secret_hint)   ServerIP: $ServerIP"
