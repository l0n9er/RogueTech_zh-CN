param(
    [string]$dict = "",
    [string]$mods = "",
    [string]$backupRoot = "",
    [string]$csv = "",
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($dict)) { $dict = Join-Path $PSScriptRoot 'dict-all.tsv' }
if ([string]::IsNullOrWhiteSpace($mods)) {
    $gr = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gr)) { Write-Host " 找不到游戏目录, 请用 -mods 指定。" -ForegroundColor Yellow; exit 1 }
    $mods = Join-Path $gr 'Mods'
}
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot 'backup\Mods-defs' }
if ([string]::IsNullOrWhiteSpace($csv)) { $csv = Join-Path $packRoot 'strings_zh-CN.csv' }
$BS = [string][char]92

# --- 字典：精确键 + 空白折叠键 两套 ---
$exact = New-Object 'System.Collections.Generic.Dictionary[string,string]'
function Fold([string]$s) { return ([regex]::Replace(($s -replace "`r`n", "`n"), '[\s]+', ' ')).Trim() }
$fold = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$metaSuffixes = New-Object 'System.Collections.Generic.HashSet[string]'
# 先收集第三列中的元数据标记；部分旧行把标记直接粘在第二列末尾，
# 只有预扫描整张表后才能同时识别两种格式。
$rawLines = [IO.File]::ReadAllLines($dict, [Text.Encoding]::UTF8)
foreach ($raw in $rawLines) {
    $parts = $raw.Split([char]9)
    if ($parts.Count -ge 3) {
        foreach ($tag in $parts[2..($parts.Count - 1)]) {
            if ($tag -match '^[A-Za-z][A-Za-z0-9_-]*$') { [void]$metaSuffixes.Add($tag) }
        }
    }
}
foreach ($l in $rawLines) {
    if ([string]::IsNullOrWhiteSpace($l)) { continue }
    $i = $l.IndexOf("`t"); if ($i -lt 1) { continue }
    $k = ($l.Substring(0, $i) -replace (($BS + $BS) + 'n'), "`r`n")
    # dict-all.tsv 的第三列是来源/语言元数据（如 ZH、Components），
    # 只能把第二列当作译文；过去把整行剩余内容当译文，导致元数据写进游戏。
    $rest = $l.Substring($i + 1)
    $j = $rest.IndexOf("`t")
    if ($j -ge 0) {
        $tail = $rest.Substring($j + 1)
        # 少数历史导出行把正文中的制表符拆成了多列；若第二列仍是英文、
        # 后续列才出现中文，整行不是可安全用于字段替换的键值对，跳过。
        if ($tail -match '[\u4e00-\u9fff]' -and $rest.Substring(0, $j) -notmatch '[\u4e00-\u9fff]') { continue }
        $rest = $rest.Substring(0, $j)
    } else {
        # 兼容“译文ZH”/“译文Components”这类历史粘连行。
        foreach ($tag in ($metaSuffixes | Sort-Object Length -Descending)) {
            if ($rest.Length -gt $tag.Length -and $rest.EndsWith($tag, [StringComparison]::Ordinal)) {
                $rest = $rest.Substring(0, $rest.Length - $tag.Length)
                break
            }
        }
    }
    $v = ($rest -replace (($BS + $BS) + 'n'), "`r`n")
    if (-not $exact.ContainsKey($k)) { $exact[$k] = $v }
    $fk = Fold $k
    if ($fk.Length -gt 12 -and -not $fold.ContainsKey($fk)) { $fold[$fk] = $v }
}
$script:metaPattern = (($metaSuffixes | ForEach-Object { [regex]::Escape($_) }) -join '|')

