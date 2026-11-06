# check-rsc.ps1 -- static sanity gate for generated .rsc files
# Catches the failures that break a Terminal paste on RouterOS v6:
# unbalanced braces/quotes, leftover {{placeholders}}, CRLF, secrets
# in the structural file, and unknown top-level menus.
param([Parameter(Mandatory = $true, Position = 0)][string]$Path,
      [switch]$AllowSecret)

$ErrorActionPreference = 'Stop'
$raw = [IO.File]::ReadAllText((Resolve-Path $Path))
$fail = @()

if ($raw -match '\{\{')                        { $fail += 'leftover {{placeholder}}' }
if ($raw -match "`r`n")                        { $fail += 'CRLF line endings (must be LF)' }
if (-not $AllowSecret -and
    $raw -match 'secret=[^\s"]*[A-Za-z0-9]{20,}') { $fail += 'embedded secret value' }

# balanced { } and " "
$opens = ([regex]::Matches($raw, '\{')).Count
$closes = ([regex]::Matches($raw, '\}')).Count
if ($opens -ne $closes) { $fail += "unbalanced braces: $opens open / $closes close" }
if (([regex]::Matches($raw, '"')).Count % 2) { $fail += 'odd number of quotes' }

# every command line must start with / or be a continuation/brace/comment
$knownMenus = '^/(interface|ip|ip\s|system|radius|log|queue|tool|user|snmp)'
$lines = $raw -split "`n"
$prevContinuation = $false
for ($i = 0; $i -lt $lines.Count; $i++) {
    $t = $lines[$i].Trim()
    $wasCont = $prevContinuation
    $prevContinuation = $t.EndsWith('\')
    if ($wasCont) { continue }
    if ($t -eq '' -or $t.StartsWith('#') -or $t.StartsWith(':') -or
        $t -match '^[}\)]' -or $t -match '^\s') { continue }
    if ($t.StartsWith('/') -and $t -notmatch $knownMenus) {
        $fail += "line $($i+1): unknown menu path: $t"
    } elseif (-not $t.StartsWith('/') -and $t -notmatch '^[:/#}]') {
        $fail += "line $($i+1): not a command/comment: $t"
    }
}

if ($fail) {
    Write-Host "FAIL $Path" -ForegroundColor Red
    $fail | ForEach-Object { Write-Host "  - $_" }
    exit 1
}
Write-Host "PASS $Path ($($lines.Count) lines)" -ForegroundColor Green
