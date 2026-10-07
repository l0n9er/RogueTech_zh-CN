param(
    [string]$PackageRoot = 'D:\\RT\\汉化包',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$dict = Join-Path $PackageRoot '工具\\dict-all.tsv'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $PackageRoot 'backup'
$before = Join-Path $backupDir ('dict-all-before-gap-normalize-' + $stamp + '.tsv')
$quarantine = Join-Path $backupDir ('corrupt-gap-rows-' + $stamp + '.tsv')
$lines = [IO.File]::ReadAllLines($dict, [Text.Encoding]::UTF8)
$kept = New-Object 'System.Collections.Generic.List[string]'
$bad = New-Object 'System.Collections.Generic.List[string]'
$seen = New-Object 'System.Collections.Generic.HashSet[string]'
$objectRows = 0
$normalized = 0
$discarded = 0

function IsCleanGapValue([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    $han = ([regex]::Matches($text, '[\u4e00-\u9fff]')).Count
    $latin = ([regex]::Matches($text, '[A-Za-z]')).Count
    if ($han -lt 2) { return $false }
    if ($text -match '<\/?[^>]*[\u4e00-\u9fff][^>]*>|<col或|</颜色>|</col或>') { return $false }
    $ratio = $han / [Math]::Max(1, ($han + $latin))
    # 低于此比例的文本基本是英文原文中只替换了几个词，不能作为可用译文。
    if ($ratio -lt 0.35) { return $false }
    $space = ([regex]::Matches($text, '[A-Za-z]{2,}\s+(在|或|和|是|以|的|该|至|与|将|拥有|配备|一台)\s+[A-Za-z]{2,}')).Count
    $inside = ([regex]::Matches($text, '[A-Za-z]+(在|或|和|是|以|的|该|至|与|将|拥有|配备|一台)[A-Za-z]+')).Count
    if ($ratio -lt 0.35 -and ($space -ge 1 -or $inside -ge 1)) { return $false }
    if ($space -ge 2 -or $inside -ge 3) { return $false }
    return $true
}

foreach ($line in $lines) {
    $parts = $line.Split([char]9, 3)
    if ($parts.Count -lt 3 -or $parts[0] -notlike '@{Field=*') {
        [void]$kept.Add($line)
        continue
    }
    $objectRows++
    $marker = $parts[0].IndexOf('; Text=')
    if ($marker -lt 0) {
        [void]$bad.Add($line); $discarded++; continue
    }
    $key = $parts[0].Substring($marker + 7)
    # PowerShell 对象字符串最后的一个 } 是对象结束符，不属于原文。
    if ($key.EndsWith('}')) { $key = $key.Substring(0, $key.Length - 1) }
    $value = $parts[1]
    if (-not (IsCleanGapValue $value) -or [string]::IsNullOrWhiteSpace($key)) {
        [void]$bad.Add($line); $discarded++; continue
    }
    if ($seen.Contains($key)) { continue }
    [void]$seen.Add($key)
    [void]$kept.Add($key + "`t" + $value + "`tDirect-LLM-Normalized")
    $normalized++
}

if (-not $DryRun) {
    if (-not (Test-Path $backupDir)) { [IO.Directory]::CreateDirectory($backupDir) | Out-Null }
    [IO.File]::Copy($dict, $before, $true)
    [IO.File]::WriteAllLines($quarantine, $bad, (New-Object Text.UTF8Encoding $true))
    [IO.File]::WriteAllLines($dict, $kept, (New-Object Text.UTF8Encoding $false))
}
Write-Output ("对象键行=$objectRows 规范化=$normalized 隔离=$discarded 保留总行=$($kept.Count)" + $(if ($DryRun) { ' [DryRun]' } else { '' }))
if (-not $DryRun) { Write-Output "原词典备份=$before"; Write-Output "隔离文件=$quarantine" }
