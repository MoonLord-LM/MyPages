# 站点镜像

## 主站

部署在自建服务器上，使用 GitHub Webhooks 自动同步  

[https://www.moonlord.cc](https://www.moonlord.cc)  
[https://moonlord.cc](https://moonlord.cc)  
[https://01.moonlord.cc](https://01.moonlord.cc)  
[https://02.moonlord.cc](https://02.moonlord.cc)  

## GitHub Pages 镜像站点

部署在 GitHub Pages 上，使用 GitHub Actions 自动同步  

[https://github.moonlord.cc](https://github.moonlord.cc)  

## CloudFlare Pages 镜像站点

部署在 CloudFlare Pages 上，使用 Cloudflare Wrangler 手动同步  

[https://cloudflare.moonlord.cc](https://cloudflare.moonlord.cc)  

由于带宽资源和存储空间整体较优，一些大的静态资源文件仅在这个站点部署  

## Vercel 镜像站点

部署在 Vercel 上，使用 GitHub App 自动同步  

[https://vercel.moonlord.cc](https://vercel.moonlord.cc)  

## Netlify 镜像站点

部署在 Netlify 上，使用 GitHub App 自动同步  

[https://netlify.moonlord.cc](https://netlify.moonlord.cc)  

## 站点 Clean / Pretty URL 效果

| 站点 | 完整文件路径 | / | /index | /index.html |
| -- | -- | -- | -- | -- |
| 主站 | [/about/mirror.html](https://www.moonlord.cc/about/mirror.html) ✅ | [/about/](https://www.moonlord.cc/about/) ✅ | [/about/index](https://www.moonlord.cc/about/index) ✅ | [/about/index.html](https://www.moonlord.cc/about/index.html) ✅ |
| GitHub | [/about/mirror.html](https://github.moonlord.cc/about/mirror.html) ✅ | [/about/](https://github.moonlord.cc/about/) ✅ | [/about/index](https://github.moonlord.cc/about/index) ✅ | [/about/index.html](https://github.moonlord.cc/about/index.html) ✅ |
| CloudFlare | [/about/mirror.html](https://cloudflare.moonlord.cc/about/mirror.html) ℹ️ 308 跳转 | [/about/](https://cloudflare.moonlord.cc/about/) ✅ | [/about/index](https://cloudflare.moonlord.cc/about/index) ℹ️ 308 跳转 | [/about/index.html](https://cloudflare.moonlord.cc/about/index.html) ℹ️ 308 跳转 |
| Vercel | [/about/mirror.html](https://vercel.moonlord.cc/about/mirror.html) ✅ | [/about/](https://vercel.moonlord.cc/about/) ✅ | [/about/index](https://vercel.moonlord.cc/about/index) ❌ 404 报错 | [/about/index.html](https://vercel.moonlord.cc/about/index.html) ✅ |
| Netlify | [/about/mirror.html](https://netlify.moonlord.cc/about/mirror.html) ✅ | [/about/](https://netlify.moonlord.cc/about/) ✅ | [/about/index](https://netlify.moonlord.cc/about/index) ✅ | [/about/index.html](https://netlify.moonlord.cc/about/index.html) ✅ |

## 站点 HTTP Range Requests / 206 Partial Content 效果

以 /favicon.ico 为基准，发送四种 `Range` 请求头测试  

| 站点 | 单段范围 `bytes=0-99` | 尾部范围 `bytes=-100` | 超出范围 `bytes=99999999-` | 多段范围 `bytes=0-9,20-29` |
| -- | -- | -- | -- | -- |
| 主站 | ✅ 206 Partial Content | ✅ 206 Partial Content | ✅ 416 + Content-Range | ✅ 206 multipart/byteranges |
| GitHub | ✅ 206 Partial Content | ✅ 206 Partial Content | ✅ 416 + Content-Range | ℹ️ 200 返回全文 |
| CloudFlare | ✅ 206 Partial Content | ✅ 206 Partial Content | ✅ 416 + Content-Range | ✅ 206 multipart/byteranges |
| Vercel | ✅ 206 Partial Content | ✅ 206 Partial Content | ℹ️ 416 但响应体仍是全文 | ℹ️ 200 返回全文 |
| Netlify | ✅ 206 Partial Content | ✅ 206 Partial Content | ℹ️ 缓存命中时 416（无 Content-Range），否则 200 全文 | ℹ️ 200 返回全文 |

## 站点 404 Not Found 效果

请求不存在的路径 /404/404/404.html 测试  

| 站点 | 状态码 | 返回内容 |
| -- | -- | -- |
| 主站 | [/404/404/404.html](https://www.moonlord.cc/404/404/404.html) ❌ 404 | text/plain `404 Not Found: /404/404/404.html`，附 120 秒后跳回首页的 Refresh 头 |
| GitHub | [/404/404/404.html](https://github.moonlord.cc/404/404/404.html) ❌ 404 | GitHub Pages 默认 404 页面（text/html） |
| CloudFlare | [/404/404/404.html](https://cloudflare.moonlord.cc/404/404/404.html) ℹ️ 200 | 首页 HTML，状态码不是 404 |
| Vercel | [/404/404/404.html](https://vercel.moonlord.cc/404/404/404.html) ❌ 404 | text/plain `The page could not be found`，另含 `NOT_FOUND` 与请求 ID |
| Netlify | [/404/404/404.html](https://netlify.moonlord.cc/404/404/404.html) ❌ 404 | Netlify 默认 `Page not found` 页面（text/html） |
