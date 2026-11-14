# 默认指令

当用户没有给出明确指令，或者只是简单的 “执行 LLM” 等模糊指令时，按以下步骤行动：  
1. 尝试读取 README.md 文件，理解整个工程结构  
2. 尝试读取 LLM.md 文件，理解已有的编码规范和操作要求  
3. 审核全部的代码和文档，尝试给出对已有内容的修改建议  
4. 从其它角度考虑，尝试给出发散性的建议，例如新增功能特性、优化整体架构、删除多余内容、补充编码规范，完善文档信息等  
5. 逐条审核修改建议，综合考虑修改内容的正确性、复杂度、改动价值，只把高价值的建议提供给用户  



# Issue

这里记录一些已知问题  
在使用 LLM 分析代码时，请参考已有结论，避免重复报告问题  

## deploy.php 安全性问题

脚本 deploy.php 内部已保证了部署的安全性，重复触发也不会有明显危害  
不需要增加额外的鉴权机制  

## 静态资源的手动管理

由于 GitHub 仓库大小有限制，因此一些大的静态资源，只在 CloudFlare Pages 上托管部署  
手动上传网址 https://dash.cloudflare.com/2d295aefa3699c7b878cf0468beaf53e/pages/view/moonlord/deployments/new  
手动上传脚本 [上传 Cloudflare Pages.bat](./tools/cloudflare/上传%20Cloudflare%20Pages.bat)  
部署后，使用 https://cloudflare.moonlord.cc/static/* 的链接，访问静态资源文件  
另外，还需要手动维护 [list.json](https://cloudflare.moonlord.cc/static/list.json) 静态资源清单文件  
刷新清单脚本 [刷新 Cloudflare Pages 清单.bat](./tools/cloudflare/刷新%20list.json%20列表.bat)  



# TODO

这里记录一些代办事项  

## 通过 header.html 注入 CSS 代码规范性问题

目前，通过 header.html 注入的 `<style>` 会在 `<body>` 后面  
虽然可以正常解析，但是不符合 HTML 规范  



# 编码规范

## 编码格式

所有文本文件，统一使用 UTF-8 无 BOM 编码，换行符统一使用 CRLF（`\r\n`）  

## 代码修改范围

注意：/dist 目录的内容，只通过 GitHub 流水线自动构建生成，不应该在本地直接修改内容  

## 注释规范

代码本身就是最好的说明，额外的注释反而增加维护成本  
仅添加少量的注释，并且应该是对代码目标的说明，而不是复述一遍代码本身，复述没有任何意义  

## 链接规范

相对路径的链接，优先在本页面打开  
完整路径的链接，优先在新页面打开  

## 页面字体和大小

普通内容，优先使用 `{ font-family: "Microsoft YaHei UI", sans-serif; }` 字体  
对于代码块，要保持等宽，使用 `{ font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace; font-variant-ligatures: none; }` 字体  

字体大小，统一使用 px 单位  
各级标题 h1-h6 对应的字体大小，建议为 28、24、20、16、14、12px  
除首页外，其它正常的卡片的标题，建议为 20px  
按钮、输入框、导航等交互控件，建议为 16px  
普通文本，建议为 14px  
