# 覆盖率巡检：扫描游戏 Mods 下所有 JSON/CSV 中应当汉化的文本，统计仍为英文的条目。
# 输出 TSV，便于后续分类。仅读，不写。
param(
  [string]$GameRoot = "D:\soft\steam\steamapps\common\BattleTech",
  [string]$OutDir   = "D:\RT\汉化包\backup"
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$mods = Join-Path $GameRoot 'Mods'

function Has-CJK([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return $false }
  foreach ($ch in $s.ToCharArray()) {
    $c = [int][char]$ch
    if (($c -ge 0x4E00 -and $c -le 0x9FFF) -or ($c -ge 0x3400 -and $c -le 0x4DBF) -or
        ($c -ge 0xF900 -and $c -le 0xFAFF) -or ($c -ge 0x3000 -and $c -le 0x303F) -or
        ($c -ge 0xFF00 -and $c -le 0xFFEF)) { return $true }
  }
  return $false
}

# 纯技术/可保留英文的内容判定
function Is-NoTranslate([string]$s) {
  $t = $s.Trim()
  if ($t.Length -eq 0) { return $true }
  # 纯数字 / 数值 / 单位 / 标点
  if ($t -match '^[\s0-9.,\-+/%*()\[\]{}:;!?&#@$_=<>\|\\~`]+$') { return $true }
  # 形如 AC/10, LBX-10, 3xLRM
  if ($t -match '^[A-Za-z0-9\.\-/\+]{1,12}$') { return $true }   # 单个短token(型号/缩写)
  # 内部标识符: 驼峰或下划线连接的代码式字符串, 无空格
  if ($t -match '^[A-Za-z0-9_\.]+$' -and $t -notmatch '\s') { return $true }
  return $false
}

$rows = New-Object System.Collections.ArrayList
$fileCount = 0
$jsonFiles = Get-ChildItem -Path $mods -Recurse -File -Include *.json -ErrorAction SilentlyContinue
foreach ($f in $jsonFiles) {
  $rel = $f.FullName.Substring($mods.Length).TrimStart('\')
  # 跳过明显非本地化目录
  if ($rel -match '\\\.modtek\\') { continue }
  $fileCount++
  $txt = $null
  try { $txt = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) } catch { continue }
  if ($txt -notmatch 'CULTURE_EN_US|CULTURE_DE_DE|CULTURE_RU_RU|\bTEXT\b|\bText\b|Description|Details|YangsThoughts|StockRole|UIName|FriendlyName|Name"') { continue }

  $obj = $null
  try { $obj = $txt | ConvertFrom-Json } catch { continue }
  if ($null -eq $obj) { continue }

  # 递归提取与 KEY/TEXT 对
  $stack = New-Object System.Collections.Stack
  $stack.Push($obj)
  while ($stack.Count -gt 0) {
    $cur = $stack.Pop()
    if ($null -eq $cur) { continue }
    if ($cur -is [System.Management.Automation.PSCustomObject]) {
      $props = $cur.PSObject.Properties.Name
      if ($props -contains 'CULTURE_EN_US') {
        $en = [string]$cur.CULTURE_EN_US
        $key = ''
        if ($props -contains 'ID') { $key = [string]$cur.ID }
        elseif ($props -contains 'Key') { $key = [string]$cur.Key }
        elseif ($props -contains 'key') { $key = [string]$cur.key }
        $zh = ''
        if ($props -contains 'CULTURE_ZH_CN') { $zh = [string]$cur.CULTURE_ZH_CN }
        $status = 'EN'
        if (Has-CJK $zh) { $status = 'ZH' }
        elseif ($zh) { $status = 'ZH_ASCII' }
        if ($status -ne 'ZH' -and -not (Is-NoTranslate $en)) {
          [void]$rows.Add([pscustomobject]@{ File=$rel; Key=$key; Field='CULTURE_EN_US'; Status=$status; En=$en; Zh=$zh })
        }
      }
      foreach ($p in $cur.PSObject.Properties) { if ($p.Value -is [System.Management.Automation.PSCustomObject] -or $p.Value -is [System.Array]) { $stack.Push($p.Value) } }
    }
    elseif ($cur -is [System.Array]) {
      foreach ($i in $cur) { if ($i -is [System.Management.Automation.PSCustomObject] -or $i -is [System.Array]) { $stack.Push($i) } }
    }
  }
}

Write-Host "scanned json files: $fileCount, candidates: $($rows.Count)"
$out = Join-Path $OutDir 'loc-missing.tsv'
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("File`tKey`tField`tStatus`tEN`tZH")
foreach ($r in $rows) {
  $en = ($r.En -replace '\r?\n',' ' -replace '\t',' ')
  $zh = ($r.Zh -replace '\r?\n',' ' -replace '\t',' ')
  if ($en.Length -gt 400) { $en = $en.Substring(0,400) }
  if ($zh.Length -gt 400) { $zh = $zh.Substring(0,400) }
  [void]$sb.AppendLine("$($r.File)`t$($r.Key)`t$($r.Field)`t$($r.Status)`t$en`t$zh")
}
[IO.File]::WriteAllText($out, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
Write-Host "written: $out"
