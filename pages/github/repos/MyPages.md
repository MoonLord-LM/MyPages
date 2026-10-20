2026-10-20 17:59:14 +08:00  
https://github.com/MoonLord-LM/MyPages  

---
# MyPages

[![build](https://github.com/MoonLord-LM/MyPages/actions/workflows/build.yml/badge.svg)](https://github.com/MoonLord-LM/MyPages/actions/workflows/build.yml)
[![tools](https://github.com/MoonLord-LM/MyPages/actions/workflows/tools.yml/badge.svg)](https://github.com/MoonLord-LM/MyPages/actions/workflows/tools.yml)

Static Site Generator  
静态页面生成工具  

将 `/pages` 目录下的 Markdown / HTML 等源文件，构建为可部署的静态站点，输出到 `/dist` 目录  
支持公共模板拼接、代码高亮、远程图片本地化、自动生成列表页、自动生成站点地图  

## [使用说明]

依赖 Node.js 运行，需要先安装 [`Node.js`](https://nodejs.org/en/download)  
执行 `build.bat` 即可完成构建  

## [生成规则]

### 页面文件

`/pages` 目录下存放 html 或 md 文件，视为页面文件  
优先使用 html 文件生成页面，如果没有同名的 html 文件，则使用 md 文件进行生成  
例如首页的内容就应该存放到 `/pages/index.html` 或 `/pages/index.md`  
保留名：`header.html` 和 `footer.html`，视为公共模板文件，不视作页面文件  

### 生成结果

页面生成后，按原目录结构，存放到 `/dist` 目录中，例如 `/pages/blog/post.md` → `/dist/blog/post.html`  
静态资源，按原目录结构，复制到 `/dist` 目录中，例如 `/pages/assets/style/blog.css` → `/dist/assets/style/blog.css`  
公共模板文件 `header.html` 和 `footer.html` 不复制  

### 静态资源

推荐使用 `/assets` 目录，单独存放页面使用的视频、图片、js、css、字体等各种静态资源文件  
`/pages` 目录下的所有文件，只要不是 html 或 md 文件，一律视为静态资源  
静态资源会被原样复制到 `/dist` 中对应的路径下，目录结构与 `/pages` 保持一致  
例如 `/pages/favicon.ico` → `/dist/favicon.ico`  
页面中引用静态资源时，必须使用相对路径，例如 `./assets/image/logo.png`  
如果 Markdown 中使用远程图片链接（`http(s)://`），自动下载并保存到页面所在目录的 `assets/`，并改写为本地相对路径  

### 公共模板

`header.html` 和 `footer.html` 作为页面头部和底部加载的公共模板，与原始 html 进行拼接处理  
`header.html` 的拼接位置在原始 html 的 `<body>` 标签后面，紧挨着的位置  
`footer.html` 的拼接位置在原始 html 的 `</body>` 标签前面，紧挨着的位置  
自动尝试向同级或上级目录，寻找最临近的 `header.html` 和 `footer.html` 文件，两者独立处理，缺失某个则仅省略该模板  
模板中的静态资源引用，按模板文件的位置写相对路径，但是生成时，需要根据最终文件的位置，自动调整相对路径  
自动调整相对路径，支持 `src`、`href`、`url()` 写法  

### 自动列表

当某个文件夹下存在多个页面，但没有 index 页面存在时，触发自动列表规则  
首先，生成一个 `index.html` 的列表页面，展示当前文件夹下的全部页面和摘要信息，并带有跳转到每个页面的链接  
对于 md 文件，摘要信息是第一行文本内容，对于 html 文件，摘要信息优先取 title，或者取 body 的第一行文本内容  
然后，对此文件夹下的每个页面的 html 增加内容，在页面左侧展示一个简单的竖向列表菜单，可以在列表间跳转以及返回 index 页面  

### 站点地图

自动列举 `/dist` 中所有的 html、php 文件，生成站点地图，存放到 `/dist/sitemap.xml` 中  
站点地图需要精确到文件名，例如 `index.html` 和 `index.php` 是两个不同的文件，都列举出来  

## [工程结构]

```
MyPages/
├── build.bat                             # 构建脚本
├── tools/
│   ├── tools.bat                         # 工具脚本
│   └── github/
│       ├── github-profile.bat            # 采集 GitHub 用户资料
│       ├── github-languages-color.bat    # 采集 GitHub Linguist 语言配色
├── pages/                                # 站点源文件
└── dist/                                 # 站点构建产物
```
