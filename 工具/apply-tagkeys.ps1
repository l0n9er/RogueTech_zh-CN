# 补 tag 短版键: 有些 tag 的 Description 在总表里只有"带效果后缀"的长版,
# 而 tag 文件里写的是不带后缀的短版。这里按前缀匹配复用长版译文的首段。
#
# 原理: 长版 key = 短版 key + 'newlinenewline' + 效果行;
#       译文以字面 '\n\n' 分隔首段与效果行。取首段即短版译文。
param(
    [string]$csv = "",
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($csv)) { $csv = Join-Path $packRoot 'strings_zh-CN.csv' }
if (-not [IO.File]::Exists($csv)) { Write-Host (" 找不到翻译总表: " + $csv) -ForegroundColor Yellow; exit 1 }

$shortKeys = @(
    'thispilotisboredandfeelsletdown*theymaycauseunwantedstressonothercrewmembers*',
    'thispilotisboredandlacksmotivation*theymaycauseunwantedstressonothercrewmembers*',
    'thispilotisshowingsignsofmalevolentbehaviour*theymaycauseunwantedstressonothercrewmembersaswellasdamagetoareasoftheargo*',
    'thispilotsstorytellingabilitycausesenemiestobecomedistracted*',
    'thispilotdefeatedtheso-calledhighkhaninabatchall^eventhoughtheydidntdomuchofthework*',
    'thispilotshowedthepoweroftheso-calledmurderpede*',
    'thispilotcreatedawifinetwork^muchtocomstarsanger*',
    'thispilotdid!',
    'squarepeg-roundhole',
    'legendary-spirit',
    'stayawhileandlisten!',
    'wholetthedogsout?'
)

$lines = [IO.File]::ReadAllLines($csv, [Text.Encoding]::UTF8)
$existing = New-Object 'System.Collections.Generic.HashSet[string]'
$byKey = New-Object 'System.Collections.Generic.Dictionary[string,string]'
for ($i = 1; $i -lt $lines.Count; $i++) {
    $p = $lines[$i].IndexOf(',')
    if ($p -lt 1) { continue }
    $k = $lines[$i].Substring(0, $p)
    [void]$existing.Add($k)
    if (-not $byKey.ContainsKey($k)) { $byKey[$k] = $lines[$i].Substring($p + 1) }
}

$manual = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$manual['thispilotdid!'] = '就是这个机师干的！'
$manual['squarepeg-roundhole'] = '方枘圆凿'
$manual['legendary-spirit'] = '传奇之魂'
$manual['stayawhileandlisten!'] = '且留步，听我一言！'
$manual['wholetthedogsout?'] = '谁把狗放出来了？'

$add = New-Object System.Collections.ArrayList
foreach ($sk in $shortKeys) {
    if ($existing.Contains($sk)) { continue }
    $v = $null
    if ($manual.ContainsKey($sk)) { $v = $manual[$sk] }
    if ($null -eq $v) {
        foreach ($k in $byKey.Keys) {
            if ($k -eq $sk) { continue }
            if ($k.StartsWith($sk)) {
                $lv = $byKey[$k]
                $idx = $lv.IndexOf('\n\n')
                if ($idx -gt 0) { $v = $lv.Substring(0, $idx).Trim() } else { $v = $lv.Trim() }
                break
            }
        }
    }
    if ($null -ne $v -and $v.Length -gt 0) { [void]$add.Add($sk + ',' + $v) }
    else { Write-Host ("  [未推导] " + $sk) }
}

Write-Host ("待补短版键: " + $add.Count)
foreach ($a in $add) { Write-Host ("  + " + $a.Substring(0, [Math]::Min(110, $a.Length))) }
if ($add.Count -gt 0 -and -not $DryRun) {
    $sw = New-Object IO.StreamWriter($csv, $true, (New-Object Text.UTF8Encoding $false))
    $sw.NewLine = "`r`n"
    foreach ($a in $add) { $sw.WriteLine($a) }
    $sw.Close()
    Write-Host ("已追加 -> " + $csv)
} elseif ($DryRun) { Write-Host '[DryRun]' }
