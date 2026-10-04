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
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($repo)) { $repo = $packRoot }
if ([string]::IsNullOrWhiteSpace($mods)) { $mods = Join-Path $repo 'Mods' }
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
    @('Ta', 'TA')
)
$map = New-Object 'System.Collections.Generic.Dictionary[string,string]'
foreach ($p in $pairs) { $map[$p[0]] = $p[1] }

$targets = New-Object System.Collections.ArrayList
foreach ($f in (Get-ChildItem $mods -Recurse -Filter 'Localization.json' -File -ErrorAction SilentlyContinue)) {
    if ($f.FullName -like '*\.modtek\*') { continue }
    $t = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    if ($t -notmatch '\.Gender\?') { continue }
    [void]$targets.Add($f.FullName)
}
Write-Host ("候选 Localization.json: " + $targets.Count)

$rxExpr = New-Object System.Text.RegularExpressions.Regex ('\{([A-Za-z_][A-Za-z0-9_.]*)\.Gender\?([^}]*)\}')
$stats = @{ files = 0; exprs = 0; branches = 0 }
$enc = New-Object Text.UTF8Encoding $false
# 计数器需在脚本作用域, 否则 MatchEvaluator 里的自增传不出来
$script:exprN = 0
$script:brN = 0
$script:map = $map

$evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
    param($m)
    $obj = $m.Groups[1].Value
    $body = $m.Groups[2].Value
    $parts = $body -split '\|'
    $out = New-Object System.Collections.ArrayList
    $hit = $false
    foreach ($p in $parts) {
        $ci = $p.IndexOf(':')
        if ($ci -lt 0) { [void]$out.Add($p); continue }
        $cond = $p.Substring(0, $ci)
        $val = $p.Substring($ci + 1)
        $trimmed = $val.Trim()
        if ($script:map.ContainsKey($trimmed)) {
            $hit = $true
            $script:brN++
            [void]$out.Add($cond + ':' + $script:map[$trimmed])
        } else {
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
    $new = $rxExpr.Replace($orig, $evaluator)
    if ($new -ne $orig) {
        $stats.files++; $stats.exprs += $script:exprN; $stats.branches += $script:brN
        if (-not $DryRun) { [IO.File]::WriteAllText($path, $new, $enc) }
        Write-Host ("  " + $path.Substring($mods.Length).TrimStart('\') + "  表达式=" + $script:exprN + " 分支=" + $script:brN)
    }
}
Write-Host ("=== 共改 " + $stats.files + " 文件, " + $stats.exprs + " 表达式, " + $stats.branches + " 分支 ===")
if ($DryRun) { Write-Host '[DryRun] 未写盘' }
