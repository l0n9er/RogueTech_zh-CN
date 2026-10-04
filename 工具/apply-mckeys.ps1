# 补充 MissionControl 任务目标的 CSV 兜底键
#
# 背景: MissionControl 的 contractTypeBuilds\*\common.jsonc 里定义的目标
# Title / ProgressFormat 在运行时直接查翻译总表(与原版 objective 同一机制),
# 但表中缺这些键, 于是游戏显示英文原文(如截图中的
# "DEFECTOR MUST SURVIVE AND REACH THE EVAC ZONE" 与
# "with 0/1 unit for 1 round")。
#
# 依据: 原版 dev/de-DE 等表中同类 objective 文本都有键
# (例如 de-DE 有 reachtheevaczone、[unitsoccupyingsofar]/... 系列),
# 证明游戏对这些文本走 CSV 查表。
#
# 键按归一化规则书写: 小写 -> 去标签 -> ,=>^ -> .=>* -> 去引号 -> 去空白。
param(
    [string]$csv = "",
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($csv)) { $csv = Join-Path $packRoot 'strings_zh-CN.csv' }
if (-not [IO.File]::Exists($csv)) { Write-Host (" 找不到翻译总表: " + $csv) -ForegroundColor Yellow; exit 1 }

# 键 -> 译文
$pairs = [ordered]@{
    # ---------- MissionControl common.jsonc 的目标标题 ----------
    'defeatcontender01'                                        = '击败参赛者01'
    'destroythehostiletoalllance'                              = '摧毁敌对全体小队'
    'destroytheenemylance'                                     = '摧毁敌方小队'
    'defeatenemyvanguardlance(wave1)'                          = '击败敌方先锋小队（第1波）'
    'defeatsecondopforlance'                                   = '击败敌方第二小队'
    'defeatthirdopforlance'                                    = '击败敌方第三小队'
    'defeatflankerlance'                                       = '击败侧翼小队'
    'defeatanotherflankinglance'                               = '击败另一支侧翼小队'
    '(optional)destroyenemylance01b'                           = '(可选) 摧毁敌方小队01b'
    'destroytarget_lance_01'                                   = '摧毁目标小队01'
    'destroytarget_lance_02'                                   = '摧毁目标小队02'
    'destroytarget_lance_03'                                   = '摧毁目标小队03'
    'destroytarget_lance_04'                                   = '摧毁目标小队04'
    'destroytarget_lance_05'                                   = '摧毁目标小队05'
    'destroytarget_lance_06'                                   = '摧毁目标小队06'
    'defeatthepctarget'                                        = '击败玩家方目标'
    'defeattarget_lance_02'                                    = '击败目标小队02'
    'defeattarget_lance_03'                                    = '击败目标小队03'
    'defeattarget_lance_04'                                    = '击败目标小队04'
    'defeattarget_lance_05'                                    = '击败目标小队05'
    'aplayerunitreachestherallypoint'                          = '一名玩家单位抵达集结点'
    'defectormustsurviveandreachtheevaczone'                   = '叛逃者必须存活并抵达撤离区域'
    'destroyvanguardlance'                                     = '摧毁先锋小队'
    'destroytarget_lance_07'                                   = '摧毁目标小队07'
    'destroytarget_lance_08'                                   = '摧毁目标小队08'
    'destroytarget_lance_09'                                   = '摧毁目标小队09'
    'destroytarget_lance_10'                                   = '摧毁目标小队10'
    'objectiveexitmission'                                     = '撤离任务区域'
    # ---------- MissionControl common.jsonc 的进度格式 ----------
    '[unitsoccupyingsofar]/[numberofunitstooccupy]'            = '[unitsOccupyingSoFar]/[numberOfUnitsToOccupy]'
    '[unitsoccupyingsofar]/[numberofunitstooccupy]occupyingunit' = '[unitsOccupyingSoFar]/[numberOfUnitsToOccupy] 个单位占领中'
    'with[unitsoccupyingsofar]/[numberofunitstooccupy]unitfor[durationremaining]round' = '以 [unitsOccupyingSoFar]/[numberOfUnitsToOccupy] 个单位占领 [durationRemaining] 回合'
    '[numberofunitstodefend]structuremustsurvive^[numberofunitstodefendremaining]remainingfor[durationremaining]round(s)' = '[numberOfUnitsToDefend] 座建筑必须存活，[numberOfUnitsToDefendRemaining] 座尚存，持续 [durationRemaining] 回合'
    '[numberofunitstodefend]structuresmustsurvive^[numberofunitstodefendremaining]structuresremainingfor[durationremaining]round(s)' = '[numberOfUnitsToDefend] 座建筑必须存活，[numberOfUnitsToDefendRemaining] 座尚存，持续 [durationRemaining] 回合'
}

$dict = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($l in [IO.File]::ReadLines($csv, [Text.Encoding]::UTF8)) {
    $p = $l.IndexOf(',')
    if ($p -lt 1) { continue }
    [void]$dict.Add($l.Substring(0, $p))
}
$add = New-Object System.Collections.ArrayList
foreach ($k in $pairs.Keys) {
    if ($dict.Contains($k)) { continue }
    [void]$add.Add($k + ',' + $pairs[$k])
}
Write-Host ("待补: " + $add.Count + " / 候选 " + $pairs.Count)
foreach ($a in $add) { Write-Host ("  + " + $a.Substring(0, [Math]::Min(110, $a.Length))) }
if ($add.Count -gt 0 -and -not $DryRun) {
    $sw = New-Object IO.StreamWriter($csv, $true, (New-Object Text.UTF8Encoding $false))
    $sw.NewLine = "`r`n"
    foreach ($a in $add) { $sw.WriteLine($a) }
    $sw.Close()
    Write-Host ("已追加 -> " + $csv)
} elseif ($DryRun) { Write-Host '[DryRun] 未写盘' }
