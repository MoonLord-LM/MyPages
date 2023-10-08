@echo off

:begin

del /F /S /Q "package.json" >nul 2>nul
del /F /S /Q "package-lock.json" >nul 2>nul
rmdir /S /Q "node_modules"
rmdir /S /Q "docs"

echo {"name":"mypages","version":"1.0.0","description":"Static Site Generator Test","scripts":{"docs:dev":"vuepress dev docs","docs:build":"vuepress build docs"}}>"package.json"

call npm init -y
call npm install -D "vuepress@next"
call npm install -D "@vuepress/plugin-search@next"
call npm install -D "vuepress-plugin-md-enhance"

mkdir "docs"
echo # Hello VuePress > "docs/README.md"

call npm run docs:build
call npm run docs:dev

pause
cls
goto :begin
