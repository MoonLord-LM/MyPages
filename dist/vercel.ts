// Vercel 配置文件
// 包含重定向规则，注意要和 404.php 文件中的 $redirects 映射规则保持一致

import { defineConfig } from 'vercel';

export default defineConfig ({
  cleanUrls: true,
  trailingSlash: true,
  redirects: [
    {
      source: '/service/network-proxy',
      destination: '/service/network-proxy/index.html',
      statusCode: 301,
    },
  ],
});
