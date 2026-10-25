param(
    [string]$Root = (Split-Path $PSScriptRoot -Parent),
    [string]$ModsPath = '',
    [string]$CsvPath = ''
)

$ErrorActionPreference = 'Stop'

function Format-UnitDetail([string]$Value) {
    if ([string]::IsNullOrEmpty($Value)) { return $Value }
    $normalized = $Value -replace '<mspace(?:=[^>]+)?>', ''
    $normalized = $normalized -replace '</mspace>', ''
    if ($normalized.IndexOf('<b>数值', [StringComparison]::Ordinal) -lt 0) { return $normalized }

    $normalized = $normalized -replace '(?i)</b>[ \t]+(?=<color=#ffcc00>)', '</b>\n'
    $normalized = $normalized -replace '(?i)</b>[ \t]+(?=<b><color=#ffcc00>)', '</b>\n'
    $normalized = $normalized -replace '(?i)</color>[ \t]+(?=<color=#ff0000>)', '</color>\n\n'
    $normalized = $normalized -replace '</color>[ \t]+(#武器:)', '</color>\n$1'
    $numberPattern = '-?\d+(?:\.\d+)?'
    $yellowPattern = '(?i)<color=#ffcc00>(?<body>.*?)</color>'
    $yellow = $null
    foreach ($candidate in [regex]::Matches($normalized, $yellowPattern, [Text.RegularExpressions.RegexOptions]::Singleline)) {
        if ($candidate.Groups['body'].Value.IndexOf('<b>数值', [StringComparison]::Ordinal) -ge 0) {
            $yellow = $candidate
            break
        }
    }
    if ($null -eq $yellow) { return $normalized }
    $body = $yellow.Groups['body'].Value -replace '\\n', ' '
    $header = [regex]::Match($body, '<b>数值(?<labels>[^<]*)</b>')
    if (-not $header.Success) { return $normalized }
    $headerEnd = $header.Index + $header.Length
    $labelText = $header.Groups['labels'].Value
    if ([string]::IsNullOrWhiteSpace($labelText)) {
        $outsideLabels = [regex]::Match($body.Substring($headerEnd), '^[ \t]+(?<labels>[^<]*?)(?=<b>)')
        if ($outsideLabels.Success) {
            $labelText = $outsideLabels.Groups['labels'].Value
            $headerEnd += $outsideLabels.Index + $outsideLabels.Length
        }
    }
    $labels = @($labelText.Trim() -split '[ \t]+' | Where-Object { $_ })
    $rowPattern = '<b>(?<label>[^<]+)</b>[ \t]+(?<values>' + $numberPattern + '(?:[ \t]+' + $numberPattern + ')*)'
    $rows = [regex]::Matches($body.Substring($headerEnd), $rowPattern)
    if ($rows.Count -eq 0) { return $normalized }
    $parsedRows = @()
    foreach ($row in $rows) {
        $values = @($row.Groups['values'].Value -split '[ \t]+' | Where-Object { $_ })
        $parsedRows += [pscustomobject]@{ Label = $row.Groups['label'].Value.Trim(); Values = $values }
    }
    $maxValues = ($parsedRows | ForEach-Object { $_.Values.Count } | Measure-Object -Maximum).Maximum
    $columnCount = [Math]::Max($labels.Count, [int]$maxValues)
    if ($columnCount -lt 1) { return $normalized }
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
    $table = '<b>数值' + $headerGap + (($headerValues -join (' ' * $columnGap)).TrimEnd()) + '</b>'
    $bodyLines = ''
    foreach ($row in $parsedRows) {
        if ($row.Label -eq '总计' -or $row.Label -eq '合计') { $bodyLines += "\n" }
        $rowCells = New-Object 'System.Collections.Generic.List[string]'
        for ($index = 0; $index -lt $row.Values.Count; $index++) {
            $cell = $row.Values[$index]
            if ($index -lt $row.Values.Count - 1) { $cell = $cell.PadRight($columnWidths[$index]) }
            [void]$rowCells.Add($cell)
        }
        $rowGap = ' ' * ([Math]::Max(1, $labelWidth - $row.Label.Length + 1))
        $bodyLines += "\n<b>$($row.Label)</b>" + $rowGap + (($rowCells -join (' ' * $columnGap)).TrimEnd())
    }
    $table += $bodyLines
    $prefix = $body.Substring(0, $header.Index).Trim() -replace '[ \t]+', ' '
    $prefix = [regex]::Replace($prefix, '[ \t]*(<b>结构\b)', '\n$1')
    if ($prefix.Length -gt 0) { $prefix += "\n" }
    $replacement = '<color=#ffcc00>' + $prefix + $table + '</color>'
    $normalized = $normalized.Remove($yellow.Index, $yellow.Length).Insert($yellow.Index, $replacement)
    return $normalized
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
$script:failedFields = 0
if ([string]::IsNullOrWhiteSpace($ModsPath)) { $ModsPath = Join-Path $Root 'Mods' }
if ([string]::IsNullOrWhiteSpace($CsvPath)) { $CsvPath = Join-Path $Root 'strings_zh-CN.csv' }
foreach ($file in Get-ChildItem -LiteralPath $ModsPath -Recurse -File -Filter 'Localization.json') {
    try {
        if (Update-LocalizationJson $file.FullName) { $changedFiles++ }
    } catch {
        $script:failedFields++
        Write-Warning ("单位详情表格修复跳过文件: {0} :: {1}" -f $file.FullName, $_.Exception.Message)
    }
}

$csvLines = [IO.File]::ReadAllLines($CsvPath, [Text.Encoding]::UTF8)
$csvChanged = $false
for ($index = 0; $index -lt $csvLines.Count; $index++) {
    try {
        $value = Format-UnitDetail $csvLines[$index]
    } catch {
        $script:failedFields++
        Write-Warning ("单位详情表格修复跳过 CSV 行 {0}: {1}" -f ($index + 1), $_.Exception.Message)
        continue
    }
    if ($value -ne $csvLines[$index]) {
        $csvLines[$index] = $value
        $csvChanged = $true
    }
}
if ($csvChanged) {
    [IO.File]::WriteAllLines($CsvPath, $csvLines, (New-Object Text.UTF8Encoding($false)))
    $changedFiles++
}

Write-Host ("单位详情表格修复: files={0} failed={1}" -f $changedFiles, $script:failedFields)
