param(
    [string]$mods = "",
    [string]$backupRoot = ""
)
$ErrorActionPreference = 'Stop'
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($mods)) {
    $gr = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gr)) { throw '找不到游戏目录，请用 -mods 指定。' }
    $mods = Join-Path $gr 'Mods'
}
if ([string]::IsNullOrWhiteSpace($backupRoot)) {
    $backupRoot = Join-Path $packRoot ('backup\literal-newlines-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

# JSON 中的 "\\n" 会被解析成两个可见字符：反斜杠和 n；游戏不会把它显示为换行。
# 在说明字段的 JSON 字符串中将其改为 "\n"，让 JSON 解析后得到真实换行。
$slash = [string][char]92
$doubleEscapedNewline = $slash + $slash + 'n'
$singleEscapedNewline = $slash + 'n'
$doubleEscapedReturn = $slash + $slash + 'r'
$singleEscapedReturn = $slash + 'r'
$fieldPattern = '"(?<field>Details|YangsThoughts|StockRole|Full)"\s*:\s*"(?<value>(?:[^"\\]|\\.)*)"'
$rx = [regex]::new($fieldPattern)
$enc = New-Object Text.UTF8Encoding $false
$files = Get-ChildItem -LiteralPath $mods -Recurse -File -Filter '*.json' | Where-Object {
    $_.FullName -notmatch '[\\/](\.modtek|ModSaves|Localization|localization)[\\/]'
}
$changedFiles = 0
$changedValues = 0
$changedEscapes = 0
foreach ($file in $files) {
    $original = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
    if ($original -notmatch '"(Details|YangsThoughts|StockRole|Full)"\s*:') { continue }
    $localValues = 0
    $localEscapes = 0
    $updated = $rx.Replace($original, [Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $value = $m.Groups['value'].Value
        $fixed = $value.Replace($doubleEscapedNewline, $singleEscapedNewline).
                        Replace($doubleEscapedReturn, $singleEscapedReturn)
        if ($fixed -ne $value) {
            $localValues++
            $localEscapes += ([regex]::Matches($value, [regex]::Escape($doubleEscapedNewline))).Count
            $localEscapes += ([regex]::Matches($value, [regex]::Escape($doubleEscapedReturn))).Count
            return '"' + $m.Groups['field'].Value + '": "' + $fixed + '"'
        }
        return $m.Value
    })
    if ($updated -eq $original) { continue }

    # 验证原始 JSON 结构，防止转义修复意外破坏文件。
    try { $null = $updated | ConvertFrom-Json -ErrorAction Stop }
    catch { throw ("JSON 校验失败，未写入: " + $file.FullName + " :: " + $_.Exception.Message) }

    $relative = $file.FullName.Substring($mods.Length).TrimStart([char[]]@('\','/'))
    $backup = Join-Path $backupRoot $relative
    $parent = Split-Path $backup -Parent
    if (-not (Test-Path -LiteralPath $parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    if (-not (Test-Path -LiteralPath $backup)) { [IO.File]::WriteAllText($backup, $original, $enc) }
    [IO.File]::WriteAllText($file.FullName, $updated, $enc)
    $changedFiles++
    $changedValues += $localValues
    $changedEscapes += $localEscapes
}
Write-Output ("换行转义修复：文件={0} 字段值={1} 转义序列={2} 备份={3}" -f $changedFiles, $changedValues, $changedEscapes, $backupRoot)
