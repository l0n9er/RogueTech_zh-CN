param(
    [Parameter(Mandatory=$true)][string]$mods,
    [Parameter(Mandatory=$true)][string]$backupRoot
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

# 额外语音包不是汉化包自带文件，只在用户已经安装该语音包时就地补齐
# credits 的中文说明。文件先备份到本次安装目录，便于还原脚本恢复。
$target = Join-Path $mods 'Core\CustomVoices\voicepacks\MWSphere.json'
if (-not [IO.File]::Exists($target)) {
    Write-Host '未发现额外语音包 MWSphere，跳过'
    exit 0
}

$text = [IO.File]::ReadAllText($target, [Text.Encoding]::UTF8)
$obj = $null
try { $obj = $text | ConvertFrom-Json } catch {
    Write-Host 'MWSphere.json 格式无法解析，跳过（保留原文件）'
    exit 0
}
if ($null -eq $obj -or $null -eq $obj.credits) {
    Write-Host 'MWSphere.json 缺少 credits 字段，跳过'
    exit 0
}
if ($obj.credits.PSObject.Properties.Name -contains 'CULTURE_ZH_CN') {
    Write-Host 'MWSphere 已有中文说明，跳过'
    exit 0
}

$enProp = $obj.credits.PSObject.Properties['CULTURE_EN_US']
if ($null -eq $enProp -or [string]::IsNullOrWhiteSpace([string]$enProp.Value)) {
    Write-Host 'MWSphere 缺少英文说明，跳过'
    exit 0
}

$zh = "<color=#35dde0>感谢 <b><color=#4dff4d>Yuntow</color></b>制作并提供语音包。如想亲自向他致谢，可访问他的 Twitch 频道：<b><color=#4dff4d>https://www.twitch.tv/yuntow</color></b>。`n`n内圈机甲战士语音包适用于<b>内圈机师</b>。也可以用于其他单位，但强烈建议不要给氏族机师使用，因为其中部分台词偏向内圈（例如：欢迎来到内圈）。</color>"
$zhJson = $zh | ConvertTo-Json -Compress
$pattern = '(?s)("CULTURE_EN_US"\s*:\s*"(?:\\.|[^"\\])*")(\s*,\s*"CULTURE_RU_RU"\s*:)'
$rx = New-Object System.Text.RegularExpressions.Regex($pattern)
$match = $rx.Match($text)
if (-not $match.Success) {
    Write-Host 'MWSphere 未找到可插入的本地化字段，跳过'
    exit 0
}
$newText = $rx.Replace($text, {
    param($m)
    return ($m.Groups[1].Value + ', "CULTURE_ZH_CN": ' + $zhJson + $m.Groups[2].Value)
}, 1)

$rel = 'Mods\Core\CustomVoices\voicepacks\MWSphere.json'
$bak = Join-Path $backupRoot $rel
$bakParent = Split-Path $bak -Parent
if (-not [IO.Directory]::Exists($bakParent)) { [void][IO.Directory]::CreateDirectory($bakParent) }
[IO.File]::Copy($target, $bak, $true)
[IO.File]::WriteAllText($target, $newText, (New-Object Text.UTF8Encoding($false)))

# 二次解析确认插入后仍是合法 JSON。
[IO.File]::ReadAllText($target, [Text.Encoding]::UTF8) | ConvertFrom-Json | Out-Null
Write-Host '已补齐 MWSphere 中文说明（1 个文件）'
