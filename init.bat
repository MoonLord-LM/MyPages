:: check Node.js
call node --version
call npm --version

:: install VuePress
call npm init
call npm install -D "vuepress@next"
call npm install -D "@vuepress/plugin-search@next"

:: check this files
:: \.github\workflows\node.js.yml
:: \.github\workflows\vuepress-build-docs.yml
