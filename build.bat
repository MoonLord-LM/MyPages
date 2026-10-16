@echo off
chcp 65001 >nul
setlocal disabledelayedexpansion
set "script=%~0" & set "script_path=%~f0" & set "script_dir=%~dp0" & set "script_name=%~n0" & set "script_ext=%~x0" & set "script_name_ext=%~nx0"
setlocal enabledelayedexpansion
if /i "!cd!"=="!SystemRoot!\System32" ( cd /d "!script_dir!" )
powershell -NoProfile -Command "Write-Host '[ !script_name_ext! ]' -ForegroundColor Cyan" && echo.



powershell -NoProfile -Command "Write-Host '静态站点生成' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '将 /pages 文件夹的站点文件，构建生成到 /dist 文件夹' -ForegroundColor Green"
echo.



REM 检查 Node.js 组件
call node -v >nul 2>&1
if !errorlevel! neq 0 (
    echo 错误：缺少 Node.js 组件 & REM
    echo 请从 https://nodejs.org/en/download 下载，并完成安装 & REM
    "explorer.exe" "https://nodejs.org/en/download"
    echo.
    pause
    exit /b 1
)

REM 检查 npm 组件
call npm -v >nul 2>&1
if !errorlevel! neq 0 (
    echo 错误：缺少 npm 组件 & REM
    echo 请从 https://nodejs.org/en/download 下载，并完成安装 & REM
    "explorer.exe" "https://nodejs.org/en/download"
    echo.
    pause
    exit /b 1
)



REM 代码渲染 highlight.js
set "hljs_css_url=https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.12.0/styles/default.min.css"
set "hljs_js_url=https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.12.0/highlight.min.js"

REM 站点地图所使用的站点根地址（与 pages/robots.txt 中的 Sitemap 保持一致）
set "site_url=https://www.moonlord.cc"

set "temp_dir=!script_dir!tmp"
if not exist "!temp_dir!" ( mkdir "!temp_dir!" )
set "temp_js=!temp_dir!\build.mjs"
if exist "!temp_js!" ( del /f /q "!temp_js!" )



set "begin_marker=-----BEGIN NODEJS CODE-----"
set "end_marker=-----END NODEJS CODE-----"
set "pages_dir_marker=-----PROJECT PAGES DIR-----"
set "dist_dir_marker=-----PROJECT DIST DIR-----"
set "hljs_css_url_marker=-----HIGHLIGHTJS CSS URL-----"
set "hljs_js_url_marker=-----HIGHLIGHTJS JS URL-----"
set "site_url_marker=-----PROJECT SITE URL-----"
powershell -NoProfile -Command ^
    "[System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8;" ^
    "$lines = Get-Content -Encoding UTF8 -LiteralPath $env:script_path;" ^
    "$begin = [array]::IndexOf($lines, $env:begin_marker) + 1;" ^
    "$end = [array]::IndexOf($lines, $env:end_marker);" ^
    "if ($begin -lt 1 -or $end -lt $begin) {" ^
    "    Write-Host '错误：未找到内嵌的 Node.js 代码块' -ForegroundColor Red;" ^
    "    exit 1;" ^
    "};" ^
    "$code = $lines[$begin..($end - 1)];" ^
    "$pagesDir = ($env:script_dir + 'pages') -replace '\\', '/';" ^
    "$distDir = ($env:script_dir + 'dist') -replace '\\', '/';" ^
    "for ($i = 0; $i -lt $code.Count; $i++) {" ^
    "    $code[$i] = $code[$i].Replace($env:pages_dir_marker, $pagesDir);" ^
    "    $code[$i] = $code[$i].Replace($env:dist_dir_marker, $distDir);" ^
    "    $code[$i] = $code[$i].Replace($env:hljs_css_url_marker, $env:hljs_css_url);" ^
    "    $code[$i] = $code[$i].Replace($env:hljs_js_url_marker, $env:hljs_js_url);" ^
    "    $code[$i] = $code[$i].Replace($env:site_url_marker, $env:site_url);" ^
    "};" ^
    "$utf8NoBOM = [System.Text.UTF8Encoding]::new($false);" ^
    "[System.IO.File]::WriteAllLines($env:temp_js, $code, $utf8NoBOM);"
if !errorlevel! neq 0 (
    echo 错误：提取内嵌代码失败
    echo.
    if exist "!temp_js!" ( del /f /q "!temp_js!" )
    pause
    exit /b 1
)
if not exist "!temp_js!" (
    echo 错误：提取内嵌代码文件生成失败："!temp_js!"
    echo.
    pause
    exit /b 1
)

