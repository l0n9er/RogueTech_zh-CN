param(
    [string]$mods = "",
    [string]$pairs = "",
    [string]$backupRoot = "",
    [string]$fileList = "",
    [string]$report = "",
    [string]$csv = "",
    [string]$fallbackDict = "",
    [switch]$DryRun
)

# 事件/闪点正文不经过 strings_zh-CN.csv，必须直接改写 JSON。
# 本工具只作用于事件、闪点和 RogueTechCore 合同文件的显示字段；合同 JSON 不匹配 Name。
# 本地化表中的长文本经过 JSON 解码后再匹配，能够正确处理 \r\n、引号和
# 插值占位符；写回时重新使用 JSON 序列化，避免生成非法 JSON 或字面化换行。
$ErrorActionPreference = 'Stop'
$BS = [string][char]92
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($mods)) {
    $gr = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gr)) { throw "找不到游戏目录" }
    $mods = Join-Path $gr 'Mods'
}
if ([string]::IsNullOrWhiteSpace($backupRoot)) {
    $backupRoot = Join-Path $packRoot 'backup\Mods-events-auto'
}
if ([string]::IsNullOrWhiteSpace($report)) {
    $report = Join-Path $backupRoot 'event-residuals.tsv'
}
if ([string]::IsNullOrWhiteSpace($csv)) {
    $csv = Join-Path $packRoot 'strings_zh-CN.csv'
}

Add-Type -AssemblyName System.Web.Extensions
$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$ser.MaxJsonLength = [int]::MaxValue
$enc = New-Object Text.UTF8Encoding $false

$explicitPairs = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$eventPairs = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$fallbackPairs = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$eventNormPairs = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$fallbackNormPairs = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$csvPairs = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$csvLooseCandidates = New-Object 'System.Collections.Generic.Dictionary[string,object]'

function NormalizeText([string]$s) {
    if ($null -eq $s) { return '' }
    $t = $s.Replace("`r`n", "`n").Replace("`r", "`n")
    # 兼容词典/源文件中把换行写成字面 \r\n 的情况。
    $t = $t.Replace('\r\n', "`n").Replace('\n', "`n").Replace('\r', "`n")
    return [regex]::Replace($t, '\s+', ' ').Trim()
}

function CsvKey([string]$s) {
    if ($null -eq $s) { return '' }
    $t = $s.ToLowerInvariant()
    $t = $t.Replace("`r`n", 'newline').Replace("`n", 'newline').Replace("`r", 'newline')
    # 某些运行时 JSON 曾把本应为换行的转义又多转义了一次。
    $t = $t.Replace('\r\n', 'newline').Replace('\n', 'newline').Replace('\r', 'newline')
    $t = $t.Replace(']]', '')
    $t = [regex]::Replace($t, '<[^>]*>', '')
    $t = $t.Replace(',', '^').Replace('.', '*')
    $t = [regex]::Replace($t, '["''`]', '')
    return [regex]::Replace($t, '\s+', '')
}

function CsvLooseKey([string]$s) {
    return [regex]::Replace((CsvKey $s), '[^a-z0-9\u3400-\u9fff]', '')
}

function TranslationScore([string]$s) {
    $plain = [regex]::Replace($s, '<[^>]*>|\[\[[\s\S]*?\]\]|\{[^{}]*\}', '')
    $han = [regex]::Matches($plain, '[\u3400-\u9fff]').Count
    $latin = [regex]::Matches($plain, '[A-Za-z]').Count
    return ($han - (2 * $latin))
}

function DecodeControlEscapes([string]$value) {
    if ($null -eq $value) { return $value }
    $slash = [regex]::Escape($BS)
    $pattern = $slash + '+r' + $slash + '+n|' + $slash + '+[nrt]'
    return [regex]::Replace($value, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $last = [char]$m.Value[$m.Value.Length - 1]
        if ($last -eq 'n') {
            if ($m.Value.EndsWith('rn', [StringComparison]::Ordinal)) { return ([string][char]13 + [char]10) }
            return [string][char]10
        }
        if ($last -eq 'r') { return [string][char]13 }
        if ($last -eq 't') { return [string][char]9 }
        return $m.Value
    })
}

function ConvertCsvJsonValue([string]$value) {
    if ($null -eq $value) { return $value }
    # CSV 的富文本别名使用 0x1F，写回 JSON 必须恢复为逗号。
    $decoded = $value.Replace([string][char]0x1F, ',')
    return DecodeControlEscapes $decoded
}