# 已有词典中的机甲描述常会在末尾追加 Quirk、装甲限制等动态文本。
# 按规范化前缀建索引，在本轮扫描中替换已知译文的开头，避免再次遍历 Mods。
$prefixMap = @{}
$prefixSeen = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($entry in $exact.GetEnumerator()) {
    $ek = [string]$entry.Key
    $ev = [string]$entry.Value
    if ($ek.Length -lt 20 -or $ek -match '[\u3400-\u9fff]' -or $ev -notmatch '[\u3400-\u9fff]') { continue }
    $en = Fold $ek
    if ($en.Length -lt 20 -or $prefixSeen.Contains($en)) { continue }
    [void]$prefixSeen.Add($en)
    $ep = $en.Substring(0, [Math]::Min(24, $en.Length))
    if (-not $prefixMap.ContainsKey($ep)) {
        $prefixMap[$ep] = New-Object 'System.Collections.Generic.List[object]'
    }
    [void]$prefixMap[$ep].Add([pscustomobject]@{ Key = $ek; Norm = $en; Value = $ev })
}
Write-Host ("prefix entries: " + $prefixSeen.Count)

function FlexiblePrefixPattern([string]$s) {
    $sb = New-Object Text.StringBuilder
    $inWs = $false
    foreach ($ch in $s.ToCharArray()) {
        if ([char]::IsWhiteSpace($ch)) {
            if (-not $inWs) { [void]$sb.Append('\s+'); $inWs = $true }
        } else {
            [void]$sb.Append([regex]::Escape([string]$ch)); $inWs = $false
        }
    }
    return '^' + $sb.ToString()
}
Write-Host ("dict exact: " + $exact.Count + "   folded: " + $fold.Count + "   metadata: " + $metaSuffixes.Count)

function Unesc([string]$s) {
    $t = [regex]::Replace($s, ($BS + $BS + 'u([0-9a-fA-F]{4})'), [System.Text.RegularExpressions.MatchEvaluator]{ param($mm) [char][int]("0x" + $mm.Groups[1].Value) })
    $t = $t.Replace($BS + '/', '/').Replace($BS + '"', '"').Replace($BS + $BS, $BS)
    $t = $t.Replace($BS + 'n', "`n").Replace($BS + 'r', "`r").Replace($BS + 't', "`t")
    return $t
}
function Esc([string]$s) {
    $t = $s.Replace($BS, $BS + $BS).Replace('"', $BS + '"')
    return $t.Replace("`n", $BS + 'n').Replace("`r", $BS + 'r').Replace("`t", $BS + 't')
}

