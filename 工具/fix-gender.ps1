# 修复译文里残留英文的 {X.Gender?...} 条件分支
#
# 背景: 游戏用 {角色.Gender?分支:值|...} 在文本里做性别变体。中文不区分动词
# 变位(he acts / they act 都是"他装"), 所以两个分支应填同一个中文动词。
# 部分译文只翻了句子、把表达式原样留着英文分支, 于是出现
# "He acts 起来就像 he's 我的老板似的" 这种半英半中。
#
# 本脚本按 (英文分支值 -> 中文) 的映射, 就地改写 Localization.json 里的
# CULTURE_ZH_CN 字段, 保留表达式结构不变。
param(
    [string]$mods = "",
    [string]$repo = "",
    [string]$baseDataRoot = "",
    [string]$csv = "",
    [string]$backupRoot = "",
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($repo)) { $repo = $packRoot }
if ([string]::IsNullOrWhiteSpace($mods)) { $mods = Join-Path $repo 'Mods' }
if ([string]::IsNullOrWhiteSpace($csv)) { $csv = Join-Path $packRoot 'strings_zh-CN.csv' }
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot 'backup\GenderBranches' }
if (-not (Test-Path $mods)) { Write-Host (" 找不到 Mods: " + $mods) -ForegroundColor Yellow; exit 1 }

# 英文分支值 -> 中文。动词两分支同值(中文无变位); 缩写按中文习惯给对应词。
# 注意: PowerShell 哈希键不区分大小写, 所以用数组存放(保持大小写敏感)。
$pairs = @(
    # --- 动词(中文不变位, 两分支一致) ---
    @('recover', '康复'), @('recovers', '康复'),
    @('rise', '起身'), @('rises', '起身'),
    @('sit', '坐下'), @('sits', '坐下'),
    @('stalk', '大步走开'), @('stalks', '大步走开'),
    @('start', '开始'), @('starts', '开始'),
    @('think', '想'), @('thinks', '想'),
    @('are', '是'), @('is', '是'),
    @('were', '是'), @('was', '是'),
    @('disembark', '下船'), @('disembarks', '下船'),
    @('fight', '战斗'), @('fights', '战斗'),
    @('gesture', '打手势'), @('gestures', '打手势'),
    @('get', '变得'), @('gets', '变得'),
    @('hand', '递过'), @('hands', '递过'),
    @('have', '有'), @('has', '有'),
    @('hesitate', '犹豫'), @('hesitates', '犹豫'),
    @('look', '看着'), @('looks', '看着'),
    @('pause', '停顿'), @('pauses', '停顿'),
    # --- 否定式 ---
    @("weren't", '不是'), @("wasn't", '不是'),
    # --- 缩写(接在主语后) ---
    @("'s", '是'), @("'re", '是'),
    @("he's", '他是'), @("she's", '她是'), @("they're", '他们是'),
    @("He's", '他是'), @("She's", '她是'), @("They've", '他们已经'),
    @("they've", '他们已经'),
    # --- 代词分支里残留的英文 ---
    @('Ta', '其'), @('FFF', '清')
)
$map = New-Object 'System.Collections.Generic.Dictionary[string,string]'
foreach ($p in $pairs) { $map[$p[0]] = $p[1] }