function NormalizeEventTranslation([string]$value) {
    if ($null -eq $value) { return $value }
    $rules = @(
        @{ Pattern='(?i)\bEasy(?=\s*</color\s*>)'; Replacement='简单' },
        @{ Pattern='(?i)\bMedium(?=\s*</color\s*>)'; Replacement='中等' },
        @{ Pattern='(?i)\bHard(?=\s*</color\s*>)'; Replacement='困难' },
        @{ Pattern='(?i)\bThunderbolt(?:\s+Missiles?|\s+导弹)\b'; Replacement='雷电导弹' },
        @{ Pattern='(?i)注意\s*(?:Andrew|安德鲁)'; Replacement='安德鲁请注意' },
        @{ Pattern='(?i)\bCommercial JumpShip Travel Authority\b'; Replacement='商业跳跃飞船运输管理局（CJSTA）' },
        @{ Pattern='(?i)\bMercenary Review Board\b'; Replacement='雇佣兵评审委员会（MRB）' },
        @{ Pattern='(?i)\bGhost Beer\b'; Replacement='幽灵熊啤酒' },
        @{ Pattern='(?i)\bGhost Bear Watch\b'; Replacement='幽灵熊守望组织' },
        @{ Pattern='(?i)\bGhost Bear MechWarriors?\b'; Replacement='幽灵熊氏族机甲战士' },
        @{ Pattern='(?i)\bClan Ghost Bear\b'; Replacement='幽灵熊氏族' },
        @{ Pattern='(?i)\bGhost Bear Clan\b'; Replacement='幽灵熊氏族' },
        @{ Pattern='(?i)\bGhost Bear\b'; Replacement='幽灵熊氏族' },
        @{ Pattern='(?i)\bInner Sphere\b'; Replacement='内星区' },
        @{ Pattern='(?i)\bClan Space\b'; Replacement='氏族空间' },
        @{ Pattern='(?i)\bAlpha Group\b'; Replacement='阿尔法组' },
        @{ Pattern='(?i)\bBeta Group\b'; Replacement='贝塔组' },
        @{ Pattern='(?i)\bBlack Market\b'; Replacement='黑市' },
        @{ Pattern='(?i)\bDr\.?\s+Murad\b'; Replacement='穆拉德博士' },
        @{ Pattern='(?i)\bKF Drive\b'; Replacement='KF 引擎' },
        @{ Pattern='(?i)\bK-F Drive\b'; Replacement='K-F 引擎' },
        @{ Pattern='(?i)\bCommercial JumpShips?\b'; Replacement='商业跳跃飞船' },
        @{ Pattern='(?i)\bJumpShips?\b'; Replacement='跳跃飞船' },
        @{ Pattern='(?i)\bMechWarriors?\b'; Replacement='机甲战士' },
        @{ Pattern='(?i)\bBattle ?Mechs?\b'; Replacement='战斗机甲' },
        @{ Pattern='(?i)\bBattle Armou?r\b'; Replacement='战斗装甲' },
        @{ Pattern='(?i)\bC-Bills?\b'; Replacement='C币' },
        @{ Pattern='(?i)\bquiaff\b'; Replacement='对吧' },
        @{ Pattern='(?i)\bQuineg\b'; Replacement='不' },
        @{ Pattern='(?i)\bAff，来看看'; Replacement='好，来看看' },
        @{ Pattern='(?i)\bAff，'; Replacement='是，' },
        @{ Pattern='(?i)\bAff\b'; Replacement='是' },
        @{ Pattern='(?i)\bNeg，'; Replacement='不，' },
        @{ Pattern='(?i)\bNeg\b'; Replacement='不' },
        @{ Pattern='(?i)\bBoss\b'; Replacement='老板' },
        @{ Pattern='(?i)\bMechBay\b'; Replacement='机甲舱' },
        @{ Pattern='(?i)\bMercNet\b'; Replacement='雇佣网' },
        @{ Pattern='(?i)\bArgo\b'; Replacement='阿尔戈号' },
        @{ Pattern='(?i)\bPeriphery\b'; Replacement='外缘星域' },
        @{ Pattern='(?i)\b1000''s\b'; Replacement='上千' },
        @{ Pattern='(?i)(?<![（(])\bMRBC\b(?![）)])'; Replacement='雇佣兵评审与担保委员会（MRBC）' },
        @{ Pattern='(?i)(?<![（(])\bCJSTA\b(?![）)])'; Replacement='商业跳跃飞船运输管理局（CJSTA）' },
        @{ Pattern='(?i)(?<![（(])\bMRB\b(?![）)])'; Replacement='雇佣兵评审委员会（MRB）' }
    )
    foreach ($rule in $rules) {
        $value = [regex]::Replace($value, $rule.Pattern, $rule.Replacement)
    }
    return $value
}