if not exist "!temp_dir!\node_modules\marked" (
    echo 正在安装 marked 依赖
    if exist "!temp_dir!\package.json" ( del /f /q "!temp_dir!\package.json" )
    if exist "!temp_dir!\package-lock.json" ( del /f /q "!temp_dir!\package-lock.json" )
    pushd "!temp_dir!"
        call npm install marked --no-audit --no-fund
        set "npm_error=!errorlevel!"
    popd
    if !npm_error! neq 0 (
        echo 错误：安装 marked 失败
        echo.
        if exist "!temp_js!" ( del /f /q "!temp_js!" )
        pause
        exit /b 1
    )
    echo.
)

set "build_attempt=0"
set "build_ok=0"
:build_retry
    set /a build_attempt+=1
    echo [构建尝试 !build_attempt!/3]
    echo.
    call node "!temp_js!"
    if !errorlevel! equ 0 (
        set "build_ok=1"
        goto build_done
    )
    echo.
    echo 构建生成失败（第 !build_attempt! 次），准备重试
    if !build_attempt! lss 3 (
        goto build_retry
    )
:build_done
if !build_ok! neq 1 (
    echo.
    echo 错误：构建生成失败
    echo.
    if exist "!temp_js!" ( del /f /q "!temp_js!" )
    pause
    exit /b 1
)
if exist "!temp_js!" ( del /f /q "!temp_js!" )



echo.
pause
exit /b



-----BEGIN NODEJS CODE-----
'use strict';

import fs from 'fs';
import path from 'path';
import https from 'https';
import http from 'http';
import child_process from 'child_process';
import { marked } from 'marked';

const RESERVED = new Set(['header.html', 'footer.html']);
const PAGES = '-----PROJECT PAGES DIR-----';
const DIST = '-----PROJECT DIST DIR-----';
const SITE_URL = '-----PROJECT SITE URL-----';

// 按页面源文件目录，向同级 / 上级逐级查找最临近的公共模板（header.html / footer.html）
// 两者独立处理；缺失则视为无模板。模板内容按路径缓存，避免重复读盘。
const templateCache = new Map();
function loadTemplateAt(p) {
    if (templateCache.has(p)) return templateCache.get(p);
    const c = fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : '';
    templateCache.set(p, c);
    return c;
}

// 站点根绝对路径(/...)按页面深度转换为相对路径，使全站链接相对且可移植
function pageDepth(outPath) {
    const rel = path.relative(DIST, path.dirname(outPath));
    return rel === '' ? 0 : rel.split(path.sep).length;
}

// 根据当前页面所在分区，返回应高亮的顶栏菜单项（与左侧菜单的 active 行为一致）
function navActiveSection(outPath) {
    const rel = path.relative(DIST, outPath).split(path.sep).join('/');
    if (rel === 'index.html') return 'index';
    if (rel.startsWith('github/')) return 'github';
    if (rel.startsWith('admin/')) return 'admin';
    if (rel.startsWith('about/')) return 'about';
    return '';
}
// 源码 header 使用相对 HTML 路径；按当前页面深度补前缀，使各层级页面都能正确跳转
// depth 0 用 ./ 前缀（与子目录页面的 ../ 一致），避免被 adjustRelativeRefs 当作裸相对路径重复处理
function relativizeNav(hdr, depth) {
    const prefix = depth === 0 ? './' : '../'.repeat(depth);
    return hdr.replace(/(<a class="nav-link"\s+href=")([^"]*)(")/g,
        (m, open, href, close) => open + prefix + href + close);
}

// 给当前分区对应的 .nav-link 加上 active 类
function markActiveNav(hdr, outPath, depth) {
    const section = navActiveSection(outPath);
    if (!section) return hdr;
    const prefix = depth === 0 ? './' : '../'.repeat(depth);
    const target = prefix + ({ index: 'index.html', github: 'github/index.html', admin: 'admin/index.html', about: 'about/index.html' })[section];
    const re = new RegExp('(<a class="nav-link" href=")' + target.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '"');
    return hdr.replace(re, '<a class="nav-link active" href="' + target + '"');
}

