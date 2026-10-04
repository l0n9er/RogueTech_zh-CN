# 合并月光石头新版汉化包中的条目
#
# 数据来源: <工具目录>\battletech-trans\resources\data\{BT,RT}\...\strings_zh-CN.csv
# 合并策略: 以本包已有键为准(本包做过术语统一与格式修复), 只补本包没有的键。
#   重点补充: 载具完整描述(含 "#武器:" 段的运行时拼接结果) 2200 条,
#   这类文本由 DLL 在运行时拼好后整体查表, 因此必须整段作为 key 收录。
param(
    [string]$source = "",
    [string]$csv = "",
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($csv)) { $csv = Join-Path $packRoot 'strings_zh-CN.csv' }
if (-not [IO.File]::Exists($csv)) { Write-Host (" 找不到翻译总表: " + $csv) -ForegroundColor Yellow; exit 1 }
if ([string]::IsNullOrWhiteSpace($source)) {
    Write-Host " 请用 -source 指定月光石头工具的资源目录(含 RT\ 与 BT\)" -ForegroundColor Yellow
    exit 1
}

# 收集源表(RT 优先, BT 补充)
$srcFiles = New-Object System.Collections.ArrayList
foreach ($rel in @('RT\BattleTech_Data\StreamingAssets\data\localization\strings_zh-CN.csv',
                   'BT\BattleTech_Data\StreamingAssets\data\localization\strings_zh-CN.csv')) {
    $p = Join-Path $source $rel
    if ([IO.File]::Exists($p)) { [void]$srcFiles.Add($p) }
}
if ($srcFiles.Count -eq 0) { Write-Host (" 源目录中没有找到 strings_zh-CN.csv: " + $source) -ForegroundColor Yellow; exit 1 }

# 现有键
$existing = New-Object 'System.Collections.Generic.HashSet[string]'
$lines = [IO.File]::ReadAllLines($csv, [Text.Encoding]::UTF8)
for ($i = 1; $i -lt $lines.Count; $i++) {
    $p = $lines[$i].IndexOf(',')
    if ($p -lt 1) { continue }
    [void]$existing.Add($lines[$i].Substring(0, $p))
}
Write-Host ("现有键: " + $existing.Count)

# 逐源表取缺失键(后出现的源不覆盖先出现的)
$added = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$srcStat = @{}
foreach ($sf in $srcFiles) {
    $n = 0
    foreach ($l in [IO.File]::ReadLines($sf, [Text.Encoding]::UTF8)) {
        if ([string]::IsNullOrWhiteSpace($l)) { continue }
        $p = $l.IndexOf(',')
        if ($p -lt 1) { continue }
        $k = $l.Substring(0, $p)
        if ($k -eq 'KEY') { continue }
        if ($existing.Contains($k)) { continue }
        if ($added.ContainsKey($k)) { continue }
        $v = $l.Substring($p + 1)
        # 只收含中文的值(避免把英文噪声并进来)
        if ($v -notmatch '[\u4e00-\u9fff]') { continue }
        $added[$k] = $v
        $n++
    }
    $srcStat[(Split-Path (Split-Path (Split-Path (Split-Path $sf -Parent) -Parent) -Parent) -Leaf)] = $n
    Write-Host ("  " + $sf.Substring($source.Length).TrimStart('\') + "  可补 " + $n + " 条")
}

Write-Host ("合计可补: " + $added.Count)
if ($added.Count -eq 0) { Write-Host "无需合并"; exit 0 }

# 统计类型
$wpn = 0; $biome = 0
foreach ($k in $added.Keys) {
    if ($k -like '*#weapons:newline*') { $wpn++ }
    elseif ($k -like '*biomerestrictions*') { $biome++ }
}
Write-Host ("  含 #武器 段的载具描述: " + $wpn)
Write-Host ("  含生态限制的载具描述: " + $biome)

if (-not $DryRun) {
    $sw = New-Object IO.StreamWriter($csv, $true, (New-Object Text.UTF8Encoding $false))
    $sw.NewLine = "`r`n"
    foreach ($k in $added.Keys) { $sw.WriteLine($k + ',' + $added[$k]) }
    $sw.Close()
    Write-Host ("已追加 " + $added.Count + " 条 -> " + $csv)
} else { Write-Host '[DryRun] 未写盘' }