# 中文动词不随主语变位。为常见第三人称形式生成与原形相同的译文。
$verbPairs = @(
    @('accept', '接受'), @('act', '行动'), @('agree', '同意'), @('apologize', '道歉'),
    @('arch', '挑眉'), @('attack', '攻击'), @('attend', '参加'), @('avert', '移开'),
    @('avoid', '避开'), @('begin', '开始'), @('blurt', '脱口而出'), @('capsize', '倾覆'),
    @('charge', '冲锋'), @('clear', '理清'), @('climb', '爬上'), @('close', '合上'),
    @('collapse', '倒下'), @('complain', '抱怨'), @('consider', '考虑'), @('continue', '继续'),
    @('counter', '反驳'), @('cringe', '畏缩'), @('cut', '打断'), @('dart', '猛地看向'),
    @('deserve', '值得'), @('disappear', '消失'), @('drain', '耗尽'), @('drop', '放下'),
    @('enter', '走进'), @('explain', '解释'), @('extend', '伸出'), @('fail', '失败'),
    @('fall', '跌倒'), @('fidget', '坐立不安'), @('find', '找到'), @('fire', '开火'),
    @('flash', '闪过'), @('flinch', '畏缩'), @('focus', '专注'), @('follow', '跟随'),
    @('freeze', '僵住'), @('gasp', '倒吸一口气'), @('give', '给'), @('glance', '瞥一眼'),
    @('grab', '抓住'), @('gulp', '咽下口水'), @('hold', '拿着'), @('join', '加入'),
    @('joke', '开玩笑'), @('keep', '保持'), @('knock', '敲'), @('launch', '发动'),
    @('lean', '倚靠'), @('leave', '离开'), @('let', '让'), @('lick', '舔'),
    @('lie', '躺下'), @('limp', '一瘸一拐地走'), @('linger', '逗留'), @('lose', '失去'),
    @('manage', '设法做到'), @('mention', '提到'), @('need', '需要'), @('nod', '点头'),
    @('owe', '欠'), @('own', '拥有'), @('pivot', '转身'), @('pull', '拉'),
    @('pump', '抽动'), @('push', '推'), @('raise', '抬起'), @('read', '读'),
    @('realize', '意识到'), @('redden', '涨红'), @('rejoin', '重新加入'), @('remain', '留下'),
    @('reply', '回答'), @('report', '报告'), @('return', '返回'), @('rocket', '猛冲'),
    @('root', '扎根'), @('run', '跑'), @('say', '说'), @('search', '搜寻'),
    @('see', '看见'), @('seem', '似乎'), @('shake', '摇头'), @('shape', '形成'),
    @('share', '分享'), @('ship', '运送'), @('shout', '喊道'), @('shrug', '耸肩'),
    @('shuffle', '挪动'), @('sidestep', '侧身避开'), @('sigh', '叹气'), @('sip', '抿一口'),
    @('slap', '拍打'), @('slide', '滑动'), @('slump', '瘫坐'), @('slur', '含糊地说'),
    @('smile', '微笑'), @('snap', '厉声说'), @('sober', '清醒'), @('spill', '洒出'),
    @('spin', '转身'), @('stammer', '结结巴巴地说'), @('stand', '站起'), @('stare', '盯着'),
    @('stomp', '跺脚'), @('straighten', '挺直'), @('stride', '大步走'), @('struggle', '挣扎'),
    @('stumble', '绊倒'), @('suffer', '遭受'), @('swallow', '咽下'), @('talk', '说话'),
    @('tap', '轻敲'), @('tense', '绷紧'), @('throw', '扔'), @('trip', '绊倒'),
    @('turn', '转身'), @('walk', '走'), @('want', '想要'), @('wince', '皱眉'), @('wink', '眨眼'),
    @('know', '知道'), @('try', '尝试'), @('stop', '停住')
)
foreach ($p in $verbPairs) {
    $word = $p[0]
    $zh = $p[1]
    if (-not $map.ContainsKey($word)) { $map[$word] = $zh }
    if ($word -match '(?i)[^aeiou]y$') {
        $thirdPerson = $word.Substring(0, $word.Length - 1) + 'ies'
    } elseif ($word -match '(?i)(s|x|z|ch|sh|o)$') {
        $thirdPerson = $word + 'es'
    } else {
        $thirdPerson = $word + 's'
    }
    if (-not $map.ContainsKey($thirdPerson)) { $map[$thirdPerson] = $zh }
}

$extraPairs = @(
    @("'ve", '已经'), @('re', '是'), @('are', '是'), @("aren't", '不是'),
    @('do', '做'), @('does', '做'), @("don't", '不'), @("doesn't", '不'), @("isn't", '不是'),
    @('self', '自己'), @('selves', '自己'), @("They're", '他们是'),
    @('still want', '仍想'), @('still wants', '仍想'),
    @("he's my brother", '他是我的兄弟'), @("she's my sister", '她是我的姐妹'),
    @("they're my best bud", '他们是我最好的朋友'),
    @('shrug and reach', '耸耸肩并伸手'), @('shrugs and reaches', '耸耸肩并伸手'),
    @('sigh and shake', '叹气并摇头'), @('sighs and shakes', '叹气并摇头'),
    @('colllapses', '倒下'), @('straigthens', '挺直')
)
foreach ($p in $extraPairs) { $map[$p[0]] = $p[1] }

function Find-BranchTranslation([string]$value) {
    if ($script:map.ContainsKey($value)) { return $script:map[$value] }
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    if ($value -match '(?i)ies$' -and $value.Length -gt 3) {
        $candidates.Add($value.Substring(0, $value.Length - 3) + 'y')
    }
    if ($value -match '(?i)es$' -and $value.Length -gt 2) {
        $candidates.Add($value.Substring(0, $value.Length - 2))
    }
    if ($value -match '(?i)s$' -and $value.Length -gt 1) {
        $candidates.Add($value.Substring(0, $value.Length - 1))
    }
    foreach ($candidate in $candidates) {
        if ($script:map.ContainsKey($candidate)) { return $script:map[$candidate] }
    }
    return $null
}

