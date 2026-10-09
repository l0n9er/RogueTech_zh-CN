param(
    [string]$dict = "",
    [string]$mods = "",
    [string]$backupRoot = "",
    [string]$csv = "",
    [string]$fragments = "",
    [string]$repairDict = "",
    [string[]]$extraDict = @(),
    [string]$fileList = "",
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
if ([string]::IsNullOrWhiteSpace($fragments)) { $fragments = Join-Path $PSScriptRoot 'dict-fragments.tsv' }
if ([string]::IsNullOrWhiteSpace($repairDict)) { $repairDict = Join-Path $PSScriptRoot 'dict-repair.tsv' }
$BS = [string][char]92

# 防止半翻译结果再次写入游戏：这类译文通常只把英文连接词替换成中文，
# 其余句子仍保持英文（例如“movement 以 a crawl”）。
$corruptSpacePattern = '[A-Za-z]{2,}\s+(在|或|和|是|以|的|该|至|与|将|拥有|配备|一台)\s+[A-Za-z]{2,}'
$corruptInsidePattern = '[A-Za-z]+(在|或|和|是|以|的|该|至|与|将|拥有|配备|一台)[A-Za-z]+'
$corruptTagPattern = '<\/?[^>]*[\u4e00-\u9fff][^>]*>'
function Test-CorruptDictionaryValue([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    if ($text -match $corruptTagPattern -or $text -match '<col或|</颜色>|</col或>') { return $true }
    $latin = ([regex]::Matches($text, '[A-Za-z]')).Count
    $han = ([regex]::Matches($text, '[\u4e00-\u9fff]')).Count
    $ratio = $han / [Math]::Max(1, ($latin + $han))
    $space = ([regex]::Matches($text, $corruptSpacePattern)).Count
    $inside = ([regex]::Matches($text, $corruptInsidePattern)).Count
    return (($ratio -lt 0.35 -and ($space -ge 1 -or $inside -ge 1)) -or ($space -ge 2) -or ($inside -ge 3))
}

# --- 字典：精确键 + 空白折叠键 两套 ---
$exact = New-Object 'System.Collections.Generic.Dictionary[string,string]'
function Fold([string]$s) { return ([regex]::Replace(($s -replace "`r`n", "`n"), '[\s]+', ' ')).Trim() }
$fold = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$csvExact = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$csvPrefix = New-Object 'System.Collections.Generic.Dictionary[string,string]'
function CsvKey([string]$s) {
    $t = $s.ToLowerInvariant()
    $t = $t.Replace("`r`n", 'newline').Replace("`n", 'newline').Replace("`r", 'newline')
    $t = [regex]::Replace($t, '<[^>]*>', '')
    $t = $t.Replace(',', '^').Replace('.', '*')
    $t = [regex]::Replace($t, '["''`]', '')
    return [regex]::Replace($t, '\s+', '')
}
if ([IO.File]::Exists($csv)) {
    foreach ($line in [IO.File]::ReadLines($csv, [Text.Encoding]::UTF8)) {
        $comma = $line.IndexOf(',')
        if ($comma -lt 1) { continue }
        $key = $line.Substring(0, $comma)
        # CSV 译文里的字面量 \\n 表示换行；先还原为真实换行，再由 Esc
        # 编成 JSON 的单层转义，避免游戏界面显示字面量 "\\n"。
        $value = $line.Substring($comma + 1).Replace($BS + 'n', "`n").Replace($BS + 'r', "`r")
        if (-not $csvExact.ContainsKey($key)) { $csvExact[$key] = $value }
        # 详情末尾可能已被旧版本部分汉化（例如仅 Quirk 行为中文），
        # 但正文开头仍与 CSV 英文键一致。记录稳定前缀用于整段替换。
        if ($key.Length -ge 240) {
            $prefix = $key.Substring(0, 240)
            if (-not $csvPrefix.ContainsKey($prefix)) { $csvPrefix[$prefix] = $value }
            else { $csvPrefix[$prefix] = '' }
        }
    }
}
$metaSuffixes = New-Object 'System.Collections.Generic.HashSet[string]'
# 先收集第三列中的元数据标记；部分旧行把标记直接粘在第二列末尾，
# 只有预扫描整张表后才能同时识别两种格式。
$dictFiles = @($dict)
foreach ($extra in @($extraDict)) {
    if (-not [string]::IsNullOrWhiteSpace($extra) -and [IO.File]::Exists($extra)) { $dictFiles += $extra }
}
$rawLines = foreach ($df in $dictFiles) { [IO.File]::ReadAllLines($df, [Text.Encoding]::UTF8) }
$skippedCorrupt = 0
foreach ($raw in $rawLines) {
    $parts = $raw.Split([char]9)
    if ($parts.Count -ge 3) {
        foreach ($tag in $parts[2..($parts.Count - 1)]) {
            if ($tag -match '^[A-Za-z][A-Za-z0-9_-]*$') { [void]$metaSuffixes.Add($tag) }
        }
    }
}
$metaSuffixesByLength = @($metaSuffixes | Sort-Object Length -Descending)
$dictQuality = New-Object 'System.Collections.Generic.Dictionary[string,int]'
function TranslationQuality([string]$key, [string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return -100000 }
    if (Test-CorruptDictionaryValue $value) { return -100000 }
    $keyHan = ([regex]::Matches($key, '[\u3400-\u9fff]')).Count
    $han = ([regex]::Matches($value, '[\u3400-\u9fff]')).Count
    $latin = ([regex]::Matches($value, '[A-Za-z]')).Count
    # 英文长键的英文原文不是译文；保留原文只会让安装器把英文重新写回游戏。
    if ($keyHan -eq 0 -and $han -eq 0 -and $key.Length -ge 24) { return -90000 }
    $score = $han * 10
    if ($value -ne $key) { $score += 100 }
    if ($han -gt 0 -and $latin -gt 0) { $score += 10 }
    return $score
}
foreach ($l in $rawLines) {
    if ([string]::IsNullOrWhiteSpace($l)) { continue }
    $i = $l.IndexOf("`t"); if ($i -lt 1) { continue }
    $k = ($l.Substring(0, $i)).Replace($BS + 'n', "`n")
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
        foreach ($tag in $metaSuffixesByLength) {
            if ($rest.Length -gt $tag.Length -and $rest.EndsWith($tag, [StringComparison]::Ordinal)) {
                $rest = $rest.Substring(0, $rest.Length - $tag.Length)
                break
            }
        }
    }
    $v = ($rest).Replace($BS + 'n', "`n")
    if (Test-CorruptDictionaryValue $v) { $skippedCorrupt++; continue }
    $q = TranslationQuality $k $v
    if ($q -le -90000) { continue }
    # 同一个英文键可能同时存在“英文原文”“半翻译”“完整中文”多条记录。
    # 不再采用首条记录，按质量分数选择完整译文。
    if (-not $dictQuality.ContainsKey($k) -or $q -gt $dictQuality[$k]) {
        $exact[$k] = $v
        $dictQuality[$k] = $q
    }
    $fk = Fold $k
    if ($fk.Length -gt 12 -and -not $fold.ContainsKey($fk)) { $fold[$fk] = $v }
}
$script:metaPattern = (($metaSuffixes | ForEach-Object { [regex]::Escape($_) }) -join '|')

# 已审校的短术语/名称片段，用于补全整段描述中的残留英文。
$fragmentMap = New-Object 'System.Collections.Generic.Dictionary[string,string]'
if ([IO.File]::Exists($fragments)) {
    foreach ($fl in [IO.File]::ReadAllLines($fragments, [Text.Encoding]::UTF8)) {
        $fp = $fl.Split([char]9)
        if ($fp.Count -ge 2 -and $fp[0].Length -ge 4 -and $fp[1] -match '[\u3400-\u9fff]' -and -not $fragmentMap.ContainsKey($fp[0])) {
            $fragmentMap[$fp[0]] = $fp[1]
        }
    }
}
$fragmentKeys = @($fragmentMap.Keys | Sort-Object Length -Descending)
Write-Host ("fragments: " + $fragmentMap.Count)

# 旧版词典中已有一批“英文正文 + 中文词片段”的结果，游戏文件里可能已经
# 写入这些坏值，无法再通过原始英文键命中。这个覆盖表按坏值直接恢复到
# 历史审校过的完整译文，优先于常规词典查找。
$repairMap = New-Object 'System.Collections.Generic.Dictionary[string,string]'
if ([IO.File]::Exists($repairDict)) {
    foreach ($rl in [IO.File]::ReadAllLines($repairDict, [Text.Encoding]::UTF8)) {
        $rp = $rl.Split([char]9, 2)
        if ($rp.Count -lt 2 -or [string]::IsNullOrWhiteSpace($rp[0])) { continue }
        $rk = $rp[0].Replace($BS + 'n', "`n").Replace($BS + 'r', "`r").Replace($BS + 't', "`t")
        $rv = $rp[1].Replace($BS + 'n', "`n").Replace($BS + 'r', "`r").Replace($BS + 't', "`t")
        if (-not $repairMap.ContainsKey($rk)) { $repairMap[$rk] = $rv }
    }
}
Write-Host ("repair entries: " + $repairMap.Count)

# 修复旧版本留下的“英文正文 + 中文片段”污染。先建立唯一的反向片段表，
# 只有混合文本在完整匹配失败时才用它恢复英文候选键。
$reverseFragmentMap = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$reverseAmbiguous = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($entry in $fragmentMap.GetEnumerator()) {
    $en = [string]$entry.Key
    $zh = [string]$entry.Value
    if ($zh.Length -lt 2 -or $reverseAmbiguous.Contains($zh)) { continue }
    if ($reverseFragmentMap.ContainsKey($zh)) {
        if ($reverseFragmentMap[$zh] -ne $en) {
            [void]$reverseFragmentMap.Remove($zh)
            [void]$reverseAmbiguous.Add($zh)
        }
    } else {
        $reverseFragmentMap[$zh] = $en
    }
}
$reverseFragmentKeys = @($reverseFragmentMap.Keys | Sort-Object Length -Descending)
function ReverseFragments([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s) -or $s -notmatch '[\u4e00-\u9fff]') { return $s }
    foreach ($key in $script:reverseFragmentKeys) {
        $s = $s.Replace($key, $script:reverseFragmentMap[$key])
    }
    return $s
}

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
foreach ($prefix in @($prefixMap.Keys)) {
    $prefixMap[$prefix] = @($prefixMap[$prefix] | Sort-Object { $_.Norm.Length } -Descending)
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

function ApplyFragments([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s) -or $script:fragmentMap.Count -eq 0 -or $s -notmatch '[A-Za-z]') { return $s }
    $saved = New-Object 'System.Collections.Generic.List[string]'
    $protected = [regex]::Replace($s, '<[^>]*>|\[\[[\s\S]*?\]\]|\{[^{}]*\}', [Text.RegularExpressions.MatchEvaluator]{
        param($m) $i = $saved.Count; [void]$saved.Add($m.Value); return ('__FRAG' + $i + '__')
    })
    foreach ($key in $script:fragmentKeys) {
        if ($protected.IndexOf($key, [StringComparison]::Ordinal) -ge 0) {
            $protected = $protected.Replace($key, $script:fragmentMap[$key])
        }
    }
    return [regex]::Replace($protected, '__FRAG(\d+)__', [Text.RegularExpressions.MatchEvaluator]{
        param($m) $saved[[int]$m.Groups[1].Value]
    })
}

