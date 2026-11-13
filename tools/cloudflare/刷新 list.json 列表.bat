@echo off
chcp 65001 >nul
setlocal disabledelayedexpansion
set "script=%~0" & set "script_path=%~f0" & set "script_dir=%~dp0" & set "script_name=%~n0" & set "script_ext=%~x0" & set "script_name_ext=%~nx0"
setlocal enabledelayedexpansion
if /i "!cd!"=="!SystemRoot!\System32" ( cd /d "!script_dir!" )
powershell -NoProfile -Command "Write-Host '[ !script_name_ext! ]' -ForegroundColor Cyan" && echo.



powershell -NoProfile -Command "Write-Host '扫描指定文件夹下的所有文件，生成 list.json 列表' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '自动重命名缺少指纹或指纹与内容不符的文件' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '自动计算上传到 Cloudflare Pages 后的访问 URL' -ForegroundColor Green"
echo.



REM 静态资源文件文件夹（相对本脚本目录）
for %%i in ("!script_dir!..\..\dist\static") do set "static_dir=%%~fi"

REM list.json 中 URL 的前缀
set "cloudflare_url_prefix1=https://cloudflare.moonlord.cc/static/"
set "cloudflare_url_prefix2=https://moonlord.pages.dev/static/"



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
    echo 错误：生成 list.json 失败，请检查上面的报错信息
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

$scanDir = $env:static_dir;
$outputFile = [System.IO.Path]::Combine($env:static_dir, 'list.json');
$excludeNames = @($env:script_name_ext, 'upload.bat', 'list.json');
$pathPrefix = '/static/';
$urlPrefixCloudflare = $env:cloudflare_url_prefix1;
$urlPrefixPages = $env:cloudflare_url_prefix2;
$fpLen = 128;

function Get-FileFingerprint($Path) {
    $sha = [System.Security.Cryptography.SHA512]::Create();
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path);
        $hash = $sha.ComputeHash($bytes);
        return ([System.BitConverter]::ToString($hash).Replace('-', '')).ToLowerInvariant().Substring(0, $fpLen);
    } finally {
        $sha.Dispose();
    }
}

# 计算文件相对于扫描根目录（static）的路径
function Get-RelativePath($FullPath) {
    return $FullPath.Substring($scanDir.Length).TrimStart('\');
}

# 匹配“基名.<指纹>.扩展名”的格式
$fpRegex = '^(.*)\.([0-9a-f]{' + $fpLen + '})\.([^.]+)$';

$renamedCount = 0;
$finalRels = @();

foreach ($item in (Get-ChildItem -LiteralPath $scanDir -File -Recurse)) {
    if ($excludeNames -contains $item.Name) { continue; }

    $fp = Get-FileFingerprint $item.FullName;
    $name = $item.Name;
    $hasFp = $false;
    $expectedName = $null;
    $fpMatch = [regex]::Match($name, $fpRegex);

    if ($fpMatch.Success) {
        if ($fpMatch.Groups[2].Value -eq $fp) {
            $hasFp = $true;
            $expectedName = $name;
        } else {
            # 指纹与内容不符，用正确指纹重命名
            $expectedName = $fpMatch.Groups[1].Value + '.' + $fp + '.' + $fpMatch.Groups[3].Value;
        }
    } else {
        # 无指纹，在扩展名前拼接
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($name);
        $ext  = [System.IO.Path]::GetExtension($name);
        $expectedName = $stem + '.' + $fp + $ext;
    }

    if ($hasFp) {
        $finalRels += Get-RelativePath $item.FullName;
    } else {
        $targetPath = [System.IO.Path]::Combine($item.DirectoryName, $expectedName);
        if (Test-Path -LiteralPath $targetPath) {
            Write-Host ('跳过（目标已存在）: ' + $name + ' -> ' + $expectedName);
            $finalRels += Get-RelativePath $item.FullName;
        } else {
            Move-Item -LiteralPath $item.FullName -Destination $targetPath;
            $renamedCount++;
            Write-Host ('重命名: ' + $name + ' -> ' + $expectedName);
            $finalRels += Get-RelativePath $targetPath;
        }
    }
}

[System.Array]::Sort($finalRels, [System.StringComparer]::Ordinal);

$blocks = foreach ($rel in $finalRels) {
    $encodedRel = $rel -replace '\\', '/' -replace ' ', '%20';
    $filePath = $pathPrefix + $encodedRel;
    $urlCloudflare = $urlPrefixCloudflare + $encodedRel;
    $urlPages = $urlPrefixPages + $encodedRel;

    '    {' + [System.Environment]::NewLine +
    '        "file":  "' + $filePath + '",' + [System.Environment]::NewLine +
    '        "url":  [' + [System.Environment]::NewLine +
    '            "' + $urlCloudflare + '",' + [System.Environment]::NewLine +
    '            "' + $urlPages + '"' + [System.Environment]::NewLine +
    '        ]' + [System.Environment]::NewLine +
    '    }';
}

$json = '[' + [System.Environment]::NewLine + ($blocks -join (',' + [System.Environment]::NewLine)) + [System.Environment]::NewLine + ']';
[System.IO.File]::WriteAllText($outputFile, $json, [System.Text.UTF8Encoding]::new($false));

Write-Host ('已重命名 ' + $renamedCount + ' 个文件');
Write-Host ''
Write-Host ('已生成 list.json，共 ' + $finalRels.Count + ' 个文件') -ForegroundColor Green;
-----END POWERSHELL CODE-----
