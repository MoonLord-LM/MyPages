@echo off
chcp 65001 >nul
setlocal disabledelayedexpansion
set "script=%~0" & set "script_path=%~f0" & set "script_dir=%~dp0" & set "script_name=%~n0" & set "script_ext=%~x0" & set "script_name_ext=%~nx0"
setlocal enabledelayedexpansion
if /i "!cd!"=="!SystemRoot!\System32" ( cd /d "!script_dir!" )
powershell -NoProfile -Command "Write-Host '[ !script_name_ext! ]' -ForegroundColor Cyan" && echo.



powershell -NoProfile -Command "Write-Host '清理 quark.json 中的夸克网盘资源链接，删除已失效链接' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '失效链接的 URL 保存到 quark-invalid.json' -ForegroundColor Green"
echo.



set "json_file=!script_dir!quark.json"
set "invalid_file=!script_dir!quark-invalid.json"
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
$invalidPath = $env:invalid_file
$utf8 = [System.Text.UTF8Encoding]::new($false)
$pattern = '(?s)\{(?:[^{}]|"(?:\\.|[^"\\])*")*\}'

try {
    $raw = [System.IO.File]::ReadAllText($jsonPath, [System.Text.Encoding]::UTF8)
    $records = ConvertFrom-Json -InputObject $raw
} catch {
    Write-Host '错误：数据文件解析失败' -ForegroundColor Red
    exit 1
}

$total = @($records).Count
if ($total -eq 0) {
    Write-Host '数据文件为空'
    exit 0
}

$elements = [regex]::Matches($raw, $pattern)
if ($elements.Count -ne $total) {
    Write-Host '错误：数据结构不匹配' -ForegroundColor Red
    exit 1
}

$drop = [bool[]]::new($total)
$dropCount = 0
$invalidUrls = [System.Collections.Generic.List[string]]::new()
for ($i = 0; $i -lt $total; $i++) {
    $prop = $records[$i].PSObject.Properties['check_valid']
    if ($null -ne $prop -and $prop.Value -is [bool] -and -not $prop.Value) {
        $drop[$i] = $true
        $dropCount++
        $url = [string]$records[$i].url
        if ($url) { $invalidUrls.Add($url) }
    }
}

if ($dropCount -eq 0) {
    Write-Host ('清理完成：共 ' + $total + ' 条，无失效链接') -ForegroundColor Green
    exit 0
}

$sb = [System.Text.StringBuilder]::new()
[void]$sb.Append($raw.Substring(0, $elements[0].Index))
$kept = 0
for ($i = 0; $i -lt $total; $i++) {
    if ($drop[$i]) { continue }
    if ($kept -gt 0) {
        $prevEnd = $elements[$i - 1].Index + $elements[$i - 1].Length
        $gap = $raw.Substring($prevEnd, $elements[$i].Index - $prevEnd)
        $comma = $gap.IndexOf(',')
        if ($comma -lt 0) {
            Write-Host '错误：数据结构不匹配' -ForegroundColor Red
            exit 1
        }
        [void]$sb.Append(',')
        [void]$sb.Append($gap.Substring($comma + 1))
    }
    [void]$sb.Append($elements[$i].Value)
    $kept++
}

if ($kept -eq 0) {
    $outText = '[]' + $raw.Substring($raw.LastIndexOf(']') + 1)
} else {
    $last = $elements[$total - 1]
    [void]$sb.Append($raw.Substring($last.Index + $last.Length))
    $outText = $sb.ToString()
}

try {
    $checked = ConvertFrom-Json -InputObject $outText
    if (@($checked).Count -ne $kept) { throw 'count' }
    foreach ($r in $checked) {
        $prop = $r.PSObject.Properties['check_valid']
        if ($null -ne $prop -and $prop.Value -is [bool] -and -not $prop.Value) { throw 'false' }
    }
} catch {
    Write-Host '错误：结果校验失败' -ForegroundColor Red
    exit 1
}

try {
    $invalidList = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    if ([System.IO.File]::Exists($invalidPath)) {
        $invalidRaw = [System.IO.File]::ReadAllText($invalidPath, [System.Text.Encoding]::UTF8)
        if (-not [string]::IsNullOrWhiteSpace($invalidRaw)) {
            $oldRecords = ConvertFrom-Json -InputObject $invalidRaw
            foreach ($old in $oldRecords) {
                if ($null -eq $old) { continue }
                $oldUrl = [string]$old.url
                if ($oldUrl -and $seen.Add($oldUrl)) {
                    $invalidList.Add([pscustomobject][ordered]@{ url = $oldUrl })
                }
            }
        }
    }
    foreach ($url in $invalidUrls) {
        if ($seen.Add($url)) {
            $invalidList.Add([pscustomobject][ordered]@{ url = $url })
        }
    }
    $invalidText = ConvertTo-Json -InputObject $invalidList -Depth 5
    [System.IO.File]::WriteAllText($invalidPath, $invalidText + "`n", $utf8)
} catch {
    Write-Host '错误：保存失效记录失败' -ForegroundColor Red
    exit 1
}

try {
    [System.IO.File]::WriteAllText($jsonPath, $outText, $utf8)
} catch {
    Write-Host '错误：写入结果失败' -ForegroundColor Red
    exit 1
}

Write-Host ('清理完成：共 ' + $total + ' 条，删除 ' + $dropCount + ' 条，保留 ' + $kept + ' 条') -ForegroundColor Green
Write-Host ('已写回: ' + $jsonPath) -ForegroundColor Green
Write-Host ('已保存失效链接: ' + $invalidPath)
exit 0
-----END POWERSHELL CODE-----
