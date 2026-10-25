# 合并月光石头新版汉化包中的条目
#
# 数据来源: <工具目录>\battletech-trans\resources\data\{BT,RT}\...\strings_zh-CN.csv
# 合并策略: 月光石头 RT 表同键覆盖当前译文, 当前包独有键保留。
#   载具完整描述(含 "#武器:" 段的运行时拼接结果)必须整段作为 key 收录。
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

# 允许直接传 data\RT, 也允许传包含 RT\ 的 resources\data。
$sourceCsv = $source
if ([IO.Directory]::Exists((Join-Path $source 'BattleTech_Data'))) {
    $sourceCsv = Join-Path $source 'BattleTech_Data\StreamingAssets\data\localization\strings_zh-CN.csv'
} else {
    $sourceCsv = Join-Path $source 'RT\BattleTech_Data\StreamingAssets\data\localization\strings_zh-CN.csv'
}
if (-not [IO.File]::Exists($sourceCsv)) {
    Write-Host (" 月光石头 RT 表不存在: " + $sourceCsv) -ForegroundColor Yellow
    exit 1
}

function Read-CsvTable([string]$path) {
    $map = New-Object 'System.Collections.Generic.Dictionary[string,string]'
    $order = New-Object 'System.Collections.Generic.List[string]'
    $duplicates = 0
    foreach ($line in [IO.File]::ReadLines($path, [Text.Encoding]::UTF8)) {
        $comma = $line.IndexOf(',')
        if ($comma -lt 1) { continue }
        $key = $line.Substring(0, $comma)
        if ($key -eq 'KEY') { continue }
        if ($map.ContainsKey($key)) { $duplicates++ }
        else { [void]$order.Add($key) }
        $map[$key] = $line.Substring($comma + 1)
    }
    return [pscustomobject]@{ Map = $map; Order = $order; Duplicates = $duplicates }
}

$currentLines = [IO.File]::ReadAllLines($csv, [Text.Encoding]::UTF8)
$current = Read-CsvTable $csv
$sourceTable = Read-CsvTable $sourceCsv
$sourceMap = $sourceTable.Map
$seen = New-Object 'System.Collections.Generic.HashSet[string]'
$output = New-Object 'System.Collections.Generic.List[string]'
$replaced = 0
$deduplicated = 0

for ($index = 0; $index -lt $currentLines.Count; $index++) {
    $line = $currentLines[$index]
    $comma = $line.IndexOf(',')
    if ($index -eq 0 -or $comma -lt 1) {
        [void]$output.Add($line)
        continue
    }
    $key = $line.Substring(0, $comma)
    if (-not $seen.Add($key)) {
        $deduplicated++
        continue
    }
    if ($sourceMap.ContainsKey($key)) {
        [void]$output.Add($key + ',' + $sourceMap[$key])
        $replaced++
    } else {
        [void]$output.Add($line)
    }
}

$added = 0
foreach ($key in $sourceTable.Order) {
    if ($seen.Add($key)) {
        [void]$output.Add($key + ',' + $sourceMap[$key])
        $added++
    }
}

Write-Host ("当前键: " + $current.Map.Count + "，月光石头键: " + $sourceMap.Count)
Write-Host ("月光石头重复键: " + $sourceTable.Duplicates + "，当前重复键: " + $current.Duplicates)
Write-Host ("同键覆盖: " + $replaced + "，追加月光石头独有: " + $added + "，删除重复行: " + $deduplicated)
if (-not $DryRun) {
    [IO.File]::WriteAllLines($csv, $output, (New-Object Text.UTF8Encoding($false)))
    Write-Host ("已写入 " + $output.Count + " 行 -> " + $csv)
} else { Write-Host '[DryRun] 未写盘' }
