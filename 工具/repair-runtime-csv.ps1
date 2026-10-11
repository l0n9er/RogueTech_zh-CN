param([Parameter(Mandatory=$true)][string]$csv)
$ErrorActionPreference = 'Stop'
$fs = [char]31
$raw = [IO.File]::ReadAllText($csv, [Text.UTF8Encoding]::new($true))
$lines = [regex]::Split($raw, '(?<=\r?\n)')
$changed = 0; $targeted = 0
$terms = [ordered]@{
  'JES II Strategic Missile Carrier'='JES II战略导弹运载车'; 'The Morningstar City Command Vehicle'='晨星城市指挥车'; 'The Morningstar'='晨星';
  'Machine Guns?'='机枪'; 'Anti Missile System'='反导弹系统'; 'Quick Off The Line'='启动迅速'; 'relegated to the pages of history'='成为历史';
  'R10 Mechanized Infantry Combat Vehicle \(ICV\)'='R10机械化步兵战车（ICV）'; 'Scapha Hovertank'='Scapha悬浮坦克'; 'venerable combat vehicle'='久负盛名的战斗载具';
  'venerable SRM/LRM carriers'='久负盛名的SRM/LRM运载车'; 'Extra-Extralight Fusion Engine'='超超轻型聚变引擎'; 'Extra-Extralight Fusion'='超超轻型聚变';
  'Republic Standing Guard'='共和国常备卫队'; 'Prefectures'='行政区'; 'Pod ?space'='吊舱空间'; 'Model O Class LB'='O型LB'; 'The Yellow Jacket'='黄蜂';
  'medium lasers?'='中型激光'; 'guided missiles'='制导导弹'; 'salvaged wrecks'='打捞残骸'; 'clantech'='氏族技术'; 'Fusion Engine'='聚变引擎';
  'Heavy Hover APC'='重型气垫装甲运兵车'; 'Heavy Tracked APC'='重型履带式装甲运兵车'; 'Foot Infantry'='徒步步兵'; 'Motorized Infantry'='摩托化步兵';
  'Jump Infantry'='跳跃步兵'; 'Infantry Bay'='步兵舱'; 'Star League'='星际联盟'; 'Biome Restrictions?'='生物群系限制'; 'Movement'='移动';
  'Armor'='装甲'; 'Structure'='结构'; 'Values'='数值'; 'Front'='正面'; 'Left'='左侧'; 'Right'='右侧'; 'Rear'='后方'; 'Total'='总计';
  'Quirk'='特性'; 'Rugged'='坚固'; 'Can Resupply/Repair'='可补给/维修'; 'Has firing ports'='设有射击孔'; 'Lunar'='月球'; 'Martian'='火星';
  '\bICE\b'='内燃机'; 'Ammunition'='弹药'; 'Equipment'='装备'; 'Standard Fusion Engine'='标准聚变引擎'; 'Standard Fusion'='标准聚变';
  'garrison'='驻军'; 'assault tank'='突击坦克'; 'artillery rounds'='炮兵炮弹'; 'ferro-fibrous'='铁纤维'; 'counterparts'='同类车辆';
  'periphery'='外围'; 'reloads'='再装填弹药'; 'stealth'='隐形'; 'overhaul'='大修'; 'necessity'='必需品'; 'relegated'='降为二线';
  'amphibious'='两栖'; 'hull[- ]mounted'='车体安装的'; 'XL Engine'='XL引擎'; 'rated'='额定'; 'venerable'='久负盛名的';
  'boondoggle'='无意义的浪费项目'; 'carrier'='运载车'; 'downgrade'='降级'; '\bhex\b'='格'; '\bmech\b'='机甲'; 'crippling'='致命的';
  '\bjihad\b'='圣战'; 'firepower'='火力'; 'companion'='搭档'; 'hull'='车体'; 'Fire and Forget'='发射后不管'; 'Advanced Optics'='高级光学';
  'Cavalry Attack Helicopter'='骑兵攻击直升机'; 'Urban Assault Vehicle'='城市突击载具'; 'Support Transport Vehicle'='支援运输车'; 'Hover Scout'='悬浮侦察车';
  'Advanced Scout Vehicle'='高级侦察载具'; 'Assault Hover Craft'='突击气垫船'; 'Assault VTOL'='突击VTOL'; 'Weapons Bay'='武器舱'; 'Infantry Transport Bay'='步兵运输舱';
  'PPC carrier'='PPC运载车'; 'Stealth Assault Bomber'='隐形攻击轰炸机'; 'Laser Carrier'='激光运载车'; 'combat vehicles?'='战斗载具'; 'Assault mech'='突击机甲';
  'battlemechs'='战斗机甲'; 'fighter mechs'='战斗机甲'; 'Rocket'='火箭'; 'Inner Sphere'='内层星域'; 'House Liao'='廖氏'
}
function Repair-Value([string]$text, [string]$key) {
  $chunks = [regex]::Split($text, '(\[\[.*?\]\])', [Text.RegularExpressions.RegexOptions]::Singleline)
  for($i=0;$i -lt $chunks.Count;$i+=2){ $chunks[$i] = $chunks[$i].Replace($fs,' ') }
  $text = ($chunks -join '').Replace('#Weapons:','#武器:')
  foreach($pair in $terms.GetEnumerator()){ $text = [regex]::Replace($text, $pair.Key, $pair.Value, [Text.RegularExpressions.RegexOptions]::IgnoreCase) }
  $nl='\n'
  if (($key -match '\*biomerestrictions:|\*movement:|newlinenewline') -and $text -notmatch '\\n') { $text=[regex]::Replace($text, '\s*(<b><color=)', "$nl$nl`$1", 1) }
  $text=[regex]::Replace($text, '</color></b>\s{2,}<b><color=', "</color></b>$nl$nl<b><color=")
  $text=[regex]::Replace($text, '</color>\s{2,}<b><color=', "</color>$nl$nl<b><color=")
  $text=[regex]::Replace($text, '</color>(?:</b>)?\s{2,}#武器:', { param($m) $m.Value -replace '\s{2,}#武器:', "$nl#武器:" })
  $text=$text.Replace('  #武器:', "$nl#武器:")
  return $text
}
for($idx=0;$idx -lt $lines.Count;$idx++){ $line=$lines[$idx]
  if($line -notmatch '^(.*?),(.*?)(\r?\n)?$'){ continue }
  $mkey=$Matches[1]; $mvalue=$Matches[2]; $meol=$Matches[3]
  if($mkey -notmatch '(?i)#weapons|\*biomerestrictions:|\*movement:|\*armor:'){ continue }
  $targeted++; $new=Repair-Value $mvalue $mkey
  if($new -cne $mvalue){$changed++}; $line = $mkey+','+$new+$meol
  $lines[$idx]=$line
}
[IO.File]::WriteAllText($csv, ($lines -join ''), [Text.UTF8Encoding]::new($false))
Write-Output ("运行时条目: $targeted，已修复: $changed")

