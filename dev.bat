:begin

call npm list "vuepress@next" ^
  || call npm install -D "vuepress@next"

call npm list "@vuepress/plugin-search@next" ^
  || call npm install -D "@vuepress/plugin-search@next"

call npm list "vuepress-plugin-md-enhance@next" ^
  || call npm install -D "vuepress-plugin-md-enhance@next"

call npm run docs:dev

pause
cls
goto :begin
