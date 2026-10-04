# 为"基础游戏 tag"生成中文覆盖文件
#
# 背景: 机师个性 tooltip 的文字来自 MDD 数据库的 Tag 表。基础游戏的 46 个
# pilot tag(如 pilot_criminal)只在游戏本体 MDD\data\tagdata.sql 里定义,
# 玩家改不了它; 但 ModTek 的 CustomTag 机制允许模组用 tags\*.json 覆盖
# 同名 tag("Updated tag: xxx in MDDB")。
#
# 做法: 从 MDD 数据库读出这些 tag 的英文文本 -> 按总表查中文 -> 在
# Mods\Core\MechAffinity\tags\ 生成同名覆盖文件。
param(
    [string]$mods = "",
    [string]$csv = "",
    [string]$gameRoot = "",
    [string]$backupRoot = "",
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($gameRoot)) {
    $gameRoot = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gameRoot)) { Write-Host " 找不到游戏目录" -ForegroundColor Yellow; exit 1 }
}
if ([string]::IsNullOrWhiteSpace($mods)) { $mods = Join-Path $gameRoot 'Mods' }
if ([string]::IsNullOrWhiteSpace($csv)) { $csv = Join-Path $packRoot 'strings_zh-CN.csv' }
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot 'backup\Mods-tagoverride' }

function Normalize([string]$s) {
    $t = $s.ToLower()
    $t = $t -replace "`r`n", 'newline' -replace "`n", 'newline'
    $t = [regex]::Replace($t, '<[^>]*>', '')
    $t = $t.Replace(',', '^').Replace('.', '*')
    $t = [regex]::Replace($t, '["''`]', '')
    $t = [regex]::Replace($t, '\s+', '')
    return $t
}

# 1) 读总表
$dict = New-Object 'System.Collections.Generic.Dictionary[string,string]'
foreach ($l in [IO.File]::ReadLines($csv, [Text.Encoding]::UTF8)) {
    $p = $l.IndexOf(',')
    if ($p -lt 1) { continue }
    $k = $l.Substring(0, $p)
    if (-not $dict.ContainsKey($k)) { $dict[$k] = $l.Substring($p + 1) }
}
Write-Host ("总表键: " + $dict.Count)

# 2) 读 MDD 数据库(用 x86 PowerShell 调 editors 的 System.Data.SQLite)
$dumpPs1 = Join-Path $env:TEMP 'dump_tags.ps1'
$sqliteDll = Join-Path $gameRoot 'BattleTech_Data\StreamingAssets\editors\System.Data.SQLite.dll'
$db = Join-Path $gameRoot 'Mods\.modtek\Database\MetadataDatabase.db'
if (-not (Test-Path $db)) { $db = Join-Path $gameRoot 'BattleTech_Data\StreamingAssets\MDD\MetadataDatabase.db' }
$edDir = Split-Path $sqliteDll -Parent
@"
`$env:PATH = "$edDir;`$env:PATH"
[void][Reflection.Assembly]::LoadFrom("$sqliteDll")
`$conn = New-Object System.Data.SQLite.SQLiteConnection ("Data Source=$db;Version=3;Read Only=True;")
`$conn.Open()
`$cmd = `$conn.CreateCommand()
`$cmd.CommandText = "SELECT Name, FriendlyName, Description FROM Tag WHERE PlayerVisible=1"
`$rd = `$cmd.ExecuteReader()
`$rows = @()
while (`$rd.Read()) {
    `$fn = if (`$rd.IsDBNull(1)) { '' } else { `$rd.GetString(1) }
    `$de = if (`$rd.IsDBNull(2)) { '' } else { `$rd.GetString(2) }
    `$rows += ("{0}|{1}|{2}" -f `$rd.GetString(0), `$fn, `$de)
}
`$rd.Close(); `$conn.Close()
`$rows | Set-Content '$dumpPs1.tsv' -Encoding UTF8
Write-Output ("rows: " + `$rows.Count)
"@ | Set-Content $dumpPs1 -Encoding UTF8

$x86 = "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
& $x86 -NoProfile -ExecutionPolicy Bypass -File $dumpPs1 | Out-Null
$tsv = $dumpPs1 + '.tsv'
if (-not (Test-Path $tsv)) { Write-Host " 无法读取 MDD 数据库" -ForegroundColor Yellow; exit 1 }
Write-Host ("MDD tag 行: " + (Get-Content $tsv | Measure-Object -Line).Lines)

# 3) 生成覆盖文件
$tagDir = Join-Path $mods 'Core\MechAffinity\tags'
$stat = @{ made = 0; skip = 0; miss = 0 }
$enc = New-Object Text.UTF8Encoding $false
foreach ($l in (Get-Content $tsv)) {
    $parts = $l -split '\|', 3
    if ($parts.Count -lt 3) { continue }
    $name = $parts[0].Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    if ($name -notmatch '^(pilot_|affinityLevel)') { continue }
    $fn = $parts[1]; $de = $parts[2]
    $fnZh = $null; $deZh = $null
    if (-not [string]::IsNullOrWhiteSpace($fn)) { $fnZh = $dict[(Normalize $fn)] }
    if (-not [string]::IsNullOrWhiteSpace($de)) { $deZh = $dict[(Normalize $de)] }
    if ($null -eq $fnZh -and $null -eq $deZh) { $stat.miss++; continue }
    $target = Join-Path $tagDir ($name + '.json')
    if (Test-Path $target) { $stat.skip++; continue }   # 已有(模组自带, 已在上一步处理)
    if ($DryRun) { $stat.made++; continue }
    $obj = [ordered]@{
        Name = $name
        Important = $false
        PlayerVisible = $true
        FriendlyName = $(if ($null -ne $fnZh) { $fnZh } else { $fn })
        Description = $(if ($null -ne $deZh) { $deZh } else { $de })
    }
    $json = $obj | ConvertTo-Json -Depth 3
    [IO.File]::WriteAllText($target, $json, $enc)
    $stat.made++
}
Write-Host ("=== 生成 tag 覆盖文件 ===")
Write-Host ("  新建 " + $stat.made + " 个; 跳过(已存在) " + $stat.skip + " 个; 无译文 " + $stat.miss + " 个")
if ($DryRun) { Write-Host '  [DryRun] 未写盘' }
