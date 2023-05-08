:begin


call node --version
call npm --version
if not exist "package.json" ( call npm init )


call del /F /S /Q "package-lock.json" >nul 2>nul
:: call rmdir /S /Q "node_modules" >nul 2>nul
:: call npm cache clean --force


call npm install -D "vuepress@next" && call npm list "vuepress@next"
call npm install -D "@vuepress/plugin-search@next" && call npm list "@vuepress/plugin-search@next"
call npm install -D "vuepress-plugin-md-enhance" && call npm list "vuepress-plugin-md-enhance"


call npm run docs:build
call npm run docs:dev


pause
cls
goto :begin
