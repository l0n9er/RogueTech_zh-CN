param(
    [string]$Root = (Split-Path $PSScriptRoot -Parent),
    [string]$ModsPath = '',
    [string]$CsvPath = ''
)

$ErrorActionPreference = 'Stop'

function Format-UnitDetail([string]$Value) {
    if ($Value.IndexOf('<b>数值', [StringComparison]::Ordinal) -lt 0) { return $Value }
    $normalized = $Value -replace '<mspace(?:=[^>]+)?>', ''
    $normalized = $normalized -replace '</mspace>', ''
    $numberPattern = '-?\d+(?:\.\d+)?'
    $tablePattern = '<b>数值</b>[ \t]+(?<labels>[^<\r\n]+)(?<rows>(?:\\n<b>(?!(?:总计|合计)</b>)[^<\r\n]+</b>[ \t]+' + $numberPattern + '(?:[ \t]+' + $numberPattern + ')*)+)(?<total>\\n(?:\\n)?<b>(?:总计|合计)</b>[ \t]+' + $numberPattern + '(?:[ \t]+' + $numberPattern + ')*)?'
    $rowPattern = '\\n<b>(?<label>[^<]+)</b>[ \t]+(?<values>' + $numberPattern + '(?:[ \t]+' + $numberPattern + ')*)'
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $labels = @($match.Groups['labels'].Value.Trim() -split '[ \t]+' | Where-Object { $_ })
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

        if ($labels.Count -lt 1) { return $match.Value }
        $columnCount = [Math]::Max($labels.Count, (($parsedRows | ForEach-Object { $_.Values.Count } | Measure-Object -Maximum).Maximum))
        $labelWidth = '数值'.Length
        foreach ($row in $parsedRows) { $labelWidth = [Math]::Max($labelWidth, $row.Label.Length) }
        $columnWidths = New-Object int[] $columnCount
        for ($index = 0; $index -lt $columnCount; $index++) {
            if ($index -lt $labels.Count) { $columnWidths[$index] = $labels[$index].Length }
            foreach ($row in $parsedRows) {
                if ($index -lt $row.Values.Count) { $columnWidths[$index] = [Math]::Max($columnWidths[$index], $row.Values[$index].Length) }
            }
        }
        $columnGap = 3
        $headerValues = New-Object 'System.Collections.Generic.List[string]'
        for ($index = 0; $index -lt $labels.Count; $index++) {
            [void]$headerValues.Add($labels[$index].PadRight($columnWidths[$index]))
        }
        $headerGap = ' ' * ([Math]::Max(1, $labelWidth - '数值'.Length + 1))
        $header = '<b>数值</b>' + $headerGap + '<mspace=0.5em>' + (($headerValues -join (' ' * $columnGap)).TrimEnd()) + '</mspace>'
        $body = ''
        foreach ($row in $parsedRows) {
            if ($row.Label -eq '总计' -or $row.Label -eq '合计') { $body += "\n" }
            $rowCells = New-Object 'System.Collections.Generic.List[string]'
            for ($index = 0; $index -lt $row.Values.Count; $index++) {
                $cell = $row.Values[$index]
                if ($index -lt $row.Values.Count - 1) { $cell = $cell.PadRight($columnWidths[$index]) }
                [void]$rowCells.Add($cell)
            }
            $rowGap = ' ' * ([Math]::Max(1, $labelWidth - $row.Label.Length + 1))
            $body += "\n<b>$($row.Label)</b>" + $rowGap + '<mspace=0.5em>' + (($rowCells -join (' ' * $columnGap)).TrimEnd()) + '</mspace>'
        }
        return $header + $body
    }
    return [regex]::Replace($normalized, $tablePattern, $evaluator)
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
if ([string]::IsNullOrWhiteSpace($ModsPath)) { $ModsPath = Join-Path $Root 'Mods' }
if ([string]::IsNullOrWhiteSpace($CsvPath)) { $CsvPath = Join-Path $Root 'strings_zh-CN.csv' }
foreach ($file in Get-ChildItem -LiteralPath $ModsPath -Recurse -File -Filter 'Localization.json') {
    if (Update-LocalizationJson $file.FullName) { $changedFiles++ }
}

$csvLines = [IO.File]::ReadAllLines($CsvPath, [Text.Encoding]::UTF8)
$csvChanged = $false
for ($index = 0; $index -lt $csvLines.Count; $index++) {
    $value = Format-UnitDetail $csvLines[$index]
    if ($value -ne $csvLines[$index]) {
        $csvLines[$index] = $value
        $csvChanged = $true
    }
}
if ($csvChanged) {
    [IO.File]::WriteAllLines($CsvPath, $csvLines, (New-Object Text.UTF8Encoding($false)))
    $changedFiles++
}

Write-Host ("单位详情表格修复: files={0}" -f $changedFiles)
