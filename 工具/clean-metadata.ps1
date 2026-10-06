param(
    [string]$mods = "",
    [string]$backupRoot = ""
)
$ErrorActionPreference = 'Stop'
$BS = [string][char]92
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($mods)) {
    $gr = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gr)) { throw 'Game directory not found' }
    $mods = Join-Path $gr 'Mods'
}
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot 'backup\Mods-metadata' }
$enc = New-Object Text.UTF8Encoding $false
$tags = 'ZH|Components|ambushconvoy|RogueTechCore|CustomSalvage|CustomActivatableEquipment|CustomPilotProgression|Localization|Base|CAC|CU|AIM|DE|RU'
$rx = [regex]'"(Details|YangsThoughts|StockRole)"\s*:\s*"((?:[^"\\]|\\.)*)"'
$stats = @{ files = 0; changed = 0; cleaned = 0 }
foreach ($f in (Get-ChildItem $mods -Recurse -File -Filter '*.json' -Force -ErrorAction SilentlyContinue)) {
    $stats.files++
    $orig = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    if ($orig -notmatch '[\u4e00-\u9fff].*(?:ZH|Components|ambushconvoy)"') { continue }
    $new = $rx.Replace($orig, {
        param($m)
        $v = $m.Groups[2].Value
        if ($v -notmatch '[\u4e00-\u9fff]') { return $m.Value }
        $clean = [regex]::Replace($v, '[\s]*(?:' + $tags + ')[\s]*$', '')
        if ($clean -eq $v) { return $m.Value }
        $stats.cleaned++
        return '"' + $m.Groups[1].Value + '": "' + $clean + '"'
    })
    if ($new -eq $orig) { continue }
    $rel = $f.FullName.Substring($mods.Length).TrimStart($BS)
    $bak = Join-Path $backupRoot $rel
    $parent = Split-Path $bak -Parent
    if (-not (Test-Path $parent)) { [void][IO.Directory]::CreateDirectory($parent) }
    if (-not (Test-Path $bak)) { [IO.File]::WriteAllText($bak, $orig, $enc) }
    [IO.File]::WriteAllText($f.FullName, $new, $enc)
    $stats.changed++
}
Write-Host ('files=' + $stats.files + ' changed=' + $stats.changed + ' cleaned=' + $stats.cleaned)