function AddPair([string]$en, [string]$zh, [bool]$isEventKey) {
    if ([string]::IsNullOrWhiteSpace($en) -or [string]::IsNullOrWhiteSpace($zh)) { return }
    if ($en -eq $zh -or $zh -notmatch '[\u4e00-\u9fff]') { return }
    $zh = NormalizeEventTranslation $zh
    # 已确认的旧坏条目不能重新进入自动覆盖通道。
    if ($zh -match 'active 的道路再次交汇') { return }
    $target = if ($isEventKey) { $eventPairs } else { $fallbackPairs }
    $normTarget = if ($isEventKey) { $eventNormPairs } else { $fallbackNormPairs }
    if (-not $target.ContainsKey($en)) { $target[$en] = $zh }
    $nk = NormalizeText $en
    if ($nk -and -not $normTarget.ContainsKey($nk)) { $normTarget[$nk] = $zh }
}

function DecodeDictionaryValue([string]$raw) {
    if ($raw -notmatch '\\[nrt"\\]') { return $raw }
    try { $decoded = [string]$ser.DeserializeObject('"' + $raw + '"') }
    catch { $decoded = $raw.Replace('\\"', '"').Replace('\\n', [string][char]10).Replace('\\r', [string][char]13).Replace('\\t', [string][char]9) }
    return DecodeControlEscapes $decoded
}

# 先读人工审核过的短词/事件词典，让它优先于自动收集的本地化条目。
if (-not [string]::IsNullOrWhiteSpace($pairs)) {
    foreach ($pairFile in ($pairs -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        if (-not [IO.File]::Exists($pairFile)) { throw ("找不到事件词典: " + $pairFile) }
        foreach ($line in [IO.File]::ReadLines($pairFile, [Text.Encoding]::UTF8)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $i = $line.IndexOf("`t")
            if ($i -lt 1) { continue }
            $en = DecodeDictionaryValue ($line.Substring(0, $i))
            $zh = DecodeDictionaryValue ($line.Substring($i + 1))
            $zh = NormalizeEventTranslation $zh
            if (-not $explicitPairs.ContainsKey($en)) { $explicitPairs[$en] = $zh }
        }
    }
}

function Walk-Loc($node) {
    if ($node -is [System.Collections.IDictionary]) {
        $name = [string]$node['Name']
        $loc = $node['Localization']
        if ($name -and $loc -is [System.Collections.IDictionary]) {
            $en = [string]$loc['CULTURE_EN_US']
            $zh = [string]$loc['CULTURE_ZH_CN']
            $isEventKey = $name -match '(?i)(event|flashpoint|backgroundevent|eventualit)'
            AddPair $en $zh $isEventKey
        }
        foreach ($k in @($node.Keys)) { Walk-Loc $node[$k] }
    } elseif ($node -is [System.Collections.IEnumerable] -and -not ($node -is [string])) {
        foreach ($v in $node) { Walk-Loc $v }
    }
}

$locCount = 0
$locFiles = Get-ChildItem $mods -Recurse -File -Filter 'Localization.json' -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -match '(?i)[\\/]Localization[\\/]ZH$' }
foreach ($lf in $locFiles) {
    try {
        $obj = $ser.DeserializeObject([IO.File]::ReadAllText($lf.FullName, [Text.Encoding]::UTF8))
        Walk-Loc $obj
        $locCount++
    } catch {
        Write-Host ("跳过本地化表: " + $lf.FullName) -ForegroundColor Yellow
    }
}

# 事件专用翻译优先，通用本地化条目作为兜底；人工词典始终最高优先级。
$allPairs = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$allNormPairs = New-Object 'System.Collections.Generic.Dictionary[string,string]'
foreach ($entry in $fallbackPairs.GetEnumerator()) {
    if (-not $allPairs.ContainsKey($entry.Key)) { $allPairs[$entry.Key] = $entry.Value }
}
foreach ($entry in $eventPairs.GetEnumerator()) { $allPairs[$entry.Key] = $entry.Value }
foreach ($entry in $fallbackNormPairs.GetEnumerator()) {
    if (-not $allNormPairs.ContainsKey($entry.Key)) { $allNormPairs[$entry.Key] = $entry.Value }
}
foreach ($entry in $eventNormPairs.GetEnumerator()) { $allNormPairs[$entry.Key] = $entry.Value }
foreach ($entry in $explicitPairs.GetEnumerator()) {
    $allPairs[$entry.Key] = $entry.Value
    $nk = NormalizeText $entry.Key
    if ($nk) { $allNormPairs[$nk] = $entry.Value }
}

