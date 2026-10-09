param(
    [Parameter(Mandatory=$true)][string]$mods,
    [string]$backupRoot = ""
)
$ErrorActionPreference = 'Stop'
$enc = New-Object Text.UTF8Encoding($false)
if ([string]::IsNullOrWhiteSpace($backupRoot)) {
    $backupRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'backup\json-sanitize'
}

# JSON 字符串不能包含裸的 U+0000..U+001F。旧版翻译流程把 CSV 的
# 0x1F 别名分隔符写进了 Details，导致整份载具/机甲 JSON 无法解析，
# 后续所有处理器只能跳过。这里把裸控制字符统一变为空格；别名中的
# 分隔符随后由 fix-ctl.ps1 按 JSON 规则规范成半角逗号。
$changed = 0
$controls = 0
$invalid = 0
$files = Get-ChildItem $mods -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike '*\.modtek\*' -and $_.Name -notlike '*.zhbak*' }
foreach ($f in $files) {
    $orig = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    # 用一次正则替换取代逐字符 PowerShell 循环；在 4 万份定义上可将
    # 清理从数分钟降到可接受范围，同时只命中 JSON 禁止的控制字符。
    $matches = [regex]::Matches($orig, '[\x00-\x08\x0B\x0C\x0E-\x1F]')
    $controls += $matches.Count
    $n = [regex]::Replace($orig, '[\x00-\x08\x0B\x0C\x0E-\x1F]', ' ')
    if ($n -eq $orig) { continue }
    $rel = $f.FullName.Substring($mods.Length).TrimStart('\')
    $bak = Join-Path $backupRoot $rel
    $parent = Split-Path $bak -Parent
    if (-not (Test-Path $parent)) { [void][IO.Directory]::CreateDirectory($parent) }
    if (-not (Test-Path $bak)) { [IO.File]::WriteAllText($bak, $orig, $enc) }
    [IO.File]::WriteAllText($f.FullName, $n, $enc)
    $changed++
    # Windows PowerShell 5 的 ConvertFrom-Json 不支持 -Depth；这里只做语法验证。
    try { $null = $n | ConvertFrom-Json -ErrorAction Stop } catch { $invalid++ }
}
Write-Host ("JSON 控制字符清理：扫描=" + @($files).Count + " 文件，修复=" + $changed + "，替换=" + $controls + "，仍无效=" + $invalid)
if ($invalid -gt 0) { exit 1 }
