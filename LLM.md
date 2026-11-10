# Issue

这里记录一些已知问题  
在使用 LLM 分析代码时，请参考已有结论，避免重复报告问题  

## deploy.php 安全性问题

脚本 deploy.php 内部已保证了部署的安全性，重复触发也不会有明显危害  
不需要增加额外的鉴权机制  

## 站点地图的统计范围

目前站点地图会把 /webhook 和 /admin 这种特殊目录中的页面也统计进来  
暂时保持现状，后续再考虑是否修改  



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
