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

发送三种 `Range` 请求头测试 /favicon.ico

| 站点 | 单段范围 `bytes=0-99` | 尾部范围 `bytes=-100` | 多段范围 `bytes=0-9,20-29` |
| -- | -- | -- | -- |
| 主站 | ✅ 206 Partial Content | ✅ 206 Partial Content | ✅ 206 multipart/byteranges |
| GitHub | ✅ 206 Partial Content | ✅ 206 Partial Content | ⚠️ 200 返回全文 |
| CloudFlare | ✅ 206 Partial Content | ✅ 206 Partial Content | ✅ 206 multipart/byteranges |
| Vercel | ✅ 206 Partial Content | ✅ 206 Partial Content | ⚠️ 200 返回全文 |
| Netlify | ✅ 206 Partial Content | ✅ 206 Partial Content | ⚠️ 200 返回全文 |

## 站点 404 Not Found 效果

请求不存在的路径 /404/404/404.html  

| 站点 | 状态码 | 返回内容 |
| -- | -- | -- |
| 主站 | [/404/404/404.html](https://www.moonlord.cc/404/404/404.html) ✅ 404 | 提示信息：`404 Not Found: /404/404/404.html`，120 秒后返回首页 |
| GitHub | [/404/404/404.html](https://github.moonlord.cc/404/404/404.html) ✅ 404 | GitHub 默认 404 页面 |
| CloudFlare | [/404/404/404.html](https://cloudflare.moonlord.cc/404/404/404.html) ⚠️ 200 | 直接展示首页内容 |
| Vercel | [/404/404/404.html](https://vercel.moonlord.cc/404/404/404.html) ✅ 404 | Vercel 默认 404 页面 |
| Netlify | [/404/404/404.html](https://netlify.moonlord.cc/404/404/404.html) ✅ 404 | Netlify 默认 404 页面 |