$script:exact = $exact; $script:fold = $fold; $script:prefixMap = $prefixMap
$stats = @{ files = 0; changed = 0; repl = 0; miss = 0; viaFold = 0; viaPrefix = 0; cleaned = 0 }
$missList = New-Object 'System.Collections.Generic.List[string]'
$eval = [System.Text.RegularExpressions.MatchEvaluator]{
    param($m)
    $fld = $m.Groups[1].Value
    $val = Unesc $m.Groups[2].Value
    # 清理旧版本安装时已经写入字段的词典元数据污染（例如“。 ZH”）。
    # 只处理词典第三列实际出现过的标记，并要求标记位于文本末尾。
    $cleaned = $false
    if ($script:metaPattern.Length -gt 0 -and $val -match '[\u4e00-\u9fff]') {
        # 历史词典既有“译文 ZH”也有“译文ZH”两种粘连形式；两者都要清理。
        # 元数据只允许出现在字符串末尾，因此不会误伤正文中的同名词。
        $clean = [regex]::Replace($val, '[\s]*(?:' + $script:metaPattern + ')[\s]*$', '')
        if ($clean -ne $val) { $val = $clean; $stats.cleaned++; $cleaned = $true }
    }
    if ([string]::IsNullOrWhiteSpace($val)) { return $m.Value }
    if ($cleaned) {
        $m2 = '"' + $fld + '": "' + (Esc $val) + '"'
        if ($m2 -ne $m.Value) { $stats.repl++ }
        return $m2
    }
    if ($val -match '[\u4e00-\u9fff]' -and -not $cleaned) { return $m.Value }
    $zh = $null
    if ($script:exact.ContainsKey($val)) { $zh = $script:exact[$val] }
    if ($null -eq $zh) {
        $fk = Fold $val
        if ($script:fold.ContainsKey($fk)) { $zh = $script:fold[$fk]; $stats.viaFold++ }
    }
    if ($null -eq $zh) {
        $normVal = Fold $val
        if ($normVal.Length -ge 24) {
            $prefix = $normVal.Substring(0, 24)
            if ($script:prefixMap.ContainsKey($prefix)) {
                foreach ($entry in ($script:prefixMap[$prefix] | Sort-Object { $_.Norm.Length } -Descending)) {
                    if (-not $normVal.StartsWith($entry.Norm, [StringComparison]::Ordinal)) { continue }
                    $newVal = $null
                    if ($val.StartsWith($entry.Key, [StringComparison]::Ordinal)) {
                        $newVal = $entry.Value + $val.Substring($entry.Key.Length)
                    } else {
                        $pattern = FlexiblePrefixPattern $entry.Key
                        $mm = [regex]::Match($val, $pattern, [Text.RegularExpressions.RegexOptions]::Singleline)
                        if ($mm.Success) { $newVal = $entry.Value + $val.Substring($mm.Length) }
                    }
                    if ($null -ne $newVal -and $newVal -ne $val) {
                        $stats.repl++; $stats.viaPrefix++
                        return '"' + $fld + '": "' + (Esc $newVal) + '"'
                    }
                }
            }
        }
    }
    if ($null -eq $zh -or [string]::IsNullOrWhiteSpace($zh)) {
        $stats.miss++
        if ($missList.Count -lt 20000) { $missList.Add($fld + "`t" + ($val -replace "`r?`n", ($BS + 'n'))) }
        return $m.Value
    }
    $m2 = '"' + $fld + '": "' + (Esc $zh) + '"'
    if ($m2 -eq $m.Value) { return $m.Value }
    $stats.repl++
    return $m2
}
$rx = [regex]('"(Details|YangsThoughts|StockRole)"\s*:\s*"((?:[^"' + $BS + $BS + ']|' + $BS + $BS + '.)*)"')
$excl = @(
    ($BS + '.modtek' + $BS)
    'ModSaves'
    'Localization'
    'localization'
)
$files = Get-ChildItem $mods -Recurse -File -Filter '*.json' | Where-Object {
    $p = $_.FullName; $bad = $false
    foreach ($e in $excl) { if ($p -like ('*' + $e + '*')) { $bad = $true } }
    if ($_.Name -in @('mod.json', 'modstate.json')) { $bad = $true }
    -not $bad
}
$enc = New-Object Text.UTF8Encoding $false
$ser = $null
if (-not $DryRun) {
    Add-Type -AssemblyName System.Web.Extensions
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = [int]::MaxValue
}
foreach ($f in $files) {
    $stats.files++
    $orig = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    $new = $rx.Replace($orig, $eval)
    if ($new -eq $orig) { continue }
    if (-not $DryRun) {
        [void]$ser.DeserializeObject($new)
        $rel = $f.FullName.Substring($mods.Length).TrimStart($BS)
        $bak = Join-Path $backupRoot $rel
        $d = Split-Path $bak -Parent
        if (-not (Test-Path $d)) { [void][IO.Directory]::CreateDirectory($d) }
        if (-not (Test-Path $bak)) { [IO.File]::WriteAllText($bak, $orig, $enc) }
        [IO.File]::WriteAllText($f.FullName, $new, $enc)
        $stats.changed++
    }
}
$line = "mode=" + $(if ($DryRun) { 'dry' } else { 'written' }) + " files=" + $stats.files + " changed=" + $stats.changed + " repl=" + $stats.repl + " cleaned=" + $stats.cleaned + " viaFold=" + $stats.viaFold + " viaPrefix=" + $stats.viaPrefix + " miss=" + $stats.miss
Write-Host $line
# 报告写到包内 backup 目录(不污染游戏目录, 便于排查)
$reportDir = Join-Path $packRoot 'backup'
if (-not (Test-Path $reportDir)) { [void][IO.Directory]::CreateDirectory($reportDir) }
[IO.File]::WriteAllText((Join-Path $reportDir 'coverage-summary.txt'), $line, (New-Object Text.UTF8Encoding $false))
if ($missList.Count -gt 0) {
    [IO.File]::WriteAllLines((Join-Path $reportDir 'still-missing-raw.tsv'), $missList, (New-Object Text.UTF8Encoding $true))
    Write-Host ("missing samples -> backup\still-missing-raw.tsv (" + $missList.Count + ")")
}
