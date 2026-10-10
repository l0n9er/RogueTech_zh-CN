param(
 [Parameter(Mandatory=$true)][string]$mods,
 [string]$out = "",
 [switch]$AllowEnglishNameOnly
)
$ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($out)) { $out=Join-Path (Split-Path $PSScriptRoot -Parent) 'backup\unit-fields-qa.tsv' }
$parent=Split-Path $out -Parent
if (!(Test-Path $parent)) {[IO.Directory]::CreateDirectory($parent)|Out-Null}
$rows=New-Object 'System.Collections.Generic.List[string]'; [void]$rows.Add("Status`tFile`tField`tSample")
$stats=@{scanned=0;invalid=0;english=0;sentence=0;contaminated=0;mojibake=0;literalNewline=0;newline=0;control=0;markup=0;placeholder=0}
$sentenceRx=[regex]::new('\bPowered\s+by\b|\bis\s+armed\s+with\b|\bwas\s+designed\b|\bThis\s+(?:variant|unit|configuration)\b|\bThe\s+[A-Za-z][-A-Za-z ]{2,80}\s+is\b|\band\s+a\s+pair\s+of\b|\b(?:Left|Right)\s+(?:Lower|Upper)\b',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
$wordRx=[regex]::new('\b[A-Za-z]{3,}\b'); $hanRx=[regex]::new('[\u3400-\u9fff]'); $tagRx=[regex]::new('</?\s*[A-Za-z][^>]*>')
function Add-Row([string]$s,[string]$f,[string]$k,[string]$v) { $x=($v -replace "`r?`n",' ' -replace "`t",' '); if($x.Length -gt 240){$x=$x.Substring(0,240)+'...'}; [void]$rows.Add(($s+"`t"+$f+"`t"+$k+"`t"+$x)) }
function Inspect([string]$f,[string]$k,[string]$v) {
 if([string]::IsNullOrWhiteSpace($v)){return}; $en=$wordRx.Matches($v).Count; $han=$hanRx.Matches($v).Count
 if($v.IndexOf([char]0xFFFD) -ge 0 -or $v.IndexOf([char]0x00C3) -ge 0 -or $v.IndexOf([char]0x00C2) -ge 0){$stats.mojibake++;Add-Row 'MOJIBAKE' $f $k $v}
 if($v -match '[\x00-\x08\x0B\x0C\x0E-\x1F]'){$stats.control++;Add-Row 'CONTROL' $f $k $v}
 if($v -match '\\n'){$stats.literalNewline++;Add-Row 'LITERAL_NEWLINE' $f $k $v}
 if($v -match '(?:`r`n|`n)[ \t]+|[ \t]+(?:`r`n|`n)|(?:`r`n|`n){3,}'){$stats.newline++;Add-Row 'NEWLINE_SHAPE' $f $k $v}
 $sent=$sentenceRx.IsMatch($v); if($sent){$stats.sentence++;Add-Row 'ENGLISH_SENTENCE' $f $k $v}
 if($en -ge 10 -and $han -eq 0 -and !$AllowEnglishNameOnly){$stats.english++;Add-Row 'ENGLISH' $f $k $v}
 # 只将高置信度英文句法与中文共存判为混杂；型号、厂商和武器专名中的英文词不单独报错。
 if($han -gt 0 -and $sent){$stats.contaminated++;Add-Row 'CONTAMINATED' $f $k $v}
 $lt=([regex]::Matches($v,'<')).Count; $gt=([regex]::Matches($v,'>')).Count; if($lt -ne $gt -or ($lt -gt 0 -and $tagRx.Matches($v).Count -lt $lt)){$stats.markup++;Add-Row 'MARKUP' $f $k $v}
 if($v -match '\{[^{}]*$|^[^{}]*\}|%(?:\d+\$)?[sdif]'){$stats.placeholder++;Add-Row 'PLACEHOLDER' $f $k $v}
}
$files=@(Get-ChildItem $mods -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue|Where-Object{$_.FullName -notlike '*\.modtek\*' -and $_.FullName -notmatch '[\\/]Localization[\\/]' -and $_.FullName -notmatch '[\\/]localization[\\/]' -and $_.Name -match '^(chassisdef_|mechdef_|vehiclechassisdef_|vehicledef_|weapondef_|ammunitionBoxDef_)'})
foreach($f in $files){$stats.scanned++;$txt=[IO.File]::ReadAllText($f.FullName,[Text.Encoding]::UTF8);try{$obj=$txt|ConvertFrom-Json -ErrorAction Stop}catch{$stats.invalid++;Add-Row 'INVALID_JSON' $f.FullName '-' $_.Exception.Message;continue};$stack=New-Object Collections.Stack;$stack.Push($obj);while($stack.Count -gt 0){$cur=$stack.Pop();if($null -eq $cur){continue};if($cur -is [Array]){foreach($i in $cur){if($i -is [PSCustomObject] -or $i -is [Array]){$stack.Push($i)}};continue};if(!($cur -is [PSCustomObject])){continue};foreach($p in $cur.PSObject.Properties){if($p.Value -is [PSCustomObject] -or $p.Value -is [Array]){$stack.Push($p.Value)};if($p.Name -in @('Details','YangsThoughts','StockRole')){Inspect $f.FullName $p.Name ([string]$p.Value)}}}}
[IO.File]::WriteAllLines($out,$rows,(New-Object Text.UTF8Encoding($false)));Write-Host("单位字段检查：扫描=$($stats.scanned) 无效JSON=$($stats.invalid) 纯英文=$($stats.english) 英文句法=$($stats.sentence) 混入污染=$($stats.contaminated) 乱码=$($stats.mojibake) 字面换行=$($stats.literalNewline) 换行异常=$($stats.newline) 控制字符=$($stats.control) 标签异常=$($stats.markup) 占位符异常=$($stats.placeholder)");Write-Host("报告: "+$out);if($stats.invalid -gt 0 -or $stats.english -gt 0 -or $stats.sentence -gt 0 -or $stats.contaminated -gt 0 -or $stats.mojibake -gt 0 -or $stats.literalNewline -gt 0 -or $stats.newline -gt 0 -or $stats.control -gt 0 -or $stats.markup -gt 0 -or $stats.placeholder -gt 0){exit 1}
