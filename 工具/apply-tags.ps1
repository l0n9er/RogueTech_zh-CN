# 汉化机师个性/亲和 tag 的显示文本(FriendlyName / Description)
#
# 背景: 机师面板上的个性 tooltip("罪犯"、"幸运"等) 显示的文字来自 MDD 数据库
# 的 Tag 表, 而该表由 ModTek 从两类源构建:
#   · 各模组的 tags\*.json (CustomTag 类型, 启动时 "Updated tag: xxx in MDDB")
#   · 游戏本体 MDD\data\tagdata.sql (玩家不可改的原始表)
# 模组侧这些文件目前是纯英文, 本脚本按翻译总表的值把它们就地改写,
# ModTek 下次启动就会把中文写进数据库。
#
# 键的对应: 直接拿 FriendlyName / Description 的原文按总表归一化规则查表
#   (小写 -> 去标签 -> ,=>^ -> .=>* -> 去引号 -> 去空白)
param(
    [string]$mods = "",
    [string]$csv = "",
    [string]$backupRoot = "",
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($mods)) {
    $gr = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gr)) { Write-Host " 找不到游戏目录" -ForegroundColor Yellow; exit 1 }
    $mods = Join-Path $gr 'Mods'
}
if ([string]::IsNullOrWhiteSpace($csv)) { $csv = Join-Path $packRoot 'strings_zh-CN.csv' }
if (-not [IO.File]::Exists($csv)) { Write-Host (" 找不到翻译总表: " + $csv) -ForegroundColor Yellow; exit 1 }
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot 'backup\Mods-tags' }

function Normalize([string]$s) {
    $t = $s.ToLower()
    $t = $t -replace "`r`n", 'newline' -replace "`n", 'newline'
    $t = [regex]::Replace($t, '<[^>]*>', '')
    $t = $t.Replace(',', '^').Replace('.', '*')
    $t = [regex]::Replace($t, '["''`]', '')
    $t = [regex]::Replace($t, '\s+', '')
    return $t
}

# 读总表
$dict = New-Object 'System.Collections.Generic.Dictionary[string,string]'
foreach ($l in [IO.File]::ReadLines($csv, [Text.Encoding]::UTF8)) {
    $p = $l.IndexOf(',')
    if ($p -lt 1) { continue }
    $k = $l.Substring(0, $p)
    if (-not $dict.ContainsKey($k)) { $dict[$k] = $l.Substring($p + 1) }
}
Write-Host ("总表键: " + $dict.Count)

# 收集 tag 定义文件
$targets = New-Object System.Collections.ArrayList
foreach ($f in (Get-ChildItem $mods -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
    if ($f.FullName -like '*\.modtek\*') { continue }
    if ($f.Name -in @('mod.json', 'modstate.json')) { continue }
    try { $t = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) } catch { continue }
    if ($t -notmatch '"PlayerVisible"') { continue }
    [void]$targets.Add($f.FullName)
}
Write-Host ("tag 定义文件: " + $targets.Count)

$stats = @{ files = 0; fn = 0; desc = 0; miss = 0 }
$missList = New-Object System.Collections.ArrayList
$enc = New-Object Text.UTF8Encoding $false

foreach ($path in $targets) {
    $orig = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    $j = $null
    try { $j = $orig | ConvertFrom-Json } catch { continue }
    if ($null -eq $j.PlayerVisible -or $null -eq $j.Name) { continue }
    $new = $orig
    $changed = $false

    foreach ($field in @('FriendlyName', 'Description')) {
        $val = $j.$field
        if ([string]::IsNullOrWhiteSpace($val)) { continue }
        if ($val -match '[\u4e00-\u9fff]') { continue }   # 已是中文
        $n = Normalize $val
        $zh = $null
        if ($dict.ContainsKey($n)) { $zh = $dict[$n] }
        if ($null -eq $zh) {
            $stats.miss++
            if ($missList.Count -lt 200) { [void]$missList.Add($j.Name + "`t" + $field + "`t" + $val) }
            continue
        }
        if ($zh -eq $val) { continue }
        # 替换 JSON 值(字段名唯一, 直接字符串替换; 值里可能有转义引号, 用简单查找)
        $pattern = '"' + $field + '"\s*:\s*"' + [regex]::Escape($val) + '"'
        $rx = New-Object System.Text.RegularExpressions.Regex $pattern
        if ($rx.IsMatch($new)) {
            $new = $rx.Replace($new, ('"' + $field + '": "' + $zh.Replace('\', '\\').Replace('"', '\"') + '"'), 1)
            $changed = $true
            if ($field -eq 'FriendlyName') { $stats.fn++ } else { $stats.desc++ }
        }
    }

    if ($changed) {
        $stats.files++
        if (-not $DryRun) {
            $rel = $path.Substring($mods.Length).TrimStart('\')
            $bak = Join-Path $backupRoot $rel
            $d = Split-Path $bak -Parent
            if (-not (Test-Path $d)) { [void][IO.Directory]::CreateDirectory($d) }
            if (-not (Test-Path $bak)) { [IO.File]::WriteAllText($bak, $orig, $enc) }
            [IO.File]::WriteAllText($path, $new, $enc)
        }
    }
}

Write-Host ("=== tag 文本汉化 ===")
Write-Host ("  文件 " + $stats.files + " 个; FriendlyName " + $stats.fn + " 处; Description " + $stats.desc + " 处; 未命中 " + $stats.miss)
if ($DryRun) { Write-Host '  [DryRun] 未写盘' }
if ($missList.Count -gt 0) {
    $rep = Join-Path $packRoot 'backup'
    if (-not (Test-Path $rep)) { [void][IO.Directory]::CreateDirectory($rep) }
    [IO.File]::WriteAllLines((Join-Path $rep 'tags-missing.tsv'), @($missList), (New-Object Text.UTF8Encoding $true))
    Write-Host ("  未命中清单 -> backup\tags-missing.tsv (" + $missList.Count + ")")
}
