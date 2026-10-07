param(
    [string]$GameMods = 'D:\\soft\\steam\\steamapps\\common\\BATTLETECH\\Mods',
    [string]$PackageRoot = 'D:\\RT\\汉化包',
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding $false
$dict = Join-Path $PackageRoot '工具\\dict-all.tsv'
$quarantine = Join-Path $PackageRoot ('backup\\corrupt-dict-all-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.tsv')
$repairRoot = Join-Path $PackageRoot ('backup\\corruption-repair-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$backupBefore = Join-Path $repairRoot 'current'
$null = New-Item -ItemType Directory -Path $repairRoot -Force
$roots = @(Get-ChildItem (Join-Path $PackageRoot 'backup') -Directory | Where-Object { $_.Name -like 'Mods-*' })

# 这组模式识别“英文句子中只替换了少量连接词”的半翻译结果。
$spacePattern = '[A-Za-z]{2,}\s+(在|或|和|是|以|的|该|至|与|将|拥有|配备|一台)\s+[A-Za-z]{2,}'
$insidePattern = '[A-Za-z]+(在|或|和|是|以|的|该|至|与|将|拥有|配备|一台)[A-Za-z]+'
$malformedTagPattern = '<\/?[^>]*[\u4e00-\u9fff][^>]*>'
function Test-CorruptTranslation([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    # 翻译模型曾把中文连接词写进英文单词，或把 color 标签中的字母替换成汉字。
    # 这两类即使文本很短也会直接显示错乱，必须优先拦截。
    if ($text -match $malformedTagPattern) { return $true }
    if ($text -match '<col或|</颜色>|</col或>') { return $true }
    $latin = ([regex]::Matches($text, '[A-Za-z]')).Count
    $han = ([regex]::Matches($text, '[\u4e00-\u9fff]')).Count
    $ratio = $han / [Math]::Max(1, ($latin + $han))
    $space = ([regex]::Matches($text, $spacePattern)).Count
    $inside = ([regex]::Matches($text, $insidePattern)).Count
    $short = $text.Length -lt 100
    $lowHan = $ratio -lt 0.35
    return (($lowHan -and ($space -ge 1 -or $inside -ge 1)) -or ($space -ge 2) -or ($inside -ge 3))
}

$lines = [IO.File]::ReadAllLines($dict, [Text.Encoding]::UTF8)
$kept = New-Object 'System.Collections.Generic.List[string]'
$bad = New-Object 'System.Collections.Generic.List[string]'
foreach ($line in $lines) {
    $parts = $line.Split([char]9, 3)
    # 仅隔离 Direct-LLM 生成的半翻译行；普通 ZH 行中可能合法保留厂商名/型号。
    if ($parts.Count -ge 3 -and $parts[2] -like 'Direct-LLM-*' -and (Test-CorruptTranslation $parts[1])) {
        [void]$bad.Add($line)
    } else {
        [void]$kept.Add($line)
    }
}
if (-not $DryRun) {
    [IO.File]::WriteAllLines($quarantine, $bad, (New-Object Text.UTF8Encoding $true))
    [IO.File]::WriteAllLines($dict, $kept, $utf8)
}
Write-Output "隔离半翻译词条=$($bad.Count) 保留词条=$($kept.Count)" 

if (-not (Test-Path -LiteralPath $GameMods)) { exit 0 }
$malformedTagScanPattern = '<\/?[^>]*[\x{4e00}-\x{9fff}][^>]*>'
$scanPattern = $spacePattern + '|' + $insidePattern + '|' + $malformedTagScanPattern + '|<col或|</颜色>|</col或>'
$candidateFiles = @(rg -l -P $scanPattern $GameMods -g '*.json' | Where-Object {
    $_ -notmatch '[\\/]Localization[\\/]' -and $_ -notmatch '[\\/]localization[\\/]' -and $_ -notmatch '[\\/]\\.modtek[\\/]' -and $_ -notmatch '[\\/]ModSaves[\\/]'
})
$restored = 0
$unrestored = New-Object 'System.Collections.Generic.List[string]'
foreach ($file in $candidateFiles) {
    $rel = $file.Substring($GameMods.Length).TrimStart([char[]]@('\','/'))
    $cleanSources = New-Object 'System.Collections.Generic.List[object]'
    foreach ($root in $roots) {
        $source = Join-Path $root.FullName $rel
        if (-not (Test-Path -LiteralPath $source)) { continue }
        try { $sourceText = [IO.File]::ReadAllText($source, [Text.Encoding]::UTF8) } catch { continue }
        if ($sourceText -notmatch $spacePattern -and $sourceText -notmatch $insidePattern) {
            [void]$cleanSources.Add([pscustomobject]@{Path=$source; Time=(Get-Item -LiteralPath $source).LastWriteTimeUtc})
        }
    }
    if ($cleanSources.Count -eq 0) { [void]$unrestored.Add($rel); continue }
    $source = ($cleanSources | Sort-Object Time -Descending | Select-Object -First 1).Path
    if (-not $DryRun) {
        $destBackup = Join-Path $backupBefore $rel
        $destDir = Split-Path $destBackup -Parent
        if (-not (Test-Path -LiteralPath $destDir)) { [IO.Directory]::CreateDirectory($destDir) | Out-Null }
        if (-not (Test-Path -LiteralPath $destBackup)) { Copy-Item -LiteralPath $file -Destination $destBackup -Force }
        Copy-Item -LiteralPath $source -Destination $file -Force
    }
    $restored++
}
Write-Output "恢复干净文件=$restored 无干净备份=$($unrestored.Count)"
if ($unrestored.Count -gt 0) {
    $report = Join-Path $repairRoot 'unrestored-files.txt'
    if (-not $DryRun) { [IO.File]::WriteAllLines($report, $unrestored, (New-Object Text.UTF8Encoding $true)) }
    $unrestored | Select-Object -First 20
}
