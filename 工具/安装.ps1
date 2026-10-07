param(
    [string]$gameRoot = "",
    # 必须明确指定 Steam 或 GOG；未指定时由脚本提示选择。
    [string]$edition = '',
    # 可选: 月光石头新版汉化包的数据目录(…\battletech-trans\resources\data)。
    # 指定后会从中增量合并本包缺少的条目(主要是运行时拼接的载具整段描述)。
    [string]$moonstone = ""
)
$ErrorActionPreference = 'Stop'
$enc = New-Object Text.UTF8Encoding $false
$totalSteps = 25
$groupTotal = 6
$stepGroup = @{
    1 = 1; 2 = 1; 3 = 1; 4 = 1
    5 = 2; 6 = 2
    7 = 3; 8 = 3; 9 = 3; 10 = 3; 11 = 3; 12 = 3; 13 = 3; 14 = 3; 15 = 3; 16 = 3; 17 = 3; 18 = 3; 19 = 3; 20 = 3
    21 = 4; 22 = 4
    23 = 5; 24 = 5
    25 = 6
}
$groupTitle = @{
    1 = '基础资源安装'
    2 = '清理旧备份与启动环境'
    3 = '数据、文本与界面汉化'
    4 = '运行时文本与标签修复'
    5 = '格式、标点与术语修复'
    6 = '最终校验'
}
$script:currentStep = '准备'
$script:lastGroup = 0
$script:installLog = $null
$script:installerPath = $PSCommandPath
$script:modsJsonFileList = ''

# 控制台与子 PowerShell 输出统一采用 UTF-8，避免中文工具输出在父进程中乱码。

try {
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    [Console]::InputEncoding = [Text.Encoding]::UTF8
    [Console]::TreatControlCAsInput = $false
} catch { }

function LogLine($m) {
    if (-not [string]::IsNullOrWhiteSpace($script:installLog)) {
        Add-Content -LiteralPath $script:installLog -Value ([string]$m) -Encoding UTF8
    }
}
function Say($m)  { Write-Host $m; LogLine $m }
function Step($n, $m) {
    $group = $stepGroup[[int]$n]
    if ($group -ne $script:lastGroup) {
        $script:lastGroup = $group
        $heading = "[阶段 " + $group + "/" + $groupTotal + "] " + $groupTitle[$group]
        Write-Host ""
        Write-Host $heading -ForegroundColor Cyan
        LogLine $heading
    }
    $script:currentStep = ("阶段 " + $group + "/" + $groupTotal + " · 子步骤 " + $n + "/" + $totalSteps + " · " + $m)
    Write-Host ("  · " + $m)
    LogLine ("  · " + $m)
}
function OptionalStep($n, $m) {
    $group = $stepGroup[[int]$n]
    if ($group -ne $script:lastGroup) {
        $script:lastGroup = $group
        $heading = "[阶段 " + $group + "/" + $groupTotal + "] " + $groupTitle[$group]
        Write-Host ""
        Write-Host $heading -ForegroundColor Cyan
        LogLine $heading
    }
    $script:currentStep = ("阶段 " + $group + "/" + $groupTotal + " · 子步骤 " + $n + "/" + $totalSteps + " · 扩展 · " + $m)
    Write-Host ("  · [扩展] " + $m)
    LogLine ("  · [扩展] " + $m)
}
function Ok($m)   { Write-Host ("      " + $m); LogLine ("      " + $m) }
function Warn($m) { Write-Host ("      警告: " + $m) -ForegroundColor Yellow; LogLine ("警告: " + $m) }

trap {
    $msg = $_.Exception.Message
    Write-Host ""
    Write-Host (" 安装在 " + $script:currentStep + " 失败: " + $msg) -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($script:installLog)) {
        LogLine ("失败: " + $script:currentStep + " :: " + $msg)
        Write-Host (" 详细日志: " + $script:installLog) -ForegroundColor Yellow
    }
    if (-not [string]::IsNullOrWhiteSpace($backupDir)) {
        Write-Host (" 已生成的备份仍保留在: " + $backupDir) -ForegroundColor Yellow
    }
    exit 1
}

