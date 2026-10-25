param(
    [string]$Root = (Split-Path $PSScriptRoot -Parent),
    [string]$ModsPath = '',
    [string]$CsvPath = '',
    [string]$BackupRoot = ''
)

$ErrorActionPreference = 'Stop'
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
    $BackupRoot = Join-Path $packRoot ('backup\detail-format-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$detailColors = '#(?:e62e00|ff0000|e20000|e51717|cc1c12|ff0d00|d80404|e11919|ffef00|ffcc00|f0ff00|ffff00)'
$detailLabelPattern = '(?:\u751f\u7269\u7fa4\u7cfb\u9650\u5236|\u73af\u5883\u9650\u5236|\u79fb\u52a8|\u88c5\u7532|\u7ed3\u6784|\u6570\u503c|\u7279\u8d28|\u7279\u6027|\u7279\u70b9|\u7279\u5f81|\u6295\u653e\u8d39\u7528\u500d\u7387|\u90e8\u7f72\u8d39\u7528\u500d\u7387|\u6295\u653e\u6210\u672c\u500d\u7387|\u90e8\u7f72\u6210\u672c\u500d\u7387|\u624b\u81c2\u9a71\u52a8\u5668\u9650\u5236|\u624b\u81c2\u6267\u884c\u5668\u9650\u5236|\u624b\u81c2\u9650\u5236|\u624b\u81c2\u9a71\u52a8\u5668\u9650\u4f4d|\u624b\u81c2\u6267\u884c\u5668\u9650\u4f4d)'

function Normalize-UnitDetailText([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $Text = $Text.Replace('<<NL>', '\n')
    $colors = $detailColors
    $redColors = '#(?:e62e00|ff0000|e20000|e51717|cc1c12|ff0d00|d80404|e11919)'
    $redBlock = '(?i:<b><color=' + $redColors + '>(?:<b>)?(?:特质|特性|特点|特征)[:：].*?</color></b>)'
    $redFeatureBlock = '(?i:(?:<b>)?<color=' + $redColors + '>(?:<b>)?(?:特质|特性|特点|特征)[:：].*?</color>(?:</b>)?)'
    $costBlock = '(?i:<b><color=' + $redColors + '>(?:<b>)?(?:投放|部署)(?:费用|成本)倍率[:：].*?</color></b>)'
    $Text = [regex]::Replace($Text, '(' + $redBlock + ')[ \t]+(?=' + $costBlock + ')', '$1\n\n')
    $Text = [regex]::Replace($Text, '(' + $costBlock + ')[ \t]+(?=<color=#(?:ffef00|ffcc00|f0ff00|ffff00))', '$1\n\n')
    $Text = [regex]::Replace($Text, '(?i)</color></b>[ \t]+(?=<b>)', '</color></b>\n')
    $Text = [regex]::Replace($Text, '(?i)</color>[ \t]+(?=<b>)', '</color>\n')
    $Text = [regex]::Replace($Text, '(?i)</color>[ \t]*(?:\\n)*(?=<color=' + $redColors + '>(?:<b>)?(?:特性|特质|特点|特征)[:：])', '</color>\n\n')
    $Text = [regex]::Replace($Text, '(' + $redFeatureBlock + ')[ \t]*(?!(?:\\n|<br>|$))', '$1\n')
    $Text = [regex]::Replace($Text, '<b>(?:\\n)*(?=<color=' + $colors + '>' + $detailLabelPattern + ')', '<b>', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $targetTagPattern = '(?i)(?<!<b>)(?:<b>)?<color=' + $colors + '>(?:<b>)?(?=' + $detailLabelPattern + ')'
    if ($Text -notmatch $targetTagPattern) {
        return $Text
    }

    $boundary = '(?<!<b>)(?:<b>)?<color=' + $colors + '>(?:<b>)?(?=' + $detailLabelPattern + ')'
    $breakPattern = '(?:\\n)+(?=' + $boundary + ')'
    $Text = [regex]::Replace($Text, $breakPattern, '\n', [Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $missingBreakPattern = '(?<!\\n)(?<!<br>)(?<!<<NL>>)(?=' + $boundary + ')'
    $Text = [regex]::Replace($Text, $missingBreakPattern, '\n', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $Text = [regex]::Replace($Text, '(' + $redBlock + ')[ \t]*(?:\\n)+(?=' + $costBlock + ')', '$1\n\n')
    $Text = [regex]::Replace($Text, '(' + $costBlock + ')[ \t]*(?:\\n)+(?=<color=#(?:ffef00|ffcc00|f0ff00))', '$1\n\n')
    $Text = [regex]::Replace($Text, '(?<align></align>)?</color>[ \t]*(?:\\n)*(?=<color=#(?:ff0000|e62e00)>(?:特性|特质|特点|特征)[:：])', '${align}</color>\n\n', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    return $Text
}

function Backup-FormatTarget([string]$Path, [string]$RelativePath) {
    $backupPath = Join-Path $BackupRoot $RelativePath
    if (Test-Path -LiteralPath $backupPath) { return }
    $parent = Split-Path $backupPath -Parent
    if (-not (Test-Path -LiteralPath $parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    [IO.File]::Copy($Path, $backupPath, $false)
}

function Update-DetailsJson([string]$Path) {
    $lines = [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)
    $changed = $false
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $match = [regex]::Match($lines[$index], '^(?<indent>\s*)"(?<field>Details|YangsThoughts|StockRole|CULTURE_ZH_CN)"\s*:\s*"(?<value>(?:[^"\\]|\\.)*)"(?<tail>\s*,?)\s*$')
        if (-not $match.Success) { continue }
        $value = Normalize-UnitDetailText $match.Groups['value'].Value
        if ($value -eq $match.Groups['value'].Value) { continue }
        $lines[$index] = $match.Groups['indent'].Value + '"' + $match.Groups['field'].Value + '": "' + $value + '"' + $match.Groups['tail'].Value
        $changed = $true
    }
    if ($changed) {
        $relative = $Path.Substring($ModsPath.Length).TrimStart([char[]]@([char]92, [char]47))
        Backup-FormatTarget $Path (Join-Path 'Mods' $relative)
        [IO.File]::WriteAllLines($Path, $lines, (New-Object Text.UTF8Encoding($false)))
    }
    return $changed
}

$changedFiles = 0
if ([string]::IsNullOrWhiteSpace($ModsPath)) { $ModsPath = Join-Path $Root 'Mods' }
if ([string]::IsNullOrWhiteSpace($CsvPath)) { $CsvPath = Join-Path $Root 'strings_zh-CN.csv' }
foreach ($file in Get-ChildItem -LiteralPath $ModsPath -Recurse -File -Filter 'Localization.json') {
    if (Update-DetailsJson $file.FullName) { $changedFiles++ }
}
foreach ($file in Get-ChildItem -LiteralPath $ModsPath -Recurse -File -Filter '*.json' | Where-Object { $_.Name -ne 'Localization.json' }) {
    if (Update-DetailsJson $file.FullName) { $changedFiles++ }
}

$csvLines = [IO.File]::ReadAllLines($CsvPath, [Text.Encoding]::UTF8)
$csvChanged = $false
for ($index = 1; $index -lt $csvLines.Count; $index++) {
    $comma = $csvLines[$index].IndexOf(',')
    if ($comma -lt 1) { continue }
    $key = $csvLines[$index].Substring(0, $comma)
    $value = $csvLines[$index].Substring($comma + 1)
    $targetValuePattern = '(?i)(?:<b>)?<color=' + $detailColors + '>(?:<b>)?' + $detailLabelPattern
    if ($key -notmatch 'quirk:.*dropcostmultiplier|armactuatorlimit' -and
        $value -notmatch $targetValuePattern -and $value -notmatch '<<NL>') { continue }
    $updated = Normalize-UnitDetailText $value
    if ($updated -eq $value) { continue }
    $csvLines[$index] = $key + ',' + $updated
    $csvChanged = $true
}
if ($csvChanged) {
    Backup-FormatTarget $CsvPath 'BattleTech_Data\StreamingAssets\data\localization\strings_zh-CN.csv'
    [IO.File]::WriteAllLines($CsvPath, $csvLines, (New-Object Text.UTF8Encoding($false)))
    $changedFiles++
}

Write-Host ("详情颜色换行修复: files={0}" -f $changedFiles)
