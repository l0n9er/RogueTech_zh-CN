# 补充界面弹窗缺失的本地化兜底键
#
# 背景: 游戏中 [[A<0x1F>B]] 形式的文本会先去翻译总表查同形态的键; 界面里仍显示英文的
# 几处, 都是因为表中缺该键(而非语法问题)。本次补齐以下三类:
#
#   1) 维修弹窗 (ArmorRepair.dll / CustomUnits.dll 硬编码)
#   2) 载具报废/改装提示 (CustomUnits.dll)
#   3) 采购类菜单项 (游戏本体 Assembly-CSharp.dll, 载具语境)
#
# 键一律按游戏的归一化规则书写: 小写 -> 换行=newline -> 去 <...> 标签 ->
#   , 变 ^ -> . 变 * -> 去引号 -> 去空白。
# 含别名占位符的键保留 0x1F (与官方 CSV 一致, 紧贴无空格)。
param(
    [string]$csv = "",
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$FS = [string][char]31
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($csv)) { $csv = Join-Path $packRoot 'strings_zh-CN.csv' }
if (-not [IO.File]::Exists($csv)) { Write-Host (" 找不到翻译总表: " + $csv) -ForegroundColor Yellow; exit 1 }

# 用数组保证顺序可读; 每项 = 键 + TAB + 译文
$rows = @(
    # ---------- 1) 维修弹窗 ----------
    ("mechrepairsneeded" + "`t" + "机甲需要维修"),
    ("vehiclerepairsneeded!" + "`t" + "战车需要维修!"),
    ("wantmycrewtogetstarted?" + "`t" + "要我的机组开始动手吗?"),
    ("boss^imveryverysorry(reallynot)*drunkentechbrokethisvehicle" + "`t" + "老板，我非常非常抱歉(真的)。醉酒的技师弄坏了这辆战车"),
    ("boss^{0}damaged*itllcost<color=#de6729>{1}{2:n0}</color>and{3}daysfortheserepairs*wantmycrewtogetstarted?newlinenewlinealso^{4}" + "`t" + "老板，{0} 受损了。维修需要 <color=#DE6729>{1}{2:n0}</color> 和 {3} 天。要我的机组开始动手吗？`n`n另外，{4}"),
    # ---------- 2) 载具报废 / 改装 ----------
    ("youmustrefitthevehcile" + "`t" + "你必须改装该战车。"),
    ("repairvehicle?" + "`t" + "修理战车？"),
    ("cannotscrapvehicle" + "`t" + "无法报废战车"),
    ("cannotrefitvehicle" + "`t" + "无法改装战车"),
    ("scrapvehicle" + "`t" + "报废战车"),
    ("cancelscrapvehicle" + "`t" + "取消报废战车"),
    ("thisvehicleisalreadyundermaintenance*youmustfirstcanceltheexistingtaskinordertobeginrepairs" + "`t" + "该战车已在维护中。你必须先取消现有任务才能开始维修。"),
    ("thisvehicleisalreadyundermaintenance*youmustfirstcanceltheexistingtaskinordertorefitthisvehicle" + "`t" + "该战车已在维护中。你必须先取消现有任务才能改装该战车。"),
    ("thisvehicleisalreadyundermaintenance*youmustfirstcanceltheexistingtaskinordertoscrapthisvehicle" + "`t" + "该战车已在维护中。你必须先取消现有任务才能报废该战车。"),
    ("thisvehicleisalreadyundermaintenance*youmustfirstcanceltheexistingtaskinordertosetrepairs" + "`t" + "该战车已在维护中。你必须先取消现有任务才能安排维修。"),
    ("newlinenewlinethefollowingcomponentshavebeendestroyed*ifyoucontinuewiththerepair^replacementcomponentswillnotbeinstalled*ifyouwanttoreplacethemwithidenticalordifferentcomponents^youmustrefitthevehcile*newlinenewline" + "`t" + "\n\n以下部件已损毁。若继续维修，将不会安装替换部件。若你希望以相同或不同的部件替换它们，必须改装该战车。\n\n"),
    # ---------- 3) 载具语境菜单项 ----------
    ("equipandrepairthisvehicle" + "`t" + "装备并修理该战车"),
    ("viewvehiclesandparts" + "`t" + "查看战车与部件"),
    ("showallvehicles" + "`t" + "显示所有战车"),
    ("scrapvehicleforc-bills" + "`t" + "报废战车以换取星币"),
    ("scheduletasktoaddthisvehicletobays" + "`t" + "安排任务将该战车加入机库"),
    ("sellvehicles" + "`t" + "出售战车")
)

# 读现有键
$dict = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($l in [IO.File]::ReadLines($csv, [Text.Encoding]::UTF8)) {
    $p = $l.IndexOf(',')
    if ($p -lt 1) { continue }
    [void]$dict.Add($l.Substring(0, $p))
}

$add = New-Object System.Collections.ArrayList
foreach ($r in $rows) {
    $i = $r.IndexOf("`t")
    if ($i -lt 1) { continue }
    $k = $r.Substring(0, $i)
    $v = $r.Substring($i + 1)
    if ($dict.Contains($k)) { continue }
    # 值里不能有裸逗号(CSV 分隔符); 全角逗号安全, 半角需转义为 \u002C? 游戏按行首逗号切分,
    # 官方表的值含半角逗号时不做转义, 直接原样; 这里避免引入半角逗号即可。
    [void]$add.Add($k + ',' + $v)
}

Write-Host ("待补键: " + $add.Count + " / 候选 " + $rows.Count)
foreach ($a in $add) { Write-Host ("  + " + $a.Substring(0, [Math]::Min(100, $a.Length))) }

if ($add.Count -gt 0 -and -not $DryRun) {
    $sw = New-Object IO.StreamWriter($csv, $true, (New-Object Text.UTF8Encoding $false))
    $sw.NewLine = "`r`n"
    foreach ($a in $add) { $sw.WriteLine($a) }
    $sw.Close()
    Write-Host ("已追加 " + $add.Count + " 键 -> " + $csv)
} elseif ($DryRun) { Write-Host '[DryRun] 未写盘' }
