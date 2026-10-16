@echo off
chcp 65001 >nul
setlocal disabledelayedexpansion
set "script=%~0" & set "script_path=%~f0" & set "script_dir=%~dp0" & set "script_name=%~n0" & set "script_ext=%~x0" & set "script_name_ext=%~nx0"
setlocal enabledelayedexpansion
if /i "!cd!"=="!SystemRoot!\System32" ( cd /d "!script_dir!" )
powershell -NoProfile -Command "Write-Host '[ !script_name_ext! ]' -ForegroundColor Cyan" && echo.



powershell -NoProfile -Command "Write-Host '处理当前目录中的工具脚本' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '运行 github\github-profile.bat 脚本，并同步生成的文件，到 ..\pages\github 目录' -ForegroundColor Green"
echo.



set "gen_tool=!script_dir!github\github-profile.bat"
set "src_dir=!script_dir!github\profile"
set "dst_dir=!script_dir!..\pages\github"



echo 开始运行生成器: !gen_tool! & REM
echo 生成结果目录: !src_dir! & REM
echo.

call "!gen_tool!" <nul
if !errorlevel! neq 0 (
    echo 错误：生成器执行失败，已终止同步
    echo.
    pause
    exit /b 1
)
if not exist "!src_dir!" (
    echo 错误：未找到生成结果目录 "!src_dir!"
    echo.
    pause
    exit /b 1
)
echo 生成器执行完成
echo.

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
    echo 错误：文件同步到 "!dst_dir!" 失败
    echo.
    pause
    exit /b 1
)
echo 文件同步完成: !dst_dir!
echo.



echo.
pause
exit /b



-----BEGIN POWERSHELL CODE-----
[System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8;

$srcDir = $env:src_dir
$dstDir = $env:dst_dir

if (-not ([System.IO.Directory]::Exists($srcDir))) {
    Write-Host ('错误：源目录不存在: ' + $srcDir) -ForegroundColor Red
    exit 1
}

function Copy-Dir-Tree {
    param([string]$Src, [string]$Dst)
    foreach ($entry in [System.IO.Directory]::GetFileSystemEntries($Src)) {
        $name = [System.IO.Path]::GetFileName($entry)
        $target = [System.IO.Path]::Combine($Dst, $name)
        if ([System.IO.Directory]::Exists($entry)) {
            [System.IO.Directory]::CreateDirectory($target) | Out-Null
            Copy-Dir-Tree -Src $entry -Dst $target
        } else {
            [System.IO.File]::Copy($entry, $target, $true)
        }
    }
}

try {
    if ([System.IO.Directory]::Exists($dstDir)) {
        [System.IO.Directory]::Delete($dstDir, $true)
    }
    [System.IO.Directory]::CreateDirectory($dstDir) | Out-Null
    Copy-Dir-Tree -Src $srcDir -Dst $dstDir
    Write-Host ('已同步: ' + $dstDir)
} catch {
    Write-Host ('错误：同步失败: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
-----END POWERSHELL CODE-----
