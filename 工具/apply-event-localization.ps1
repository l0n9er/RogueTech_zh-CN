param(
    [string]$mods = "",
    [string]$backupRoot = "",
    [switch]$DryRun
)

# 从模组 Localization/ZH/Localization.json 按事件 ID 提取 CULTURE_ZH_CN，
# 就地覆盖 events/backgroundEvent 中直接显示的 Name/Details。事件选项与
# 正文都走这条通道，不能只依赖有限的人工 dict-events.tsv。
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

Add-Type -AssemblyName System.Web.Extensions
$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$ser.MaxJsonLength = [int]::MaxValue
$enc = New-Object Text.UTF8Encoding $false
$pairs = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$locCount = 0

function Walk-Loc($node) {
    if ($node -is [System.Collections.IDictionary]) {
        $name = [string]$node['Name']
        $loc = $node['Localization']
        if ($name -and $loc -is [System.Collections.IDictionary] -and
            ($name -match '(?i)(^|\.)event_|\.backgroundEvent|\.events?\.' )) {
            $en = [string]$loc['CULTURE_EN_US']
            $zh = [string]$loc['CULTURE_ZH_CN']
            if ($en -and $zh -and $en -ne $zh -and $zh -match '[\u4e00-\u9fff]' -and -not $pairs.ContainsKey($en)) {
                $pairs[$en] = $zh
            }
        }
        foreach ($k in $node.Keys) { Walk-Loc $node[$k] }
    } elseif ($node -is [System.Collections.IEnumerable] -and -not ($node -is [string])) {
        foreach ($v in $node) { Walk-Loc $v }
    }
}

$locFiles = Get-ChildItem $mods -Recurse -File -Filter 'Localization.json' -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -match '(?i)Localization[\\/]ZH$' }
foreach ($lf in $locFiles) {
    try {
        $obj = $ser.DeserializeObject([IO.File]::ReadAllText($lf.FullName, [Text.Encoding]::UTF8))
        Walk-Loc $obj
        $locCount++
    } catch { Write-Host ("跳过本地化表: " + $lf.FullName) -ForegroundColor Yellow }
}

function Unesc([string]$s) {
    return $s.Replace($BS + '/', '/').Replace($BS + '"', '"').Replace($BS + $BS, $BS)
}
function Esc([string]$s) {
    $e = $s.Replace($BS, $BS + $BS).Replace('"', $BS + '"')
    $e = $e.Replace("`r", $BS + 'r').Replace("`n", $BS + 'n').Replace("`t", $BS + 't')
    return $e
}

$Q = [string][char]34
$rxPattern = $Q + '(Name|Details)' + $Q + '\s*:\s*' + $Q + '((?:[^' + $Q + $BS + $BS + ']|' + $BS + $BS + '.)*)' + $Q
$rx = New-Object System.Text.RegularExpressions.Regex $rxPattern
$stats = @{ files = 0; changed = 0; repl = 0 }
$files = Get-ChildItem $mods -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue |
    Where-Object {
        $relPath = $_.FullName.Substring($mods.Length).TrimStart($BS)
        $relPath -notmatch ('(?i)' + [regex]::Escape('.modtek') + [regex]::Escape($BS)) -and
        $relPath -match '(?i)(^|\\)(events?|backgroundEvent)(\\|$)'
    }
foreach ($f in $files) {
    $stats.files++
    $orig = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    $new = $rx.Replace($orig, {
        param($m)
        $val = Unesc $m.Groups[2].Value
        if ($val -match '[\u4e00-\u9fff]' -or -not $pairs.ContainsKey($val)) { return $m.Value }
        $stats.repl++
        return ('"' + $m.Groups[1].Value + '": "' + (Esc $pairs[$val]) + '"')
    })
    if ($new -eq $orig) { continue }
    $stats.changed++
    if (-not $DryRun) {
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction SilentlyContinue
        try { [void]$ser.DeserializeObject($new) } catch { Write-Host ("跳过(JSON 无效): " + $f.Name); continue }
        $rel = $f.FullName.Substring($mods.Length).TrimStart($BS)
        $bak = Join-Path $backupRoot $rel
        $d = Split-Path $bak -Parent
        if (-not [IO.Directory]::Exists($d)) { [void][IO.Directory]::CreateDirectory($d) }
        if (-not [IO.File]::Exists($bak)) { [IO.File]::WriteAllText($bak, $orig, $enc) }
        [IO.File]::WriteAllText($f.FullName, $new, $enc)
    }
}
Write-Host ("Localization 表=" + $locCount + " 事件译文=" + $pairs.Count +
            " files=" + $stats.files + " changed=" + $stats.changed + " repl=" + $stats.repl)
