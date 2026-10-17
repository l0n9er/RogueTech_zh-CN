param(
    [Parameter(Mandatory = $true)][string]$mods,
    [string]$pairs = "",
    [string]$backupRoot = ""
)
$ErrorActionPreference = 'Stop'
$enc = New-Object Text.UTF8Encoding($false)
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($pairs)) { $pairs = Join-Path $PSScriptRoot 'dict-localization-missing.tsv' }
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot 'backup\Mods-localization-missing' }
if (-not [IO.File]::Exists($pairs)) { throw "Missing localization pairs: $pairs" }

$map = New-Object 'System.Collections.Generic.Dictionary[string,string]'
foreach ($line in [IO.File]::ReadAllLines($pairs, [Text.Encoding]::UTF8)) {
    $i = $line.IndexOf("`t")
    if ($i -gt 0) { $map[$line.Substring(0, $i)] = $line.Substring($i + 1) }
}

$files = Get-ChildItem -LiteralPath $mods -Recurse -File -Filter 'Localization.json' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '[\\/]Localization[\\/]' }
$changedFiles = 0
$changedItems = 0
foreach ($file in $files) {
    $lines = [IO.File]::ReadAllLines($file.FullName, [Text.Encoding]::UTF8)
    $updated = New-Object 'System.Collections.Generic.List[string]'
    $changed = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $m = [regex]::Match($line, '^(?<indent>\s*)"CULTURE_EN_US"\s*:\s*"(?<value>(?:[^"\\]|\\.)*)"\s*,?\s*$')
        if (-not $m.Success -or -not $map.ContainsKey($m.Groups['value'].Value)) {
            [void]$updated.Add($line)
            continue
        }
        $next = if ($i + 1 -lt $lines.Count) { $lines[$i + 1].Trim() } else { '' }
        if ($next -match '^"CULTURE_ZH_CN"\s*:') {
            [void]$updated.Add($line)
            $zhLine = $lines[++$i]
            $zhMatch = [regex]::Match($zhLine, '^(?<indent>\s*)"CULTURE_ZH_CN"\s*:\s*"(?<value>(?:[^"\\]|\\.)*)"(?<comma>,?)\s*$')
            if ($zhMatch.Success -and $zhMatch.Groups['value'].Value -ne $map[$m.Groups['value'].Value]) {
                [void]$updated.Add($zhMatch.Groups['indent'].Value + '"CULTURE_ZH_CN": "' + $map[$m.Groups['value'].Value] + '"' + $zhMatch.Groups['comma'].Value)
                $changed = $true
                $changedItems++
            } else {
                [void]$updated.Add($zhLine)
            }
            continue
        }
        [void]$updated.Add(($line.TrimEnd().TrimEnd(',') + ','))
        $comma = if ($next.StartsWith('}')) { '' } else { ',' }
        [void]$updated.Add($m.Groups['indent'].Value + '"CULTURE_ZH_CN": "' + $map[$m.Groups['value'].Value] + '"' + $comma)
        $changed = $true
        $changedItems++
    }
    if (-not $changed) { continue }
    $text = ($updated -join "`r`n") + "`r`n"
    try { $null = $text | ConvertFrom-Json -ErrorAction Stop } catch { throw "Localization JSON validation failed: $($file.FullName) :: $($_.Exception.Message)" }
    $relative = $file.FullName.Substring($mods.Length).TrimStart([char]92, [char]47)
    $backup = Join-Path $backupRoot $relative
    $parent = Split-Path $backup -Parent
    if (-not [IO.Directory]::Exists($parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    if (-not [IO.File]::Exists($backup)) { [IO.File]::WriteAllText($backup, ($lines -join "`r`n") + "`r`n", $enc) }
    [IO.File]::WriteAllText($file.FullName, $text, $enc)
    $changedFiles++
}
Write-Host ("缺失本地化补全: files={0}, entries={1}" -f $changedFiles, $changedItems)
