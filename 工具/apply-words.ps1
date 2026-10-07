# 直接把 JSON 里 dialogueContent[].words 的英文替换为中文
#
# 背景: 游戏对 words(对话字幕) 不查 CSV, 也不支持 [[...]] 插值查表,
#       而是直接显示 JSON 里的字符串。月光石头的本地化表(CULTURE_ZH_CN)
#       虽有译文, 但对应的源文件从未被改写成 __/Name/__ 占位符,
#       所以译文用不上。这里直接在源文件上替换。
#
# 保护: HTML 标签、{占位符}、\\\\n 转义序列原样保留
param(
    [string]$mods = "",
    [string]$pairs = "",
    [string]$backupRoot = "",
    [string]$fileList = "",
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$BS = [string][char]92
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($mods)) {
    $gr = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gr)) { Write-Host " 找不到游戏目录" -ForegroundColor Yellow; exit 1 }
    $mods = Join-Path $gr 'Mods'
}
if ([string]::IsNullOrWhiteSpace($pairs)) { $pairs = Join-Path $PSScriptRoot 'dict-words.tsv' }
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot 'backup\Mods-words' }
if (-not [IO.File]::Exists($pairs)) { Write-Host (" 找不到对照表: " + $pairs) -ForegroundColor Yellow; exit 1 }

# ---- 读对照表 ----
$map = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$sr = New-Object IO.StreamReader($pairs, [Text.Encoding]::UTF8)
while (-not $sr.EndOfStream) {
    $l = $sr.ReadLine()
    if ([string]::IsNullOrWhiteSpace($l)) { continue }
    $i = $l.IndexOf("`t"); if ($i -lt 1) { continue }
    $k = $l.Substring(0, $i)
    $v = $l.Substring($i + 1)
    if (-not $map.ContainsKey($k)) { $map[$k] = $v }
}
$sr.Close()
Write-Host ("对照表: " + $map.Count + " 条")

# 为同一句对白的换行/多余空格变体建立归一化索引。
# 部分额外模组把同一段 words 写成 `\r`、`\n` 或真实换行，
# 不应因此重复维护多份完全相同的译文。
$normMap = New-Object 'System.Collections.Generic.Dictionary[string,string]'
foreach ($entry in $map.GetEnumerator()) {
    $nk = [regex]::Replace([string]$entry.Key, '\\r|\\n|\r|\n|\s+', ' ').Trim()
    if (-not [string]::IsNullOrWhiteSpace($nk) -and -not $normMap.ContainsKey($nk)) {
        $normMap[$nk] = $entry.Value
    }
}

$enc = New-Object Text.UTF8Encoding $false
$ser = $null
if (-not $DryRun) {
    Add-Type -AssemblyName System.Web.Extensions
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = [int]::MaxValue
}
$stats = @{ files = 0; changed = 0; repl = 0 }
$script:map = $map
$script:normMap = $normMap
$script:stats = $stats

# 匹配 "words": "..."  (处理转义)
$rx = [regex]('"words"\s*:\s*"((?:[^"' + $BS + $BS + ']|' + $BS + $BS + '.)*)"')

function Unesc([string]$s) {
    $t = $s.Replace($BS + '/', '/').Replace($BS + '"', '"').Replace($BS + $BS, $BS)
    return $t
}

$excl = @(
    ($BS + '.modtek' + $BS)
    'ModSaves'
)
$allFiles = if (-not [string]::IsNullOrWhiteSpace($fileList) -and [IO.File]::Exists($fileList)) {
    Get-Content -Encoding UTF8 $fileList | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ FullName = $_; Name = [IO.Path]::GetFileName($_); Extension = [IO.Path]::GetExtension($_) } }
} else { Get-ChildItem $mods -Recurse -File -Filter '*.json' }
$files = $allFiles | Where-Object {
    $p = $_.FullName; $bad = $false
    foreach ($e in $excl) { if ($p -like ('*' + $e + '*')) { $bad = $true } }
    if ($_.Name -in @('mod.json', 'modstate.json')) { $bad = $true }
    -not $bad
}

foreach ($f in $files) {
    $stats.files++
    $orig = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    if ($orig -notmatch '"words"') { continue }
    $new = $rx.Replace($orig, {
        param($m)
        $val = Unesc $m.Groups[1].Value
        if ($val -match '[\u4e00-\u9fff]') { return $m.Value }   # 已译
        $lookup = $val
        if (-not $script:map.ContainsKey($lookup)) {
            # 部分模组在 words 原文末尾多留空格；对白显示不应受此影响。
            $trimmed = $val.Trim()
            if ($script:map.ContainsKey($trimmed)) {
                $lookup = $trimmed
            } else {
                $nk = [regex]::Replace($val, '\\r|\\n|\r|\n|\s+', ' ').Trim()
                if (-not $script:normMap.ContainsKey($nk)) { return $m.Value }
                $zh = $script:normMap[$nk]
                $script:stats.repl++
                $e = $zh.Replace($BS, $BS + $BS).Replace('"', $BS + '"')
                $e = $e.Replace("`n", $BS + 'n').Replace("`r", $BS + 'r').Replace("`t", $BS + 't')
                return '"words": "' + $e + '"'
            }
        }
        $zh = $script:map[$lookup]
        $script:stats.repl++
        # 重新转义
        $e = $zh.Replace($BS, $BS + $BS).Replace('"', $BS + '"')
        $e = $e.Replace("`n", $BS + 'n').Replace("`r", $BS + 'r').Replace("`t", $BS + 't')
        return '"words": "' + $e + '"'
    })
    if ($new -eq $orig) { continue }
    if (-not $DryRun) {
        try { [void]$ser.DeserializeObject($new) } catch { Write-Host ("跳过(JSON 无效): " + $f.Name); continue }
        $rel = $f.FullName.Substring($mods.Length).TrimStart($BS)
        $bak = Join-Path $backupRoot $rel
        $d = Split-Path $bak -Parent
        if (-not [IO.Directory]::Exists($d)) { [void][IO.Directory]::CreateDirectory($d) }
        if (-not [IO.File]::Exists($bak)) { [IO.File]::WriteAllText($bak, $orig, $enc) }
        [IO.File]::WriteAllText($f.FullName, $new, $enc)
    }
    $stats.changed++
}
Write-Host ("files=" + $stats.files + " changed=" + $stats.changed + " repl=" + $stats.repl)
