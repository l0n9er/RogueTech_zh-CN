param(
    [Parameter(Mandatory = $true)][string]$file,
    [Parameter(Mandatory = $true)][string]$pairs,
    [string]$backupRoot = ''
)
$ErrorActionPreference = 'Stop'
$enc = New-Object Text.UTF8Encoding($false)
if (-not [IO.File]::Exists($file)) { Write-Host 'RtConfig.xml not found; skipped'; exit 0 }
if (-not [IO.File]::Exists($pairs)) { throw "Missing translation pairs: $pairs" }
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'backup\rtconfig' }
$map = New-Object 'System.Collections.Generic.Dictionary[string,string]'
foreach ($line in [IO.File]::ReadAllLines($pairs, [Text.Encoding]::UTF8)) {
    $parts = $line.Split([char]9, 2)
    if ($parts.Count -eq 2 -and $parts[0].Length -gt 0 -and -not $map.ContainsKey($parts[0])) { $map[$parts[0]] = $parts[1] }
}
$original = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8)
$updated = $original
foreach ($key in @('Custom Mechs only usable by RTO Legend Pilots. Requires RTO Legends Pilots to be installed.','Custom Mechs for the RTO Legend Pilots.','Custom Mechs only usable by RTO Legend Pilots. Requires RTO','RTO Legends Mechs','Pilots based on well-known RTO players from the past and present')) {
    if ($map.ContainsKey($key)) { $updated = $updated.Replace($key, $map[$key]) }
}
# Repair the suffix left by older installs. The pattern stays ASCII-only for
# Windows PowerShell encoding compatibility; its replacement comes from TSV.
$fullKey = 'Custom Mechs only usable by RTO Legend Pilots. Requires RTO Legends Pilots to be installed.'
if ($map.ContainsKey($fullKey)) {
    $translated = $map[$fullKey]
    $lastRto = $translated.LastIndexOf('RTO')
    if ($lastRto -ge 0) {
        $tail = $translated.Substring($lastRto)
        $updated = [regex]::Replace($updated, 'RTO. Legends Pilots to be installed\.', [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $tail })
    }
}
if ($updated -eq $original) { Write-Host 'RtConfig.xml needs no changes'; exit 0 }
$bak = Join-Path $backupRoot 'RtConfig.xml'
$parent = Split-Path $bak -Parent
if (-not [IO.Directory]::Exists($parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
if (-not [IO.File]::Exists($bak)) { [IO.File]::WriteAllText($bak, $original, $enc) }
[IO.File]::WriteAllText($file, $updated, $enc)
Write-Host 'Translated RTO Legends launcher text'