# ---------- 定位游戏目录 ----------
$userSpecified = -not [string]::IsNullOrWhiteSpace($gameRoot)
if (-not $userSpecified) {
    # 未指定时: 自动探测(启动器配置 / Steam 注册表 / 常见安装位置)
    $gameRoot = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gameRoot)) {
        Write-Host ""
        Write-Host " 找不到游戏目录（未找到 BattleTech.exe）。" -ForegroundColor Yellow
        Write-Host " 请用 -gameRoot 参数指定游戏安装路径，例如：" -ForegroundColor Yellow
        Write-Host '   powershell -File "工具\安装.ps1" -gameRoot "E:\Steam\steamapps\common\BATTLETECH"' -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
} else {
    # 用户明确指定: 校验不通过就直接报错, 不回退(避免静默装到别处)
    if (-not [IO.File]::Exists((Join-Path $gameRoot "BattleTech.exe"))) {
        Write-Host ""
        Write-Host (" 指定的游戏目录无效（未找到 BattleTech.exe）: " + $gameRoot) -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
}
$gameRoot = [IO.Path]::GetFullPath(([string]$gameRoot).Trim())
if ($gameRoot.Length -gt 3) { $gameRoot = $gameRoot.TrimEnd('\') }

Say "================================================"
Say " BATTLETECH / RogueTech 简体中文补丁 安装"
Say "================================================"
Say (" 游戏目录: " + $gameRoot)

# ---------- 游戏运行中则拒绝 ----------
$proc = @(Get-Process -Name BattleTech,RogueLauncher -ErrorAction SilentlyContinue)
if ($proc) {
    Write-Host ""
    $pids = [string]::Join(', ', @($proc | ForEach-Object { $_.Name + ':' + $_.Id }))
    Write-Host (" 检测到游戏或启动器正在运行（" + $pids + "）。") -ForegroundColor Yellow
    Write-Host " 请先完全退出游戏，再重新运行本安装。" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

$packRoot = Split-Path $PSScriptRoot -Parent
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$backupDir = Join-Path $packRoot ("backup\" + $stamp)
[void][IO.Directory]::CreateDirectory($backupDir)
$script:installLog = Join-Path $backupDir 'install.log'
[Diagnostics.Stopwatch]$script:installTimer = [Diagnostics.Stopwatch]::StartNew()
[IO.File]::WriteAllText($script:installLog, ("安装开始: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "`r`n"), $enc)
Say (" 备份目录: backup\" + $stamp)
Say (" 安装日志: backup\" + $stamp + "\install.log")

# 汉化 DLL 与非 DLL 资源的固定清单。先定义清单，再做一次完整预检查，
# 确保任何游戏文件被覆盖前就能发现安装包不完整。
$dllList = @(
    'BattleTech_Data\Managed\Assembly-CSharp.dll',
    'BattleTech_Data\Managed\battletech_core.dll',
    'Mods\Core\Abilifier\Abilifier.dll',
    'Mods\Core\CustomAmmoCategories\AttackImprovementMod.dll',
    'Mods\Core\CustomAmmoCategories\CustomAmmoCategories.dll',
    'Mods\Core\CustomAmmoCategories\CustomAmmoCategoriesHelper.dll',
    'Mods\Core\CustomAmmoCategories\CustomAmmoCategoriesPrivate.dll',
    'Mods\Core\CustomActivatableEquipment\CustomActivatableEquipment.dll',
    'Mods\Core\CustomComponents\CustomComponents.dll',
    'Mods\Core\CustomFilters\CustomFilters.dll',
    'Mods\Core\CustomSalvage\CustomSalvage.dll',
    'Mods\Core\CustomUnits\CustomDeploy.dll',
    'Mods\Core\CustomUnits\CustomUnits.dll',
    'Mods\Core\CustomUnits\CustomUnitsHelper.dll',
    'Mods\Core\CustomUnits\NAudio.dll',
    'Mods\Core\DropCostsEnhanced\DropCostsEnhanced.dll',
    'Mods\Core\IRTweaks\IRTweaks.dll',
    'Mods\Core\IttyBittyLivingSpace\IttyBittyLivingSpace.dll',
    'Mods\Core\LootMagnet\LootMagnet.dll',
    'Mods\Core\MechAffinity\MechAffinity.dll',
    'Mods\Core\MechEngineer\MechEngineer.dll',
    'Mods\Core\PilotHealthPopup\PilotHealthPopup.dll',
    'Mods\Core\Pilot_Fatigue\Pilot_Fatigue.dll',
    'Mods\Core\StrategicOperations\StrategicOperations.dll',
    'Mods\Core\TisButAScratch\TisButAScratch.dll',
    'Mods\WarTechIIC\WarTechIIC.dll'
)
$assetList = @(
    'BattleTech_Data\StreamingAssets\font',
    'BattleTech_Data\StreamingAssets\data\VersionManifest.csv'
)
$steamAssemblyRel = 'BattleTech_Data\Managed\Assembly-CSharp.dll'
$gogAssemblyRel = '版本\GOG\BattleTech_Data\Managed\Assembly-CSharp.dll'

function BackupAndCopy($src, $dst, $label) {
    if ([IO.File]::Exists($src)) {
        if ([IO.Directory]::Exists($dst)) { throw ("目标路径类型冲突（需要文件）: " + $label + " -> " + $dst) }
        if ([IO.File]::Exists($dst)) {
            # 备份保留原目录结构(相对游戏根), 一键还原时直接按相对路径覆盖回去
            $rel = $dst.Substring($gameRoot.Length).TrimStart('\')
            $bak = Join-Path $backupDir $rel
            $bakParent = Split-Path $bak -Parent
            if (-not [IO.Directory]::Exists($bakParent)) { [void][IO.Directory]::CreateDirectory($bakParent) }
            [IO.File]::Copy($dst, $bak, $true)
        }
        $dir = Split-Path $dst -Parent
        if (-not [IO.Directory]::Exists($dir)) { [void][IO.Directory]::CreateDirectory($dir) }
        [IO.File]::Copy($src, $dst, $true)
        return $true
    }
    if ([IO.Directory]::Exists($src)) {
        if ([IO.File]::Exists($dst)) { throw ("目标路径类型冲突（需要目录）: " + $label + " -> " + $dst) }
        # 目录资源（如 Unity font）按文件逐个备份和复制，保持还原脚本可识别的路径。
        if ([IO.Directory]::Exists($dst)) {
            foreach ($old in [IO.Directory]::GetFiles($dst, '*', [IO.SearchOption]::AllDirectories)) {
                $rel = $old.Substring($gameRoot.Length).TrimStart('\')
                $bak = Join-Path $backupDir $rel
                $bakParent = Split-Path $bak -Parent
                if (-not [IO.Directory]::Exists($bakParent)) { [void][IO.Directory]::CreateDirectory($bakParent) }
                [IO.File]::Copy($old, $bak, $true)
            }
        }
        foreach ($item in [IO.Directory]::GetFiles($src, '*', [IO.SearchOption]::AllDirectories)) {
            $rel = $item.Substring($src.Length).TrimStart('\')
            $target = Join-Path $dst $rel
            $targetParent = Split-Path $target -Parent
            if (-not [IO.Directory]::Exists($targetParent)) { [void][IO.Directory]::CreateDirectory($targetParent) }
            [IO.File]::Copy($item, $target, $true)
        }
        return $true
    }
    throw ("包内缺少必需文件或目录: " + $label + " -> " + $src)
}

# 工具脚本统一调用方式。关键工具失败时立即停止，避免留下“看似完成”的半套安装。
function RunTool($script, $extraArgs) {
    $sp = Join-Path $PSScriptRoot $script
    if (-not (Test-Path $sp)) { throw ("缺少安装工具: " + $script) }
    $arg = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $sp) + $extraArgs
    # 这些工具本来各自递归枚举 Mods。复用安装时生成的文件清单，避免每个
    # 子进程都重新遍历数万文件；工具仍保留自身字段与路径过滤规则。
    $indexedTools = @('fold-apply.ps1','apply-fields.ps1','apply-words.ps1','apply-norm.ps1','apply-tags.ps1','clean-metadata.ps1')
    if ($script -in $indexedTools -and -not [string]::IsNullOrWhiteSpace($script:modsJsonFileList) -and
        -not ($extraArgs -contains '-fileList')) {
        $arg += @('-fileList', $script:modsJsonFileList)
    }
    Write-Host ("      正在处理: " + $script + " ...") -ForegroundColor DarkGray
    LogLine ((Get-Date -Format 'HH:mm:ss') + " RUN " + $script)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $output = @(& powershell @arg 2>&1)
    $rc = $LASTEXITCODE
    $timer.Stop()
    foreach ($line in $output) {
        $text = [string]$line
        if (-not [string]::IsNullOrWhiteSpace($text)) { Write-Host ("      " + $text); LogLine $text }
    }
    LogLine ((Get-Date -Format 'HH:mm:ss') + " DONE " + $script + " " + [math]::Round($timer.Elapsed.TotalSeconds, 1) + "s")
    if ($rc -ne 0) { throw ($script + " 返回码 " + $rc) }
}

function AssertPackageInputs {
    $missing = New-Object 'System.Collections.Generic.List[string]'
    $mustExist = @(
        @{ Path = (Join-Path $packRoot 'strings_zh-CN.csv'); Type = 'Leaf' },
        @{ Path = (Join-Path $packRoot 'Mods'); Type = 'Container' }
    )
    foreach ($item in $mustExist) {
        if (-not (Test-Path -LiteralPath $item.Path -PathType $item.Type)) {
            [void]$missing.Add($item.Path)
        }
    }
    foreach ($rel in ($dllList + $assetList)) {
        $p = Join-Path $packRoot $rel
        # 资源清单既可能是单文件（当前 font 就是文件），也可能是目录。
        # 先按实际包内类型判断；不存在时统一按 Leaf 检查并报告缺失。
        $type = if ([IO.Directory]::Exists($p)) { 'Container' } else { 'Leaf' }
        if (-not (Test-Path -LiteralPath $p -PathType $type)) {
            [void]$missing.Add($p)
        }
    }
    $gogAssembly = Join-Path $packRoot $gogAssemblyRel
    if (-not (Test-Path -LiteralPath $gogAssembly -PathType Leaf)) {
        [void]$missing.Add($gogAssembly)
    }
    $body = [IO.File]::ReadAllText($script:installerPath, [Text.Encoding]::UTF8)
    $refs = [regex]::Matches($body, "'([^']+\.(?:ps1|tsv))'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    foreach ($rel in $refs) {
        $p = Join-Path $PSScriptRoot $rel
        if (-not (Test-Path -LiteralPath $p)) { [void]$missing.Add($p) }
    }
    if ($missing.Count -gt 0) {
        throw ("安装包缺少 " + $missing.Count + " 个必需文件:`r`n  " + [string]::Join("`r`n  ", $missing))
    }
    Ok "安装包预检查通过"
}

function ResolveGameEdition {
    $steamAssembly = Join-Path $packRoot $steamAssemblyRel
    $gogAssembly = Join-Path $packRoot $gogAssemblyRel
    $selected = ([string]$edition).Trim()
    if ([string]::IsNullOrWhiteSpace($selected)) {
        Write-Host ""
        Write-Host "请选择游戏版本：" -ForegroundColor Cyan
        Write-Host "  [1] Steam"
        Write-Host "  [2] GOG"
        $answer = (Read-Host "请输入 1 或 2").Trim()
        if ($answer -eq '1') { $selected = 'Steam' }
        elseif ($answer -eq '2') { $selected = 'GOG' }
        else { throw "版本选择无效，请重新运行并选择 Steam 或 GOG。" }
    }
    if ($selected -notin @('Steam','GOG')) {
        throw ("版本参数无效: " + $selected + "。请使用 -edition Steam 或 -edition GOG。")
    }
    $script:gameEdition = $selected
    $script:selectedAssembly = if ($selected -eq 'GOG') { $gogAssembly } else { $steamAssembly }
    Say (" 已选择游戏版本: " + $selected)
}

AssertPackageInputs
ResolveGameEdition

# ---------- 1) 翻译总表 ----------
Step 1 "写入翻译总表"
$csvName = "strings_zh-CN.csv"
$csvDst = Join-Path $gameRoot "BattleTech_Data\StreamingAssets\data\localization\$csvName"
if (BackupAndCopy (Join-Path $packRoot $csvName) $csvDst "翻译总表") {
    $n = @([IO.File]::ReadAllLines($csvDst, [Text.Encoding]::UTF8)).Count
    Ok ("已写入，" + $n + " 行")
}

# ---------- 2) 亲和数据 ----------
Step 2 "写入 MechAffinity 亲和数据"
$affSrc = Join-Path $packRoot "Mods\Core\MechAffinity\AffinityDefs"
if ([IO.Directory]::Exists($affSrc)) {
    $cnt = 0
    foreach ($f in [IO.Directory]::GetFiles($affSrc, "*.json")) {
        $dst = Join-Path $gameRoot ("Mods\Core\MechAffinity\AffinityDefs\" + [IO.Path]::GetFileName($f))
        if (BackupAndCopy $f $dst "亲和数据") { $cnt++ }
    }
    Ok ("" + $cnt + " 个文件")
} else { throw "包内缺少亲和数据目录: $affSrc" }

# ---------- 3) 本地化表与其余模组数据 ----------
# 包内 Mods\ 下还有各模组的 Localization.json（CULTURE_ZH_CN 译文）与
# CustomLocalization 的 mod.json 等数据文件。这些译文只存在于包内 ——
# 安装脚本的词典（dict-all.tsv）不带它们：fold-apply 只处理
# Details/YangsThoughts/StockRole 三种字段，且显式排除 Localization 目录。
# 若不复制，界面里的一大批装备、技能、背景说明仍会是英文。
# DLL 由下一步按固定清单处理，这里跳过 *.dll 避免重复写入。
Step 3 "写入模组本地化表与数据文件"
$dataSrc = Join-Path $packRoot "Mods"
$dataCnt = 0
if ([IO.Directory]::Exists($dataSrc)) {
    foreach ($f in [IO.Directory]::GetFiles($dataSrc, "*", [IO.SearchOption]::AllDirectories)) {
        $rel = $f.Substring($dataSrc.Length).TrimStart('\')
        if ($rel -like "*.dll") { continue }
        # 工具运行时生成的备份目录不能随包复制进游戏。ModTek 会按文件名
        # 识别其中的 .json.bak，并把它们再次当作正式定义加载，造成重复键。
        if ($rel -match '(^|\\)_bak_faction(\\|$)' -or $rel -like "*.json.bak") { continue }
        $dst = Join-Path $gameRoot ("Mods\" + $rel)
        [void](BackupAndCopy $f $dst $rel)
        $dataCnt++
        if (($dataCnt % 100) -eq 0) { Write-Host ("      已处理 " + $dataCnt + " 个数据文件...") -ForegroundColor DarkGray }
    }
    Ok ("" + $dataCnt + " 个文件")
} else { Warn "包内缺少 Mods 目录，已跳过" }

# 用户额外安装的 MWSphere 语音包不在发布包内；若存在则仅补写 credits 的
# CULTURE_ZH_CN，并将原文件纳入本次备份。没有该语音包时安全跳过。
RunTool 'apply-voicepacks.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-backupRoot', $backupDir)

# ---------- 4) 汉化 DLL ----------
# 这些 DLL 出自月光石头的《BATTLETECH 汉化工具》，通过反编译修改硬编码
# 字符串实现界面汉化。Assembly-CSharp.dll 按用户选择的 Steam/GOG 版本替换，
# 其余 DLL 按原始相对路径逐个替换。
Step 4 "写入汉化 DLL（界面文字）"
$dllCnt = 0
foreach ($rel in $dllList) {
    $s = if ($rel -eq $steamAssemblyRel) { $script:selectedAssembly } else { Join-Path $packRoot $rel }
    $d = Join-Path $gameRoot $rel
    [void](BackupAndCopy $s $d $rel)
    $dllCnt++
    if (($dllCnt % 10) -eq 0) { Write-Host ("      已处理 " + $dllCnt + " 个 DLL...") -ForegroundColor DarkGray }
}
Ok ("已写入 " + $dllCnt + " 个 DLL（" + $script:gameEdition + " 版）")

$assetCnt = 0
foreach ($rel in $assetList) {
    $s = Join-Path $packRoot $rel
    $d = Join-Path $gameRoot $rel
    [void](BackupAndCopy $s $d $rel)
    $assetCnt++
}
Ok ("已写入 " + $assetCnt + " 个汉化资源（字体 / 资源清单）")

# ---------- 5) 清理遗留备份 ----------
# MechAffinity 会把自己目录下的所有文件都当作定义加载，.zhbak 会导致
# 定义重复、键冲突，进而读档失败，必须移出游戏目录。
Step 5 "清理遗留的 .zhbak 备份"
$zhs = @(Get-ChildItem (Join-Path $gameRoot "Mods") -Recurse -File -Force -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -like "*.zhbak*" })
if ($zhs.Count -eq 0) { Ok "无遗留备份" }
else {
    foreach ($z in $zhs) {
        $rel = $z.FullName.Substring($gameRoot.Length).TrimStart("\")
        # 保留目录结构, 放到 backup\<时间戳>\zhbak\<相对路径> 下, 便于追溯
        $bak = Join-Path $backupDir ("zhbak\" + $rel)
        $bakParent = Split-Path $bak -Parent
        if (-not [IO.Directory]::Exists($bakParent)) { [void][IO.Directory]::CreateDirectory($bakParent) }
        [IO.File]::Move($z.FullName, $bak)
    }
    Ok ("已移出 " + $zhs.Count + " 个文件")
}

# 早期汉化工具把 FactionDef 的原文件备份到 Mods 内的 _bak_faction。
# ModTek 会把其中的 .json.bak 仍按 FactionDef 加载，造成重复键并卡死读档。
$badBakDirs = @(Get-ChildItem (Join-Path $gameRoot "Mods") -Recurse -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq '_bak_faction' })
if ($badBakDirs.Count -eq 0) { Ok "无遗留的 faction 备份目录" }
else {
    foreach ($bd in $badBakDirs) {
        $rel = $bd.FullName.Substring($gameRoot.Length).TrimStart("\")
        $dst = Join-Path $backupDir ("bakdirs\" + $rel)
        $parent = Split-Path $dst -Parent
        if (-not [IO.Directory]::Exists($parent)) { [void][IO.Directory]::CreateDirectory($parent) }
        Move-Item -LiteralPath $bd.FullName -Destination $dst -Force
    }
    Ok ("已移出 " + $badBakDirs.Count + " 个 faction 备份目录")
}

# ---------- 6) 禁用启动器安全检查并清理 ModTek 缓存 ----------
# RogueLauncher 启动游戏前会做哈希校验，把汉化过的文件判为 "file tamper
# detected" 并用缓存里的英文原版覆盖回 Mods（实测一次启动 7400+ 条），
# 汉化因此大面积失效。把 SafeLaunchDisabled 设为 true 可跳过该覆盖。
# 同时移出 ModTek 的定义数据库与静态缓存。仅清 Cache 不会刷新
# .modtek\Database 中的 MetadataDatabase.db/database_cache.json，旧存档事件与
# 机师定义会继续从旧数据库读取，导致磁盘 JSON 已中文但界面仍显示英文。
Step 6 "禁用启动器校验并重建 ModTek 缓存"
$modtekRoot = Join-Path $gameRoot "Mods\.modtek"
$movedModtekState = 0
foreach ($stateName in @('Cache', 'Database')) {
    $statePath = Join-Path $modtekRoot $stateName
    if (-not (Test-Path -LiteralPath $statePath)) { continue }
    $stateBackup = Join-Path $backupDir (Join-Path 'modtek-state' $stateName)
    $stateBackupParent = Split-Path -Parent $stateBackup
    if (-not (Test-Path -LiteralPath $stateBackupParent)) {
        [void][IO.Directory]::CreateDirectory($stateBackupParent)
    }
    if (Test-Path -LiteralPath $stateBackup) {
        $stateBackup = Join-Path $backupDir (Join-Path 'modtek-state' ($stateName + '-' + (Get-Date -Format 'HHmmss')))
    }
    Move-Item -LiteralPath $statePath -Destination $stateBackup -Force
    $movedModtekState++
    Ok ("已备份并移出 ModTek " + $stateName + "，游戏下次启动时会重建")
}
if ($movedModtekState -eq 0) { Ok "未发现 ModTek Cache/Database，跳过清理" }
RunTool 'fix-launcher-safe.ps1' @('-backupRoot', $backupDir)
Ok "完成"

# 建立本次安装的 Mods JSON 文件索引，供多个字段处理器复用。
$script:modsJsonFileList = Join-Path $backupDir 'mods-json-files.txt'
$modsRootForIndex = Join-Path $gameRoot 'Mods'
$jsonPaths = Get-ChildItem $modsRootForIndex -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue |
             ForEach-Object { $_.FullName }
[IO.File]::WriteAllLines($script:modsJsonFileList, [string[]]$jsonPaths, (New-Object Text.UTF8Encoding $false))
Ok ("已建立 JSON 文件索引：" + $jsonPaths.Count + " 个文件")

# ---------- 7) 数据字段汉化 ----------
Step 7 "汉化数据字段（Details / YangsThoughts / StockRole）"
RunTool 'fold-apply.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                           '-pairs', (Join-Path $PSScriptRoot 'dict-all.tsv'),
                           '-extraDict', (Join-Path $PSScriptRoot 'dict-details-direct.tsv'),
                           '-csv', (Join-Path $packRoot 'strings_zh-CN.csv'),
                           '-backupRoot', (Join-Path $packRoot 'backup\Mods-defs'))
Ok "完成"

# ---------- 8) 装备特性说明汉化 ----------
# BonusDescriptions_*.json 的 Short/Long/Full 是装备"特性"栏的显示文本
Step 8 "补译装备特性说明（BonusDescriptions）"
RunTool 'apply-bonus.ps1' @('-dir', (Join-Path $gameRoot 'Mods'),
                            '-pairs', (Join-Path $PSScriptRoot 'dict-bonus.tsv'),
                            '-backupRoot', (Join-Path $packRoot 'backup\Mods-bonus'))
Ok "完成"

# ---------- 8b) 游戏本体 stat 说明模板汉化 ----------
# BattleTech_Data\StreamingAssets\data\simGameStatDesc\*.json 的 Result 模板
# 不查 CSV, 直接在 JSON 里显示, 必须就地替换
Step 9 "汉化游戏本体状态说明模板（simGameStatDesc）"
RunTool 'apply-statdesc.ps1' @('-game', $gameRoot,
                               '-pairs', (Join-Path $PSScriptRoot 'dict-statdesc.tsv'),
                               '-backupRoot', (Join-Path $packRoot 'backup\simGameStatDesc'))
# 模组自带的 SimGameStatDesc(Aircademy/IRTweaks/IttyBittyLivingSpace/
# MissionControl/RogueTechCore 等 40 余个) 同样不查 CSV, 里面的合约报酬、
# 声望变化、维护费用等结果模板同样是玩家可见文本。
$modStatDict = Join-Path $PSScriptRoot 'dict-statdesc-mod.tsv'
if ([IO.File]::Exists($modStatDict)) {
    RunTool 'apply-statdesc.ps1' @('-game', $gameRoot,
                                   '-pairs', $modStatDict,
                                   '-ModsOnly',
                                   '-backupRoot', (Join-Path $packRoot 'backup\simGameStatDesc-mod'))
}
Ok "完成"

# ---------- 9) 对话/字幕汉化 ----------
# 游戏对 dialogueContent[].words 不查 CSV, 直接显示 JSON 里的字符串,
# 必须就地替换(月光石头的本地化表虽有译文, 但源文件未被改写, 用不上)
Step 10 "汉化对话与字幕（words）"
RunTool 'apply-words.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                            '-pairs', (Join-Path $PSScriptRoot 'dict-words.tsv'),
                            '-backupRoot', (Join-Path $packRoot 'backup\Mods-words'))
Ok "完成"

# ---------- 9b) 任务标题/描述/物品界面名/合约简报 ----------
# 这些字段同样不查 CSV(或查询优先级低), 一并就地补译
# shortDescription/longDescription 是合约简报正文, ShortDesc 是技能/AI 能力简述;
# 这三个字段曾被完全遗漏, 玩家在合约界面看到的是整段英文
Step 11 "补译任务标题、目标描述、物品界面名与合约简报"
foreach ($pair in @(
    @{ f = 'title';       d = 'dict-title.tsv' },
    @{ f = 'description'; d = 'dict-desc.tsv' },
    @{ f = 'UIName';      d = 'dict-uiname.tsv' },
    @{ f = 'ErrorMessage'; d = 'dict-errmsg.tsv' }
)) {
    $dict = Join-Path $PSScriptRoot $pair.d
    if ([IO.File]::Exists($dict)) {
        RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                     '-pairs', $dict,
                                     '-fields', $pair.f,
                                     '-csv', $csvDst,
                                     '-backupRoot', (Join-Path $packRoot 'backup\Mods-fields'))
    }
}
# Quicsell 武器定义的 Description.Name 与状态效果名直接显示在装备详情中，
# 不经过 CSV。限定到三个单发火炮定义，避免把其它模组的内部 Name 当作显示名。
$qsDict = Join-Path $PSScriptRoot 'dict-quicsell.tsv'
if ([IO.File]::Exists($qsDict)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $qsDict,
                                 '-fields', 'Name',
                                 '-pathLike', 'Optionals\Quicsell\Weapons\Weapon_Artillery_LongTom_Oneshot_Quicsell.json,Optionals\Quicsell\Weapons\Weapon_Artillery_Sniper_Oneshot_Quicsell.json,Optionals\Quicsell\Weapons\Weapon_Artillery_Thumper_Oneshot_Quicsell.json',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-quicsell'))
}
# QuicksellCustoms 的机甲详情与 YangsThoughts 直接来自 JSON，必须就地补译。
$qscDetailsDict = Join-Path $PSScriptRoot 'dict-quicksellcustoms.tsv'
if ([IO.File]::Exists($qscDetailsDict)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $qscDetailsDict,
                                 '-fields', 'Details,YangsThoughts',
                                 '-pathLike', 'Optionals\QuicksellCustoms',
                                 '-JsonValue',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-quicksellcustoms'))
}
# QuicksellCustoms 的装备、状态效果、模式和 StockRole 显示字段直接来自 JSON，
# 不经过总表。只限定该模组，避免改写其它模组的内部 Name 标识符。
$qscDisplayDict = Join-Path $PSScriptRoot 'dict-quicksellcustoms-display.tsv'
if ([IO.File]::Exists($qscDisplayDict)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $qscDisplayDict,
                                 '-fields', 'Name,UIName,StockRole',
                                 '-pathLike', 'Optionals\QuicksellCustoms',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-quicksellcustoms-display'))
}
# dict-brief.tsv 的译文保留 JSON 转义形式（其中的 \n 是真正的换行），
# 必须使用 -JsonValue，避免旧版本把反斜杠翻倍成游戏可见的“\N”。
$briefDict = Join-Path $PSScriptRoot 'dict-brief.tsv'
if ([IO.File]::Exists($briefDict)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $briefDict,
                                 '-fields', 'shortDescription,longDescription,ShortDesc',
                                 '-JsonValue',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-fields'))
}
# 事件及背景事件直接读取 JSON 的 Description.Name/Details 与选项 Name/Details，
# 不经过 strings_zh-CN.csv。限定事件目录，避免把其它模组的内部 Name 改成中文。
$eventDict = Join-Path $PSScriptRoot 'dict-events.tsv'
if ([IO.File]::Exists($eventDict)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $eventDict,
                                 '-fields', 'Name,Details',
                                 '-pathLike', 'events,backgroundEvent',
                                 '-JsonValue',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-events'))
}
# 自动从各模组 Localization/ZH 表覆盖所有事件正文、标题和选项，
# 解决人工事件词典只覆盖少量条目导致同类英文漏翻的问题。
RunTool 'apply-event-localization.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                         '-backupRoot', (Join-Path $packRoot 'backup\Mods-events-auto'))
# 个别模组 mod.json 的 description 是玩家可见的设置说明, 需 -IncludeModJson 放行
$descExtra = Join-Path $PSScriptRoot 'dict-desc-extra.tsv'
if ([IO.File]::Exists($descExtra)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $descExtra,
                                 '-fields', 'description',
                                 '-IncludeModJson',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-fields'))
}
Ok "完成"

# ---------- 9d) 模组本地化覆盖表（mod_localized_text.json） ----------
# 8 个模组用这个文件覆盖引擎文本(战斗浮动提示、菜单按钮、台词、光照面板)。
# 游戏先按英文原文查 CSV 挤兑键, 查不到就退回文件里的英文原值 —— 所以
# 既要补 CSV 缺的键, 也要把文件里的值就地改成中文(CodeWords 已全员中文,
# 证明这条通道有效)。数组项(战斗台词)一并处理。
Step 12 "汉化模组本地化覆盖表（mod_localized_text）"
$mtDict = Join-Path $PSScriptRoot 'dict-modtext.tsv'
if ([IO.File]::Exists($mtDict)) {
    RunTool 'apply-modtext.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                  '-pairs', $mtDict,
                                  '-backupRoot', (Join-Path $packRoot 'backup\Mods-modtext'))
}
Ok "完成"

# ---------- 9e) IRTweaks / CustomFilters 菜单 ----------
# IRTweaks 的难度设置菜单与 CustomFilters 的库存页签: 这些文件的
# Name/Tooltip/Text/Caption 直接显示。字段名在别处可能是内部标识符或
# 匹配键, 所以用 -pathLike 把处理范围压到这两个模组的菜单文件。
Step 13 "汉化难度设置菜单与库存页签"
$menuDict = Join-Path $PSScriptRoot 'dict-menus.tsv'
if ([IO.File]::Exists($menuDict)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $menuDict,
                                 '-fields', 'Name,Tooltip,Text,Caption',
                                 '-pathLike', 'IRTweaks\Menus,CustomFilters\RogueTechTabs.json',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-menus'))
}
Ok "完成"
# ---------- 9f) MechEngineer 部位命名模板 ----------
# Settings.json 的 MechLocationNamingTemplates 决定步兵/原型机甲/机甲小队/
# VTOL/四足机甲等特殊单位在机甲实验室里各部位的显示名(如 "Trooper 5")。
Step 14 "汉化特殊单位部位显示名"
$locDict = Join-Path $PSScriptRoot 'dict-locnames.tsv'
if ([IO.File]::Exists($locDict)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $locDict,
                                 '-fields', 'Label',
                                 '-pathLike', 'MechEngineer\Settings.json',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-locnames'))
}
# 战斗中"臂装精度加成"在提示里的显示名(WEAPON MOUNT)
$mechFixDict = Join-Path $PSScriptRoot 'dict-mechfix.tsv'
if ([IO.File]::Exists($mechFixDict)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $mechFixDict,
                                 '-fields', 'CombatHUDTooltipName',
                                 '-pathLike', 'MechEngineer\Settings.json',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-mechfix'))
}
# CustomFilters 的库存筛选标签: 只有 DLC / +Blacklisted 两条英文
$cfDict = Join-Path $PSScriptRoot 'dict-cf.tsv'
if ([IO.File]::Exists($cfDict)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $cfDict,
                                 '-fields', 'Label',
                                 '-pathLike', 'CustomFilters\Settings.json',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-cf'))
}
Ok "完成"

# ---------- 9g) 角色创建背景与合约结束评价 ----------
# RogueBackgrounds 的 OptionName/OptionDescription/Intro 是角色创建界面里
# 背景选项的标题与说明; 各派系 faction_*.json 的 MissionSuccessStatements /
# GoodFaithFailureStatements / BadFaithFailureStatements 是任务结束时雇主对
# 你的评价。两类都是直接显示 JSON 里的字符串。
# 译文取自各模组 Localization/ZH 表(已是 JSON 转义形式, 含 0x1F 占位符),
# 所以用 -JsonValue 避免二次转义。
Step 15 "汉化角色背景与合约评价"
$bgDict = Join-Path $PSScriptRoot 'dict-bg.tsv'
if ([IO.File]::Exists($bgDict)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $bgDict,
                                 '-fields', 'OptionName,OptionDescription,Intro,MissionSuccessStatement,GoodFaithFailureStatement,BadFaithFailureStatement',
                                 '-pathLike', 'RogueBackgrounds,RogueTechCore\Factions',
                                 '-JsonValue',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-bg'))
}
Ok "完成"

# FactionDef 的评价文本使用数组字段（MissionSuccessStatements 等），
# 通用字段替换器无法处理；必须用专用数组处理器。备份放到包外，
# 避免 .bak 被 ModTek 当成正式定义加载。
$factionDict = Join-Path $PSScriptRoot 'faction_tr_all_merged.tsv'
$factionDir = Join-Path $gameRoot 'Mods\Core\RogueTechCore\Factions'
if ([IO.File]::Exists($factionDict) -and [IO.Directory]::Exists($factionDir)) {
    RunTool '_apply-faction.ps1' @('-Pairs', $factionDict,
                                   '-FactionDir', $factionDir,
                                   '-BackupRoot', (Join-Path $packRoot 'backup\Mods-faction'))
}

# ---------- 9h) 合约名、闪点简报、地图名与其它零散显示字段 ----------
# contractName 是合约列表里显示的合约名; FlashpointShortDescription 是闪点
# 简报; FriendlyName 是地图/环境显示名; BioDescription 是背景短文;
# BonusValueA/B 是加成说明; ErrorOverweight 是改装校验的报错文字。
# 译文同样取自各模组 Localization/ZH 表(-JsonValue)。
Step 16 "汉化合约名、闪点简报与地图名"
$extraDict = Join-Path $PSScriptRoot 'dict-extra.tsv'
if ([IO.File]::Exists($extraDict)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $extraDict,
                                 '-fields', 'FlashpointShortDescription,BioDescription,contractName,FriendlyName,AssignedCastDescription,viewLabel,ErrorOverweight,BonusValueA,BonusValueB',
                                 '-pathLike', 'Flashpoints,RogueFlashPointModule,RogueBackgrounds,RogueTechCore,CustomMaps,CAB-Maps,ExtendedConversations,RGoBoom,MechEngineer,EnviromentalDesignMasks',
                                 '-JsonValue',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-extra'))
}
Ok "完成"
# Quirk_*.json 的 Description.Name 是显示名(装备特性栏), 包内不含这些定义
# 文件, 只能靠词典在目标机应用。Name 字段在别处可能是内部标识符, 所以
# 限定只处理 Quirks 目录下的文件。
Step 17 "补译 Quirk 特性显示名"
$quirkDict = Join-Path $PSScriptRoot 'dict-quirk.tsv'
if ([IO.File]::Exists($quirkDict)) {
    RunTool 'apply-quirk.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                '-pairs', $quirkDict,
                                '-backupRoot', (Join-Path $packRoot 'backup\Mods-quirk'))
}
# RogueMunitions 的状态效果 Description.Name 直接显示在战斗浮动提示中，
# 不经过 Details/CSV；限定到该模组，避免全局替换其它定义中的内部 Name。
$effectDict = Join-Path $PSScriptRoot 'dict-effect.tsv'
if ([IO.File]::Exists($effectDict)) {
    RunTool 'apply-fields.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                                 '-pairs', $effectDict,
                                 '-fields', 'Name',
                                 '-pathLike', 'Core\RogueMunitions',
                                 '-backupRoot', (Join-Path $packRoot 'backup\Mods-effects'))
}
Ok "完成"

# ---------- 10) 装备分类显示名 ----------
Step 18 "汉化装备分类显示名"
RunTool 'apply-category-zh.ps1' @('-gameRoot', $gameRoot)
Ok "完成"

# ---------- 10b) 界面弹窗兜底键 + 性别分支 ----------
# ArmorRepair / CustomUnits 的维修弹窗、载具报废提示等文本由 DLL 拼接后
# 走总表查表, 表中缺键就显示英文。这里补齐这些键。
# MissionControl 的 contractTypeBuilds\*\common.jsonc 定义的任务目标
# Title / ProgressFormat 同样走总表查表(与原版 objective 同机制), 缺键则
# 显示英文(如 "DEFECTOR MUST SURVIVE AND REACH THE EVAC ZONE")。
Step 19 "补充界面弹窗与任务目标兜底键"
RunTool 'apply-uikeys.ps1' @('-csv', $csvDst) | Out-Null
RunTool 'apply-pronouns.ps1' @('-csv', $csvDst) | Out-Null
RunTool 'apply-mckeys.ps1' @('-csv', $csvDst) | Out-Null
Ok "完成"

# 载具的 Details 由 DLL 在运行时拼好(含 "#武器:" 段)后整段查表, 因此必须把
# "整段描述" 作为 key 收录。这些条目来自月光石头新版汉化包, 随包分发总表已含;
# 若用户把包放在工具同机目录, 也可用 -moonstone 指定源目录做增量合并。
if (-not [string]::IsNullOrWhiteSpace($moonstone)) {
    OptionalStep 20 "合并月光石头新版条目"
    RunTool 'merge-moonstone.ps1' @('-source', $moonstone, '-csv', $csvDst) | Out-Null
    Ok "完成"
} else {
    OptionalStep 20 "跳过月光石头新版条目（未指定 -moonstone）"
    Ok "未执行"
}

# 译文里的 {角色.Gender?分支:值} 若留着英文动词, 句子里会半英半中
# (例: "He acts 起来就像 he's 我的老板似的")。中文无动词变位, 两分支同值。
Step 21 "修复译文中的性别分支残留英文"
RunTool 'fix-gender.ps1' @('-mods', (Join-Path $gameRoot 'Mods')) | Out-Null
Ok "完成"

# 机师个性 tooltip("罪犯"等)的文字来自 MDD 数据库的 Tag 表, 该表由 ModTek
# 从各模组 tags\*.json 构建。这里把模组 tag 文件的 FriendlyName/Description
# 就地汉化; 基础游戏独有、模组没有的 tag(如 pilot_criminal)另生成覆盖文件,
# 由 ModTek 的 CustomTag 机制覆盖("Updated tag: xxx in MDDB")。
Step 22 "汉化机师个性/亲和 tag 文本"
RunTool 'apply-tags.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                           '-csv', $csvDst,
                           '-extraPairs', (Join-Path $PSScriptRoot 'dict-tags.tsv'),
                           '-backupRoot', (Join-Path $packRoot 'backup\Mods-tags')) | Out-Null
RunTool 'apply-tagkeys.ps1' @('-csv', $csvDst) | Out-Null
RunTool 'apply-basetags.ps1' @('-gameRoot', $gameRoot,
                               '-csv', $csvDst,
                               '-backupRoot', (Join-Path $packRoot 'backup\Mods-tagoverride')) | Out-Null
Ok "完成"

# ---------- 11) 控制字符与标点空格 ----------
# 别名分隔符必须按文件类型区分: JSON 用半角逗号, CSV 用紧贴的 0x1F。
# 写成 "[[OBJ <0x1F> {...}]]"(两侧带空格)会让游戏报 INVALID ALIAS,
# 界面回退显示"错误"(日志 output_log.txt 可见 "INVALID ALIAS SCN_MW ...")。
Step 23 "清理控制字符、标点空格与插值占位符"
RunTool 'fix-ctl.ps1' @('-gameRoot', $gameRoot) | Out-Null
RunTool 'cleanup.ps1' @('-gameRoot', $gameRoot) | Out-Null
RunTool 'fix-interp-punct.ps1' @('-csv', $csvDst)
Ok "完成"

# ---------- 11) 术语归一化与格式修复 ----------
Step 24 "术语归一化与格式修复"
RunTool 'apply-norm.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                           '-backupRoot', (Join-Path $packRoot 'backup\Mods-norm'))
RunTool 'norm-csv.ps1' @('-csv', $csvDst)
RunTool 'clean-metadata.ps1' @('-mods', (Join-Path $gameRoot 'Mods'),
                               '-backupRoot', (Join-Path $packRoot 'backup\Mods-metadata'))
Ok "完成"

# ---------- 12) 校验 ----------
Step 25 "校验"
$zhs2 = @(Get-ChildItem (Join-Path $gameRoot "Mods") -Recurse -File -Force -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -like "*.zhbak*" })
if ($zhs2.Count -gt 0) { Warn ("仍有 " + $zhs2.Count + " 个 .zhbak 留在 Mods 下") }
else { Ok "Mods 下无遗留备份文件" }
$csvLine = @([IO.File]::ReadAllLines($csvDst, [Text.Encoding]::UTF8)).Count
Ok ("翻译总表: " + $csvLine + " 行")

# 注册表标识符校验: 单位类型名(UnitTypes_*.json 的 Name)是内部标识符, 绝不能被汉化
# 一旦被译成中文(如 Quad -> 四足), 四足机甲的槽位限制会失效, 报
# "过量 足部驱动器: 该单位在 左臂 中最多只能安装 0 个 / QuadIncompatible 无法与 四足机甲 搭配使用"
# check-registry 发现问题会自动按基线还原(所以这里只提示, 不中断)
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check-registry.ps1') -mods (Join-Path $gameRoot 'Mods')
if ($LASTEXITCODE -ne 0) {
    Warn "检测到标识符被汉化（已自动还原），详见 backup\registry-check.txt"
} else { Ok "注册表标识符正常" }

Say ""
Say "================================================"
Say " 安装完成，请重新启动游戏。"
Say (" 如需回滚，备份在: backup\" + $stamp)
if ($null -ne $script:installTimer) {
    $script:installTimer.Stop()
    Say (" 总耗时: " + [math]::Round($script:installTimer.Elapsed.TotalMinutes, 1) + " 分钟")
}
Say "================================================"