function injectHeader(html, outPath, srcDir) {
    const tp = findTemplate(srcDir, 'header.html');
    if (!tp) return html;
    const depth = pageDepth(outPath);
    const base = path.dirname(tp);
    let hdr = loadTemplateAt(tp);
    // 先处理顶栏导航的相对路径与 active 高亮（产出 ./ 或 ../ 前缀，避免被下面的通用重写重复处理）
    hdr = markActiveNav(relativizeNav(hdr, depth), outPath, depth);
    // 再统一调整模板内其余静态资源引用（src / href / url()）：按模板位置解析后回退到页面目录
    hdr = adjustRelativeRefs(hdr, base, path.dirname(outPath));
    // 根目录（depth 0）的顶栏导航去掉多余的 ./ 前缀：href="index.html" 而非 "./index.html"
    // 必须在 adjustRelativeRefs 之后执行，否则裸相对路径会被重新解析前缀
    hdr = hdr.replace(/(<a\s+class="nav-link[^"]*"\s+href=")\.\//g, '$1');
    return html.replace(/<body([^>]*)>/i, '<body$1>\n' + hdr);
}

function injectFooter(html, outPath, srcDir) {
    const tp = findTemplate(srcDir, 'footer.html');
    if (!tp) return html;
    const ftr = adjustRelativeRefs(loadTemplateAt(tp), path.dirname(tp), path.dirname(outPath));
    return html.replace(/<\/body>/i, ftr + '\n</body>');
}

console.log('源文件目录: ' + PAGES);
console.log('输出目录: ' + DIST);

if (typeof marked !== 'function' && !(marked && typeof marked.parse === 'function')) {
    console.error('错误：未找到 marked 组件，需要执行 npm install marked');
    process.exit(1);
}
if (typeof marked === 'function' && marked.setOptions) {
    marked.setOptions({ gfm: true, breaks: false });
}

fs.rmSync(DIST, { recursive: true, force: true });
fs.mkdirSync(DIST, { recursive: true });

function findTemplate(dir, name) {
    let current = dir;
    for (;;) {
        const candidate = path.join(current, name);
        if (fs.existsSync(candidate)) return candidate;
        const parent = path.dirname(current);
        if (parent === current) return null;
        current = parent;
    }
}

