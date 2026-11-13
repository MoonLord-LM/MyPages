@echo off
chcp 65001 >nul
setlocal disabledelayedexpansion
set "script=%~0" & set "script_path=%~f0" & set "script_dir=%~dp0" & set "script_name=%~n0" & set "script_ext=%~x0" & set "script_name_ext=%~nx0"
setlocal enabledelayedexpansion
if /i "!cd!"=="!SystemRoot!\System32" ( cd /d "!script_dir!" )
powershell -NoProfile -Command "Write-Host '[ !script_name_ext! ]' -ForegroundColor Cyan" && echo.



powershell -NoProfile -Command "Write-Host '上传静态资源文件到 Cloudflare Pages 的指定工程' -ForegroundColor Green"
echo.



REM 静态资源文件文件夹
for %%i in ("!script_dir!..\..\dist") do set "static_dir=%%~fi"

REM Cloudflare Pages 工程名
set "cloudflare_project=moonlord"

REM 网络代理设置
set HTTP_PROXY=http://127.0.0.1:10809
set HTTPS_PROXY=http://127.0.0.1:10809
set NO_PROXY=localhost,127.0.0.1



set "exclude_name1=_redirects"
set "exclude_name2=_headers"
for /f "delims=" %%c in ('
    powershell -NoProfile -Command ^
        "[System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8;" ^
        "@(Get-ChildItem -LiteralPath $env:static_dir -File -Force -Recurse | Where-Object { $_.Name -ne $env:exclude_name1 -and $_.Name -ne $env:exclude_name2 }).Count"
') do set "file_count=%%c"
echo 文件总数：!file_count!
echo.

set "temp_dir=%temp%\MyPages_%random%_%random%_%random%_%random%\"
if exist "!temp_dir!" ( rmdir /s /q "!temp_dir!" )
if not exist "!temp_dir!" ( mkdir "!temp_dir!" )
pushd "!temp_dir!"
if !errorlevel! neq 0 (
    echo 错误：无法进入临时目录
    echo.
    pause
    exit /b 1
)

call npx -y wrangler login
call npx -y wrangler pages deploy "!static_dir!" --project-name "!cloudflare_project!" --branch "main" --commit-message "!file_count!"

popd
if exist "!temp_dir!" ( rmdir /s /q "!temp_dir!" )

echo.
echo 上传完成



echo.
pause
exit /b
