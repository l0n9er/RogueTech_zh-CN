param(
    [Parameter(Mandatory=$true)][string]$mods,
    [string]$out = ""
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($out)) { $out = Join-Path (Split-Path $PSScriptRoot -Parent) 'backup\unit-fields-qa.tsv' }
$parent = Split-Path $out -Parent
if (-not (Test-Path $parent)) { [void][IO.Directory]::CreateDirectory($parent) }
$rows = New-Object 'System.Collections.Generic.List[string]'
[void]$rows.Add("Status`tFile`tField`tSample")
$stats = @{ scanned = 0; invalid = 0; english = 0; contaminated = 0; literalNewline = 0; control = 0 }
$files = @(Get-ChildItem $mods -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object {
    $_.FullName -notlike '*\.modtek\*' -and
    $_.FullName -notmatch '[\\/]Localization[\\/]' -and
    $_.FullName -notmatch '[\\/]localization[\\/]' -and
    $_.Name -match '^(chassisdef_|mechdef_|vehiclechassisdef_|vehicledef_|weapondef_|ammunitionBoxDef_)'
})
foreach ($f in $files) {
    $stats.scanned++
    $txt = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    try { $obj = $txt | ConvertFrom-Json -ErrorAction Stop }
    catch {
        $stats.invalid++
        [void]$rows.Add(("INVALID_JSON`t" + $f.FullName + "`t-`t" + ($_.Exception.Message -replace "`t",' ')))
        continue
    }
    $stack = New-Object Collections.Stack
    $stack.Push($obj)
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        if ($null -eq $cur) { continue }
        if ($cur -is [Array]) {
            foreach ($i in $cur) {
                if ($i -is [PSCustomObject] -or $i -is [Array]) { $stack.Push($i) }
            }
            continue
        }
        if (-not ($cur -is [PSCustomObject])) { continue }
        foreach ($prop in $cur.PSObject.Properties) {
            if ($prop.Value -is [PSCustomObject] -or $prop.Value -is [Array]) { $stack.Push($prop.Value) }
            if ($prop.Name -notin @('Details','YangsThoughts','StockRole')) { continue }
            $v = [string]$prop.Value
            if ([string]::IsNullOrWhiteSpace($v)) { continue }
            $en = ([regex]::Matches($v, '\b[A-Za-z]{3,}\b')).Count
            $han = ([regex]::Matches($v, '[\u3400-\u9fff]')).Count
            $sample = (($v -replace "`r?`n", ' ' -replace "`t", ' ') -replace '\\n', '<\\n>')
            if ($sample.Length -gt 180) { $sample = $sample.Substring(0,180) }
            if ($v -match '\\n') { $stats.literalNewline++; [void]$rows.Add(("LITERAL_NEWLINE`t"+$f.FullName+"`t"+$prop.Name+"`t"+$sample)) }
            if ($v -match '[\x00-\x08\x0B\x0C\x0E-\x1F]') { $stats.control++; [void]$rows.Add(("CONTROL`t"+$f.FullName+"`t"+$prop.Name+"`t"+$sample)) }
            if ($en -ge 12 -and $han -eq 0) { $stats.english++; [void]$rows.Add(("ENGLISH`t"+$f.FullName+"`t"+$prop.Name+"`t"+$sample)); continue }
            # 合法署名/厂商名保留英文，不应被误判为半翻译污染。
            $mixedCheck = $v -replace 'Aries Games and Miniatures', ''
            if ($en -ge 12 -and $han -gt 0 -and $mixedCheck -match '[A-Za-z]{2,}[\u3400-\u9fff][A-Za-z]{2,}') {
                $stats.contaminated++; [void]$rows.Add(("CONTAMINATED`t"+$f.FullName+"`t"+$prop.Name+"`t"+$sample))
            }
        }
    }
}
[IO.File]::WriteAllLines($out, $rows, (New-Object Text.UTF8Encoding($false)))
Write-Host ("单位字段检查：扫描="+$stats.scanned+" 无效JSON="+$stats.invalid+" 纯英文="+$stats.english+" 混入污染="+$stats.contaminated+" 字面换行="+$stats.literalNewline+" 控制字符="+$stats.control)
Write-Host ("报告: "+$out)
if ($stats.invalid -gt 0 -or $stats.contaminated -gt 0 -or $stats.literalNewline -gt 0 -or $stats.control -gt 0) { exit 1 }
