@echo off
chcp 65001 >nul
setlocal disabledelayedexpansion
set "script=%~0" & set "script_path=%~f0" & set "script_dir=%~dp0" & set "script_name=%~n0" & set "script_ext=%~x0" & set "script_name_ext=%~nx0"
setlocal enabledelayedexpansion
if /i "!cd!"=="!SystemRoot!\System32" ( cd /d "!script_dir!" )
powershell -NoProfile -Command "Write-Host '[ !script_name_ext! ]' -ForegroundColor Cyan" && echo.



powershell -NoProfile -Command "Write-Host '从 Cloudflare Pages 下载静态资源清单，并按清单恢复静态资源文件' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '恢复到 dist/static 目录，供重新部署时一并上传' -ForegroundColor Green"
echo.



REM 静态资源文件文件夹
for %%i in ("!script_dir!..\..\dist\static") do set "static_dir=%%~fi"

REM 线上静态资源清单地址
set "list_url=https://cloudflare.moonlord.cc/static/list.json"



REM 从自身文件末尾的 -----BEGIN POWERSHELL CODE----- / -----END POWERSHELL CODE----- 之间提取 PowerShell 代码
powershell -NoProfile -Command ^
    "[System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8;" ^
    "$lines = Get-Content -Encoding UTF8 -LiteralPath $env:script_path;" ^
    "$begin = [array]::IndexOf($lines, '-----BEGIN POWERSHELL CODE-----') + 1;" ^
    "$end = [array]::IndexOf($lines, '-----END POWERSHELL CODE-----');" ^
    "if ($begin -lt 1 -or $end -lt $begin) {" ^
    "    Write-Host '错误：未找到内嵌的 PowerShell 代码块' -ForegroundColor Red;" ^
    "    exit 1;" ^
    "};" ^
    "$code = $lines[$begin..($end - 1)] -join [System.Environment]::NewLine;" ^
    "Invoke-Expression $code"
if !errorlevel! neq 0 (
    echo 错误：下载静态资源失败，请检查上面的报错信息
    echo.
    pause
    exit /b 1
)
echo.



echo.
pause
exit /b



-----BEGIN POWERSHELL CODE-----
[System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8;
$ProgressPreference='SilentlyContinue';

$staticDir = $env:static_dir;
$listUrl = $env:list_url;
$listFile = [System.IO.Path]::Combine($staticDir, 'list.json');

if (-not (Test-Path -LiteralPath $staticDir)) {
    [System.IO.Directory]::CreateDirectory($staticDir) | Out-Null;
}

function Get-LocalPath($FileField) {
    $relative = [System.Uri]::UnescapeDataString($FileField).TrimStart('/');
    if ($relative.StartsWith('static/')) {
        $relative = $relative.Substring('static/'.Length);
    }
    return [System.IO.Path]::Combine($staticDir, $relative.Replace('/', '\'));
}

Write-Host ('下载清单: ' + $listUrl);
Invoke-WebRequest -Uri $listUrl -OutFile $listFile -UseBasicParsing -ErrorAction Stop;

$parsedEntries = Get-Content -LiteralPath $listFile -Encoding UTF8 -Raw | ConvertFrom-Json;
$entries = @($parsedEntries | ForEach-Object { $_ });
Write-Host ('清单条目数: ' + $entries.Count);
if ($entries.Count -lt 1) {
    throw '线上清单为空，终止下载';
}

$downloadEntries = @($entries);

$downloaded = 0;
foreach ($entry in $downloadEntries) {
    $downloaded++;
    Write-Host ('下载第 ' + $downloaded + ' 个文件')
    $destination = Get-LocalPath $entry.file;
    $directory = [System.IO.Path]::GetDirectoryName($destination);
    if (-not (Test-Path -LiteralPath $directory)) {
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null;
    }
    Invoke-WebRequest -Uri $entry.url[0] -OutFile $destination -UseBasicParsing -ErrorAction Stop;
}

Write-Host '';
Write-Host ('下载完成，共下载 ' + $downloaded + ' 个文件') -ForegroundColor Green;
-----END POWERSHELL CODE-----
