param(
    [string]$Pairs = 'D:\RT\汉化包\工具\faction_tr_all_merged.tsv',
    [string]$FactionDir = 'D:\RT\汉化包\Mods\Core\RogueTechCore\Factions',
    [string]$BackupRoot = '',
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'

$map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
foreach ($line in [IO.File]::ReadLines($Pairs, [Text.Encoding]::UTF8)) {
    $tab = $line.IndexOf("`t")
    if ($tab -lt 1) { continue }
    $en = $line.Substring(0, $tab).Trim()
    $zh = $line.Substring($tab + 1).Trim()
    if ($en.Length -gt 2 -and $zh -match '[\u4e00-\u9fff]' -and -not $map.ContainsKey($en)) {
        $map.Add($en, $zh)
    }
}

$fields = @('ReputationStatements', 'MissionSuccessStatements', 'GoodFaithFailureStatements', 'BadFaithFailureStatements')
if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
    # 兼容手工调用：未指定外部备份目录时仍使用旧位置。
    $backupDir = Join-Path $FactionDir '_bak_faction'
} else {
    $backupDir = $BackupRoot
}
$utf8 = New-Object Text.UTF8Encoding $false
$filesChanged = 0
$replacements = 0
$matched = 0
$jsonFailures = 0
$fileStats = New-Object 'System.Collections.Generic.List[string]'

function ConvertTo-SourceJsonString([string]$value) {
    # PowerShell 5.1 serializes apostrophes as \u0027, while the source files keep them literal.
    return (($value | ConvertTo-Json -Compress).Replace('\u0027', "'"))
}

foreach ($file in Get-ChildItem -LiteralPath $FactionDir -Filter '*.json' -File) {
    $original = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
    try { $json = $original | ConvertFrom-Json } catch { $jsonFailures++; continue }
    $updated = $original
    $fileReplacements = 0

    foreach ($field in $fields) {
        $arr = $json.$field
        if ($null -eq $arr) { continue }
        foreach ($statement in @($arr)) {
            $key = [string]$statement
            if (-not $map.ContainsKey($key)) { continue }
            $oldLiteral = ConvertTo-SourceJsonString $key
            $newLiteral = ConvertTo-SourceJsonString $map[$key]
            $pos = 0
            while (($hit = $updated.IndexOf($oldLiteral, $pos, [StringComparison]::Ordinal)) -ge 0) {
                $fileReplacements++
                $matched++
                $pos = $hit + $newLiteral.Length
            }
            $updated = $updated.Replace($oldLiteral, $newLiteral)
        }
    }

    # 数组解析对带 HTML 标签的个别旧定义可能出现边界差异；
    # 再按原始 JSON 字符串做一次兜底，确保词典命中项不漏翻。
    foreach ($entry in $map.GetEnumerator()) {
        $oldLiteral = ConvertTo-SourceJsonString ([string]$entry.Key)
        if ($updated.IndexOf($oldLiteral, [StringComparison]::Ordinal) -lt 0) { continue }
        $newLiteral = ConvertTo-SourceJsonString ([string]$entry.Value)
        $pos = 0
        while (($hit = $updated.IndexOf($oldLiteral, $pos, [StringComparison]::Ordinal)) -ge 0) {
            $fileReplacements++
            $matched++
            $pos = $hit + $newLiteral.Length
        }
        $updated = $updated.Replace($oldLiteral, $newLiteral)
    }

    if ($fileReplacements -eq 0) { continue }
    $filesChanged++
    $replacements += $fileReplacements
    [void]$fileStats.Add("$($file.Name)`t$fileReplacements")
    if ($DryRun) { continue }

    if (-not (Test-Path -LiteralPath $backupDir)) {
        [IO.Directory]::CreateDirectory($backupDir) | Out-Null
    }
    $backup = Join-Path $backupDir ($file.Name + '.bak')
    if (-not (Test-Path -LiteralPath $backup)) {
        [IO.File]::WriteAllText($backup, $original, $utf8)
    }
    $null = $updated | ConvertFrom-Json
    [IO.File]::WriteAllText($file.FullName, $updated, $utf8)
}

Write-Output "翻译映射=$($map.Count) 命中语句=$matched 改动文件=$filesChanged JSON失败=$jsonFailures"
$fileStats | Sort-Object
if ($DryRun) { Write-Output '[DryRun] 未写入文件' }
