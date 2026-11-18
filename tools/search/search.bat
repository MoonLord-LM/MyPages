@echo off
chcp 65001 >nul
setlocal disabledelayedexpansion
set "script=%~0" & set "script_path=%~f0" & set "script_dir=%~dp0" & set "script_name=%~n0" & set "script_ext=%~x0" & set "script_name_ext=%~nx0"
setlocal enabledelayedexpansion
if /i "!cd!"=="!SystemRoot!\System32" ( cd /d "!script_dir!" )
powershell -NoProfile -Command "Write-Host '[ !script_name_ext! ]' -ForegroundColor Cyan" && echo.



echo 调用当前目录中的工具脚本
echo 调用 quark-catch-1.bat 脚本，采集夸克网盘资源链接
echo 调用 quark-catch-2.bat 脚本，采集夸克网盘资源链接
echo 调用 quark-catch-3.bat 脚本，采集夸克网盘资源链接
echo 调用 quark-update 3000.bat 脚本，更新搜索数据与资源收录页面
echo.



REM 设置 Git 仓库的本地配置
git config --local core.autocrlf false
git config --local core.safecrlf false
git config --local core.ignorecase false
git config --local core.quotepath false
git config --local i18n.logoutputencoding utf-8
git config --local i18n.commitencoding utf-8

echo.
echo 当前 Git 配置：
git config --local --list
echo.



set "tool1=!script_dir!quark-catch-1.bat"
set "tool2=!script_dir!quark-catch-2.bat"
set "tool3=!script_dir!quark-catch-3.bat"
set "tool4=!script_dir!quark-update 3000.bat"

echo 开始调用: !tool1! & REM
echo.
call "!tool1!" <nul
if !errorlevel! neq 0 (
    echo 错误：执行失败
    echo.
    pause
    exit /b 1
)

echo 开始调用: !tool2! & REM
echo.
call "!tool2!" <nul
if !errorlevel! neq 0 (
    echo 错误：执行失败
    echo.
    pause
    exit /b 1
)

echo 开始调用: !tool3! & REM
echo.
call "!tool3!" <nul
if !errorlevel! neq 0 (
    echo 错误：执行失败
    echo.
    pause
    exit /b 1
)

echo 开始调用: !tool4! & REM
echo.
call "!tool4!" <nul
if !errorlevel! neq 0 (
    echo 错误：执行失败
    echo.
    pause
    exit /b 1
)

echo.
pause
exit /b
