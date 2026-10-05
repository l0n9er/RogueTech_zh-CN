# 找出游戏英文(dev-WWW)总表中未收录进本补丁 CSV 的键
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$loc = 'D:\soft\steam\steamapps\common\BattleTech\BattleTech_Data\StreamingAssets\data\localization'
$dev = [IO.File]::ReadAllLines((Join-Path $loc 'strings_dev-WWW.csv'), [Text.Encoding]::UTF8)
$zh  = [IO.File]::ReadAllLines((Join-Path $loc 'strings_zh-CN.csv'), [Text.Encoding]::UTF8)
$h = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($l in $zh) {
  if ($l.Length -eq 0) { continue }
  $i = $l.IndexOf(',')
  if ($i -gt 0) { [void]$h.Add($l.Substring(0, $i)) }
}
$miss = New-Object System.Collections.ArrayList
foreach ($l in $dev) {
  if ($l.Length -eq 0) { continue }
  $i = $l.IndexOf(',')
  if ($i -le 0) { continue }
  $k = $l.Substring(0, $i)
  if (-not $h.Contains($k)) { [void]$miss.Add($l) }
}
$out = 'D:\RT\汉化包\backup\csv-missing-dev.tsv'
$sb = New-Object System.Text.StringBuilder
foreach ($l in $miss) {
  $i = $l.IndexOf(',')
  $k = $l.Substring(0, $i)
  $v = $l.Substring($i + 1)
  if ($v.Length -gt 500) { $v = $v.Substring(0, 500) }
  [void]$sb.AppendLine(($k -replace '\t', ' ') + "`t" + ($v -replace "`r?`n", ' ' -replace '\t', ' '))
}
[IO.File]::WriteAllText($out, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
Write-Host ('missing dev keys: ' + $miss.Count)
Write-Host ('written: ' + $out)