function adjustRelativeRefs(content, templateAssetBase, pageOutDir) {
    function rewritePath(ref) {
        if (!ref) return ref;
        if (/^(https?:)?\/\//i.test(ref)) return ref;   // 协议相对 / http(s) 外链
        if (/^[#?]/.test(ref)) return ref;              // 锚点 / 查询
        if (/^(data|mailto):/i.test(ref)) return ref;   // 特殊协议
        if (ref.startsWith('/')) {                      // 站点根绝对路径：按 DIST 根解析后回退到页面目录
            const absAsset = path.resolve(DIST, ref.slice(1));
            let relPath = path.relative(pageOutDir, absAsset).split(path.sep).join('/');
            if (relPath === '') relPath = './' + path.basename(ref);
            if (!/^(\.\.?\/)/.test(relPath)) relPath = './' + relPath;
            return relPath;
        }
        if (path.isAbsolute(ref)) return ref;           // 其它绝对路径：保持原样
        if (/^(\.\.?\/)/.test(ref)) return ref;         // 已经是 ./ 或 ../ 的相对路径（如顶栏导航）：保持原样
        const absAsset = path.resolve(templateAssetBase, ref);   // 模板内裸相对资源：按模板位置解析
        let relPath = path.relative(pageOutDir, absAsset).split(path.sep).join('/');
        if (relPath === '') relPath = './' + path.basename(ref);
        if (!/^(\.\.?\/)/.test(relPath)) relPath = './' + relPath;
        return relPath;
    }

    content = content.replace(/(src|href)\s*=\s*("([^"]*)"|'([^']*)')/gi,
        (match, attr, quoted, doubleQuoted, singleQuoted) => {
            const val = (doubleQuoted !== undefined) ? doubleQuoted : singleQuoted;
            const q = quoted.slice(0, 1);
            return attr + '=' + q + rewritePath(val) + q;
        });

    content = content.replace(/url\(\s*([^)]*?)\s*\)/gi,
        (match, inner) => {
            let quoteChar = '';
            let value = inner.trim();
            if (/^["']/.test(value)) { quoteChar = value[0]; value = value.slice(1); }
            if (/["']$/.test(value)) { value = value.slice(0, -1); }
            return 'url(' + quoteChar + rewritePath(value) + quoteChar + ')';
        });

    return content;
}

const MARKDOWN_CSS = `
:root { color-scheme: light; }
body {
  margin: 0;
  background: #ffffff;
  color: #1f2328;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans",
    "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", Helvetica, Arial, sans-serif;
}
.markdown-body {
  --color-canvas-default: #ffffff;
  --color-canvas-subtle: #f6f8fa;
  --color-border-default: #d1d9e0;
  --color-border-muted: #d8dee4;
  --color-fg-default: #1f2328;
  --color-fg-muted: #59636e;
  --color-accent-fg: #0969da;
  --color-neutral-muted: rgba(175, 184, 193, 0.2);
  box-sizing: border-box;
  max-width: 920px;
  margin: 0 auto;
  padding: 32px 24px 64px;
  color: var(--color-fg-default);
  font-size: 16px;
  line-height: 1.6;
  word-wrap: break-word;
}
.markdown-body * { box-sizing: border-box; }
.markdown-body > *:first-child { margin-top: 0 !important; }
.markdown-body > *:last-child { margin-bottom: 0 !important; }
.markdown-body a { color: var(--color-accent-fg); text-decoration: none; }
.markdown-body a:hover { text-decoration: underline; }
.markdown-body h1, .markdown-body h2, .markdown-body h3,
.markdown-body h4, .markdown-body h5, .markdown-body h6 {
  margin: 24px 0 16px; font-weight: 600; line-height: 1.25;
}
.markdown-body h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid var(--color-border-muted); }
.markdown-body h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid var(--color-border-muted); }
.markdown-body h3 { font-size: 1.25em; }
.markdown-body h4 { font-size: 1em; }
.markdown-body h5 { font-size: .875em; }
.markdown-body h6 { font-size: .85em; color: var(--color-fg-muted); }
.markdown-body p { margin: 0 0 16px; }
.markdown-body ul, .markdown-body ol { margin: 0 0 16px; padding-left: 2em; }
.markdown-body li { margin: .25em 0; }
.markdown-body li::marker { color: var(--color-fg-muted); }
.markdown-body blockquote {
  margin: 0 0 16px; padding: 0 1em; color: var(--color-fg-muted);
  border-left: .25em solid var(--color-border-default);
}
.markdown-body code {
  font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas,
    "Liberation Mono", "Courier New", monospace;
  font-size: 85%; padding: .2em .4em; border-radius: 6px;
  background-color: var(--color-neutral-muted);
}
.markdown-body pre {
  margin: 0 0 16px; padding: 16px; overflow: auto;
  font-size: 85%; line-height: 1.45; border-radius: 6px;
  background-color: var(--color-canvas-subtle);
  border: 1px solid var(--color-border-muted);
}
.markdown-body pre code {
  display: block; padding: 0; font-size: 100%;
  background-color: transparent; border: 0; border-radius: 0;
  overflow-x: auto; white-space: pre;
}
.markdown-body pre code.hljs { background: transparent; padding: 0; }
.markdown-body table {
  border-collapse: collapse; display: block; width: max-content;
  max-width: 100%; margin: 0 0 16px; overflow: auto;
}
.markdown-body table th, .markdown-body table td {
  border: 1px solid var(--color-border-default); padding: 6px 13px;
}
.markdown-body table th { font-weight: 600; background-color: var(--color-canvas-subtle); }
.markdown-body table tr:nth-child(2n) { background-color: var(--color-canvas-subtle); }
.markdown-body img { max-width: 100%; }
.markdown-body hr { height: 1px; border: 0; background: var(--color-border-muted); margin: 24px 0; }
`;

function escapeHtml(s) {
    return String(s).replace(/[<>&]/g, c => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;' }[c]));
}

function renderMarkdownPage(title, bodyHtml, outPath, srcDir) {
    const head = [
        '<!DOCTYPE html>',
        '<html lang="zh-CN">',
        '<head>',
        '<meta charset="UTF-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
        '<title>' + escapeHtml(title) + '</title>',
        '<style>' + MARKDOWN_CSS + '</style>',
        '<link rel="stylesheet" href="-----HIGHLIGHTJS CSS URL-----">',
        '</head>',
        '<body>',
        '<article class="markdown-body">'
    ].join('\n');
    const tail = [
        '</article>',
        '<script src="-----HIGHLIGHTJS JS URL-----"><\/script>',
        '<script>document.addEventListener("DOMContentLoaded",function(){if(window.hljs){document.querySelectorAll(".markdown-body pre code").forEach(function(el){try{hljs.highlightElement(el);}catch(e){}});}});<\/script>',
        '</body>',
        '</html>'
    ].join('\n');
    return injectFooter(injectHeader(head + '\n' + bodyHtml + '\n' + tail, outPath, srcDir), outPath, srcDir);
}

function outPathFor(srcFile) {
    const outRelPath = path.relative(PAGES, srcFile).replace(/\.(md|html)$/i, '.html');
    const outPath = path.join(DIST, outRelPath);
    fs.mkdirSync(path.dirname(outPath), { recursive: true });
    return outPath;
}

let pageCount = 0;

function processPage(srcFile, bodyHtml, navHtml) {
    const outPath = outPathFor(srcFile);
    const srcDir = path.dirname(srcFile);

    if (path.extname(srcFile).toLowerCase() === '.md') {
        const titleMatch = bodyHtml.match(/<h1[ >][\s\S]*?<\/h1>/i);
        let title = path.basename(srcFile, '.md');
        if (titleMatch) {
            const tm = titleMatch[0].replace(/<[^>]+>/g, '').trim();
            if (tm) title = tm;
        }
        fs.writeFileSync(outPath, renderMarkdownPage(title, wrapWithNav(bodyHtml, navHtml), outPath, srcDir), 'utf8');
        pageCount++;
        console.log('已处理: ' + path.relative(DIST, outPath));
        return;
    }

    const finalHtml = injectFooter(injectHeader(wrapWithNav(bodyHtml, navHtml), outPath, srcDir), outPath, srcDir);
    fs.writeFileSync(outPath, finalHtml, 'utf8');
    pageCount++;
    console.log('已处理: ' + path.relative(DIST, outPath));
}

const AUTOLIST_CSS = `
.auto-list {
  position: fixed;
  top: 0;
  left: 0;
  bottom: 0;
  width: 220px;
  overflow: auto;
  padding: 16px;
  box-sizing: border-box;
  border-right: 1px solid #d8dee4;
  background: #f6f8fa;
  font-size: 14px;
  line-height: 1.6;
}
.auto-list ul { list-style: none; margin: 0; padding: 0; }
.auto-list li { margin: 0; }
.auto-list a { display: block; padding: 8px 16px; margin: 0 -16px; color: #1a1a1a; text-decoration: none; word-break: break-all; }
.auto-list a:hover { background: #eef3f8; text-decoration: none; }
.auto-list a.active { background: linear-gradient(135deg, #6ba0ea, #9b6fe0); color: #fff; font-weight: 600; }
.auto-list li.home { margin: 0; padding: 0; }
.auto-list li.home a { display: flex; align-items: center; justify-content: flex-start; margin: -16px -16px 0; padding: 18px 16px; border-bottom: 1px solid #d8dee4; }
.auto-list li.home a svg { width: 16px; height: 16px; display: block; }
.auto-list-content { }
@media (max-width: 1360px) {
  .auto-list-content { margin-left: 240px; }
}
@media (max-width: 768px) {
  .auto-list { position: static; width: auto; border-right: none; border-bottom: 1px solid #d8dee4; }
  .auto-list-content { margin-left: 0; }
}
`;

function formatSize(bytes) {
    if (bytes < 1024) return bytes + ' B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    let i = -1, n = bytes;
    do { n /= 1024; i++; } while (n >= 1024 && i < units.length - 1);
    return n.toFixed(2) + ' ' + units[i];
}

function formatTime(date) {
    const pad = (x) => String(x).padStart(2, '0');
    return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate()) +
        ' ' + pad(date.getHours()) + ':' + pad(date.getMinutes()) + ':' + pad(date.getSeconds());
}

const REPO_ROOT = (() => {
    try {
        const out = child_process.execFileSync('git', ['-C', PAGES, 'rev-parse', '--show-toplevel'],
            { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
        if (out) return out;
    } catch (e) {}
    return path.dirname(PAGES);
})();

function gitCommitTime(srcFile) {
    try {
        const rel = path.relative(REPO_ROOT, srcFile).split(path.sep).join('/');
        const out = child_process.execFileSync('git',
            ['-C', REPO_ROOT, 'log', '-1', '--format=%ct', '--', rel],
            { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
        if (/^\d+$/.test(out)) return new Date(parseInt(out, 10) * 1000);
    } catch (e) {}
    return null;
}

function entryTime(srcFile, fallback) {
    return gitCommitTime(srcFile) || fallback;
}

function fetchBuffer(url) {
    return new Promise((resolve, reject) => {
        const doRequest = (u, redirects) => {
            if (redirects > 5) { reject(new Error('重定向次数过多')); return; }
            const mod = u.startsWith('https') ? https : http;
            const req = mod.get(u, { headers: { 'User-Agent': 'Mozilla/5.0' } }, (res) => {
                if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location) {
                    res.resume();
                    doRequest(new URL(res.headers.location, u).toString(), redirects + 1);
                    return;
                }
                if (res.statusCode !== 200) { res.resume(); reject(new Error('HTTP ' + res.statusCode)); return; }
                const chunks = [];
                res.on('data', (c) => chunks.push(c));
                res.on('end', () => resolve({ buf: Buffer.concat(chunks), contentType: (res.headers['content-type'] || '').toLowerCase() }));
            });
            req.on('error', reject);
        };
        doRequest(url, 0);
    });
}

function extFromUrlAndType(url, contentType) {
    let ext = path.extname(new URL(url).pathname).toLowerCase().replace(/^\./, '');
    if (ext && ext.length <= 4) return ext;
    if (contentType.includes('svg')) return 'svg';
    if (contentType.includes('png')) return 'png';
    if (contentType.includes('jpeg')) return 'jpg';
    if (contentType.includes('jpg')) return 'jpg';
    if (contentType.includes('gif')) return 'gif';
    if (contentType.includes('webp')) return 'webp';
    return 'img';
}

async function localizeImages(html, outPath, baseName) {
    const assetsDir = path.join(path.dirname(outPath), 'assets');
    const re = /(<img\b[^>]*?\bsrc=(["']))(https?:\/\/[^"']+)\2([^>]*?>)/gi;
    const matches = [...html.matchAll(re)];
    // 收集所有未能本地化的远程图片，循环结束后统一报错终止，绝不保留外链
    const failed = [];
    let counter = 0;
    for (const m of matches) {
        const url = m[3];
        counter++;
        // 以 repo/页面名 + 资源序号 + 文件后缀作为安全且简短的文件名
        const prefix = baseName + '-' + String(counter).padStart(3, '0');
        // 已存在同名本地资源则跳过下载，直接复用（加快构建）
        let fileName = (fs.existsSync(assetsDir))
            ? fs.readdirSync(assetsDir).find((f) => f.startsWith(prefix + '.'))
            : undefined;
        if (!fileName) {
            try {
                const result = await fetchBuffer(url);
                const ext = extFromUrlAndType(url, result.contentType);
                fileName = prefix + '.' + ext;
                fs.mkdirSync(assetsDir, { recursive: true });
                fs.writeFileSync(path.join(assetsDir, fileName), result.buf);
                console.log('已下载图片: ' + path.relative(DIST, path.join(assetsDir, fileName)));
            } catch (e) {
                failed.push(url + ' (' + e.message + ')');
            }
        }
        if (fileName) {
            const rel = 'assets/' + fileName;
            // 用函数形式替换，避免 URL/文件名/标签文本中的 $& $` $' $n 被当作特殊模式误处理
            html = html.replace(m[0], () => m[1] + rel + m[2] + m[4]);
        }
    }
    if (failed.length) {
        throw new Error('图片本地化失败：存在 ' + failed.length + ' 个无法下载的远程图片，已终止构建以确保产物均为本地资源：\n  ' + failed.join('\n  '));
    }
    return html;
}

async function mdBody(srcFile, outPath) {
    const markdown = fs.readFileSync(srcFile, 'utf8');
    const baseName = path.basename(srcFile, path.extname(srcFile));
    let html = marked(markdown);
    html = await localizeImages(html, outPath, baseName);
    return html;
}

function wrapWithNav(bodyHtml, navHtml) {
    if (!navHtml) return bodyHtml;
    return '<style>' + AUTOLIST_CSS + '</style>\n' +
        navHtml + '\n' +
        '<div class="auto-list-content">\n' +
        bodyHtml + '\n' +
        '</div>';
}

const HOME_ICON = '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor" aria-hidden="true"><path d="M6.906.664a1.749 1.749 0 0 1 2.187 0l5.25 4.2c.415.332.657.835.657 1.36v7.026A1.75 1.75 0 0 1 13.25 15h-3.5a.75.75 0 0 1-.75-.75V11a.75.75 0 0 0-.75-.75h-1.5a.75.75 0 0 0-.75.75v3.25a.75.75 0 0 1-.75.75h-3.5A1.75 1.75 0 0 1 1 13.25V6.229c0-.531.242-1.034.657-1.366l5.25-4.2z"></path></svg>';

function buildNav(currentOutPath, descriptors) {
    if (!descriptors.length) return '';
    const dir = path.dirname(currentOutPath);
    let indexRel = path.relative(dir, path.join(dir, 'index.html')).split(path.sep).join('/');
    if (indexRel === '') indexRel = './index.html';
    if (!/^(\.\.?\/|\/)/.test(indexRel)) indexRel = './' + indexRel;
    const homeItem = '    <li class="home"><a href="' + indexRel + '" title="返回目录首页" aria-label="返回目录首页">' + HOME_ICON + '</a></li>';
    const items = descriptors.map((d) => {
        let rel = path.relative(path.dirname(currentOutPath), d.outPath).split(path.sep).join('/');
        if (rel === '') rel = './' + path.basename(d.outPath);
        if (!/^(\.\.?\/|\/)/.test(rel)) rel = './' + rel;
        const active = (d.outPath === currentOutPath) ? ' class="active"' : '';
        return '    <li><a' + active + ' href="' + rel + '">' + escapeHtml(d.displayName) + '</a></li>';
    }).join('\n');
    return '<nav class="auto-list">\n  <ul>\n' + homeItem + '\n' + items + '\n  </ul>\n</nav>';
}

function buildTable(indexOutPath, fileEntries) {
    const rows = fileEntries.map((e) => {
        let rel = path.relative(path.dirname(indexOutPath), e.link).split(path.sep).join('/');
        if (rel === '') rel = './' + path.basename(e.link);
        if (!/^(\.\.?\/|\/)/.test(rel)) rel = './' + rel;
        return '    <tr><td><a href="' + rel + '">' + escapeHtml(e.label) + '</a></td>' +
            '<td>' + formatSize(e.size) + '</td>' +
            '<td>' + formatTime(e.mtime) + '</td></tr>';
    }).join('\n');
    return '<table>\n  <tbody>\n' + rows + '\n  </tbody>\n</table>';
}

function renderListPage(dirLabel, indexOutPath, fileEntries, navHtml, srcDir) {
    const head = [
        '<!DOCTYPE html>',
        '<html lang="zh-CN">',
        '<head>',
        '<meta charset="UTF-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
        '<title>' + escapeHtml(dirLabel) + '</title>',
        '<style>' + MARKDOWN_CSS + AUTOLIST_CSS + '</style>',
        '</head>',
        '<body>'
    ].join('\n');
    const listHtml = buildTable(indexOutPath, fileEntries);
    const body =
        navHtml + '\n' +
        '<div class="auto-list-content">\n' +
        '<article class="markdown-body">\n' +
        '<h1>' + escapeHtml(dirLabel) + '</h1>\n' +
        listHtml + '\n' +
        '</article>\n</div>';
    return injectFooter(injectHeader(head + '\n' + body + '\n</body>\n</html>', indexOutPath, srcDir), indexOutPath, srcDir);
}

const staticFiles = [];
const pageFilesByDir = new Map();

function collect(dir) {
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); }
    catch (e) { return; }
    for (const entry of entries) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) { collect(full); continue; }
        if (RESERVED.has(entry.name)) continue;
        const ext = path.extname(entry.name).toLowerCase();
        const stats = fs.statSync(full);
        if (ext === '.html' || ext === '.md') {
            const base = path.basename(entry.name, ext);
            if (!pageFilesByDir.has(dir)) pageFilesByDir.set(dir, new Map());
            const m = pageFilesByDir.get(dir);
            if (!m.has(base)) {
                m.set(base, { base, ext, srcFile: full, name: entry.name, stats });
            } else if (m.get(base).ext === '.md' && ext === '.html') {
                m.set(base, { base, ext, srcFile: full, name: entry.name, stats });
            }
        } else {
            staticFiles.push({ full, stats });
        }
    }
}
collect(PAGES);

for (const sf of staticFiles) {
    const relPath = path.relative(PAGES, sf.full);
    const dest = path.join(DIST, relPath);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(sf.full, dest);
    console.log('已复制: ' + relPath);
}

function toSiteUrl(relPath) {
    // relPath 为相对 /dist 的 POSIX 路径（使用 / 分隔）
    // 精确保留 index.html，例如 /blog/index.html -> /blog/index.html
    const norm = relPath.replace(/\\/g, '/');
    return SITE_URL + '/' + norm;
}

// 站点地图：将 /dist 下所有 html、php 文件，自动生成到 /dist/sitemap.xml
function buildSitemap() {
    const urls = [];
    function walk(dir) {
        let entries;
        try { entries = fs.readdirSync(dir, { withFileTypes: true }); }
        catch (e) { return; }
        for (const entry of entries) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory()) { walk(full); continue; }
            const ext = path.extname(entry.name).toLowerCase();
            if (ext !== '.html' && ext !== '.php') continue;
            const rel = path.relative(DIST, full).split(path.sep).join('/');
            let mtime;
            try { mtime = fs.statSync(full).mtime; } catch (e) { mtime = new Date(); }
            urls.push({ loc: toSiteUrl(rel), mtime });
        }
    }
    walk(DIST);
    urls.sort((a, b) => a.loc.localeCompare(b.loc));

    const items = urls.map((u) => {
        const d = u.mtime;
        const pad = (x) => String(x).padStart(2, '0');
        const lastmod = d.getUTCFullYear() + '-' + pad(d.getUTCMonth() + 1) + '-' + pad(d.getUTCDate()) +
            'T' + pad(d.getUTCHours()) + ':' + pad(d.getUTCMinutes()) + ':' + pad(d.getUTCSeconds()) + 'Z';
        return '  <url>\n    <loc>' + escapeHtml(u.loc) + '</loc>\n    <lastmod>' + lastmod + '</lastmod>\n  </url>';
    }).join('\n');

    const xml = '<?xml version="1.0" encoding="UTF-8"?>\n' +
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
        items + '\n</urlset>\n';

    const out = path.join(DIST, 'sitemap.xml');
    fs.writeFileSync(out, xml, 'utf8');
    console.log('已生成站点地图: ' + path.relative(DIST, out) + ' (共 ' + urls.length + ' 个地址)');
}

(async () => {
try {
for (const [dir, baseMap] of pageFilesByDir) {
    const pages = [...baseMap.values()];
    if (pages.length === 0) continue;

    const descriptors = pages.map((p) => {
        const outPath = outPathFor(p.srcFile);
        return Object.assign({}, p, { outPath, displayName: p.base });
    });

    const hasIndex = descriptors.some((d) => d.base.toLowerCase() === 'index');

    if (hasIndex || descriptors.length < 2) {
        for (const d of descriptors) {
            const bodyHtml = d.ext === '.md'
                ? await mdBody(d.srcFile, d.outPath)
                : fs.readFileSync(d.srcFile, 'utf8');
            processPage(d.srcFile, bodyHtml, '');
        }
        continue;
    }

    const indexOutPath = path.join(DIST, path.relative(PAGES, dir), 'index.html');
    fs.mkdirSync(path.dirname(indexOutPath), { recursive: true });

    for (const d of descriptors) {
        const navHtml = buildNav(d.outPath, descriptors);
        const bodyHtml = d.ext === '.md'
            ? await mdBody(d.srcFile, d.outPath)
            : fs.readFileSync(d.srcFile, 'utf8');
        processPage(d.srcFile, bodyHtml, navHtml);
    }

    const navHtmlIndex = buildNav(indexOutPath, descriptors);
    const dirLabel = '/' + path.relative(PAGES, dir).split(path.sep).join('/');
    const fileEntries = [];
    for (const d of descriptors) {
        let size = d.stats.size;
        try { size = fs.statSync(d.outPath).size; } catch (e) {}
        fileEntries.push({ label: d.base, link: d.outPath, size: size, mtime: entryTime(d.srcFile, d.stats.mtime) });
    }
    for (const sf of staticFiles) {
        if (path.dirname(sf.full) === dir) {
            const dest = path.join(DIST, path.relative(PAGES, sf.full));
            fileEntries.push({ label: path.basename(sf.full), link: dest, size: sf.stats.size, mtime: entryTime(sf.full, sf.stats.mtime) });
        }
    }
    fileEntries.sort((a, b) => a.label.localeCompare(b.label));
    fs.writeFileSync(indexOutPath, renderListPage(dirLabel, indexOutPath, fileEntries, navHtmlIndex, dir), 'utf8');
    pageCount++;
    console.log('已生成列表: ' + path.relative(DIST, indexOutPath));
}

console.log('处理完成：共处理 ' + pageCount + ' 个页面');

buildSitemap();
} catch (e) {
    console.error('');
    console.error('错误：构建中止 - ' + e.message);
    process.exit(1);
}
})();
-----END NODEJS CODE-----
