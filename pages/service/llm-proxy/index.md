# LLM 代理

## 1. 简单的 LLM API 代理服务

将请求分发给后端配置的服务器（一些免费的 API 资源）  
支持动态配置、负载均衡、流式请求、日志记录  
可用于分析调试 LLM 模型或 Agent 工具等  
查看源代码：[index.php ](https://github.com/MoonLord-LM/MyPages/blob/master/pages/service/llm-proxy/index.php)  

API 清单：  

| URL | 说明 |
| --- | --- |
| [https://www.moonlord.cc/service/llm-proxy/index.php/v1](https://www.moonlord.cc/service/llm-proxy/index.php/v1) | 配置地址 |
| [https://www.moonlord.cc/service/llm-proxy/index.php/v1/models](https://www.moonlord.cc/service/llm-proxy/index.php/v1/models) | 查看模型列表 |
| [https://www.moonlord.cc/service/llm-proxy/index.php/v1/models/glm-4.7-flash](https://www.moonlord.cc/service/llm-proxy/index.php/v1/models/glm-4.7-flash) | 查看模型信息 |
| [https://www.moonlord.cc/service/llm-proxy/index.php/v1/chat/completions](https://www.moonlord.cc/service/llm-proxy/index.php/v1/chat/completions) | POST 调用模型 |
| [https://www.moonlord.cc/service/llm-proxy/index.php/v1/log/view](https://www.moonlord.cc/service/llm-proxy/index.php/v1/log/view) | 查看调用日志 |
| [https://www.moonlord.cc/service/llm-proxy/index.php/v1/log/clear](https://www.moonlord.cc/service/llm-proxy/index.php/v1/log/clear) | 清空调用日志 |

## 2. 利用浏览器处理请求的 LLM API 代理服务

将请求分发给浏览器插件来处理（利用免费的网页版 LLM 资源）  
查看源代码：[local.php ](https://github.com/MoonLord-LM/MyPages/blob/master/pages/service/llm-proxy/local.php)  
