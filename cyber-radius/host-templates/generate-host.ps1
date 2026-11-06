# =============================================================================
# generate-host.ps1 -- CyberNet host .rsc generator (CYB-02)
#
# Renders host.rsc.tmpl into generated/<host-id>.rsc ready to paste in
# Winbox Terminal. Shares the hosts.json registry with generate-host.py --
# the same allocation table is used whichever tool runs.
#
# Usage (Windows PowerShell 5.1+):
#   .\generate-host.ps1 -HostId almalla-001 -ServerIP 203.0.113.10 `
#                       -Secret "<radius-secret>" -ServerPubKey "<wg-pub-b64>"
#
# -Secret is optional (auto-generated 40 chars). -ServerPubKey is needed
# only once; afterwards it is remembered in hosts.json. -Force rotates
# the host's secret + WireGuard keys while keeping its IP allocation.
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$HostId,

    [Parameter(Position = 1)]
    [string]$ServerIP,

    [Parameter(Position = 2)]
    [string]$Secret,

    [string]$ServerPubKey,

    [int]$WgPort = 0,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Numerics

$Here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$Template = Join-Path $Here 'host.rsc.tmpl'
$Registry = Join-Path $Here 'hosts.json'
$OutDir   = Join-Path $Here 'generated'

# ------------------------------------------------------------ helpers
function ConvertTo-UInt32([string]$ip) {
    $b = [System.Net.IPAddress]::Parse($ip).GetAddressBytes()
    [Array]::Reverse($b)
    return [BitConverter]::ToUInt32($b, 0)
}
function ConvertTo-IP([uint32]$i) {
    $b = [BitConverter]::GetBytes($i)
    [Array]::Reverse($b)
    return ([System.Net.IPAddress]::new($b)).ToString()
}
function Get-NetInfo([string]$cidr) {
    $p = $cidr -split '/'
    $ui = ConvertTo-UInt32 $p[0]
    $bits = 32 - [int]$p[1]
    $mask = if ($bits -eq 0) { [uint32]::MaxValue } else { ([uint32]::MaxValue -shl $bits) }
    return @{ Net = ($ui -band $mask); HostBits = $bits }
}

function Invoke-Mod([System.Numerics.BigInteger]$a, [System.Numerics.BigInteger]$m) {
    $r = $a % $m
    if ($r -lt 0) { $r += $m }
    return $r
}

function New-WgKeyPair {
    # X25519 (RFC 7748) pure-PowerShell via BigInteger; wg-compatible output.
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $priv = New-Object byte[] 32
    $rng.GetBytes($priv)
    $rng.Dispose()

    $k = [byte[]]$priv.Clone()
    $k[0]  = $k[0] -band 248
    $k[31] = ($k[31] -band 127) -bor 64
    $kInt = [System.Numerics.BigInteger]::new($k)

    $P   = [System.Numerics.BigInteger]::Subtract([System.Numerics.BigInteger]::Pow(2, 255), 19)
    $A24 = [System.Numerics.BigInteger]::new(121665)
    $x1  = [System.Numerics.BigInteger]::new(9)
    $x2  = [System.Numerics.BigInteger]::One
    $z2  = [System.Numerics.BigInteger]::Zero
    $x3  = $x1
    $z3  = [System.Numerics.BigInteger]::One
    $swap = 0

    for ($t = 254; $t -ge 0; $t--) {
        $kt = [int](($kInt -shr $t) -band [System.Numerics.BigInteger]::One)
        $swap = $swap -bxor $kt
        if ($swap -eq 1) { $tmp = $x2; $x2 = $x3; $x3 = $tmp; $tmp = $z2; $z2 = $z3; $z3 = $tmp }
        $swap = $kt

        $a  = Invoke-Mod ($x2 + $z2) $P
        $aa = Invoke-Mod ($a * $a) $P
        $b  = Invoke-Mod ($x2 - $z2) $P
        $bb = Invoke-Mod ($b * $b) $P
        $e  = Invoke-Mod ($aa - $bb) $P
        $c  = Invoke-Mod ($x3 + $z3) $P
        $d  = Invoke-Mod ($x3 - $z3) $P
        $da = Invoke-Mod ($d * $a) $P
        $cb = Invoke-Mod ($c * $b) $P
        $x3 = Invoke-Mod (($da + $cb) * ($da + $cb)) $P
        $z3 = Invoke-Mod ($x1 * (Invoke-Mod (($da - $cb) * ($da - $cb)) $P)) $P
        $x2 = Invoke-Mod ($aa * $bb) $P
        $z2 = Invoke-Mod ($e * ($aa + $A24 * $e)) $P
    }
    if ($swap -eq 1) { $tmp = $x2; $x2 = $x3; $x3 = $tmp; $tmp = $z2; $z2 = $z3; $z3 = $tmp }

    $res = Invoke-Mod ($x2 * [System.Numerics.BigInteger]::ModPow($z2, $P - 2, $P)) $P
    $rb  = $res.ToByteArray()   # little-endian, may carry a trailing sign byte
    $pub = New-Object byte[] 32
    [Array]::Copy($rb, 0, $pub, 0, [Math]::Min(32, $rb.Length))

    return @{
        Priv = [Convert]::ToBase64String($priv)
        Pub  = [Convert]::ToBase64String($pub)
    }
}

