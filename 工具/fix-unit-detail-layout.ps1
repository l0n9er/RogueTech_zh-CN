param(
    [string]$Root = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'

function Get-DisplayWidth([string]$Text) {
    $width = 0
    foreach ($char in $Text.ToCharArray()) {
        if ([int][char]$char -ge 0x2E80) { $width += 2 } else { $width++ }
    }
    return $width
}

function Format-TableRow([string]$Label, [string[]]$Values, [int[]]$ColumnStarts) {
    $labelWidth = Get-DisplayWidth $Label
    $line = "\n<b>$Label</b>" + (' ' * [Math]::Max(1, $ColumnStarts[0] - $labelWidth))
    $position = $ColumnStarts[0]
    for ($index = 0; $index -lt $Values.Count; $index++) {
        $value = $Values[$index]
        if ($position -gt $ColumnStarts[$index]) {
            $line += ' '
            $position++
        }
        elseif ($position -lt $ColumnStarts[$index]) {
            $line += (' ' * ($ColumnStarts[$index] - $position))
            $position = $ColumnStarts[$index]
        }
        $line += $value
        $position += Get-DisplayWidth $value
    }
    return $line
}

function Format-UnitDetail([string]$Value) {
    if ($Value.IndexOf('<b>数值', [StringComparison]::Ordinal) -lt 0) { return $Value }
    $tablePattern = '<b>数值[ \t]+(?<labels>[^<\r\n]+)</b>(?<rows>(?:\\n<b>(?!(?:总计|合计)</b>)[^<\r\n]+</b>[ \t]+-?\d+(?:\.\d+)?(?:[ \t]+-?\d+(?:\.\d+)?)+)+)(?<total>\\n(?:\\n)?<b>(?:总计|合计)</b>[ \t]+-?\d+(?:\.\d+)?(?:[ \t]+-?\d+)+)'
    $rowPattern = '\\n<b>(?<label>[^<]+)</b>[ \t]+(?<values>-?\d+(?:\.\d+)?(?:[ \t]+-?\d+(?:\.\d+)?)+)'
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $labels = @($match.Groups['labels'].Value.Trim() -split '[ \t]+' | Where-Object { $_ })
        $contextBeforeTable = $Value.Substring(0, $match.Index)
        $hasArmorStructureContext = $contextBeforeTable -match '(?s)<b>(?:装甲|护甲)[：:]?</b>.*<b>结构[：:]?</b>'
        if ($hasArmorStructureContext -and $labels.Count -eq 2 -and $labels[0] -eq 'A' -and $labels[1] -eq 'S') {
            $labels = @('装甲', '结构')
        }
        $rows = [regex]::Matches($match.Groups['rows'].Value, $rowPattern)
        $parsedRows = @()
        foreach ($row in $rows) {
            $values = @($row.Groups['values'].Value -split '[ \t]+' | Where-Object { $_ })
            $parsedRows += [pscustomobject]@{
                Label = $row.Groups['label'].Value
                Values = $values
            }
        }
        $total = [regex]::Match($match.Groups['total'].Value, '<b>(?<label>总计|合计)</b>[ \t]+(?<values>-?\d+(?:\.\d+)?(?:[ \t]+-?\d+(?:\.\d+)?)+)')
        if ($total.Success) {
            $values = @($total.Groups['values'].Value -split '[ \t]+' | Where-Object { $_ })
            $parsedRows += [pscustomobject]@{
                Label = $total.Groups['label'].Value
                Values = $values
            }
        }

        $columnCount = [Math]::Max($labels.Count, (($parsedRows | ForEach-Object { $_.Values.Count } | Measure-Object -Maximum).Maximum))
        if ($columnCount -lt 1) { return $match.Value }
        $labelWidth = Get-DisplayWidth '数值'
        foreach ($row in $parsedRows) {
            $labelWidth = [Math]::Max($labelWidth, (Get-DisplayWidth $row.Label))
        }
        $columnWidths = New-Object int[] $columnCount
        for ($index = 0; $index -lt $columnCount; $index++) {
            if ($index -lt $labels.Count) {
                $columnWidths[$index] = Get-DisplayWidth $labels[$index]
            }
            foreach ($row in $parsedRows) {
                if ($index -lt $row.Values.Count) {
                    $columnWidths[$index] = [Math]::Max($columnWidths[$index], (Get-DisplayWidth $row.Values[$index]))
                }
            }
        }
        $columnStarts = New-Object int[] $columnCount
        $columnGap = 6
        $columnStarts[0] = $labelWidth + $columnGap
        for ($index = 1; $index -lt $columnCount; $index++) {
            $columnStarts[$index] = $columnStarts[$index - 1] + $columnWidths[$index - 1] + $columnGap
        }

        $header = '<b>数值' + (' ' * [Math]::Max(1, $columnStarts[0] - (Get-DisplayWidth '数值')))
        for ($index = 0; $index -lt $labels.Count; $index++) {
            $header += $labels[$index]
            if ($index -lt $labels.Count - 1) {
                $header += (' ' * [Math]::Max(1, $columnStarts[$index + 1] - $columnStarts[$index] - (Get-DisplayWidth $labels[$index])))
            }
        }
        $body = '</b>'
        foreach ($row in $parsedRows) {
            if ($row.Label -eq '总计' -or $row.Label -eq '合计') { $body += "\n" }
            $body += Format-TableRow $row.Label $row.Values $columnStarts
        }
        return $header + $body
    }
    return [regex]::Replace($Value, $tablePattern, $evaluator)
}

function Update-LocalizationJson([string]$Path) {
    $lines = [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)
    $changed = $false
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $match = [regex]::Match($lines[$index], '^(?<indent>\s*)"CULTURE_ZH_CN"\s*:\s*"(?<value>(?:[^"\\]|\\.)*)"(?<tail>\s*,?)\s*$')
        if (-not $match.Success) { continue }
        $value = Format-UnitDetail $match.Groups['value'].Value
        if ($value -eq $match.Groups['value'].Value) { continue }
        $lines[$index] = $match.Groups['indent'].Value + '"CULTURE_ZH_CN": "' + $value + '"' + $match.Groups['tail'].Value
        $changed = $true
    }
    if ($changed) {
        [IO.File]::WriteAllLines($Path, $lines, (New-Object Text.UTF8Encoding($false)))
    }
    return $changed
}

$changedFiles = 0
$changedTables = 0

foreach ($file in Get-ChildItem (Join-Path $Root 'Mods') -Recurse -File -Filter 'Localization.json') {
    if (Update-LocalizationJson $file.FullName) { $changedFiles++ }
}

$csvPath = Join-Path $Root 'strings_zh-CN.csv'
$csvLines = [IO.File]::ReadAllLines($csvPath, [Text.Encoding]::UTF8)
$csvChanged = $false
for ($index = 0; $index -lt $csvLines.Count; $index++) {
    $value = Format-UnitDetail $csvLines[$index]
    if ($value -ne $csvLines[$index]) {
        $csvLines[$index] = $value
        $csvChanged = $true
    }
}
if ($csvChanged) {
    [IO.File]::WriteAllLines($csvPath, $csvLines, (New-Object Text.UTF8Encoding($false)))
    $changedFiles++
}

Write-Host ("单位详情表格修复: files={0}" -f $changedFiles)
