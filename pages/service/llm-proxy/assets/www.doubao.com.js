// 使用豆包网页版，作为 LLM 后端
// 定时从 local.php 的接口拉取请求，让豆包生成 JSON 响应，再上报回去



var proxyBaseUrl = 'https://www.moonlord.cc/service/llm-proxy/local.php';
var intervalSeconds = 2;
var isBusy = false;

var promptInstruction1 = '现在你是一个 LLM 的 Chat Completions API 服务，使用 OpenAI API 协议，并且支持 tools 工具调用。';
var promptInstruction2 = '请处理以下的 JSON 请求，并按照 OpenAI API 协议，回复 JSON 响应。';
var promptInstruction = promptInstruction1 + '\n'+ promptInstruction2 + '\n\n';

// 对话输入框
var findComposer = function () {
    return document.querySelector('[data-testid="chat_input_input"] [contenteditable="true"]');
};

// 开启新对话
var startNewChat = async function () {
    var button = document.querySelector('[data-testid="create_conversation_button"] span');
    if (button) {
        button.click();
    }
    var deadline = Date.now() + 10000;
    while (Date.now() < deadline) {
        if (findComposer()) {
            return;
        }
        console.log('doubao.com 等待新对话：输入框未出现');
        await new Promise(function (resolve) {
            setTimeout(resolve, 1000);
        });
    }
};

// 查找可用的发送按钮
var findSendButton = function () {
    var button = document.querySelector('button[data-testid="chat_input_send_button"]');
    if (button && button.getAttribute('aria-disabled') !== 'true' && button.getAttribute('data-loading') !== 'true') {
        return button;
    }
    return null;
};

// 是否仍在生成回复
var isGenerating = function () {
    var breakButton = document.querySelector('[data-testid="chat_input_local_break_button"]');
    if (breakButton && breakButton.className.indexOf('!hidden') === -1 && breakButton.offsetParent !== null) {
        return true;
    }
    return !!document.querySelector('[data-testid="message_text_content"][data-streaming="true"]');
};

// 最后一条助手回复消息
var getLastAssistantMessage = function () {
    var messages = document.querySelectorAll('[data-testid="receive_message"][data-message-role="assistant"]');
    return messages.length > 0 ? messages[messages.length - 1] : null;
};

// 最后一条助手回复的消息 ID，用于区分新旧回复
var getLastAssistantMessageId = function () {
    var message = getLastAssistantMessage();
    var content = message ? message.querySelector('[data-testid="message_content"]') : null;
    return content ? content.getAttribute('data-message-id') : null;
};

// 最后一条助手回复文本
var getLastAssistantResponse = function () {
    var message = getLastAssistantMessage();
    if (!message) {
        return null;
    }
    var contents = message.querySelectorAll('[data-testid="message_text_content"]');
    if (contents.length === 0) {
        return null;
    }
    var last = contents[contents.length - 1];
    if (last.getAttribute('data-streaming') === 'true') {
        return null;
    }
    var codeElement = last.querySelector('pre code') || (last.matches('pre code') ? last : null);
    var text = codeElement ? codeElement.textContent : (last.innerText || last.textContent || '');
    return text.trim().replace(/^```[^\n]*\n?/, '').replace(/\n?```$/, '').trim() || null;
};

// 把文本写入输入框并读回校验
var inputPromptText = function (text) {
    return new Promise(function (resolve) {
        var composer = findComposer();
        if (!composer) {
            resolve(false);
            return;
        }
        composer.focus();
        var selection = window.getSelection();
        var range = document.createRange();
        range.selectNodeContents(composer);
        selection.removeAllRanges();
        selection.addRange(range);
        if (!document.execCommand('insertText', false, text)) {
            var clipboardData = new DataTransfer();
            clipboardData.setData('text/plain', text);
            composer.dispatchEvent(new ClipboardEvent('paste', {
                bubbles: true,
                cancelable: true,
                clipboardData: clipboardData
            }));
        }
        setTimeout(function () {
            var currentText = (composer.innerText || composer.textContent || '').trim();
            resolve(currentText.indexOf(text.trim().slice(0, 20)) !== -1);
        }, 1000);
    });
};

// 等待新回复生成完成
var waitForResponse = async function (previousMessageId) {
    var deadline = Date.now() + 180000;
    while (Date.now() < deadline) {
        var messageId = getLastAssistantMessageId();
        var currentText = getLastAssistantResponse() || '';
        if (messageId && messageId !== previousMessageId && currentText && !isGenerating()) {
            return currentText;
        }
        var reason = !currentText ? '暂无回复' : (!messageId || messageId === previousMessageId ? '回复未变化' : '仍在生成');
        console.log('doubao.com 等待回复：' + reason);
        await new Promise(function (resolve) {
            setTimeout(resolve, 1000);
        });
    }
    return null;
};

// 取一个请求，交给豆包处理，再把响应写回队列
var runOnce = async function () {
    if (isBusy || isGenerating()) {
        return;
    }
    isBusy = true;
    try {
        var httpResponse = await fetch(proxyBaseUrl + '/v1/request/get');
        if (!httpResponse.ok) {
            throw new Error('HTTP ' + httpResponse.status);
        }
        var pending = await httpResponse.json();
        if (Array.isArray(pending)) {
            return;
        }

        var prompt = promptInstruction + JSON.stringify(pending.request || {}, null, 2);

        await startNewChat();
        var previousMessageId = getLastAssistantMessageId();
        var inputOk = await inputPromptText(prompt);
        var sendButton = findSendButton();
        if (!inputOk || !sendButton) {
            console.log('doubao.com 输入或发送按钮未就绪，跳过本轮');
            return;
        }
        sendButton.click();

        var text = await waitForResponse(previousMessageId);
        if (!text) {
            console.log('doubao.com 等待回复超时');
            return;
        }
        console.log('doubao.com 输出: ' + text);

        var responseBody;
        try {
            responseBody = JSON.parse(text.trim());
        } catch (error) {
            console.log('doubao.com 回复不是合法 JSON', error);
            return;
        }
        if (!responseBody || typeof responseBody !== 'object' || Array.isArray(responseBody)) {
            console.log('doubao.com 回复不是 JSON 对象，跳过本轮');
            return;
        }

        var handleResponse = await fetch(proxyBaseUrl + '/v1/request/handle', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ hash: pending.hash, response: responseBody })
        });
        if (!handleResponse.ok) {
            throw new Error('HTTP ' + handleResponse.status);
        }
        console.log('doubao.com 响应已提交');
    } catch (error) {
        console.log('doubao.com 处理失败', error);
    } finally {
        isBusy = false;
    }
};

// 启动定时轮询
setInterval(runOnce, intervalSeconds * 1000);