function New-Secret([int]$len = 40) {
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] $len
    $rng.GetBytes($bytes)
    $rng.Dispose()
    return -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

# ------------------------------------------------------------ registry
$netDefaults = [ordered]@{
    wg_net            = '10.66.0.0/24'
    server_wg_ip      = '10.66.0.1'
    wg_endpoint       = $null
    wg_endpoint_port  = 51820
    wg_listen_port    = 13231
    server_pubkey     = $null
    ssid              = 'CyberNet'
    lan_base          = '10.77.0.0/16'
    radius_auth_port  = 1812
    radius_acct_port  = 1813
    coa_port          = 3799
}
if (Test-Path $Registry) {
    $reg = Get-Content $Registry -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    $reg = [pscustomobject]@{
        network = [pscustomobject]$netDefaults
        hosts   = [pscustomobject]@{}
    }
}
$net = $reg.network
foreach ($k in $netDefaults.Keys) {
    if ($null -eq $net.PSObject.Properties[$k]) {
        $net | Add-Member -NotePropertyName $k -NotePropertyValue $netDefaults[$k]
    }
}

if ($ServerIP)     { $net.wg_endpoint      = $ServerIP }
if ($ServerPubKey) { $net.server_pubkey    = $ServerPubKey }
if ($WgPort -gt 0) { $net.wg_endpoint_port = $WgPort }
if (-not $Secret)  { $Secret = New-Secret }

$missing = @()
if (-not $net.wg_endpoint)   { $missing += 'ServerIP (-ServerIP)' }
if (-not $net.server_pubkey) { $missing += 'ServerPubKey (-ServerPubKey)' }
if ($missing.Count -gt 0) {
    throw "missing $($missing -join ', ') -- pass them once; they are stored in hosts.json afterwards"
}

# ------------------------------------------------------------ allocation
$existing = $reg.hosts.PSObject.Properties[$HostId]
if ($existing -and -not $Force) {
    throw "$HostId already generated (secret emitted once). Re-run with -Force to rotate credentials."
}

$usedWg  = @{}
$usedLan = @{}
foreach ($h in $reg.hosts.PSObject.Properties) {
    $usedWg[$h.Value.wg_ip] = $true
    $usedLan[($h.Value.lan_subnet -split '/')[0]] = $true
}

if ($existing) {
    $wgIp  = $existing.Value.wg_ip
    $lan   = $existing.Value.lan_subnet
} else {
    $wgn   = Get-NetInfo $net.wg_net
    $wgnSz = [uint32]([math]::Pow(2, $wgn.HostBits))
    $srvIp = ConvertTo-UInt32 $net.server_wg_ip
    $wgIp  = $null
    for ($i = 2; $i -lt $wgnSz - 1 -and -not $wgIp; $i++) {
        $cand = $wgn.Net + $i
        if ($cand -ne $srvIp -and -not $usedWg.ContainsKey((ConvertTo-IP $cand))) {
            $wgIp = ConvertTo-IP $cand
        }
    }
    if (-not $wgIp) { throw "no free WireGuard IP left in $($net.wg_net)" }

    $lanInfo = Get-NetInfo $net.lan_base
    $lanSub  = [uint32]([math]::Pow(2, 8))              # /24 stride
    $lanCnt  = [uint32]([math]::Pow(2, $lanInfo.HostBits - 8))
    $lan     = $null
    for ($i = 0; $i -lt $lanCnt -and -not $lan; $i++) {
        $cand = ConvertTo-IP ($lanInfo.Net + $i * $lanSub)
        if (-not $usedLan.ContainsKey($cand)) { $lan = "$cand/24" }
    }
    if (-not $lan) { throw "no free client LAN /24 left in $($net.lan_base)" }
}

