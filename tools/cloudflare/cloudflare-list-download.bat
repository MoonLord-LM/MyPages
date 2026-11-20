@echo off
chcp 65001 >nul
setlocal disabledelayedexpansion
set "script=%~0" & set "script_path=%~f0" & set "script_dir=%~dp0" & set "script_name=%~n0" & set "script_ext=%~x0" & set "script_name_ext=%~nx0"
setlocal enabledelayedexpansion
if /i "!cd!"=="!SystemRoot!\System32" ( cd /d "!script_dir!" )
powershell -NoProfile -Command "Write-Host '[ !script_name_ext! ]' -ForegroundColor Cyan" && echo.



powershell -NoProfile -Command "Write-Host '从 Cloudflare Pages 下载静态资源清单，按清单与哈希值同步本地文件' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '同步到 dist/static：删除多余、补齐缺失、校验已有文件哈希并重新下载不符项' -ForegroundColor Green"
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
    echo 错误：同步静态资源失败，请检查上面的报错信息
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
Add-Type -AssemblyName Microsoft.VisualBasic;

$staticDir = [System.IO.Path]::GetFullPath($env:static_dir);
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
    return [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($staticDir, $relative.Replace('/', '\')));
}

function Get-NameFingerprint($FileName) {
    $match = [regex]::Match($FileName, '\.([\da-fA-F]{128})\.[^.\\/]+$');
    if ($match.Success) {
        return $match.Groups[1].Value.ToLowerInvariant();
    }
    return $null;
}

function Get-FileFingerprint($Path) {
    $sha = [System.Security.Cryptography.SHA512]::Create();
    try {
        $stream = [System.IO.File]::OpenRead($Path);
        try {
            $hashBytes = $sha.ComputeHash($stream);
            return ([System.BitConverter]::ToString($hashBytes).Replace('-', '')).ToLowerInvariant();
        } finally {
            $stream.Dispose();
        }
    } finally {
        $sha.Dispose();
    }
}

$tempListFile = [System.IO.Path]::Combine($env:TEMP, 'cloudflare-list-' + [guid]::NewGuid().ToString('N') + '.json');
Write-Host ('下载清单: ' + $listUrl);
try {
    Invoke-WebRequest -Uri $listUrl -OutFile $tempListFile -UseBasicParsing -ErrorAction Stop;
    $parsedEntries = Get-Content -LiteralPath $tempListFile -Encoding UTF8 -Raw | ConvertFrom-Json;
} catch {
    throw ('下载或解析清单失败: ' + $_.Exception.Message);
}

$entries = @($parsedEntries | ForEach-Object { $_ });
Write-Host ('清单条目数: ' + $entries.Count);
if ($entries.Count -lt 1) {
    Remove-Item -Force -LiteralPath $tempListFile -ErrorAction SilentlyContinue;
    throw '线上清单为空，终止同步';
}
[System.IO.File]::Copy($tempListFile, $listFile, $true);
Remove-Item -Force -LiteralPath $tempListFile;
Write-Host ('清单已保存: ' + $listFile);

$expectedMap = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase);
foreach ($entry in $entries) {
    $localPath = Get-LocalPath $entry.file;
    $fingerprint = Get-NameFingerprint ([System.IO.Path]::GetFileName($localPath));
    if ([string]::IsNullOrEmpty($fingerprint)) {
        Write-Host ('警告：清单条目缺少有效指纹，已跳过: ' + $entry.file);
        continue;
    }
    $expectedMap[$localPath] = [pscustomobject]@{
        Fingerprint = $fingerprint;
        Url         = [string]$entry.url[0];
    };
}
Write-Host ('有效清单文件数: ' + $expectedMap.Count);

$excludeNames = @('list.json', 'upload.bat', $env:script_name_ext);
$deletedCount = 0;
foreach ($file in [System.IO.Directory]::GetFiles($staticDir, '*', [System.IO.SearchOption]::AllDirectories)) {
    $fullName = [System.IO.Path]::GetFullPath($file);
    if ($excludeNames -contains ([System.IO.Path]::GetFileName($fullName))) { continue; }
    if ($expectedMap.ContainsKey($fullName)) { continue; }
    try {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($fullName, 'OnlyErrorDialogs', 'SendToRecycleBin');
        Write-Host ('删除多余文件: ' + $fullName.Substring($staticDir.Length).TrimStart('\'));
        $deletedCount++;
    } catch {
        throw ('删除多余文件失败: ' + $_.Exception.Message);
    }
}

$missingCount = 0;
$redownloadCount = 0;
$verifiedCount = 0;

foreach ($localPath in ($expectedMap.Keys | Sort-Object)) {
    $expected = $expectedMap[$localPath];
    $fingerprint = $expected.Fingerprint;
    $relativePath = $localPath.Substring($staticDir.Length).TrimStart('\');

    if (Test-Path -LiteralPath $localPath) {
        $actualFingerprint = Get-FileFingerprint $localPath;
        if ($actualFingerprint -eq $fingerprint) {
            $verifiedCount++;
            continue;
        }
        Write-Host ('哈希不符，重新下载: ' + $relativePath);
        $redownloadCount++;
    } else {
        Write-Host ('缺失，下载: ' + $relativePath);
        $missingCount++;
    }

    $directory = [System.IO.Path]::GetDirectoryName($localPath);
    if (-not (Test-Path -LiteralPath $directory)) {
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null;
    }
    try {
        Invoke-WebRequest -Uri $expected.Url -OutFile $localPath -UseBasicParsing -ErrorAction Stop;
        $downloadedFingerprint = Get-FileFingerprint $localPath;
        if ($downloadedFingerprint -ne $fingerprint) {
            throw ('下载文件哈希不符，期望 ' + $fingerprint + '，实际 ' + $downloadedFingerprint);
        }
    } catch {
        throw ('下载文件失败: ' + $relativePath + ' - ' + $_.Exception.Message);
    }
}

Write-Host '';
Write-Host ('同步完成：校验通过 ' + $verifiedCount + ' 个，新下载 ' + $missingCount + ' 个，重新下载 ' + $redownloadCount + ' 个，删除多余 ' + $deletedCount + ' 个') -ForegroundColor Green;
-----END POWERSHELL CODE-----