$targetFields = @(
    'Name', 'Details', 'words', 'title', 'description', 'shortDescription',
    'longDescription', 'ShortDesc', 'OptionName', 'OptionDescription',
    'ResultName', 'ResultDescription', 'FlashpointShortDescription',
    'FlashpointLongDescription', 'Text', 'text', 'Caption', 'label'
)
$fieldAlt = ($targetFields | ForEach-Object { [regex]::Escape($_) }) -join '|'
$rxPattern = '"(' + $fieldAlt + ')"\s*:\s*"((?:[^"' + $BS + $BS + ']|' + $BS + $BS + '.)*)"'
$rx = [System.Text.RegularExpressions.Regex]::new(
    $rxPattern,
    [System.Text.RegularExpressions.RegexOptions]::None
)
$contractFields = @($targetFields | Where-Object { $_ -ne 'Name' })
$contractFieldAlt = ($contractFields | ForEach-Object { [regex]::Escape($_) }) -join '|'
$contractRxPattern = '"(' + $contractFieldAlt + ')"\s*:\s*"((?:[^"' + $BS + $BS + ']|' + $BS + $BS + '.)*)"'
$contractRx = [System.Text.RegularExpressions.Regex]::new(
    $contractRxPattern,
    [System.Text.RegularExpressions.RegexOptions]::None
)

function DecodeJsonString([string]$raw) {
    try {
        $decoded = [string]$ser.DeserializeObject('"' + $raw + '"')
        # 兼容历史版本写出的 "\\n"，避免游戏显示字面 \n。
        return DecodeControlEscapes $decoded
    }
    catch { return $raw.Replace($BS + '"', '"').Replace($BS + $BS, $BS) }
}

if ([IO.File]::Exists($csv)) {
    foreach ($line in [IO.File]::ReadLines($csv, [Text.Encoding]::UTF8)) {
        $comma = $line.IndexOf(',')
        if ($comma -lt 1) { continue }
        $key = $line.Substring(0, $comma)
        $value = ConvertCsvJsonValue ($line.Substring($comma + 1))
        if ($key -and $value -match '[\u4e00-\u9fff]' -and -not $csvPairs.ContainsKey($key)) {
            $csvPairs[$key] = $value
        }
        if ($key -and $value -match '[\u4e00-\u9fff]') {
            $looseKey = CsvLooseKey $key
            if ($looseKey) {
        if (-not $csvLooseCandidates.ContainsKey($looseKey)) {
            $csvLooseCandidates[$looseKey] = [pscustomobject]@{
                Value = $value
                BestScore = $null
                SecondScore = $null
            }
            continue
                }
        $candidate = $csvLooseCandidates[$looseKey]
        if ($candidate.Value -eq $value) { continue }
        $score = TranslationScore $value
        if ($null -eq $candidate.BestScore) {
            $candidate.BestScore = TranslationScore $candidate.Value
            $candidate.SecondScore = [int]::MinValue
        }
        if ($score -gt $candidate.BestScore) {
            $candidate.SecondScore = $candidate.BestScore
            $candidate.BestScore = $score
            $candidate.Value = $value
        } elseif ($score -gt $candidate.SecondScore) {
            $candidate.SecondScore = $score
        }
            }
        }
    }
}
$csvLoosePairs = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$csvLooseAmbiguous = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($entry in $csvLooseCandidates.GetEnumerator()) {
    $candidate = $entry.Value
    if ($null -eq $candidate.SecondScore) {
        $csvLoosePairs[$entry.Key] = $candidate.Value
        continue
    }
    if ($candidate.BestScore -ge ($candidate.SecondScore + 2)) {
        $csvLoosePairs[$entry.Key] = $candidate.Value
    } else {
        [void]$csvLooseAmbiguous.Add($entry.Key)
    }
}