$targets = New-Object System.Collections.ArrayList
foreach ($f in (Get-ChildItem $mods -Recurse -Filter 'Localization.json' -File -ErrorAction SilentlyContinue)) {
    if ($f.FullName -like '*\.modtek\*') { continue }
    $t = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    if ($t -notmatch '\.Gender\?') { continue }
    [void]$targets.Add($f.FullName)
}
Write-Host ("候选 Localization.json: " + $targets.Count)

$rxExpr = New-Object System.Text.RegularExpressions.Regex ('\{([A-Za-z_][A-Za-z0-9_.]*)\.Gender\?([^}]*)\}')
$zhFieldRx = New-Object System.Text.RegularExpressions.Regex ('("CULTURE_ZH_CN"\s*:\s*")((?:[^"\\]|\\.)*)(")')
$stats = @{ files = 0; exprs = 0; branches = 0 }
$enc = New-Object Text.UTF8Encoding $false
# 计数器需在脚本作用域, 否则 MatchEvaluator 里的自增传不出来
$script:exprN = 0
$script:brN = 0
$script:map = $map
$script:unknownBranches = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)

$evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
    param($m)
    $obj = $m.Groups[1].Value
    $body = [regex]::Replace($m.Groups[2].Value, ':(?=(?:Default|Male|Female|NonBinary):)', '|')
    $parts = $body -split '\|'
    $out = New-Object System.Collections.ArrayList
    $hit = $false
    foreach ($p in $parts) {
        $ci = $p.IndexOf(':')
        if ($ci -lt 0) { [void]$out.Add($p); continue }
        $cond = $p.Substring(0, $ci)
        $val = $p.Substring($ci + 1)
        $trimmed = $val.Trim()
        $lookup = $trimmed.Replace('\u0027', "'")
        $translation = Find-BranchTranslation $lookup
        if ($null -ne $translation) {
            $hit = $true
            $script:brN++
            [void]$out.Add($cond + ':' + $translation)
        } else {
            if ($trimmed -match '[A-Za-z]{2,}') { [void]$script:unknownBranches.Add($trimmed) }
            [void]$out.Add($p)
        }
    }
    if ($hit) { $script:exprN++ }
    return '{' + $obj + '.Gender?' + ($out -join '|') + '}'
}