$script:exact = $exact; $script:fold = $fold; $script:prefixMap = $prefixMap; $script:csvExact = $csvExact; $script:csvPrefix = $csvPrefix
$script:fragmentMap = $fragmentMap; $script:fragmentKeys = $fragmentKeys; $script:repairMap = $repairMap
$script:reverseFragmentMap = $reverseFragmentMap; $script:reverseFragmentKeys = $reverseFragmentKeys
$stats = @{ files = 0; changed = 0; repl = 0; miss = 0; viaFold = 0; viaPrefix = 0; viaFragment = 0; cleaned = 0 }
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
    if ($script:repairMap.ContainsKey($val)) {
        $rv = $script:repairMap[$val]
        if ($rv -ne $val) {
            $stats.repl++
            return '"' + $fld + '": "' + (Esc $rv) + '"'
        }
    }
    if ($cleaned) {
        $m2 = '"' + $fld + '": "' + (Esc $val) + '"'
        if ($m2 -ne $m.Value) { $stats.repl++ }
        return $m2
    }
    $zh = $null
    $mixedValue = ($val -match '[\u4e00-\u9fff]' -and -not $cleaned)
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    if ($mixedValue) {
        $reversed = ReverseFragments $val
        if ($reversed -ne $val) { [void]$candidates.Add($reversed) }
    }
    [void]$candidates.Add($val)
    foreach ($candidate in $candidates) {
        if ($script:exact.ContainsKey($candidate)) { $zh = $script:exact[$candidate] }
    if ($null -eq $zh) {
            $fk = Fold $candidate
            if ($script:fold.ContainsKey($fk)) { $zh = $script:fold[$fk]; $stats.viaFold++ }
        }
        if ($null -eq $zh -and $script:csvExact.Count -gt 0) {
            $ck = CsvKey $candidate
            if ($script:csvExact.ContainsKey($ck)) { $zh = $script:csvExact[$ck] }
        }
        if ($null -eq $zh -and $script:csvPrefix.Count -gt 0) {
            $ck = CsvKey $candidate
            if ($ck.Length -ge 240) {
                $cp = $ck.Substring(0, 240)
                if ($script:csvPrefix.ContainsKey($cp) -and -not [string]::IsNullOrWhiteSpace($script:csvPrefix[$cp])) { $zh = $script:csvPrefix[$cp] }
            }
        }
        if ($null -eq $zh) {
            $normVal = Fold $candidate
            if ($normVal.Length -ge 24) {
                $prefix = $normVal.Substring(0, 24)
                if ($script:prefixMap.ContainsKey($prefix)) {
                    foreach ($entry in $script:prefixMap[$prefix]) {
                        if (-not $normVal.StartsWith($entry.Norm, [StringComparison]::Ordinal)) { continue }
                        $newVal = $null
                        if ($candidate.StartsWith($entry.Key, [StringComparison]::Ordinal)) {
                            $newVal = $entry.Value + $candidate.Substring($entry.Key.Length)
                        } else {
                            $pattern = FlexiblePrefixPattern $entry.Key
                            $mm = [regex]::Match($candidate, $pattern, [Text.RegularExpressions.RegexOptions]::Singleline)
                            if ($mm.Success) { $newVal = $entry.Value + $candidate.Substring($mm.Length) }
                        }
                        if ($null -ne $newVal -and $newVal -ne $candidate) {
                            $zh = $newVal
                            $stats.viaPrefix++
                            break
                        }
                    }
                }
            }
        }
        if ($null -ne $zh -and -not [string]::IsNullOrWhiteSpace($zh)) { break }
    }
    if ($null -ne $zh -and -not [string]::IsNullOrWhiteSpace($zh)) {
        $m2 = '"' + $fld + '": "' + (Esc $zh) + '"'
        if ($m2 -ne $m.Value) { $stats.repl++ }
        return $m2
    }
    # 完整词条无法命中时，不再对长段落做片段替换。
    # 旧逻辑把英文正文中的零散词替换成中文，产生“英文正文 + 中文片段”
    # 的污染（机甲/武器详情最明显）。短字段仍允许使用片段词典，避免
    # StockRole 等简短显示值失去已有术语翻译。
    $englishWords = ([regex]::Matches($val, '\b[A-Za-z]{3,}\b')).Count
    $allowFragment = ($val.Length -lt 160 -or $englishWords -lt 8)
    if ($allowFragment) {
        $fragmentVal = ApplyFragments $val
        if ($fragmentVal -ne $val) {
            $stats.repl++; $stats.viaFragment++
            return '"' + $fld + '": "' + (Esc $fragmentVal) + '"'
        }
    }
    if ($null -eq $zh -or [string]::IsNullOrWhiteSpace($zh)) {
        if ($mixedValue) { return $m.Value }
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
if (-not [string]::IsNullOrWhiteSpace($fileList) -and [IO.File]::Exists($fileList)) {
    $files = Get-Content -Encoding UTF8 $fileList | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
        $p = $_; $bad = $false
        foreach ($e in $excl) { if ($p -like ('*' + $e + '*')) { $bad = $true; break } }
        if ([IO.Path]::GetFileName($p) -in @('mod.json', 'modstate.json')) { $bad = $true }
        if (-not $bad -and [IO.Path]::GetExtension($p) -eq '.json') { Get-Item -LiteralPath $p }
    }
} else {
    $files = Get-ChildItem $mods -Recurse -File -Filter '*.json' | Where-Object {
        $p = $_.FullName; $bad = $false
        foreach ($e in $excl) { if ($p -like ('*' + $e + '*')) { $bad = $true } }
        if ($_.Name -in @('mod.json', 'modstate.json')) { $bad = $true }
        -not $bad
    }
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
    # 大量 Mod JSON 只有配置/内部数据，没有可处理的详情字段；先做字面量
    # 预筛，避免对这些文件运行包含长前缀匹配的字段正则。
    if ($orig -notmatch '"(Details|YangsThoughts|StockRole)"\s*:') { continue }
    $new = $rx.Replace($orig, $eval)
    if ($new -eq $orig) { continue }
    if (-not $DryRun) {
        # JavaScriptSerializer 在部分 PowerShell 7 环境会因 System.Web 版本冲突
        # 抛出 WebResourceAttribute 加载错误；写入前改用内置 JSON 解析器兜底验证。
        try {
            [void]$ser.DeserializeObject($new)
        } catch {
            try { $null = $new | ConvertFrom-Json -ErrorAction Stop }
            catch { throw }
        }
        $rel = $f.FullName.Substring($mods.Length).TrimStart($BS)
        $bak = Join-Path $backupRoot $rel
        $d = Split-Path $bak -Parent
        if (-not (Test-Path $d)) { [void][IO.Directory]::CreateDirectory($d) }
        if (-not (Test-Path $bak)) { [IO.File]::WriteAllText($bak, $orig, $enc) }
        [IO.File]::WriteAllText($f.FullName, $new, $enc)
        $stats.changed++
    }
}
$line = "mode=" + $(if ($DryRun) { 'dry' } else { 'written' }) + " files=" + $stats.files + " changed=" + $stats.changed + " repl=" + $stats.repl + " cleaned=" + $stats.cleaned + " viaFold=" + $stats.viaFold + " viaPrefix=" + $stats.viaPrefix + " viaFragment=" + $stats.viaFragment + " miss=" + $stats.miss + " skippedCorrupt=" + $skippedCorrupt
Write-Host $line
# 报告写到包内 backup 目录(不污染游戏目录, 便于排查)
$reportDir = Join-Path $packRoot 'backup'
if (-not (Test-Path $reportDir)) { [void][IO.Directory]::CreateDirectory($reportDir) }
[IO.File]::WriteAllText((Join-Path $reportDir 'coverage-summary.txt'), $line, (New-Object Text.UTF8Encoding $false))
if ($missList.Count -gt 0) {
    [IO.File]::WriteAllLines((Join-Path $reportDir 'still-missing-raw.tsv'), $missList, (New-Object Text.UTF8Encoding $true))
    Write-Host ("missing samples -> backup\still-missing-raw.tsv (" + $missList.Count + ")")
}
