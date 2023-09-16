@echo off

del /F /S /Q "package.json" >nul 2>nul
del /F /S /Q "package-lock.json" >nul 2>nul

echo {"name":"mypages","version":"1.0.0","description":"Static Site Generator Test","scripts":{"docs:dev":"vuepress dev docs","docs:build":"vuepress build docs"}}>"package.json"

call npm init -y
call npm install -D "vuepress@next"
call npm install -D "@vuepress/plugin-search@next"
call npm install -D "vuepress-plugin-md-enhance"

call npm run docs:build
call npm run docs:dev

pause
exit
