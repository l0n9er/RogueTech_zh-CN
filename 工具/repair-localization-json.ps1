param(
    [Parameter(Mandatory = $true)][string]$mods,
    [Parameter(Mandatory = $true)][string]$pairs,
    [string]$backupRoot = ''
)
$ErrorActionPreference = 'Stop'
$enc = New-Object Text.UTF8Encoding($false)
$bs = [string][char]92
$zhFire = [string][char]0x706B + [char]0x70AE
$zhAccuracy = [string][char]0x7CBE + [char]0x5EA6
if (-not [IO.File]::Exists($pairs)) { throw "Missing translation pairs: $pairs" }
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'backup\localization-format' }
$map = New-Object 'System.Collections.Generic.Dictionary[string,string]'
foreach ($line in [IO.File]::ReadAllLines($pairs, [Text.Encoding]::UTF8)) {
    $parts = $line.Split([char]9, 2)
    if ($parts.Count -eq 2 -and $parts[0].Length -gt 0 -and -not $map.ContainsKey($parts[0])) { $map[$parts[0]] = $parts[1] }
}
$files = Get-ChildItem -LiteralPath $mods -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '[\\/]Localization[\\/]' -or $_.FullName -match '[\\/]localization[\\/]' -or $_.Name -eq 'Localization.json' }
$changedFiles = 0
$changedItems = 0
foreach ($file in $files) {
    $original = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
    if ($original -notmatch '<<NL>|Sniper|Fire in a high arc at ground targets') { continue }
    $updated = $original.Replace('<<NL> ', $bs + 'n').Replace('<<NL>', $bs + 'n')
    foreach ($key in @('Sniper' + $zhFire + ' Cannon','Sniper' + $zhFire,'Fire in a high arc at ground targets. -5 ' + $zhAccuracy)) {
        if (-not $map.ContainsKey($key)) { continue }
        if ($key.EndsWith($zhAccuracy, [StringComparison]::Ordinal)) {
            $updated = $updated.Replace('"CULTURE_EN_US": "' + $key + '"', '"CULTURE_EN_US": "Fire in a high arc at ground targets. -5 Accuracy"')
        } else {
            $updated = $updated.Replace($key, $map[$key])
        }
    }
    if ($updated -eq $original) { continue }
    try { $null = $updated | ConvertFrom-Json -ErrorAction Stop }
    catch { throw ("Localization JSON validation failed; not written: " + $file.FullName + " :: " + $_.Exception.Message) }
    $relative = $file.FullName.Substring($mods.Length).TrimStart([char]92, [char]47)
    $backup = Join-Path $backupRoot $relative
    $parent = Split-Path $backup -Parent
    if (-not [IO.Directory]::Exists($parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    if (-not [IO.File]::Exists($backup)) { [IO.File]::WriteAllText($backup, $original, $enc) }
    [IO.File]::WriteAllText($file.FullName, $updated, $enc)
    $changedFiles++
    $changedItems += ([regex]::Matches($original, '<<NL>')).Count
}
Write-Host ("Localization formatting repaired: files={0}, newline markers={1}" -f $changedFiles, $changedItems)