foreach ($path in $targets) {
    $orig = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    $script:exprN = 0
    $script:brN = 0
    $new = $zhFieldRx.Replace($orig, [System.Text.RegularExpressions.MatchEvaluator] {
        param($fieldMatch)
        $raw = $fieldMatch.Groups[2].Value
        if ($raw -notmatch '[\u4e00-\u9fff]') { return $fieldMatch.Value }
        $fixed = $rxExpr.Replace($raw, $evaluator)
        if ($fixed -eq $raw) { return $fieldMatch.Value }
        return $fieldMatch.Groups[1].Value + $fixed + $fieldMatch.Groups[3].Value
    })
    if ($new -ne $orig) {
        $stats.files++; $stats.exprs += $script:exprN; $stats.branches += $script:brN
        if (-not $DryRun) {
            try { [void]($new | ConvertFrom-Json) }
            catch { throw ("修复性别分支后 JSON 无效: " + $path + " :: " + $_.Exception.Message) }
            $relative = $path.Substring($mods.Length).TrimStart([char]92, [char]47)
            $backup = Join-Path $backupRoot (Join-Path 'Mods' $relative)
            $parent = Split-Path $backup -Parent
            if (-not [IO.Directory]::Exists($parent)) { [void][IO.Directory]::CreateDirectory($parent) }
            if (-not [IO.File]::Exists($backup)) { [IO.File]::WriteAllText($backup, $orig, $enc) }
            [IO.File]::WriteAllText($path, $new, $enc)
        }
        Write-Host ("  " + $path.Substring($mods.Length).TrimStart('\') + "  表达式=" + $script:exprN + " 分支=" + $script:brN)
    }
}

function Repair-EventFile([string]$path, [string]$root, [string]$scope) {
    $orig = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    if ($orig -notmatch '\.Gender\?' -or $orig -notmatch '[\u4e00-\u9fff]') { return }
    $fields = @(
        'Name', 'Details', 'words', 'title', 'description', 'shortDescription',
        'longDescription', 'ShortDesc', 'OptionName', 'OptionDescription',
        'ResultName', 'ResultDescription', 'FlashpointShortDescription',
        'FlashpointLongDescription', 'Text', 'text', 'Caption', 'label'
    )
    $fieldAlt = ($fields | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $bs = [string][char]92
    $fieldRx = [regex]::new('("(' + $fieldAlt + ')"\s*:\s*")((?:[^"' + $bs + $bs + ']|' + $bs + $bs + '.)*)(")')
    $new = $fieldRx.Replace($orig, {
        param($fieldMatch)
        $raw = $fieldMatch.Groups[3].Value
        if ($raw -notmatch '[\u4e00-\u9fff]') { return $fieldMatch.Value }
        $fixed = $script:rxExpr.Replace($raw, $script:evaluator)
        if ($fixed -eq $raw) { return $fieldMatch.Value }
        $script:eventExprN++
        return ($fieldMatch.Groups[1].Value + $fixed + $fieldMatch.Groups[4].Value)
    })
    if ($new -eq $orig) { return }
    try { [void]($new | ConvertFrom-Json) }
    catch { throw ("修复性别分支后 JSON 无效: " + $path + " :: " + $_.Exception.Message) }
    $script:eventFilesChanged++
    if (-not $DryRun) {
        $relative = $path.Substring($root.Length).TrimStart([char]92, [char]47)
        $backup = Join-Path $backupRoot (Join-Path $scope $relative)
        $parent = Split-Path $backup -Parent
        if (-not [IO.Directory]::Exists($parent)) { [void][IO.Directory]::CreateDirectory($parent) }
        if (-not [IO.File]::Exists($backup)) { [IO.File]::WriteAllText($backup, $orig, $enc) }
        [IO.File]::WriteAllText($path, $new, $enc)
    }
}

$script:rxExpr = $rxExpr
$script:evaluator = $evaluator
$script:eventExprN = 0
$script:eventFilesChanged = 0
$eventPattern = '(?i)(^|[\\/])(?:events?|eventualities|backgroundevents?|flashpoints?|forcedevents?)(?:[\\/]|$)'
$eventFiles = Get-ChildItem $mods -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object {
    $relative = $_.FullName.Substring($mods.Length).TrimStart([char]92, [char]47)
    $relative -match $eventPattern -and $relative -notmatch '(?i)(^|[\\/])(?:\.modtek|ModSaves|Localization)(?:[\\/]|$)'
}
foreach ($file in $eventFiles) { Repair-EventFile $file.FullName $mods 'Mods' }

if (-not [string]::IsNullOrWhiteSpace($baseDataRoot) -and [IO.Directory]::Exists($baseDataRoot)) {
    foreach ($folder in @('events', 'flashpoints')) {
        $dir = Join-Path $baseDataRoot $folder
        if (-not [IO.Directory]::Exists($dir)) { continue }
        foreach ($file in (Get-ChildItem $dir -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue)) {
            Repair-EventFile $file.FullName $baseDataRoot 'BattleTech_Data'
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($csv) -and [IO.File]::Exists($csv)) {
    $origCsv = [IO.File]::ReadAllText($csv, [Text.Encoding]::UTF8)
    $script:exprN = 0
    $script:brN = 0
    $csvRowRx = [System.Text.RegularExpressions.Regex]::new('(?m)^([^,\r\n]*,)([^\r\n]*)(\r?)$')
    $newCsv = $csvRowRx.Replace($origCsv, [System.Text.RegularExpressions.MatchEvaluator] {
        param($row)
        $value = $row.Groups[2].Value
        if ($value -notmatch '[\u4e00-\u9fff]' -or $value -notmatch '\.Gender\?') { return $row.Value }
        $fixed = $script:rxExpr.Replace($value, $script:evaluator)
        if ($fixed -eq $value) { return $row.Value }
        return $row.Groups[1].Value + $fixed + $row.Groups[3].Value
    })
    if ($newCsv -ne $origCsv) {
        if (-not $DryRun) {
            $backup = Join-Path $backupRoot 'strings_zh-CN.csv'
            $parent = Split-Path $backup -Parent
            if (-not [IO.Directory]::Exists($parent)) { [void][IO.Directory]::CreateDirectory($parent) }
            if (-not [IO.File]::Exists($backup)) { [IO.File]::WriteAllText($backup, $origCsv, $enc) }
            [IO.File]::WriteAllText($csv, $newCsv, $enc)
        }
        Write-Host ("  " + $csv + "  表达式=" + $script:exprN + " 分支=" + $script:brN)
    }
}

Write-Host ("=== 共改 " + $stats.files + " 文件, " + $stats.exprs + " 表达式, " + $stats.branches + " 分支 ===")
Write-Host ("事件 JSON: 文件=" + $script:eventFilesChanged + " 表达式=" + $script:eventExprN)
if ($script:unknownBranches.Count -gt 0) {
    Write-Host ("未匹配英文分支=" + $script:unknownBranches.Count + ': ' + ([string]::Join(', ', ($script:unknownBranches | Sort-Object)))) -ForegroundColor Yellow
}
if ($DryRun) { Write-Host '[DryRun] 未写盘' }
