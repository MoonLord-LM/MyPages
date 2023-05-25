import { defineUserConfig } from 'vuepress';
import { defaultTheme } from '@vuepress/theme-default';
import { searchPlugin } from '@vuepress/plugin-search';
import { mdEnhancePlugin } from "vuepress-plugin-md-enhance";

export default defineUserConfig({
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
    navbar: false,
    /*
    navbar: [
      // 菜单 1
      {
        text: '菜单 1 NavbarItem',
        link: '/menu1/article1.md',
        activeMatch: '/menu1/article1',
      },
      // 菜单 2
      {
        text: '菜单 2 NavbarGroup',
        children: [
          {
            text: '子菜单 1',
            link: '/menu1/article1.md',
            activeMatch: '/menu1/article1',
          },
          {
            text: '子菜单 2',
            link: '/menu2/article2.md',
            activeMatch: '/menu2/article2',
          },
        ]
      },
      // 菜单 3
      {
        text: '菜单 3 NavbarGroup Level 2',
        children: [
          {
            text: '子菜单分类 1',
            children : [
              {
                text: '子菜单 1',
                link: '/menu1/article1.md',
                activeMatch: '/menu1/article1',
              },
              {
                text: '子菜单 2',
                link: '/menu2/article2.md',
                activeMatch: '/menu2/article2',
              },
            ]
          },
          {
            text: '子菜单分类 2',
            children : [
              {
                text: '子菜单 3',
                link: '/menu3/article3.md',
                activeMatch: '/menu3/article3',
              },
              {
                text: '子菜单 4',
                link: '/menu3/article4.md',
                activeMatch: '/menu3/article4',
              },
            ]
          },
        ]
      },
      // 菜单 4
      {
        text: '菜单 4 链接',
        link: 'https://www.github.com',
      },
      // 菜单 5
      {
        text: '菜单 5 链接组',
        children: [
          {
            text: '链接 1 GitHub',
            link: 'https://www.github.com',
          },
          {
            text: '链接 2 Google',
            link: 'https://www.google.com',
          },
        ]
      },
    ],
    */

    // 导航栏右侧的仓库地址
    repoLabel: '仓库地址',
    repo: 'https://github.com/MoonLord-LM/MyPages',

    // 正文中的编辑本页
    docsRepo: 'https://github.com/MoonLord-LM/MyPages',
    docsBranch: 'master',
    docsDir: 'docs',
    editLinkPattern: ':repo/edit/:branch/:path',
    editLinkText: '编辑本页面',

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
    mdEnhancePlugin({
      mermaid: true,
    }),
  ],

})
