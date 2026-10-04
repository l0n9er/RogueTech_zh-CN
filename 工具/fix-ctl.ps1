# 插值占位符 [[...]] 分隔符规范化
#
# 游戏语法与各文件类型的正确形态(经全盘取证):
#   · JSON 文件(events / simGameConstants / simGameStatDesc 等):
#       原版一律写成 [[OBJ,{OBJ.F}]] 与 [[前缀[目标],显示名]] —— 用半角逗号。
#       全盘 3917 个原版 JSON 中 0x1F 出现 0 次。
#   · 本地化 CSV(strings_*.csv):
#       官方 dev/de-DE/fr-FR/ru-RU 一律写成 [[OBJ<0x1F>{OBJ.F}]] —— 0x1F 紧贴两侧, 无空格。
#       1F 与两侧空格共存的形态在官方表中仅 de 1 处 / dev 2 处, 属异常。
#
# 故障现象与证据:
#   JSON 里写成 "[[OBJ <0x1F> {OBJ.F}]]"(两边带空格)时游戏解析失败,
#   output_log.txt 记录 "INVALID ALIAS SCN_MW  Ice Trey" 等 11 条报错,
#   界面回退显示 error —— 环境把 error 译作"错误", 于是出现
#   "错误 has lost the following tags"/"你与 错误 的声望降低了 1" 这类文本。
#
# 历史教训:
#   · 早期版本把 0x1F 当成误写替换为全角逗号 -> 大面积"错误"兜底;
#   · 之后的修正版又给 0x1F 两侧加了空格 -> 仍然是解析失败(就是本次修的 bug);
#   · 正确做法: JSON 用逗号, CSV 用紧贴的 0x1F, 两者都不带空格。
param(
    [string]$gameRoot = "",
    [string]$packRoot = ""
)
$ErrorActionPreference = 'Stop'
$FS = [string][char]31        # 0x1F 单元分隔符
$SP = [string][char]32
$FW = [string][char]0xFF0C    # 全角逗号
$enc = New-Object Text.UTF8Encoding $false

if ([string]::IsNullOrWhiteSpace($packRoot)) { $packRoot = Split-Path $PSScriptRoot -Parent }
if ([string]::IsNullOrWhiteSpace($gameRoot)) {
    $gameRoot = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gameRoot)) {
        Write-Host " 找不到游戏目录, 请用 -gameRoot 指定。" -ForegroundColor Yellow
        exit 1
    }
}

# [[对象]] / [[对象[目标]] 之后的分隔段(空白 + 可选 0x1F + 空白, 或逗号)
$rxHead = '(\[\[[A-Za-z_][A-Za-z0-9_.*]*(?:[ \t]*\[[^\[\]\r\n]*\])?)'
$rxSepAll = New-Object System.Text.RegularExpressions.Regex (
    $rxHead + '[ \t]*(?:' + [regex]::Escape($FS) + '|[，,])[ \t]*')
$rxNeedSep = New-Object System.Text.RegularExpressions.Regex (
    $rxHead + '[ \t]*(?=\{|\S)')
# 无分隔形态: [[OBJ{OBJ.F}]] 缺分隔符。
# 只认后面紧跟 '{' 的情形 —— 后面跟 ']' 的 [[OBJ]] 是无字段的畸形串,
# 补分隔符只会把它弄得更糟(踩过: 曾把 [[DM.BaseDescriptionDefs]] 写成 [[DM.BaseDescriptionDefs<0x1F>]])。
$rxNoSep = New-Object System.Text.RegularExpressions.Regex (
    $rxHead + '(?=\{)')

function Normalize-Csv([string]$t) {
    $t = $rxSepAll.Replace($t, ('$1' + $FS))
    $t = $rxNoSep.Replace($t, ('$1' + $FS))
    return $t
}
function Normalize-Json([string]$t) {
    $t = $rxSepAll.Replace($t, '$1,')
    # JSON 里不允许裸 0x1F 作分隔, 统一为逗号
    $t = $rxNoSep.Replace($t, '$1,')
    return $t
}

$stat = @{ json = 0; csv = 0; files = 0 }
$targets = New-Object System.Collections.ArrayList

$modsDir = Join-Path $gameRoot 'Mods'
if ([IO.Directory]::Exists($modsDir)) {
    foreach ($f in (Get-ChildItem $modsDir -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notlike '*\.modtek\*' -and $_.Name -notlike '*.zhbak*' })) {
        [void]$targets.Add($f.FullName)
    }
}
if (-not [string]::IsNullOrWhiteSpace($packRoot)) {
    foreach ($f in (Get-ChildItem (Join-Path $packRoot 'Mods') -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notlike '*\.modtek\*' -and $_.Name -notlike '*.zhbak*' })) {
        [void]$targets.Add($f.FullName)
    }
}
[void]$targets.Add((Join-Path $gameRoot 'BattleTech_Data\StreamingAssets\data\localization\strings_zh-CN.csv'))
[void]$targets.Add((Join-Path $packRoot 'strings_zh-CN.csv'))
[void]$targets.Add((Join-Path $packRoot '可选-模组形式\CustomLocalization-ZH-CN\StreamingAssets\data\localization\strings_zh-CN.csv'))

$seen = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($path in $targets) {
    if (-not [IO.File]::Exists($path)) { continue }
    if (-not $seen.Add($path.ToLower())) { continue }
    $t = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    if ($t.IndexOf('[[') -lt 0) { continue }
    $stat.files++
    $orig = $t
    if ([IO.Path]::GetExtension($path) -ieq '.csv') {
        $t = Normalize-Csv $t
    } else {
        $t = Normalize-Json $t
    }
    if ($t -ne $orig) {
        [IO.File]::WriteAllText($path, $t, $enc)
        if ([IO.Path]::GetExtension($path) -ieq '.csv') { $stat.csv++ } else { $stat.json++ }
    }
}

Write-Host '=== 插值占位符分隔符规范化 ==='
Write-Host ("  扫描文件 " + $stat.files + " 个")
Write-Host ("  JSON -> 逗号形态  : " + $stat.json + " 个")
Write-Host ("  CSV  -> 0x1F 紧贴 : " + $stat.csv + " 个")

# 复核
$left = 0
foreach ($path in $seen) {
    if (-not [IO.File]::Exists($path)) { continue }
    $t = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    $isCsv = ([IO.Path]::GetExtension($path) -ieq '.csv')
    if ($isCsv) {
        $left += ([regex]::Matches($t, [regex]::Escape($SP + $FS) + '|' + [regex]::Escape($FS + $SP))).Count
    } else {
        $left += ([regex]::Matches($t, [regex]::Escape($FS))).Count
    }
}
Write-Host ("  复核: 非规范形态残留 = " + $left)
