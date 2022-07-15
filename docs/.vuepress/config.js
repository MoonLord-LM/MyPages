const { defaultTheme } = require('@vuepress/theme-default')

module.exports = {
  // 基础路径
  base: '/',

  // 主题设置
  theme: defaultTheme({

    // 导航栏左侧的 Logo 图片
    logo: '/images/hero.png',
    logoDark: '/images/hero.png',

    // 导航栏右侧的菜单
    navbar: [
        // NavbarItem
        {
          text: 'Foo',
          link: '/foo/',
        },
        // NavbarGroup
        {
          text: 'Group',
          children: ['/group/foo.md', '/group/bar.md'],
        },
        // 字符串 - 页面文件路径
        '/bar/README.md',
    ],

    // 导航栏右侧的仓库地址
    repoLabel: '联系我们',
    repo: 'https://github.com/MoonLord-LM/MyPages/',

  }),
}
