# 重新打包发布 zip（排除 .git / backup / 自身）
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$packRoot = Split-Path $PSScriptRoot -Parent
# 文件名带日期+时间后缀, 便于区分版本; 保留已有发布包
$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$zip = Join-Path $packRoot ('RT汉化包_' + $stamp + '.zip')

# 需要排除的目录（相对包根）
$excludeDirs = @('.git', 'backup')
$requiredFiles = @(
    '安装.bat',
    '还原.bat',
    '工具\安装.ps1',
    '工具\还原.ps1',
    '工具\apply-event-localization.ps1',
    '工具\dict-events.tsv',
    '工具\dict-events-short.tsv',
    '工具\dict-events-auto.tsv',
    '工具\dict-events-residual.tsv',
    'strings_zh-CN.csv',
    'Mods\Core\RogueTechCore\Localization\ZH\Localization.json',
    '版本\GOG\BattleTech_Data\Managed\Assembly-CSharp.dll'
)
$missingFiles = New-Object 'System.Collections.Generic.List[string]'
$installerPath = Join-Path $packRoot '工具\安装.ps1'
$tokens = $null
$parseErrors = $null
$installerAst = [System.Management.Automation.Language.Parser]::ParseFile($installerPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw ("安装脚本语法无效，无法验证发布资源清单: " + $parseErrors[0].Message)
}
$manifestAssignments = @($installerAst.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $node.Left.VariablePath.UserPath -in @('dllList', 'assetList')
}, $true))
$manifestNames = @($manifestAssignments | ForEach-Object { $_.Left.VariablePath.UserPath })
if (-not ($manifestNames -contains 'dllList') -or -not ($manifestNames -contains 'assetList')) {
    throw '安装脚本缺少可识别的 DLL/资源清单，无法验证发布完整性。'
}
foreach ($assignment in $manifestAssignments) {
    $paths = @($assignment.Right.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
    }, $true) | ForEach-Object { $_.Value })
    foreach ($relative in $paths) {
        $sourcePath = Join-Path $packRoot $relative
        if ([IO.File]::Exists($sourcePath)) {
            $requiredFiles += $relative
        } elseif ([IO.Directory]::Exists($sourcePath)) {
            $children = Get-ChildItem $sourcePath -Recurse -File -Force
            foreach ($child in $children) {
                $requiredFiles += $child.FullName.Substring($packRoot.Length).TrimStart('\')
            }
        } else {
            [void]$missingFiles.Add($relative)
        }
    }
}
$installerBody = [IO.File]::ReadAllText($installerPath, [Text.Encoding]::UTF8)
$installerRefs = [regex]::Matches($installerBody, "'([^']+\.(?:ps1|tsv))'") |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
$generatedReports = @('event-residuals.tsv', 'basegame-event-residuals.tsv')
foreach ($relative in $installerRefs) {
    if ($generatedReports -contains $relative) { continue }
    $sourcePath = Join-Path $PSScriptRoot $relative
    if ([IO.File]::Exists($sourcePath)) {
        $requiredFiles += (Join-Path '工具' $relative)
    } else {
        [void]$missingFiles.Add((Join-Path '工具' $relative))
    }
}
$requiredFiles = @($requiredFiles | Sort-Object -Unique)
$missingFiles.AddRange([string[]]@($requiredFiles | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $packRoot $_) -PathType Leaf)
}))
if ($missingFiles.Count -gt 0) {
    throw ("打包前检查失败，缺少必需文件: " + ($missingFiles.ToArray() -join ', '))
}

$files = Get-ChildItem $packRoot -Recurse -File -Force | Where-Object {
    $rel = $_.FullName.Substring($packRoot.Length).TrimStart('\')
    if ($rel -like 'RT汉化包*.zip') { return $false }
    if (@($rel -split '[\\/]' | Where-Object { $_ -in $excludeDirs }).Count -gt 0) { return $false }
    if ($rel -match '(?i)(^|\\)__pycache__(\\|$)' -or $_.Extension -in @('.pyc', '.pyo')) { return $false }
    # 排除人工审校工作簿、.zhbak / 临时产物
    if ($_.Name -eq '对白本土化审校_第一批.xlsx') { return $false }
    if ($_.Name -like '*.zhbak*') { return $false }
    return $true
}

Write-Host ("待打包文件数: " + $files.Count)
$total = ($files | Measure-Object -Property Length -Sum).Sum
Write-Host ("原始大小: " + [Math]::Round($total/1MB,1) + " MB")

$archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
try {
    $n = 0
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($packRoot.Length).TrimStart('\')
        $entryName = $rel -replace '\\', '/'
        $entry = $archive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
        $es = $entry.Open()
        $fs = [IO.File]::OpenRead($f.FullName)
        try { $fs.CopyTo($es) } finally { $fs.Close(); $es.Close() }
        $n++
        if ($n % 100 -eq 0) { Write-Host ("  " + $n + " ...") }
    }
} finally { $archive.Dispose() }

$zi = Get-Item $zip
Write-Host ("完成: " + $zi.Name + "  " + [Math]::Round($zi.Length/1MB,1) + " MB  " + $n + " 个文件")

$check = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    $entryNames = @($check.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
    $requiredEntries = @($requiredFiles | ForEach-Object { $_ -replace '\\', '/' })
    $missingEntries = @($requiredEntries | Where-Object { $entryNames -notcontains $_ })
    $excludedEntries = @($entryNames | Where-Object { $_ -match '(?i)(^|/)(\.git|backup)(/|$)' })
    if ($missingEntries.Count -gt 0) {
        throw ("打包校验失败，ZIP 缺少必需文件: " + ($missingEntries -join ', '))
    }
    if ($excludedEntries.Count -gt 0) {
        throw ("打包校验失败，ZIP 意外包含排除目录: " + ($excludedEntries -join ', '))
    }
    if ($entryNames.Count -ne $n) {
        throw ("打包校验失败，预期文件数 " + $n + "，ZIP 实际条目数 " + $entryNames.Count)
    }
} finally {
    $check.Dispose()
}
Write-Host ("ZIP 校验通过: 必需文件 " + $requiredFiles.Count + " 项，排除目录无泄漏")
