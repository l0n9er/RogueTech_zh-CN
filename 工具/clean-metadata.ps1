param(
    [string]$mods = "",
    [string]$backupRoot = "",
    [string]$fileList = ""
)
$ErrorActionPreference = 'Stop'
$BS = [string][char]92
$packRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($mods)) {
    $gr = & (Join-Path $PSScriptRoot 'find-game.ps1')
    if ([string]::IsNullOrWhiteSpace($gr)) { throw 'Game directory not found' }
    $mods = Join-Path $gr 'Mods'
}
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot = Join-Path $packRoot 'backup\Mods-metadata' }
$enc = New-Object Text.UTF8Encoding $false
$tagList = @('ZH','Components','ambushconvoy','RogueTechCore','CustomSalvage','CustomActivatableEquipment','CustomPilotProgression','Localization','Base','CAC','CU','AIM','DE','RU')
$tags = ($tagList | ForEach-Object { [regex]::Escape($_) }) -join '|'
$rx = [regex]'"(Details|YangsThoughts|StockRole)"\s*:\s*"((?:[^"\\]|\\.)*)"'
$stats = @{ files = 0; changed = 0; cleaned = 0 }
$metadataFiles = if (-not [string]::IsNullOrWhiteSpace($fileList) -and [IO.File]::Exists($fileList)) {
    Get-Content -Encoding UTF8 $fileList | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ FullName = $_; Name = [IO.Path]::GetFileName($_); Extension = [IO.Path]::GetExtension($_) } }
} else { Get-ChildItem $mods -Recurse -File -Filter '*.json' -Force -ErrorAction SilentlyContinue }
foreach ($f in $metadataFiles) {
    $stats.files++
    $orig = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    # 先用字面量筛选候选文件；绝大多数 JSON 不含中文或元数据后缀，
    # 不必为它们运行字段正则替换。
    if ($orig.IndexOf([char]0x4e00) -lt 0) { continue }
    $tagCandidate = $false
    foreach ($tag in $tagList) {
        if ($orig.IndexOf($tag, [StringComparison]::Ordinal) -ge 0) { $tagCandidate = $true; break }
    }
    if (-not $tagCandidate) { continue }
    $new = $rx.Replace($orig, {
        param($m)
        $v = $m.Groups[2].Value
        if ($v -notmatch '[\u4e00-\u9fff]') { return $m.Value }
        $clean = [regex]::Replace($v, '[\s]*(?:' + $tags + ')[\s]*$', '')
        if ($clean -eq $v) { return $m.Value }
        $stats.cleaned++
        return '"' + $m.Groups[1].Value + '": "' + $clean + '"'
    })
    if ($new -eq $orig) { continue }
    $rel = $f.FullName.Substring($mods.Length).TrimStart($BS)
    $bak = Join-Path $backupRoot $rel
    $parent = Split-Path $bak -Parent
    if (-not (Test-Path $parent)) { [void][IO.Directory]::CreateDirectory($parent) }
    if (-not (Test-Path $bak)) { [IO.File]::WriteAllText($bak, $orig, $enc) }
    [IO.File]::WriteAllText($f.FullName, $new, $enc)
    $stats.changed++
}
Write-Host ('files=' + $stats.files + ' changed=' + $stats.changed + ' cleaned=' + $stats.cleaned)
