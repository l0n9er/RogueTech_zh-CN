param(
    [string]$Root = (Split-Path $PSScriptRoot -Parent),
    [string]$ModsPath = '',
    [string]$CsvPath = ''
)

$ErrorActionPreference = 'Stop'

function Get-DisplayWidth([string]$Text) {
    $width = 0
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $codePoint = [int][char]$Text[$index]
        if ([char]::IsHighSurrogate($Text[$index]) -and $index + 1 -lt $Text.Length -and [char]::IsLowSurrogate($Text[$index + 1])) {
            $codePoint = [char]::ConvertToUtf32($Text[$index], $Text[$index + 1])
            $index++
        }
        $isWide = ($codePoint -ge 0x1100 -and $codePoint -le 0x11FF) -or
            ($codePoint -ge 0x2E80 -and $codePoint -le 0xA4CF) -or
            ($codePoint -ge 0xAC00 -and $codePoint -le 0xD7A3) -or
            ($codePoint -ge 0xF900 -and $codePoint -le 0xFAFF) -or
            ($codePoint -ge 0xFE10 -and $codePoint -le 0xFE6F) -or
            ($codePoint -ge 0xFF01 -and $codePoint -le 0xFF60) -or
            ($codePoint -ge 0xFFE0 -and $codePoint -le 0xFFE6) -or
            ($codePoint -ge 0x20000 -and $codePoint -le 0x3FFFD)
        $width += if ($isWide) { 2 } else { 1 }
    }
    return $width
}

function Pad-DisplayWidthRight([string]$Text, [int]$Width) {
    $padding = $Width - (Get-DisplayWidth $Text)
    if ($padding -gt 0) { return $Text + (' ' * $padding) }
    return $Text
}

