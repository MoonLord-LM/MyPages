:: check Node.js
call node --version
call npm --version

if not exist "package.json" ( call npm init )

:: install VuePress
call npm install -D "vuepress@next"
call npm install -D "@vuepress/plugin-search@next"
