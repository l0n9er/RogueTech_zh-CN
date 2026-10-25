param(
    [string]$gameRoot = "",
    [string]$backupRoot = "",
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$packRoot = Split-Path $PSScriptRoot -Parent
$enc = New-Object Text.UTF8Encoding $false

if ([string]::IsNullOrWhiteSpace($gameRoot)) {
    $gameRoot = & (Join-Path $PSScriptRoot 'find-game.ps1')
}
if ([string]::IsNullOrWhiteSpace($gameRoot) -or -not [IO.Directory]::Exists($gameRoot)) {
    throw 'Game root not found'
}
if ([string]::IsNullOrWhiteSpace($backupRoot)) {
    $backupRoot = Join-Path $packRoot 'backup\runtime-corruption'
}

$replacementChar = [string][char]0xFFFD
$replacements = [ordered]@{
    ('Bagele' + $replacementChar + 's jaw') = "Bagele's jaw"
    ('Stealth Charge' + $replacementChar + 'and') = 'Stealth Charge and'
}
$extensions = @('.json', '.jsonc', '.txt', '.csv')
$modsRoot = Join-Path $gameRoot 'Mods'
$files = Get-ChildItem -LiteralPath $modsRoot -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object {
    $ext = $_.Extension.ToLowerInvariant()
    $rel = $_.FullName.Substring($modsRoot.Length).TrimStart('\')
    $extensions -contains $ext -and
        $rel -notlike '.modtek\*' -and
        $_.Name -notlike '*.bak' -and
        $_.Name -notlike '*.zhbak*'
}
$fixedFiles = 0
$fixedValues = 0

foreach ($file in $files) {
    try { $original = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) }
    catch { continue }
    $updated = $original
    foreach ($old in $replacements.Keys) {
        $count = ([regex]::Matches($updated, [regex]::Escape($old))).Count
        if ($count -gt 0) {
            $updated = $updated.Replace($old, $replacements[$old])
            $fixedValues += $count
        }
    }
    if ($updated -eq $original) { continue }
    $fixedFiles++
    if (-not $DryRun) {
        $rel = $file.FullName.Substring($gameRoot.Length).TrimStart('\')
        $backup = Join-Path $backupRoot $rel
        $parent = Split-Path $backup -Parent
        if (-not [IO.Directory]::Exists($parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
        if (-not [IO.File]::Exists($backup)) { [IO.File]::WriteAllText($backup, $original, $enc) }
        [IO.File]::WriteAllText($file.FullName, $updated, $enc)
    }
}

$unresolved = New-Object 'System.Collections.Generic.List[string]'
foreach ($file in $files) {
    try { $text = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) }
    catch { continue }
    if ($text.IndexOf([char]0xFFFD) -ge 0) {
        [void]$unresolved.Add($file.FullName.Substring($gameRoot.Length).TrimStart('\'))
    }
}

Write-Output ("fixed files=" + $fixedFiles + " replacements=" + $fixedValues)
Write-Output ("unresolved replacement-character files=" + $unresolved.Count)
$unresolved | Select-Object -First 20 | ForEach-Object { Write-Output ("  " + $_) }
if ($unresolved.Count -gt 0) { exit 2 }