function Format-UnitDetail([string]$Value) {
    if ([string]::IsNullOrEmpty($Value)) { return $Value }
    $normalized = $Value -replace '<mspace(?:=[^>]+)?>', ''
    $normalized = $normalized -replace '</mspace>', ''
    if ($normalized.IndexOf('<b>数值', [StringComparison]::Ordinal) -lt 0 -and
        $normalized.IndexOf('<b>位置', [StringComparison]::Ordinal) -lt 0) { return $normalized }

    $normalized = $normalized -replace '(?i)</b>[ \t]+(?=<color=#ffcc00>)', '</b>\n'
    $normalized = $normalized -replace '(?i)</b>[ \t]+(?=<b><color=#ffcc00>)', '</b>\n'
    $normalized = $normalized -replace '(?i)</color>[ \t]+(?=<color=#ff0000>)', '</color>\n\n'
    $normalized = $normalized -replace '</color>[ \t]+(#武器:)', '</color>\n$1'
    $numberPattern = '-?\d+(?:\.\d+)?'
    $yellowPattern = '(?i)<color=(?<color>#[0-9a-f]{6,8})>(?<body>.*?)</color>'
    $yellow = $null
    foreach ($candidate in [regex]::Matches($normalized, $yellowPattern, [Text.RegularExpressions.RegexOptions]::Singleline)) {
        if (($candidate.Groups['body'].Value.IndexOf('<b>数值', [StringComparison]::Ordinal) -ge 0 -or
             $candidate.Groups['body'].Value.IndexOf('<b>位置', [StringComparison]::Ordinal) -ge 0) -and
            $candidate.Groups['color'].Value -match '(?i)^#(?:ffcc00|ffef00|f0ff00)$') {
            $yellow = $candidate
            break
        }
    }
    if ($null -eq $yellow) { return $normalized }
    $body = $yellow.Groups['body'].Value -replace '(?i)</?align(?:=left|=\\?"left\\?")?>', '' -replace '\\n', ' '
    $header = [regex]::Match($body, '<b>(?<title>数值|位置)(?<labels>[^<]*)</b>')
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
    $isArmorStructureHeader = $labels.Count -eq 2 -and
        (($labels[0] -ieq 'A' -and $labels[1] -ieq 'S') -or
         ($labels[0] -eq '装甲' -and $labels[1] -eq '结构'))
    if (-not $isArmorStructureHeader) { return $normalized }
    $armorStructureColumns = @('装甲', '结构')
    $rowPattern = '<b>(?<label>[^<]+)</b>[ \t]+(?<values>' + $numberPattern + '[ \t]+' + $numberPattern + ')'
    $rows = [regex]::Matches($body.Substring($headerEnd), $rowPattern)
    if ($rows.Count -eq 0) { return $normalized }
    $parsedRows = @()
    foreach ($row in $rows) {
        $values = @($row.Groups['values'].Value -split '[ \t]+' | Where-Object { $_ })
        $parsedRows += [pscustomobject]@{ Label = $row.Groups['label'].Value.Trim(); Values = $values }
    }
    $columnCount = $armorStructureColumns.Count
    $labelWidth = Get-DisplayWidth '数值'
    foreach ($row in $parsedRows) { $labelWidth = [Math]::Max($labelWidth, (Get-DisplayWidth $row.Label)) }
    $columnWidths = New-Object int[] $columnCount
    for ($index = 0; $index -lt $columnCount; $index++) {
        $columnWidths[$index] = Get-DisplayWidth $armorStructureColumns[$index]
        foreach ($row in $parsedRows) {
            if ($index -lt $row.Values.Count) { $columnWidths[$index] = [Math]::Max($columnWidths[$index], (Get-DisplayWidth $row.Values[$index])) }
        }
    }
    $columnGap = 3
    $headerValues = New-Object 'System.Collections.Generic.List[string]'
    for ($index = 0; $index -lt $armorStructureColumns.Count; $index++) {
        [void]$headerValues.Add((Pad-DisplayWidthRight $armorStructureColumns[$index] $columnWidths[$index]))
    }
    $headerGap = ' ' * ([Math]::Max(1, $labelWidth - (Get-DisplayWidth '数值') + 1))
    $table = '<b>数值' + $headerGap + (($headerValues -join (' ' * $columnGap)).TrimEnd()) + '</b>'
    $bodyLines = ''
    foreach ($row in $parsedRows) {
        if ($row.Label -eq '总计' -or $row.Label -eq '合计') { $bodyLines += "\n" }
        $rowCells = New-Object 'System.Collections.Generic.List[string]'
        for ($index = 0; $index -lt $row.Values.Count; $index++) {
            $cell = $row.Values[$index]
            if ($index -lt $row.Values.Count - 1) { $cell = Pad-DisplayWidthRight $cell $columnWidths[$index] }
            [void]$rowCells.Add($cell)
        }
        $rowGap = ' ' * ([Math]::Max(1, $labelWidth - (Get-DisplayWidth $row.Label) + 1))
        $bodyLines += "\n<b>$($row.Label)</b>" + $rowGap + (($rowCells -join (' ' * $columnGap)).TrimEnd())
    }
    $table = '<align=left>' + $table + $bodyLines + '</align>'
    $prefix = $body.Substring(0, $header.Index).Trim()
    $prefix = $prefix -replace '^(?:\\n|<br>)+', '' -replace '(?:\\n|<br>)+$', '' -replace '[ \t]+', ' '
    $prefix = [regex]::Replace($prefix, '[ \t]*(<b>结构\b)', '\n$1')
    if ($prefix.Length -gt 0) { $prefix += "\n" }
    $replacement = '<color=' + $yellow.Groups['color'].Value + '>' + $prefix + $table + '</color>'
    $normalized = $normalized.Remove($yellow.Index, $yellow.Length).Insert($yellow.Index, $replacement)
    return $normalized
}

function Update-LocalizationJson([string]$Path) {
    $lines = [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)
    $changed = $false
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Contains('<align="left">')) {
            $lines[$index] = $lines[$index].Replace('<align="left">', '<align=left>')
            $changed = $true
        }
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
