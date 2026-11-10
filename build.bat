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



REM 代码渲染使用 highlight.js
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

if not exist "!temp_dir!\node_modules\markdown-it" (
    echo 正在安装 markdown-it 依赖
    if exist "!temp_dir!\package.json" ( del /f /q "!temp_dir!\package.json" )
    if exist "!temp_dir!\package-lock.json" ( del /f /q "!temp_dir!\package-lock.json" )
    pushd "!temp_dir!"
        call npm install markdown-it --no-audit --no-fund
        set "npm_error=!errorlevel!"
    popd
    if !npm_error! neq 0 (
        echo 错误：安装 markdown-it 失败
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
import crypto from 'crypto';
import zlib from 'zlib';
import { execFileSync } from 'child_process';
import MarkdownIt from 'markdown-it';

const RESERVED = new Set(['header.html', 'footer.html']);
const PAGES = '-----PROJECT PAGES DIR-----';
const DIST = '-----PROJECT DIST DIR-----';
const SITE_URL = '-----PROJECT SITE URL-----';
const REPO_ROOT = path.dirname(PAGES);

// ===== 密码保护页面（*.enc.md）：加密参数与 /pages/tools/file-encrypt-aes.html 一致，正文先 gzip 压缩 =====
const ENC_MD_SUFFIX = '.enc.md';
const ENC_FILE_SUFFIX = '.html.zip.enc';
const ENC_SALT_LEN = 16;
const ENC_IV_LEN = 12;
const ENC_TAG_LEN = 16;
const ENC_HEADER_LEN = ENC_SALT_LEN + ENC_IV_LEN + ENC_TAG_LEN;
const ENC_KEY_LEN = 32;
const ENC_ITERATIONS = 10000000;
const ENC_PAGE_TITLE = '需要密码'; // 中性标题，避免出现在 title / canonical / 列表摘要中

// 站点地图用的「最后修改时间」，优先使用 pages 中对应源文件在 Git 里的最后一次提交时间。
const lastmodMap = new Map();

const templateCache = new Map();
function loadTemplateAt(p) {
    if (templateCache.has(p)) return templateCache.get(p);
    const c = fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : '';
    templateCache.set(p, c);
    return c;
}

function pageDepth(outPath) {
    const rel = path.relative(DIST, path.dirname(outPath));
    return rel === '' ? 0 : rel.split(path.sep).length;
}

function navActiveSection(outPath) {
    const rel = path.relative(DIST, outPath).split(path.sep).join('/');
    if (rel === 'index.html') return 'index';
    if (rel.startsWith('service/')) return 'service';
    if (rel.startsWith('github/')) return 'github';
    if (rel.startsWith('admin/')) return 'admin';
    if (rel.startsWith('tools/')) return 'tools';
    if (rel.startsWith('about/')) return 'about';
    return '';
}
// depth 0 用 ./ 前缀（与子目录页面的 ../ 一致），避免被 adjustRelativeRefs 当作裸相对路径重复处理
function relativizeNav(hdr, depth) {
    const prefix = depth === 0 ? './' : '../'.repeat(depth);
    return hdr.replace(/(<a class="nav-link"\s+href=")([^"]*)(")/g,
        (m, open, href, close) => open + prefix + href + close);
}

function markActiveNav(hdr, outPath, depth) {
    const section = navActiveSection(outPath);
    if (!section) return hdr;
    const prefix = depth === 0 ? './' : '../'.repeat(depth);
    const target = prefix + ({ index: 'index.html', service: 'service/index.html', github: 'github/index.html', admin: 'admin/index.html', tools: 'tools/index.html', about: 'about/index.html' })[section];
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
    hdr = adjustRelativeRefs(hdr, base, path.dirname(outPath));
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

// 链接规范化：相对路径链接在本页面打开，完整路径链接（带 http(s):// 或 //）在新页面打开
// 在构建产物上统一处理，覆盖 HTML 源文件书写的链接与 Markdown 渲染出的链接
// （Markdown 语法无法书写 target，只能在产物阶段补齐）
function normalizeLinkTargets(html) {
    function cleanAttrs(s) {
        return s.replace(/\s+/g, ' ').trim();
    }
    function isFullPath(href) {
        // 完整路径：带协议的绝对地址（http://、https://）或协议相对的 //host/path
        return /^(https?:)?\/\//i.test(href);
    }
    return html.replace(/<a\b([^>]*)>/gi, (tag, attrs) => {
        const ha = attrs.match(/\bhref\s*=\s*("([^"]*)"|'([^']*)')/i);
        if (!ha) return tag;
        const href = (ha[2] !== undefined ? ha[2] : ha[3]).trim();
        if (!href || /^(#|mailto:|tel:|javascript:)/i.test(href)) return tag;
        if (!isFullPath(href)) {
            // 相对路径：在本页面打开，移除 target="_blank"
            if (/\btarget\s*=/i.test(attrs)) {
                const na = cleanAttrs(attrs.replace(/\s*\btarget\s*=\s*("([^"]*)"|'([^']*)')/i, ''));
                return '<a ' + na + '>';
            }
            return tag;
        }
        // 完整路径：在新页面打开，强制 target="_blank" 且 rel 含 noopener（防范 reverse tabnabbing）
        let newAttrs = cleanAttrs(attrs.replace(/\s*\btarget\s*=\s*("([^"]*)"|'([^']*)')/i, ''));
        newAttrs += ' target="_blank"';
        const ra = newAttrs.match(/\brel\s*=\s*("([^"]*)"|'([^']*)')/i);
        if (ra) {
            const rv = (ra[2] !== undefined ? ra[2] : ra[3]);
            const toks = rv.split(/\s+/).filter(Boolean);
            if (!toks.includes('noopener')) toks.push('noopener');
            newAttrs = newAttrs.replace(ra[0], () => 'rel="' + toks.join(' ') + '"');
        } else {
            newAttrs += ' rel="noopener"';
        }
        return '<a ' + cleanAttrs(newAttrs) + '>';
    });
}

// 地址始终使用站点根地址 SITE_URL 加页面自身路径，与部署域名无关
// 因此镜像站部署同一份产物时，收录权重会集中到主域
function injectCanonical(html, outPath) {
    const rel = path.relative(DIST, outPath).split(path.sep).join('/');
    const link = '<link rel="canonical" href="' + escapeAttr(toSiteUrl(rel)) + '">';
    // 源文件若已自带 canonical，先移除，避免与目标地址冲突
    // 不能加行首锚点：非行首书写（如挤在单行 head 内）的 canonical 删不掉，会留下重复标签
    const cleaned = html.replace(/<link\b[^>]*\brel\s*=\s*("|')?canonical\1[^>]*>\s*/gi, '');
    let res;
    if (/<\/head>/i.test(cleaned)) res = cleaned.replace(/<\/head>/i, link + '\n</head>');
    else if (/<head\b[^>]*>/i.test(cleaned)) res = cleaned.replace(/<head\b([^>]*)>/i, '<head$1>\n' + link);
    else if (/<body\b[^>]*>/i.test(cleaned)) res = cleaned.replace(/<body\b([^>]*)>/i, '<head>\n' + link + '\n</head>\n<body$1>');
    else if (/<html\b[^>]*>/i.test(cleaned)) res = cleaned.replace(/<html\b([^>]*)>/i, '<html$1>\n<head>\n' + link + '\n</head>');
    else res = cleaned;
    return normalizeLinkTargets(res);
}

console.log('源文件目录: ' + PAGES);
console.log('输出目录: ' + DIST);

const md = new MarkdownIt({ html: true, linkify: false, typographer: false });

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
        // 任意 scheme:（tel: / javascript: / blob: / file: / data: / mailto: 等）一律原样保留，避免被当成相对路径解析损坏
        if (/^[a-z][a-z0-9+.-]*:/i.test(ref)) return ref;
        if (/^(https?:)?\/\//i.test(ref)) return ref;
        if (/^[#?]/.test(ref)) return ref;
        if (/^(data|mailto):/i.test(ref)) return ref;
        if (ref.startsWith('/')) {
            const absAsset = path.resolve(DIST, ref.slice(1));
            let relPath = path.relative(pageOutDir, absAsset).split(path.sep).join('/');
            if (relPath === '') relPath = './' + path.basename(ref);
            if (!/^(\.\.?\/)/.test(relPath)) relPath = './' + relPath;
            return relPath;
        }
        if (path.isAbsolute(ref)) return ref;
        if (/^(\.\.?\/)/.test(ref)) return ref;
        const absAsset = path.resolve(templateAssetBase, ref);
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
  color: var(--color-fg-default);
  font-size: 14px;
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
.markdown-body h1 { font-size: 28px; padding-bottom: .3em; border-bottom: 1px solid var(--color-border-muted); }
.markdown-body h2 { font-size: 24px; padding-bottom: .3em; border-bottom: 1px solid var(--color-border-muted); }
.markdown-body h3 { font-size: 20px; }
.markdown-body h4 { font-size: 16px; }
.markdown-body h5 { font-size: 14px; }
.markdown-body h6 { font-size: 12px; color: var(--color-fg-muted); }
.markdown-body p { margin: 0 0 16px; }
.markdown-body ul, .markdown-body ol { margin: 0 0 16px; padding-left: 2em; }
.markdown-body li { margin: .25em 0; }
.markdown-body li::marker { color: var(--color-fg-muted); }
.markdown-body blockquote {
  margin: 0 0 16px; padding: 0 1em; color: var(--color-fg-muted);
  border-left: .25em solid var(--color-border-default);
}
.markdown-body code {
  font-size: 14px; padding: .2em .4em; border-radius: 6px;
  background-color: var(--color-neutral-muted);
}
.markdown-body pre {
  margin: 0 0 16px; padding: 16px; overflow: auto;
  font-size: 14px; line-height: 1.45; border-radius: 6px;
  background-color: var(--color-canvas-subtle);
  border: 1px solid var(--color-border-muted);
}
.markdown-body pre code {
  display: block; padding: 0; font-size: 14px;
  background-color: transparent; border: 0; border-radius: 0;
  overflow-x: auto; white-space: pre;
}
.markdown-body pre code.hljs { background: transparent; padding: 0; }
.markdown-body .code-block { position: relative; margin: 0 0 16px; }
.markdown-body .code-block > pre { margin: 0; }
.copy-code-btn {
  position: absolute; top: 8px; right: 8px; z-index: 1;
  padding: 4px 8px; font-size: 12px; line-height: 18px;
  color: var(--color-fg-muted); background: var(--color-canvas-default);
  border: 1px solid var(--color-border-default); border-radius: 6px;
  cursor: pointer; opacity: 0; pointer-events: none;
  transition: opacity .15s, color .15s, border-color .15s;
}
.code-block:hover .copy-code-btn,
.copy-code-btn:focus-visible,
.copy-code-btn.copied,
.copy-code-btn.failed { opacity: 1; pointer-events: auto; }
@media (hover: none) { .copy-code-btn { opacity: 1; pointer-events: auto; } }
.copy-code-btn:hover { color: var(--color-accent-fg); border-color: var(--color-accent-fg); }
.copy-code-btn.copied { color: #1a7f37; border-color: #1a7f37; }
.copy-code-btn.failed { color: #b3261e; border-color: #b3261e; }
.markdown-body table {
  border-collapse: collapse; display: block; width: max-content;
  max-width: 100%; margin: 0 0 16px; overflow: auto;
}
.markdown-body table th, .markdown-body table td {
  border: 1px solid var(--color-border-default); padding: 6px 13px;
}
.markdown-body table th { font-weight: 600; background-color: var(--color-canvas-subtle); }
.markdown-body table tr:nth-child(2n) { background-color: var(--color-canvas-subtle); }
.markdown-body table td.name { white-space: nowrap; }
.markdown-body table td.desc { max-width: 560px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; color: var(--color-fg-muted); }
.markdown-body table td.desc.desc-empty { color: #8893a0; }
.markdown-body img { max-width: 100%; }
.markdown-body hr { height: 1px; border: 0; background: var(--color-border-muted); margin: 24px 0; }
`;

const CODE_COPY_JS = `
(function () {
  'use strict';
  function legacyCopy(text) {
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.setAttribute('readonly', '');
    ta.style.position = 'fixed';
    ta.style.left = '-9999px';
    document.body.appendChild(ta);
    ta.select();
    var ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { }
    document.body.removeChild(ta);
    return ok ? Promise.resolve() : Promise.reject(new Error('copy failed'));
  }
  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text).catch(function () { return legacyCopy(text); });
    }
    return legacyCopy(text);
  }
  function attach(pre) {
    if (pre.dataset.copyCodeReady) return;
    var target = pre.querySelector('code') || pre;
    var wrap = document.createElement('div');
    wrap.className = 'code-block';
    pre.parentNode.insertBefore(wrap, pre);
    wrap.appendChild(pre);
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'copy-code-btn';
    btn.textContent = '复制';
    btn.title = '复制代码到剪贴板';
    btn.setAttribute('aria-label', '复制代码到剪贴板');
    var timer;
    btn.addEventListener('click', function () {
      copyText(target.textContent).then(function () {
        btn.textContent = '已复制';
        btn.className = 'copy-code-btn copied';
      }, function () {
        btn.textContent = '复制失败';
        btn.className = 'copy-code-btn failed';
      }).then(function () {
        clearTimeout(timer);
        timer = setTimeout(function () {
          btn.textContent = '复制';
          btn.className = 'copy-code-btn';
        }, 1600);
      });
    });
    wrap.appendChild(btn);
    pre.dataset.copyCodeReady = '1';
  }
  window.initCodeCopy = function (root) {
    var pres = (root || document).querySelectorAll('pre');
    for (var i = 0; i < pres.length; i++) {
      if (pres[i].closest('.markdown-body')) attach(pres[i]);
    }
  };
  function init() { window.initCodeCopy(); }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
`;

function escapeHtml(s) {
    return String(s).replace(/[<>&]/g, c => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;' }[c]));
}

// 属性值上下文专用：在 escapeHtml 之外额外转义双引号。
// 生成器输出的标签统一使用双引号包裹属性，转义双引号即可防止内容提前闭合属性。
function escapeAttr(s) {
    return escapeHtml(s).replace(/"/g, '&quot;');
}

// 源文件最后一次提交的时间；非 Git 环境或文件未入库时，回退到文件修改时间
const commitTimeCache = new Map();
function fileLastModified(srcFile) {
    if (commitTimeCache.has(srcFile)) return commitTimeCache.get(srcFile);
    let time = null;
    try {
        const rel = path.relative(REPO_ROOT, srcFile).split(path.sep).join('/');
        const iso = execFileSync('git', ['log', '-1', '--format=%cI', '--', rel], {
            cwd: REPO_ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
        }).trim().split(/\r?\n/)[0];
        const parsed = iso ? new Date(iso) : null;
        if (parsed && !isNaN(parsed.getTime())) time = parsed;
    } catch (e) { }
    if (!time) {
        try {
            const st = fs.statSync(srcFile);
            if (st && !isNaN(st.mtime.getTime())) time = st.mtime;
        } catch (e) { }
    }
    commitTimeCache.set(srcFile, time);
    return time;
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
        '<div class="wrap">',
        '<article class="markdown-body">'
    ].join('\n');
    const tail = [
        '</article>',
        '</div>',
        '<script src="-----HIGHLIGHTJS JS URL-----"><\/script>',
        '<script>document.addEventListener("DOMContentLoaded",function(){if(window.hljs){document.querySelectorAll(".markdown-body pre code").forEach(function(el){try{hljs.highlightElement(el);}catch(e){}});}});<\/script>',
        '<script>' + CODE_COPY_JS + '<\/script>',
        '</body>',
        '</html>'
    ].join('\n');
    const html = injectFooter(injectHeader(head + '\n' + bodyHtml + '\n' + tail, outPath, srcDir), outPath, srcDir);
    return injectCanonical(html, outPath);
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
    lastmodMap.set(outPath, fileLastModified(srcFile));

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

    const finalHtml = injectCanonical(
        injectFooter(injectHeader(wrapWithNav(bodyHtml, navHtml), outPath, srcDir), outPath, srcDir),
        outPath
    );
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
@media (max-width: 1360px) {
  .auto-list-content { margin-left: 240px; }
}
@media (max-width: 768px) {
  .auto-list { position: static; width: auto; border-right: none; border-bottom: 1px solid #d8dee4; }
  .auto-list-content { margin-left: 0; }
}
`;

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

const IMAGE_EXTS = new Set(['png', 'jpg', 'jpeg', 'gif', 'svg', 'webp', 'bmp', 'ico', 'avif']);

function extFromUrlAndType(url, contentType) {
    const ext = path.extname(new URL(url).pathname).toLowerCase().replace(/^\./, '');
    if (IMAGE_EXTS.has(ext)) return ext;
    if (contentType.includes('svg')) return 'svg';
    if (contentType.includes('png')) return 'png';
    if (contentType.includes('jpeg')) return 'jpg';
    if (contentType.includes('jpg')) return 'jpg';
    if (contentType.includes('gif')) return 'gif';
    if (contentType.includes('webp')) return 'webp';
    return 'img';
}

// mirrorAssetsDir 可选：把远程图片同时写一份到 /pages，供下一轮（CI）构建作为静态资源复制
async function localizeImages(html, outPath, baseName, mirrorAssetsDir) {
    const assetsDir = path.join(path.dirname(outPath), 'assets');
    const re = /(<img\b[^>]*?\bsrc=(["']))((?:https?:)?\/\/[^"']+)\2([^>]*?>)/gi;
    const matches = [...html.matchAll(re)];
    // 收集所有未能本地化的远程图片，循环结束后统一报错终止，绝不保留外链
    const failed = [];
    let counter = 0;
    for (const m of matches) {
        const url = m[3].startsWith('//') ? 'https:' + m[3] : m[3];
        counter++;
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
                if (mirrorAssetsDir) {
                    fs.mkdirSync(mirrorAssetsDir, { recursive: true });
                    fs.writeFileSync(path.join(mirrorAssetsDir, fileName), result.buf);
                }
                console.log('已下载图片: ' + path.relative(DIST, path.join(assetsDir, fileName)));
            } catch (e) {
                failed.push(url + ' (' + e.message + ')');
            }
        }
        if (fileName) {
            const assetPath = path.join(assetsDir, fileName);
            // 图片本身不在 pages 中，沿用所属页面的最后修改时间
            if (!lastmodMap.has(assetPath)) lastmodMap.set(assetPath, lastmodMap.get(outPath));
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

async function markdownToHtml(markdown, outPath, baseName, mirrorAssetsDir) {
    let html = md.render(markdown);
    html = await localizeImages(html, outPath, baseName, mirrorAssetsDir);
    return html;
}

async function mdBody(srcFile, outPath) {
    const markdown = fs.readFileSync(srcFile, 'utf8');
    const baseName = path.basename(srcFile, path.extname(srcFile));
    // 先登记页面自身的最后修改时间，供下面下载到本地的图片沿用
    lastmodMap.set(outPath, fileLastModified(srcFile));
    return markdownToHtml(markdown, outPath, baseName);
}

function parseEncSource(markdown, srcRel) {
    const lines = String(markdown).split(/\r?\n/);
    const first = (lines[0] || '').trim();
    if (!first.startsWith('<!--') || !first.endsWith('-->')) {
        throw new Error('密码保护页面首行缺少配置注释：' + srcRel);
    }
    let cfg;
    try { cfg = JSON.parse(first.slice(4, -3).trim()); }
    catch (e) { throw new Error('密码保护页面首行配置 JSON 无效：' + srcRel); }
    if (!cfg || typeof cfg.password !== 'string' || cfg.password.length === 0) {
        throw new Error('密码保护页面缺少 password 配置：' + srcRel);
    }
    let iterations = ENC_ITERATIONS;
    if (cfg.iterations !== undefined) {
        iterations = Number(cfg.iterations);
        if (!Number.isInteger(iterations) || iterations < 1) {
            throw new Error('密码保护页面 iterations 配置无效：' + srcRel);
        }
    }
    return { password: cfg.password, iterations: iterations, markdown: lines.slice(1).join('\n') };
}

function encryptHtml(plainHtml, password, iterations) {
    const salt = crypto.randomBytes(ENC_SALT_LEN);
    const iv = crypto.randomBytes(ENC_IV_LEN);
    const key = crypto.pbkdf2Sync(Buffer.from(password, 'utf8'), salt, iterations, ENC_KEY_LEN, 'sha512');
    const gzip = zlib.gzipSync(Buffer.from(plainHtml, 'utf8'), {
        level: zlib.constants.Z_BEST_COMPRESSION, memLevel: 9
    });
    const cipher = crypto.createCipheriv('aes-256-gcm', key, iv, { authTagLength: ENC_TAG_LEN });
    const ciphertext = Buffer.concat([cipher.update(gzip), cipher.final()]);
    // 布局：salt(16) + iv(12) + tag(16) + gzip 数据的密文
    return Buffer.concat([salt, iv, cipher.getAuthTag(), ciphertext]);
}

const UNLOCK_CSS = `
.unlock {
  max-width: 560px; margin: 0 auto;
}
.unlock h1 { font-size: 28px; margin-bottom: 8px; color: #1f2328; }
.unlock-tip { color: #59636e; margin-bottom: 20px; font-size: 14px; }
.unlock-row { display: flex; gap: 10px; }
.unlock-row input {
  flex: 1; min-width: 0; padding: 11px 14px; font-size: 16px;
  border: 1px solid #ccc; border-radius: 8px; outline: none;
  /* 非密码字段：避免浏览器弹出「记住密码」，同时保留圆点遮盖 */
  -webkit-text-security: disc;
}
.unlock-row input:focus { border-color: #2a5298; }
.unlock-row button {
  padding: 11px 22px; border: none; border-radius: 8px; font-size: 16px; font-weight: 600;
  cursor: pointer; color: #fff; background: linear-gradient(135deg, #6ba0ea, #9b6fe0);
}
.unlock-row button:disabled { opacity: .5; cursor: not-allowed; }
.unlock-status { margin-top: 12px; font-size: 14px; color: #59636e; min-height: 1.4em; }
.unlock-status.err { color: #b3261e; }
`;

function unlockScript(encFileName, iterations) {
    // 该脚本在浏览器运行：密码由用户输入，页面里不含任何密钥信息
    return [
        "(function () {",
        "  'use strict';",
        "  var ITER = " + iterations + ";",
        "  var SALT_LEN = " + ENC_SALT_LEN + ", IV_LEN = " + ENC_IV_LEN +
            ", TAG_LEN = " + ENC_TAG_LEN + ", HEADER_LEN = " + ENC_HEADER_LEN + ";",
        "  var ENC_FILE = " + JSON.stringify(encFileName) + ";",
        "  var $ = function (id) { return document.getElementById(id); };",
        "  var input = $('unlockPassword'), btn = $('unlockBtn'),",
        "      statusEl = $('unlockStatus'), panel = $('unlockPanel'), content = $('unlockContent');",
        "  function setStatus(text, isErr) {",
        "    statusEl.textContent = text || '';",
        "    statusEl.className = 'unlock-status' + (isErr ? ' err' : '');",
        "  }",
        "  function setBusy(busy) {",
        "    btn.disabled = busy; input.disabled = busy;",
        "    btn.textContent = busy ? '解密中…' : '解密';",
        "  }",
        "  async function deriveKey(password, salt) {",
        "    var enc = new TextEncoder();",
        "    var base = await crypto.subtle.importKey('raw', enc.encode(password), { name: 'PBKDF2' }, false, ['deriveKey']);",
        "    return crypto.subtle.deriveKey(",
        "      { name: 'PBKDF2', salt: salt, iterations: ITER, hash: 'SHA-512' },",
        "      base, { name: 'AES-GCM', length: 256 }, false, ['decrypt']);",
        "  }",
        "  async function gunzip(data) {",
        "    if (typeof DecompressionStream === 'undefined') {",
        "      throw new Error('当前浏览器不支持 gzip 解压，请使用最新版浏览器');",
        "    }",
        "    try {",
        "      var stream = new Blob([data]).stream().pipeThrough(new DecompressionStream('gzip'));",
        "      return await new Response(stream).arrayBuffer();",
        "    } catch (e) { throw new Error('解压失败，加密内容已损坏'); }",
        "  }",
        "  async function unlock() {",
        "    var password = input.value;",
        "    if (!password) { setStatus('请输入密码', true); return; }",
        "    if (!window.crypto || !crypto.subtle) { setStatus('请在 HTTPS 或 localhost 下打开本页', true); return; }",
        "    setBusy(true);",
        "    setStatus('正在解密，请稍候…');",
        "    try {",
        "      var res = await fetch(ENC_FILE, { cache: 'no-store' });",
        "      if (!res.ok) throw new Error('HTTP ' + res.status);",
        "      var buf = new Uint8Array(await res.arrayBuffer());",
        "      if (buf.length < HEADER_LEN) throw new Error('加密内容损坏');",
        "      var salt = buf.subarray(0, SALT_LEN);",
        "      var iv = buf.subarray(SALT_LEN, SALT_LEN + IV_LEN);",
        "      var tag = buf.subarray(SALT_LEN + IV_LEN, HEADER_LEN);",
        "      var ct = buf.subarray(HEADER_LEN);",
        "      var combined = new Uint8Array(ct.length + TAG_LEN);",
        "      combined.set(ct, 0); combined.set(tag, ct.length);",
        "      var key = await deriveKey(password, salt);",
        "      var plain;",
        "      try {",
        "        plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: iv, tagLength: TAG_LEN * 8 }, key, combined);",
        "      } catch (e) { throw new Error('密码错误，解密失败'); }",
        "      content.innerHTML = new TextDecoder().decode(await gunzip(plain));",
        "      if (window.initCodeCopy) { window.initCodeCopy(content); }",
        "      content.style.display = '';",
        "      document.title = \"密码保护页面\";",
        "      panel.style.display = 'none';",
        "      setStatus('');",
        "      if (window.hljs) {",
        "        content.querySelectorAll('pre code').forEach(function (el) {",
        "          try { hljs.highlightElement(el); } catch (e) {}",
        "        });",
        "      }",
        "    } catch (e) {",
        "      setStatus(e && e.message ? e.message : String(e), true);",
        "    } finally { setBusy(false); }",
        "  }",
        "  btn.addEventListener('click', unlock);",
        "  input.addEventListener('keydown', function (e) { if (e.key === 'Enter') unlock(); });",
        "})();"
    ].join('\n');
}

function renderUnlockPage(encFileName, iterations) {
    const html = [
        '<!DOCTYPE html>',
        '<html lang="zh-CN">',
        '<head>',
        '<meta charset="UTF-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
        '<title>' + escapeHtml(ENC_PAGE_TITLE) + '</title>',
        '<style>' + MARKDOWN_CSS + UNLOCK_CSS + '</style>',
        '<link rel="stylesheet" href="-----HIGHLIGHTJS CSS URL-----">',
        '</head>',
        '<body>',
        '<div class="wrap">',
        '<div class="unlock" id="unlockPanel">',
        '  <h1>' + escapeHtml(ENC_PAGE_TITLE) + '</h1>',
        '  <p class="unlock-tip">本页内容已加密，请输入密码查看。</p>',
        '  <div class="unlock-row">',
        '    <input type="text" id="unlockPassword" placeholder="请输入密码" autocomplete="off" spellcheck="false" autocapitalize="off" autocorrect="off">',
        '    <button type="button" id="unlockBtn">解密</button>',
        '  </div>',
        '  <p class="unlock-status" id="unlockStatus"></p>',
        '</div>',
        '<article class="markdown-body" id="unlockContent" style="display:none"></article>',
        '</div>',
        '<script src="-----HIGHLIGHTJS JS URL-----"></script>',
        '<script>' + CODE_COPY_JS + '</script>',
        '<script>',
        unlockScript(encFileName, iterations),
        '</script>',
        '</body>',
        '</html>'
    ].join('\n');
    // 只产出「中间显示部分」的页面骨架：公共模板、canonical 由 processPage 每次构建注入
    return html;
}

// 密码框骨架（*.html）不含任何密钥，只依赖当前构建的 CSS / 解密脚本模板。
// .enc.md 只在本地存在，远程构建没有明文源；因此以随仓库提交的 *.html.zip.enc 为凭据，
// 每次构建都用最新模板重新渲染骨架，让它与工程其它模板 / 设置保持同步。
function refreshUnlockShell(srcDir, baseName) {
    const shellName = baseName + '.html';
    const encName = baseName + ENC_FILE_SUFFIX;
    const srcShell = path.join(srcDir, shellName);
    const srcEnc = path.join(srcDir, encName);
    if (!fs.existsSync(srcEnc)) return;

    // 迭代次数必须与密文配套：优先沿用现有骨架里的 ITER，骨架缺失时回退默认值
    let iterations = ENC_ITERATIONS;
    try {
        const m = fs.readFileSync(srcShell, 'utf8').match(/\bvar\s+ITER\s*=\s*(\d+)\s*;/);
        if (m) iterations = Number(m[1]);
    } catch (e) { }

    const html = renderUnlockPage(encName, iterations);
    // 内容不变就不写盘，避免无意义的文件改动反复触发 CI 提交
    let prev = '';
    try { prev = fs.readFileSync(srcShell, 'utf8'); } catch (e) { }
    if (prev !== html) {
        fs.writeFileSync(srcShell, html, 'utf8');
        console.log('已刷新密码框骨架: ' + path.relative(PAGES, srcShell));
    }

    // 骨架原本缺失时 collect() 不会登记，这里补上，保证本轮也生成 dist 页面 / 自动列表
    if (!pageFilesByDir.has(srcDir)) pageFilesByDir.set(srcDir, new Map());
    const m = pageFilesByDir.get(srcDir);
    if (!m.has(baseName)) {
        m.set(baseName, { base: baseName, ext: '.html', srcFile: srcShell, name: shellName, lockedPage: true });
    }
}

async function processEncryptedPage(srcFile) {
    const srcRel = path.relative(PAGES, srcFile);
    const baseName = path.basename(srcFile).slice(0, -ENC_MD_SUFFIX.length);
    const srcDir = path.dirname(srcFile);
    const shellName = baseName + '.html';
    const encName = baseName + ENC_FILE_SUFFIX;
    const srcShell = path.join(srcDir, shellName);
    const srcEnc = path.join(srcDir, encName);
    const distShell = path.join(DIST, path.relative(PAGES, srcShell));
    const distEnc = path.join(DIST, path.relative(PAGES, srcEnc));

    const cfg = parseEncSource(fs.readFileSync(srcFile, 'utf8'), srcRel);
    // 远程图片同时落到 /pages，保证下一轮（CI，无 .enc.md）仍能复制这些资源
    const bodyHtml = await markdownToHtml(cfg.markdown, distShell, baseName, path.join(srcDir, 'assets'));
    // 链接规范化（相对路径本页打开、完整路径新页打开）必须在加密前作用于正文，
    // 否则 decrypt 后注入的 HTML 不会经过 injectCanonical 的 normalizeLinkTargets，导致与普通页面行为不一致
    const normalizedBody = normalizeLinkTargets(bodyHtml);
    console.log('正在加密: ' + srcRel);
    const encBytes = encryptHtml(normalizedBody, cfg.password, cfg.iterations);
    const shellHtml = renderUnlockPage(encName, cfg.iterations);

    fs.mkdirSync(path.dirname(distShell), { recursive: true });
    fs.writeFileSync(srcShell, shellHtml, 'utf8');
    fs.writeFileSync(srcEnc, encBytes);
    fs.writeFileSync(distEnc, encBytes);
    const mtime = fileLastModified(srcFile);
    lastmodMap.set(distShell, mtime);
    lastmodMap.set(distEnc, mtime);
    // collect() 已在本函数之前执行，产出的 .html 需补登记，
    // 否则本轮不会为它生成自动列表页 / 站点地图条目
    if (!pageFilesByDir.has(srcDir)) pageFilesByDir.set(srcDir, new Map());
    pageFilesByDir.get(srcDir).set(baseName, {
        base: baseName, ext: '.html', srcFile: srcShell, name: shellName, lockedPage: true
    });
    console.log('已加密: ' + srcRel);
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
    const homeItem = '    <li class="home"><a href="' + escapeAttr(indexRel) + '" title="返回目录首页" aria-label="返回目录首页">' + HOME_ICON + '</a></li>';
    const items = descriptors.map((d) => {
        let rel = path.relative(path.dirname(currentOutPath), d.outPath).split(path.sep).join('/');
        if (rel === '') rel = './' + path.basename(d.outPath);
        if (!/^(\.\.?\/|\/)/.test(rel)) rel = './' + rel;
        const active = (d.outPath === currentOutPath) ? ' class="active"' : '';
        return '    <li><a' + active + ' href="' + escapeAttr(rel) + '">' + escapeHtml(d.displayName) + '</a></li>';
    }).join('\n');
    return '<nav class="auto-list">\n  <ul>\n' + homeItem + '\n' + items + '\n  </ul>\n</nav>';
}

function firstNonEmptyLine(text) {
    const lines = String(text).split(/\r?\n/);
    for (const line of lines) {
        const t = line.trim();
        if (t) return t;
    }
    return '';
}

function mdFirstLine(srcFile) {
    let text = '';
    try { text = fs.readFileSync(srcFile, 'utf8'); } catch (e) { return ''; }
    const line = firstNonEmptyLine(text);
    return line.replace(/^#{1,6}\s+/, '').replace(/^[-*+]\s+/, '').trim();
}

function htmlFirstLine(srcFile) {
    let text = '';
    try { text = fs.readFileSync(srcFile, 'utf8'); } catch (e) { return ''; }
    const titleMatch = text.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
    if (titleMatch) {
        const t = titleMatch[1].replace(/<[^>]+>/g, '').trim();
        if (t) return t;
    }
    const bodyMatch = text.match(/<body[^>]*>([\s\S]*?)<\/body>/i);
    let bodyText = bodyMatch ? bodyMatch[1] : text;
    bodyText = bodyText.replace(/<script[\s\S]*?<\/script>/gi, ' ');
    bodyText = bodyText.replace(/<style[\s\S]*?<\/style>/gi, ' ');
    bodyText = bodyText.replace(/<[^>]+>/g, ' ');
    bodyText = bodyText.replace(/&[a-zA-Z]+;/g, ' ').replace(/&#\d+;/g, ' ');
    return firstNonEmptyLine(bodyText);
}

function fileDescription(srcFile, ext) {
    const e = (ext || path.extname(srcFile)).toLowerCase();
    if (e === '.md') return mdFirstLine(srcFile);
    if (e === '.html') return htmlFirstLine(srcFile);
    return '';
}

function buildTable(indexOutPath, fileEntries) {
    const rows = fileEntries.map((e) => {
        let rel = path.relative(path.dirname(indexOutPath), e.link).split(path.sep).join('/');
        if (rel === '') rel = './' + path.basename(e.link);
        if (!/^(\.\.?\/|\/)/.test(rel)) rel = './' + rel;
        const desc = e.desc
            ? '<td class="desc" title="' + escapeAttr(e.desc) + '">' + escapeHtml(e.desc) + '</td>'
            : '<td class="desc desc-empty">—</td>';
        return '    <tr><td class="name"><a href="' + escapeAttr(rel) + '">' + escapeHtml(e.label) + '</a></td>' +
            desc + '</tr>';
    }).join('\n');
    return '<table>\n  <thead>\n    <tr><th>文件名</th><th>说明</th></tr>\n  </thead>\n  <tbody>\n' + rows + '\n  </tbody>\n</table>';
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
        '<div class="wrap">\n' +
        '<article class="markdown-body">\n' +
        '<h1>' + escapeHtml(dirLabel) + '</h1>\n' +
        listHtml + '\n' +
        '</article>\n</div>\n</div>';
    const html = injectFooter(injectHeader(head + '\n' + body + '\n</body>\n</html>', indexOutPath, srcDir), indexOutPath, srcDir);
    return injectCanonical(html, indexOutPath);
}

const staticFiles = [];
const pageFilesByDir = new Map();
const encryptedPages = [];
const lockedEncPages = []; // 随仓库提交的密文（*.html.zip.enc），用于每次构建刷新密码框骨架

function collect(dir) {
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); }
    catch (e) { return; }
    for (const entry of entries) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) { collect(full); continue; }
        if (RESERVED.has(entry.name)) continue;
        // 明文源文件只在本地参与构建，绝不作为页面或静态资源复制到 /dist
        if (entry.name.toLowerCase().endsWith(ENC_MD_SUFFIX)) {
            encryptedPages.push(full);
            continue;
        }
        const ext = path.extname(entry.name).toLowerCase();
        if (ext === '.html' || ext === '.md') {
            const base = path.basename(entry.name, ext);
            const lockedPage = ext === '.html' && fs.existsSync(path.join(dir, base + ENC_FILE_SUFFIX));
            if (!pageFilesByDir.has(dir)) pageFilesByDir.set(dir, new Map());
            const m = pageFilesByDir.get(dir);
            if (!m.has(base)) {
                m.set(base, { base, ext, srcFile: full, name: entry.name, lockedPage });
            } else if (m.get(base).ext === '.md' && ext === '.html') {
                m.set(base, { base, ext, srcFile: full, name: entry.name, lockedPage });
            }
        } else {
            if (entry.name.toLowerCase().endsWith(ENC_FILE_SUFFIX)) {
                lockedEncPages.push({ dir, baseName: entry.name.slice(0, -ENC_FILE_SUFFIX.length) });
            }
            staticFiles.push({ full });
        }
    }
}
collect(PAGES);

for (const sf of staticFiles) {
    const relPath = path.relative(PAGES, sf.full);
    const dest = path.join(DIST, relPath);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(sf.full, dest);
    lastmodMap.set(dest, fileLastModified(sf.full));
    console.log('已复制: ' + relPath);
}

function toSiteUrl(relPath) {
    // relPath 为相对 /dist 的 POSIX 路径（使用 / 分隔）
    // 精确保留 index.html，例如 /blog/index.html -> /blog/index.html
    const norm = relPath.replace(/\\/g, '/');
    return SITE_URL + '/' + norm;
}

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
            // 优先取 pages 源文件的最后提交时间；取不到时回退到产物文件时间
            let mtime = lastmodMap.get(full) || null;
            if (!mtime) {
                try { mtime = fs.statSync(full).mtime; } catch (e) { mtime = new Date(); }
            }
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

function buildExternalUrlList() {
    const siteHost = new URL(SITE_URL).hostname.toLowerCase();
    const siteRoot = siteHost.replace(/^www\./, '');
    const found = new Set();

    function add(raw) {
        let s = String(raw).trim();
        if (!s) return;
        // 还原 HTML 实体，保证 query 参数完整（例如 &amp; -> &）
        s = s.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&apos;/g, "'");
        if (!/^(?:https?:)?\/\//i.test(s)) return;
        const url = s.startsWith('//') ? 'https:' + s : s;
        let parsed;
        try { parsed = new URL(url); } catch (e) { return; }
        if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return;
        const host = parsed.hostname.toLowerCase();
        if (host === siteHost || host === siteRoot || host === 'www.' + siteRoot) return;
        found.add(url);
    }

    function collectUrls(html) {
        // HTML 属性中的引用；srcset 可能是 "a.png 1x, b.png 2x"，需按逗号逐个拆出
        const attrRe = /\b(href|src|srcset|action|poster|formaction|cite|content|longdesc)\s*=\s*("([^"]*)"|'([^']*)')/gi;
        for (const m of html.matchAll(attrRe)) {
            const name = m[1].toLowerCase();
            const val = (m[3] !== undefined ? m[3] : m[4]) || '';
            if (name === 'srcset') {
                for (const piece of val.split(',')) add(piece.trim().split(/\s+/)[0]);
            } else {
                add(val);
            }
        }
        const cssRe = /url\(\s*(?:"([^"]*)"|'([^']*)'|([^)]*))\s*\)/gi;
        for (const m of html.matchAll(cssRe)) {
            const val = (m[1] !== undefined ? m[1] : (m[2] !== undefined ? m[2] : m[3])) || '';
            add(val);
        }
    }

    function walk(dir) {
        let entries;
        try { entries = fs.readdirSync(dir, { withFileTypes: true }); }
        catch (e) { return; }
        for (const entry of entries) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory()) { walk(full); continue; }
            const ext = path.extname(entry.name).toLowerCase();
            if (ext !== '.html' && ext !== '.php') continue;
            collectUrls(fs.readFileSync(full, 'utf8'));
        }
    }
    walk(DIST);

    const urls = [...found].sort((a, b) => a.localeCompare(b));
    const out = path.join(DIST, 'external-url.json');
    fs.writeFileSync(out, JSON.stringify(urls, null, 2) + '\n', 'utf8');
    console.log('已生成外链清单: ' + path.relative(DIST, out) + ' (共 ' + urls.length + ' 个地址)');
}

(async () => {
try {
// 先生成密码保护页面：产物会写回 /pages，但 collect() 已结束，本轮不会重复处理
for (const srcFile of encryptedPages) {
    await processEncryptedPage(srcFile);
}
for (const p of lockedEncPages) {
    refreshUnlockShell(p.dir, p.baseName);
}
for (const [dir, baseMap] of pageFilesByDir) {
    const pages = [...baseMap.values()];
    if (pages.length === 0) continue;

    const descriptors = pages.map((p) => {
        const outPath = outPathFor(p.srcFile);
        return Object.assign({}, p, { outPath, displayName: p.base });
    });

    const hasIndex = descriptors.some((d) => d.base.toLowerCase() === 'index');
    const hasLockedPage = descriptors.some((d) => d.lockedPage);

    // 含密码保护页面的目录即使只有一个页面，也生成列表页作为入口
    if (hasIndex || (descriptors.length < 2 && !hasLockedPage)) {
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
        // 密码保护页面骨架已自带 auto-list 侧栏，这里不再重复包裹，避免整篇文档被塞进 div
        const navHtml = d.lockedPage ? '' : buildNav(d.outPath, descriptors);
        const bodyHtml = d.ext === '.md'
            ? await mdBody(d.srcFile, d.outPath)
            : fs.readFileSync(d.srcFile, 'utf8');
        processPage(d.srcFile, bodyHtml, navHtml);
    }

    const navHtmlIndex = buildNav(indexOutPath, descriptors);
    const dirLabel = '/' + path.relative(PAGES, dir).split(path.sep).join('/');
    const fileEntries = [];
    for (const d of descriptors) {
        fileEntries.push({
            label: d.base, link: d.outPath,
            desc: d.lockedPage ? '<页面受密码保护>' : fileDescription(d.srcFile, d.ext)
        });
    }
    for (const sf of staticFiles) {
        if (path.dirname(sf.full) === dir) {
            // 密文文件是密码框页面的内部数据，不列入自动列表
            if (sf.full.toLowerCase().endsWith(ENC_FILE_SUFFIX)) continue;
            const dest = path.join(DIST, path.relative(PAGES, sf.full));
            fileEntries.push({ label: path.basename(sf.full), link: dest, desc: '' });
        }
    }
    fileEntries.sort((a, b) => a.label.localeCompare(b.label));
    // 自动列表页没有源文件，取该目录下所有页面中最新的提交时间
    const newest = descriptors
        .map((d) => lastmodMap.get(d.outPath))
        .filter((t) => t && !isNaN(t.getTime()))
        .sort((a, b) => b.getTime() - a.getTime())[0];
    if (newest) lastmodMap.set(indexOutPath, newest);
    fs.writeFileSync(indexOutPath, renderListPage(dirLabel, indexOutPath, fileEntries, navHtmlIndex, dir), 'utf8');
    pageCount++;
    console.log('已生成列表: ' + path.relative(DIST, indexOutPath));
}

console.log('处理完成：共处理 ' + pageCount + ' 个页面');

buildSitemap();
buildExternalUrlList();
} catch (e) {
    console.error('');
    console.error('错误：构建中止 - ' + e.message);
    process.exit(1);
}
})();
-----END NODEJS CODE-----
