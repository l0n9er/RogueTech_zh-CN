param(
    [string]$csv = ""
)
<#
  修复插值占位符 [[...]] 内的中文标点

  背景: 游戏中 [[OBJ ， {OBJ.Field}]] 是字符串插值语法, 对象与字段引用之间
        只能用半角分隔或不加分隔。翻译时若在中间插入全角逗号(，), 游戏会报
        "INVALID ALIAS OBJ ， 字段名" 并回退成 error(显示为"错误")。

  典型故障: 事件奖励弹窗显示 "你获得了 2x 错误"

  规则: [[ 对象 [目标] ， 显示名 ]]  ->  [[ 对象 [目标]显示名 ]]
        [[ 对象 ， {对象.字段} ]]    ->  [[ 对象{对象.字段} ]]

  本脚本只删除 [[...]] 语法内部、紧跟在标识符/内层]之后的全角逗号,
  不动正文中的中文标点。
#>
$ErrorActionPreference = 'Stop'
$BS = [string][char]92
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($csv)) {
    $csv = Join-Path $packRoot 'strings_zh-CN.csv'
    if (-not [IO.File]::Exists($csv)) {
        $gr = & (Join-Path $PSScriptRoot 'find-game.ps1')
        if (-not [string]::IsNullOrWhiteSpace($gr)) {
            $csv = Join-Path $gr 'BattleTech_Data\StreamingAssets\data\localization\strings_zh-CN.csv'
        }
    }
}
if (-not [IO.File]::Exists($csv)) {
    Write-Host (" 找不到翻译总表: " + $csv) -ForegroundColor Yellow
    exit 1
}

$t = [IO.File]::ReadAllText($csv, [Text.Encoding]::UTF8)
$fw = [char]0xFF0C   # 全角逗号
$spc = [char]32
$FS = [string][char]31   # 0x1F 单元分隔符 —— [[对象<0x1F>显示名]] 的正确分隔符

$rxSpan = [regex]('\[\[[^\[\]\r\n]*(\[[^\[\]\r\n]*\][^\[\]\r\n]*)*\]\]')
$out = New-Object System.Text.StringBuilder
$pos = 0
$fixed = 0
foreach ($m in $rxSpan.Matches($t)) {
    [void]$out.Append($t.Substring($pos, $m.Index - $pos))
    $pos = $m.Index + $m.Length
    $span = $m.Value
    if (-not $span.Contains($fw)) { [void]$out.Append($span); continue }

    $res = New-Object System.Text.StringBuilder
    $i = 0; $n = $span.Length
    while ($i -lt $n) {
        $c = $span[$i]
        if ($c -eq $fw) {
            # 回看: 跳过空格后是否为 ']' 或标识符字符 -> 说明逗号前是对象/目标, 应删
            $k = $res.Length - 1
            while ($k -ge 0 -and $res[$k] -eq $spc) { $k-- }
            $isAfterObj = $false
            if ($k -ge 0) {
                if ($res[$k] -eq ']') { $isAfterObj = $true }
                elseif ([char]::IsLetterOrDigit($res[$k]) -or $res[$k] -eq '_' -or $res[$k] -eq '.') {
                    # 需要确认当前确实处在 [[ 语法内(前面有 [[)
                    $isAfterObj = $true
                }
            }
            if ($isAfterObj) {
                while ($res.Length -gt 0 -and $res[$res.Length-1] -eq $spc) { [void]$res.Remove($res.Length-1, 1) }
                # 关键: 删掉全角逗号后必须补 0x1F(单元分隔符), 而不是空格。
                # 官方 dev/de-DE/fr-FR/ru-RU 该位置一律是 "]" + 0x1F + 显示名,
                # 补成空格会让游戏解析失败并回退显示"错误"。
                [void]$res.Append($FS)
                $fixed++
                $i++
                while ($i -lt $n -and $span[$i] -eq $spc) { $i++ }
                continue
            }
        }
        [void]$res.Append($c)
        $i++
    }
    [void]$out.Append($res.ToString())
}
[void]$out.Append($t.Substring($pos, $t.Length - $pos))
$new = $out.ToString()

# 兜底: [[前缀[目标]显示名]] 缺 0x1F -> 补 0x1F(不是空格!)
$rxSep = New-Object System.Text.RegularExpressions.Regex ('(\[\[[A-Za-z_][A-Za-z0-9_.*]*\[[^\]]+\])(?=[^\x1f \]\r\n\[])')
$sepN = $rxSep.Matches($new).Count
if ($sepN -gt 0) {
    $new = $rxSep.Replace($new, ('$1' + $FS))
    Write-Host ("补充 0x1F 分隔 " + $sepN + " 处")
}

if ($fixed -gt 0 -or $sepN -gt 0) {
    [IO.File]::WriteAllText($csv, $new, (New-Object Text.UTF8Encoding $false))
    Write-Host ("已修复 " + $fixed + " 处占位符内标点")
} else {
    Write-Host "无需修复"
}
# 复核
$bad = 0
foreach ($m in $rxSpan.Matches($new)) { if ($m.Value.Contains($fw)) { $bad++ } }
Write-Host ("复核: [[...]] 内残留全角逗号 = " + $bad)