# dict-all.tsv 是旧版总词典，作为事件本地化表缺项时的兜底来源。
# 这里只取前两列，避免把来源元数据写进 JSON。
if (-not [string]::IsNullOrWhiteSpace($fallbackDict)) {
    foreach ($fallbackFile in ($fallbackDict -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        if (-not [IO.File]::Exists($fallbackFile)) { throw ("找不到事件兜底词典: " + $fallbackFile) }
        foreach ($line in [IO.File]::ReadLines($fallbackFile, [Text.Encoding]::UTF8)) {
            $tab = $line.IndexOf("`t")
            if ($tab -lt 1) { continue }
            $en = $line.Substring(0, $tab)
            $rest = $line.Substring($tab + 1)
            $tail = $rest.IndexOf("`t")
            if ($tail -ge 0) { $rest = $rest.Substring(0, $tail) }
            AddPair (DecodeDictionaryValue $en) (DecodeDictionaryValue $rest) $false
        }
    }
}
function EncodeJsonString([string]$value) { return [string]$ser.Serialize([string]$value) }
function IsEventFile($file) {
    $rel = $file.FullName.Substring($mods.Length).TrimStart([char]92, [char]47)
    if ($rel -match '(?i)(^|[\\/])\.modtek([\\/]|$)' -or
        $rel -match '(?i)(^|[\\/])ModSaves([\\/]|$)' -or
        $rel -match '(?i)(^|[\\/])Localization([\\/]|$)' -or
        [IO.Path]::GetFileName($file.FullName) -ieq 'Localization.json') { return $false }
    if ($rel -match '(?i)(^|[\\/])RogueTechCore[\\/]Contracts[\\/]') { return $true }
    if ($rel -match '(?i)(^|[\\/])(?:events?|eventualities|backgroundevents?|flashpoints?|flashpoint|forcedevents?)(?:[\\/]|$)') { return $true }
    return ([IO.Path]::GetFileName($file.FullName) -match '(?i)^(?:event|forceevent|backgroundevent|flashpoint|fp_).+\.json$')
}

$stats = @{ files = 0; changed = 0; repl = 0; candidates = 0; mixed = 0; invalid = 0 }
$residuals = New-Object System.Collections.Generic.List[string]
$allFiles = if (-not [string]::IsNullOrWhiteSpace($fileList) -and [IO.File]::Exists($fileList)) {
    Get-Content -Encoding UTF8 $fileList | Where-Object { $_ } | ForEach-Object {
        [pscustomobject]@{ FullName = $_; Name = [IO.Path]::GetFileName($_) }
    }
} else {
    Get-ChildItem $mods -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue
}
$files = $allFiles | Where-Object { IsEventFile $_ }

foreach ($f in $files) {
    $stats.files++
    $orig = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    $rel = $f.FullName.Substring($mods.Length).TrimStart([char]92, [char]47)
    $activeRx = if ($rel -match '(?i)(^|[\\/])RogueTechCore[\\/]Contracts[\\/]') { $contractRx } else { $rx }
    $matches = $activeRx.Matches($orig)
    if ($matches.Count -eq 0) { continue }
    $builder = New-Object System.Text.StringBuilder($orig.Length)
    $lastIndex = 0
    foreach ($m in $matches) {
        [void]$builder.Append($orig.Substring($lastIndex, $m.Index - $lastIndex))
        $raw = $m.Groups[2].Value
        $value = DecodeJsonString $raw
        $isInternalObjectiveId = $value -match '^(?:Timer)?Objective_[A-Za-z0-9_]+$'
        $isHiddenObjectiveTitle = ($m.Groups[1].Value -ieq 'title' -and
            ($value -match '(?i)^\s*(?:\(HIDDEN\)|HIDDEN(?:[_\s]|$))' -or
             $value -match '(?i)HiddenFlag$'))
        $isInternalName = ($m.Groups[1].Value -ieq 'Name' -and
            ($value -match '(?i)HiddenFlag$' -or
             $value -match '(?i)Internal$' -or
             $value -match '^\{[A-Za-z0-9_.]+\}$' -or
             $rel -match '(?i)(^|[\\/])milestoneSets([\\/]|$)' -or
             [IO.Path]::GetFileName($f.FullName) -ieq 'mod.json' -or
             [IO.Path]::GetFileName($f.FullName) -ieq 'AmmoCategory.json'))
        if ($isInternalObjectiveId -or $isHiddenObjectiveTitle -or $isInternalName) {
            [void]$builder.Append($m.Value)
            $lastIndex = $m.Index + $m.Length
            continue
        }
        $zh = $null
        $fromCsv = $false
        if ($explicitPairs.ContainsKey($value)) { $zh = $explicitPairs[$value] }
        elseif ($allPairs.ContainsKey($value)) { $zh = $allPairs[$value] }
        else {
            $nk = NormalizeText $value
            if ($nk -and $allNormPairs.ContainsKey($nk)) { $zh = $allNormPairs[$nk] }
            if ($null -eq $zh -and $csvPairs.Count -gt 0) {
                $ck = CsvKey $value
                if ($ck -and $csvPairs.ContainsKey($ck)) {
                    $zh = $csvPairs[$ck]
                    $fromCsv = $true
                }
            }
            if ($null -eq $zh) {
                $looseKey = CsvLooseKey $value
                if ($looseKey -and $csvLoosePairs.ContainsKey($looseKey) -and
                    -not $csvLooseAmbiguous.Contains($looseKey)) {
                    $zh = $csvLoosePairs[$looseKey]
                    $fromCsv = $true
                }
            }
        }
        if ($fromCsv) { $zh = ConvertCsvJsonValue $zh }
        if ($null -ne $zh) { $zh = NormalizeEventTranslation $zh }
        if ($null -ne $zh -and $zh -ne $value) {
            $stats.repl++
            [void]$builder.Append(('"' + $m.Groups[1].Value + '": ' + (EncodeJsonString $zh)))
            $lastIndex = $m.Index + $m.Length
            continue
        }
        $normalizedValue = NormalizeEventTranslation $value
        if ($normalizedValue -ne $value) {
            $stats.repl++
            [void]$builder.Append(('"' + $m.Groups[1].Value + '": ' + (EncodeJsonString $normalizedValue)))
            $lastIndex = $m.Index + $m.Length
            continue
        }
        if ($value -match '[A-Za-z]{3,}' -and
            $value -notmatch '(?i)HIDDEN TIMER|HIDDEN KILL OBJECTIVE|NO NEED TO EDIT|USELESS OBJECTIVE') {
            $hasChinese = ($value -match '[\u4e00-\u9fff]')
            if ($hasChinese) { $stats.mixed++ } else { $stats.candidates++ }
            $kind = if ($hasChinese) { 'Mixed' } else { 'English' }
            [void]$residuals.Add(($f.FullName + "`t" + $m.Groups[1].Value + "`t" + $kind + "`t" + (NormalizeText $value)))
        }
        [void]$builder.Append($m.Value)
        $lastIndex = $m.Index + $m.Length
    }
    [void]$builder.Append($orig.Substring($lastIndex))
    $new = $builder.ToString()
    if ($new -eq $orig) { continue }
    try { [void]$ser.DeserializeObject($new) }
    catch {
        $replacementError = $_.Exception.Message
        try { [void]$ser.DeserializeObject($orig) }
        catch {
            $stats.invalid++
            [void]$residuals.Add(($f.FullName + [char]9 + '-' + [char]9 + 'InvalidSourceJSON' + [char]9 + (NormalizeText $replacementError)))
            Write-Host ("跳过原始 JSON 无效文件: " + $f.FullName) -ForegroundColor Yellow
            continue
        }
        throw ("汉化后 JSON 无效: " + $f.FullName + " :: " + $replacementError)
    }
    $stats.changed++
    if (-not $DryRun) {
        $rel = $f.FullName.Substring($mods.Length).TrimStart([char]92, [char]47)
        $bak = Join-Path $backupRoot $rel
        $d = Split-Path $bak -Parent
        if (-not [IO.Directory]::Exists($d)) { [void][IO.Directory]::CreateDirectory($d) }
        if (-not [IO.File]::Exists($bak)) { [IO.File]::WriteAllText($bak, $orig, $enc) }
        [IO.File]::WriteAllText($f.FullName, $new, $enc)
    }
}

if (-not [string]::IsNullOrWhiteSpace($report)) {
    $reportParent = Split-Path $report -Parent
    if (-not [IO.Directory]::Exists($reportParent)) { [void][IO.Directory]::CreateDirectory($reportParent) }
    $reportLines = @("File`tField`tKind`tCandidate") + @($residuals | Sort-Object -Unique)
    [IO.File]::WriteAllLines($report, [string[]]$reportLines, $enc)
}

Write-Host ("Localization 表=" + $locCount +
            " 事件译文=" + $allPairs.Count +
            " 文件=" + $stats.files +
            " 修改=" + $stats.changed +
            " 替换=" + $stats.repl +
            " 纯英文候选=" + $stats.candidates +
            " 混合文本候选=" + $stats.mixed +
            " 原始 JSON 无效跳过=" + $stats.invalid)
if (-not $DryRun -and $residuals.Count -gt 0) {
    Write-Host ("残留候选报告: " + $report) -ForegroundColor Yellow
}
