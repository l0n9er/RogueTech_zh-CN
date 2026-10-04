# 补充游戏代词/功能词键
#
# 背景: 游戏在文本里用 {SUBJ} / {OBJ} / {POSS} 等占位符引用代词, 代词本身也走
# 翻译总表(键就是 he/she/his/her 等)。中文表里除了 "he" 之外都有译文,
# 导致句子里出现 "He acts 起来就像是 he's 我的老板似的" 这种半英半中。
#
# 本脚本补齐缺失的代词键(以及少量紧邻的功能词), 值取自游戏本体的中文习惯用法。
param(
    [string]$csv = "",
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($csv)) { $csv = Join-Path $packRoot 'strings_zh-CN.csv' }
if (-not [IO.File]::Exists($csv)) { Write-Host (" 找不到翻译总表: " + $csv) -ForegroundColor Yellow; exit 1 }

$rows = @(
    # 表里只有小写键(与 dev/de-DE 等官方表一致), 因此只补小写形态。
    ("he" + "`t" + "他")
)

$dict = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($l in [IO.File]::ReadLines($csv, [Text.Encoding]::UTF8)) {
    $p = $l.IndexOf(',')
    if ($p -lt 1) { continue }
    [void]$dict.Add($l.Substring(0, $p))
}

$add = New-Object System.Collections.ArrayList
foreach ($r in $rows) {
    $i = $r.IndexOf("`t")
    if ($i -lt 1) { continue }
    $k = $r.Substring(0, $i); $v = $r.Substring($i + 1)
    if ($dict.Contains($k)) { continue }
    [void]$add.Add($k + ',' + $v)
}

Write-Host ("待补键: " + $add.Count)
foreach ($a in $add) { Write-Host ("  + " + $a) }

if ($add.Count -gt 0 -and -not $DryRun) {
    $sw = New-Object IO.StreamWriter($csv, $true, (New-Object Text.UTF8Encoding $false))
    $sw.NewLine = "`r`n"
    foreach ($a in $add) { $sw.WriteLine($a) }
    $sw.Close()
    Write-Host ("已追加 -> " + $csv)
} elseif ($DryRun) { Write-Host '[DryRun] 未写盘' }
