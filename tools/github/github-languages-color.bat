@echo off
chcp 65001 >nul
setlocal disabledelayedexpansion
set "script=%~0" & set "script_path=%~f0" & set "script_dir=%~dp0" & set "script_name=%~n0" & set "script_ext=%~x0" & set "script_name_ext=%~nx0"
setlocal enabledelayedexpansion
if /i "!cd!"=="!SystemRoot!\System32" ( cd /d "!script_dir!" )
powershell -NoProfile -Command "Write-Host '[ !script_name_ext! ]' -ForegroundColor Cyan" && echo.



powershell -NoProfile -Command "Write-Host '采集 GitHub Linguist 的编程语言和颜色的映射，生成 languages-color.json 文件' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '采集来源 https://github.com/github-linguist/linguist/blob/main/lib/linguist/languages.yml' -ForegroundColor Green"
echo.



set "remote_url=https://raw.githubusercontent.com/github-linguist/linguist/refs/heads/main/lib/linguist/languages.yml"
set "languages_yml_file=!script_dir!languages.yml"
set "output_json=!script_dir!languages-color.json"



powershell -NoProfile -Command ^
    "[System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8;" ^
    "$ProgressPreference='SilentlyContinue';" ^
    "Invoke-WebRequest -Uri $env:remote_url -OutFile $env:languages_yml_file -UseBasicParsing;"
if !errorlevel! neq 0 (
    echo 错误：下载 !languages_yml_file! 文件失败，请检查报错信息
    echo.
    pause
    exit /b 1
)
echo 已下载 !languages_yml_file! 文件
echo.



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
    echo 错误：生成 !output_json! 文件失败，请检查报错信息
    echo.
    pause
    exit /b 1
)
echo.
echo 已生成 !output_json! 文件
echo.



echo.
pause
exit /b



-----BEGIN POWERSHELL CODE-----
[System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8;

$sourcePath = $env:languages_yml_file
$outputPath = $env:output_json

if (-not ([System.IO.File]::Exists($sourcePath))) {
    Write-Host ('源文件不存在: ' + $sourcePath) -ForegroundColor Red
    exit 1
}

$content = [System.IO.File]::ReadAllText($sourcePath, [System.Text.Encoding]::UTF8)
$lines = $content -split '\r?\n'

$colorMap = [System.Collections.Specialized.OrderedDictionary]::new()
$currentKey = $null

foreach ($line in $lines) {
    if ($line -match '^([^\s#][^:]*?):\s*$') {
        $currentKey = $Matches[1].Trim()
        continue
    }
    if ($line -match '^\s+color:\s*(.+?)\s*$') {
        $colorValue = $Matches[1].Trim().Trim([char]34)
        if ($currentKey -and $colorValue) {
            $colorMap[$currentKey] = $colorValue
        }
    }
}

$jsonLines = @()
foreach ($key in $colorMap.Keys) {
    $escapedKey = $key.Replace('\', '\\').Replace('"', '\"')
    $jsonLines += ('    "' + $escapedKey + '": "' + $colorMap[$key] + '"')
}
$json = '{' + [System.Environment]::NewLine + ($jsonLines -join (',' + [System.Environment]::NewLine)) + [System.Environment]::NewLine + '}'

$utf8NoBOM = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($outputPath, $json, $utf8NoBOM)

Write-Host ('共计 ' + $colorMap.Count + ' 种语言颜色')
-----END POWERSHELL CODE-----
