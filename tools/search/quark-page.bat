@echo off
chcp 65001 >nul
setlocal disabledelayedexpansion
set "script=%~0" & set "script_path=%~f0" & set "script_dir=%~dp0" & set "script_name=%~n0" & set "script_ext=%~x0" & set "script_name_ext=%~nx0"
setlocal enabledelayedexpansion
if /i "!cd!"=="!SystemRoot!\System32" ( cd /d "!script_dir!" )
powershell -NoProfile -Command "Write-Host '[ !script_name_ext! ]' -ForegroundColor Cyan" && echo.



powershell -NoProfile -Command "Write-Host '读取 quark.json 中的夸克网盘资源链接，按天生成资源收录页面' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '资源收录页面，以 md 文件，保存在 /pages/service/internet-search/quark 中' -ForegroundColor Green"
echo.



set "json_file=!script_dir!quark.json"
set "page_dir=!script_dir!..\..\pages\service\internet-search\quark"
if not exist "!json_file!" (
    echo 错误：未找到数据文件 "!json_file!"
    echo.
    pause
    exit /b 1
)



REM 从自身文件末尾的 -----BEGIN POWERSHELL CODE----- / -----END POWERSHELL CODE----- 之间提取 PowerShell 代码
set "begin_marker=-----BEGIN POWERSHELL CODE-----"
set "end_marker=-----END POWERSHELL CODE-----"
powershell -NoProfile -Command ^
    "[System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8;" ^
    "$lines = Get-Content -Encoding UTF8 -LiteralPath $env:script_path;" ^
    "$begin = [array]::IndexOf($lines, $env:begin_marker) + 1;" ^
    "$end = [array]::IndexOf($lines, $env:end_marker);" ^
    "if ($begin -lt 1 -or $end -lt $begin) {" ^
    "    Write-Host '错误：未找到内嵌的 PowerShell 代码块' -ForegroundColor Red;" ^
    "    exit 1;" ^
    "};" ^
    "$code = $lines[$begin..($end - 1)] -join [System.Environment]::NewLine;" ^
    "Invoke-Expression $code"
if !errorlevel! neq 0 (
    echo 错误：处理失败
    echo.
    pause
    exit /b 1
)



echo.
pause
exit /b



-----BEGIN POWERSHELL CODE-----
[System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8;
$jsonPath = $env:json_file
$pageDir = [System.IO.Path]::GetFullPath($env:page_dir)
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Escape-Md([string]$text) {
    $t = $text.Replace("`r", ' ').Replace("`n", ' ')
    $t = $t.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
    foreach ($ch in @('\', '`', '*', '_', '[', ']', '|', '#')) {
        $t = $t.Replace($ch, '\' + $ch)
    }
    return $t
}

function Format-Size($value) {
    if ($null -eq $value) { return '—' }
    $bytes = 0.0
    if (-not [double]::TryParse([string]$value, [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture, [ref]$bytes)) { return '—' }
    if ($bytes -lt 0) { return '—' }
    if ($bytes -lt 1024) { return ([int64]$bytes).ToString() + ' B' }
    $units = @('KB', 'MB', 'GB', 'TB', 'PB')
    $size = $bytes / 1024
    $i = 0
    while ($size -ge 1024 -and $i -lt 4) { $size = $size / 1024; $i++ }
    return $size.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture) + ' ' + $units[$i]
}

try {
    $raw = [System.IO.File]::ReadAllText($jsonPath, [System.Text.Encoding]::UTF8)
    $records = ConvertFrom-Json -InputObject $raw
} catch {
    Write-Host ('错误：数据文件解析失败 - ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

$total = @($records).Count
if ($total -eq 0) {
    Write-Host '数据文件为空' -ForegroundColor Green
    exit 0
}

$groups = @{}
$valid = 0
$invalid = 0
$skipped = 0
foreach ($rec in $records) {
    $prop = $rec.PSObject.Properties['check_valid']
    $mark = if ($null -ne $prop -and $prop.Value -eq $false) { '❌' } else { '✅' }

    $time = [string]$rec.time
    $url = [string]$rec.url
    if ($time -notmatch '^(\d{4}-\d{2}-\d{2}) \d{2}:\d{2}$') { $skipped++; continue }
    $day = $Matches[1]
    if ($url -notmatch '^https://pan\.quark\.cn/s/[A-Za-z0-9]+$') { $skipped++; continue }

    if (-not $groups.ContainsKey($day)) {
        $groups[$day] = [System.Collections.Generic.List[string]]::new()
    }
    $title = [string]$rec.title
    if ([string]::IsNullOrWhiteSpace($title)) { $title = '（无标题）' }
    $count = [string]$rec.file_count
    if ([string]::IsNullOrWhiteSpace($count)) { $count = '—' }
    $size = Format-Size $rec.file_size
    $groups[$day].Add('- ' + $mark + ' [' + (Escape-Md $title) + '](' + $url + ')（文件数 ' + $count + '，大小 ' + $size + '）')
    if ($mark -eq '✅') { $valid++ } else { $invalid++ }
}

$pages = [System.Collections.Generic.List[object]]::new()
foreach ($day in ($groups.Keys | Sort-Object)) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# ' + $day + ' 夸克网盘资源收录')
    $lines.Add('')
    $lines.Add('共 ' + $groups[$day].Count + ' 条资源，✅ 有效 ❌ 失效')
    $lines.Add('')
    foreach ($line in $groups[$day]) { $lines.Add($line) }
    $pages.Add([pscustomobject]@{
        Name = $day + '.md'
        Text = ($lines -join "`r`n") + "`r`n"
    })
}

try {
    [System.IO.Directory]::CreateDirectory($pageDir) | Out-Null
    foreach ($file in [System.IO.Directory]::GetFiles($pageDir, '*.md')) {
        [System.IO.File]::Delete($file)
    }
    foreach ($page in $pages) {
        [System.IO.File]::WriteAllText([System.IO.Path]::Combine($pageDir, $page.Name), $page.Text, $utf8)
    }
} catch {
    Write-Host ('错误：写入页面失败 - ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

Write-Host ('生成完成：共 ' + $total + ' 条，有效 ' + $valid + ' 条，失效 ' + $invalid + ' 条，跳过 ' + $skipped + ' 条，生成 ' + $pages.Count + ' 个页面') -ForegroundColor Green
Write-Host ('页面目录: ' + $pageDir)
-----END POWERSHELL CODE-----