$lanNet = ConvertTo-UInt32 ($lan -split '/')[0]
$gwCidr = "$(ConvertTo-IP ($lanNet + 1))/24"
$pool   = "$(ConvertTo-IP ($lanNet + 10))-$(ConvertTo-IP ($lanNet + 250))"
$keys   = New-WgKeyPair

# ------------------------------------------------------------ render
$values = [ordered]@{
    'HOST_ID'          = $HostId
    'GENERATED_AT'     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC'
    'SSID'             = $net.ssid
    'CYBER_SUBNET'     = $lan
    'CYBER_GW_CIDR'    = $gwCidr
    'CYBER_POOL'       = $pool
    'RADIUS_IP'        = $net.server_wg_ip
    'RADIUS_AUTH_PORT' = $net.radius_auth_port
    'RADIUS_ACCT_PORT' = $net.radius_acct_port
    'COA_PORT'         = $net.coa_port
    'HOST_SECRET'      = $Secret
    'WG_PRIVATE_KEY'   = $keys.Priv
    'WG_SERVER_PUBKEY' = $net.server_pubkey
    'WG_ENDPOINT'      = $net.wg_endpoint
    'WG_ENDPOINT_PORT' = $net.wg_endpoint_port
    'WG_LISTEN_PORT'   = $net.wg_listen_port
    'WG_HOST_IP_CIDR'  = "$wgIp/32"
    'WG_NET'           = $net.wg_net
}

$rsc = Get-Content $Template -Raw -Encoding UTF8
foreach ($k in $values.Keys) { $rsc = $rsc.Replace("{{$k}}", [string]$values[$k]) }
$leftover = [regex]::Matches($rsc, '\{\{[^}]+\}\}')
if ($leftover.Count -gt 0) {
    throw "unresolved placeholders: $(($leftover | ForEach-Object { $_.Value }) -join ', ')"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$rscPath = Join-Path $OutDir "$HostId.rsc"
[IO.File]::WriteAllText($rscPath, $rsc, [Text.UTF8Encoding]::new($false))

$srv = @"
# ---- $HostId -- install on the CyberNet VPS ----
# 1) WireGuard peer (add under [Interface] or /interface wireguard peers)
[Peer]
PublicKey  = $($keys.Pub)
AllowedIPs = $wgIp/32

# 2) FreeRADIUS client -> append to clients.conf
client $HostId {
    ipaddr   = $wgIp
    secret   = $Secret
    nas_type = mikrotik
    require_message_authenticator = yes
}
# client LAN behind this NAS: $lan (info only, not routed via wg)
"@
$srvPath = Join-Path $OutDir "$HostId.server.conf"
[IO.File]::WriteAllText($srvPath, $srv, [Text.UTF8Encoding]::new($false))

if ($existing) {
    $existing.Value.wg_pubkey           = $keys.Pub
    $existing.Value.radius_secret_hint  = $Secret.Substring(0, 4) + '...' + $Secret.Substring($Secret.Length - 4)
} else {
    $reg.hosts | Add-Member -NotePropertyName $HostId -NotePropertyValue ([pscustomobject]@{
        wg_ip              = $wgIp
        lan_subnet         = $lan
        wg_pubkey          = $keys.Pub
        radius_secret_hint = $Secret.Substring(0, 4) + '...' + $Secret.Substring($Secret.Length - 4)
        created            = $values['GENERATED_AT']
    })
}
[IO.File]::WriteAllText($Registry, ($reg | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))

Write-Host "host      : $HostId"
Write-Host "rsc       : $rscPath"
Write-Host "server    : $srvPath"
Write-Host "wg host ip: $wgIp/32  pub: $($keys.Pub)"
Write-Host "client LAN: $lan  (bridge $(ConvertTo-IP ($lanNet + 1)))"
Write-Host "registry  : $Registry"
