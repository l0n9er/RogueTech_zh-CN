param(
    [Parameter(Mandatory=$true)][string]$mods,
    [string]$backupRoot = ""
)
$ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($backupRoot)) { $backupRoot=Join-Path (Split-Path $PSScriptRoot -Parent) 'backup\Mods-unit-terms' }
$BS=[string][char]92; $enc=New-Object Text.UTF8Encoding($false)
function Unesc([string]$s) {
    $s=[regex]::Replace($s, ($BS+$BS+'u([0-9a-fA-F]{4})'), [Text.RegularExpressions.MatchEvaluator]{param($m)[char][int]('0x'+$m.Groups[1].Value)})
    return $s.Replace($BS+'n',"`n").Replace($BS+'r',"`r").Replace($BS+'t',"`t").Replace($BS+'"','"').Replace($BS+$BS,$BS)
}
function Esc([string]$s) { return $s.Replace($BS,$BS+$BS).Replace('"',$BS+'"').Replace("`n",$BS+'n').Replace("`r",$BS+'r').Replace("`t",$BS+'t') }
$rules=@(
 @{r='\bDrop Cost Multiplier\s*[:：]';v='部署费用倍率：'}, @{r='\bArm Actuator Limits?\s*[:：]';v='手臂驱动器限制：'},
 @{r='\bQuirk\s*[:：]';v='特性：'}, @{r='\bThis unit can not deploy in Lunar or Martian biomes due to using an ICE\.';v='该单位因使用内燃机，无法在月球或火星生物群系部署。'},
 @{r='\bThis unit can not deploy in Lunar biomes\.';v='该单位无法在月球生物群系部署。'}, @{r='\bmedium lasers?\b';v='中型激光器'},
 @{r='\bguided missiles\b';v='制导导弹'}, @{r='\bXL [Ee]ngine\b';v='XL引擎'}, @{r='\bEngine\b';v='引擎'},
 @{r='\bTorso Twist\b';v='躯干扭转'}, @{r='\bOmni ?Vehicle\b';v='全向载具'}, @{r='\bValues\b';v='数值'},
 @{r='\bArmor\b';v='装甲'}, @{r='\bStructure\b';v='结构'}, @{r='\bFusion\s*:';v='聚变：'},
 @{r='\bhexes\b';v='格'}, @{r='\bmeters\b';v='米'}, @{r='\bLight Ferro\b';v='轻型铁纤维装甲'},
 @{r='\bFerro-Fibrous\b';v='铁纤维装甲'}, @{r='\bArtillery\b';v='火炮'}, @{r='\bHeavy Tank\b';v='重型坦克'},
 @{r='\bMedium Tank\b';v='中型坦克'}, @{r='\bScout Tank\b';v='侦察坦克'}, @{r='\bCombat Vehicle\b';v='战斗车辆'}
)
$rx=[regex]'"(Details|YangsThoughts)"\s*:\s*"((?:[^"\\]|\\.)*)"';$changed=0;$files=0
foreach($f in (Get-ChildItem $mods -Recurse -File -Filter '*.json' | Where-Object {$_.Name -match '^(chassisdef_|mechdef_|vehiclechassisdef_|vehicledef_|weapondef_|ammunitionBoxDef_)'})) {
 $orig=[IO.File]::ReadAllText($f.FullName,[Text.Encoding]::UTF8);$new=$rx.Replace($orig,[Text.RegularExpressions.MatchEvaluator]{param($m)$v=Unesc $m.Groups[2].Value;$old=$v;foreach($rule in $rules){$v=[regex]::Replace($v,$rule.r,$rule.v,[Text.RegularExpressions.RegexOptions]::IgnoreCase)};if($v -eq $old){return $m.Value};$script:changed++;return '"'+$m.Groups[1].Value+'": "'+(Esc $v)+'"'});
 if($new -ne $orig){$rel=$f.FullName.Substring($mods.Length).TrimStart('\');$bak=Join-Path $backupRoot $rel;$d=Split-Path $bak -Parent;if(!(Test-Path $d)){[IO.Directory]::CreateDirectory($d)|Out-Null};if(!(Test-Path $bak)){[IO.File]::WriteAllText($bak,$orig,$enc)};[IO.File]::WriteAllText($f.FullName,$new,$enc);$files++}
}
Write-Host ("单位术语归一化：字段="+$changed+" 文件="+$files)
