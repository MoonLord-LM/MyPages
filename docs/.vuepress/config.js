const { defaultTheme } = require('@vuepress/theme-default');
const { searchPlugin } = require('@vuepress/plugin-search')

module.exports = {
  // 基础路径
  base: '/',

  // 基础标题
  title: 'MyPages Title',

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

  // 插件设置
  plugins: [
    searchPlugin({
      maxSuggestions: 10,
      locales: {
        '/': {
          placeholder: 'Search',
        },
        '/zh/': {
          placeholder: '搜索',
        },
      },
    }),
  ],

}
