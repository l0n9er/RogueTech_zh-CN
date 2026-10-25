param(
    [Parameter(Mandatory=$true)][string]$mods,
    [string]$backupRoot = "",
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot 'backup\modtek-config' }
$config = Join-Path $mods 'ModTek\config.json'
if (-not [IO.File]::Exists($config)) {
    Write-Output 'ModTek config not found, skipped'
    exit 0
}

$replacements = [ordered]@{
    'ShowLoadingScreenErrors_Description' = ([char[]](0x662f,0x5426,0x5728,0x52a0,0x8f7d,0x754c,0x9762,0x663e,0x793a,0x9519,0x8bef,0x3002) -join '')
    'ShowErrorPopup_Description' = ([char[]](0x662f,0x5426,0x5728,0x53d1,0x751f,0x9519,0x8bef,0x65f6,0x5f39,0x51fa,0x9519,0x8bef,0x63d0,0x793a,0x3002) -join '')
    'UseErrorWhiteList_Description' = ([char[]](0x662f,0x5426,0x4f7f,0x7528,0x9519,0x8bef,0x767d,0x540d,0x5355,0x8fc7,0x6ee4,0x5df2,0x77e5,0x9519,0x8bef,0x3002) -join '')
}
$enc = New-Object Text.UTF8Encoding $false
$original = [IO.File]::ReadAllText($config, [Text.Encoding]::UTF8)
$updated = $original
$changed = 0
foreach ($key in $replacements.Keys) {
    $pattern = '("' + [regex]::Escape($key) + '"\s*:\s*)"TODO"'
    $next = [regex]::Replace($updated, $pattern, ('$1"' + $replacements[$key] + '"'), 1)
    if ($next -ne $updated) { $changed++ }
    $updated = $next
}
if ($changed -gt 0 -and -not $DryRun) {
    $parent = Split-Path $backupRoot -Parent
    if (-not [IO.Directory]::Exists($parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    if (-not [IO.File]::Exists($backupRoot)) { [IO.Directory]::CreateDirectory($backupRoot) | Out-Null }
    $backup = Join-Path $backupRoot 'config.json'
    if (-not [IO.File]::Exists($backup)) { [IO.File]::WriteAllText($backup, $original, $enc) }
    [IO.File]::WriteAllText($config, $updated, $enc)
}
Write-Output ("ModTek config descriptions fixed=" + $changed)
