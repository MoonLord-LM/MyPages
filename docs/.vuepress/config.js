const { defaultTheme } = require('@vuepress/theme-default')

module.exports = {
    // 在这里进行配置
    theme: defaultTheme({
        // 导航栏左侧的 Logo 图片
        logo: '/images/hero.png',
        logoDark: '/images/hero.png',
        // 导航栏右侧
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
        repoLabel: 'MyPages',
        repo: 'https://github.com/MoonLord-LM/MyPages/',
    }),
}
