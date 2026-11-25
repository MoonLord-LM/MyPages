<?php

# 需要授权：
# chown -R 'www-data:www-data' '/var/www/'

# 需要配置文件：
# /var/www/config/local.json
# 配置文件格式：
# { "Redis": { "host", "port", "tls", "password" } }

const LOCAL_CONFIG_FILE = '/var/www/config/local.json';
const PROXY_LOG = '/var/www/config/local.log';
const PROXY_LOG_MAX_BYTES = 5 * 1024 * 1024;

const MODEL_ID = 'WebModel';
const MODEL_NAME = 'WebAPI';
const MODEL_VENDOR = 'WebAPI';
const MODEL_DESC = 'WebAPI';

const PROXY_QUEUE = 'llm-proxy:local:queue';
const PROXY_REQUEST_PREFIX = 'llm-proxy:local:request:';
const REQUEST_TTL = 120;
const WAIT_SECONDS = 45;
const POLL_SECONDS = 3;

date_default_timezone_set('Asia/Shanghai');
mb_internal_encoding('UTF-8');
ini_set('default_charset', 'UTF-8');

function output_json($status_code, $data) {
    http_response_code($status_code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE), "\n";
    exit;
}

function output_error($status_code, $message) {
    output_json($status_code, ['error' => ['message' => $message, 'type' => $message, 'code' => $message, 'param' => $message]]);
}

function read_redis_config() {
    $content = @file_get_contents(LOCAL_CONFIG_FILE);
    if ($content === false) {
        output_error(500, 'redis config unavailable');
    }
    $config = json_decode($content, true);
    if (!is_array($config) || !isset($config['Redis']) || !is_array($config['Redis'])) {
        output_error(500, 'redis config invalid');
    }
    $redis_config = $config['Redis'];
    if (!isset($redis_config['host'], $redis_config['port'])) {
        output_error(500, 'redis config missing host or port');
    }
    if (!is_string($redis_config['host']) || !is_numeric($redis_config['port'])) {
        output_error(500, 'redis config invalid');
    }
    if (isset($redis_config['tls']) && !is_bool($redis_config['tls'])) {
        output_error(500, 'redis config invalid');
    }
    if (isset($redis_config['password']) && !is_string($redis_config['password'])) {
        output_error(500, 'redis config invalid');
    }
    return $redis_config;
}

function list_models() {
    output_json(200, [
        'object' => 'list',
        'data' => [['id' => MODEL_ID, 'object' => 'model', 'created' => 0, 'owned_by' => MODEL_NAME]],
    ]);
}

function get_model_info($id) {
    if ($id !== MODEL_ID) {
        output_error(404, 'model not found');
    }
    output_json(200, [
        'id' => MODEL_ID,
        'object' => 'model',
        'created' => 0,
        'owned_by' => MODEL_NAME,
        'name' => MODEL_NAME,
        'vendor' => MODEL_VENDOR,
        'desc' => MODEL_DESC,
    ]);
}

function append_proxy_log($request, $status_code, $response) {
    if (@filesize(PROXY_LOG) > PROXY_LOG_MAX_BYTES) {
        @file_put_contents(PROXY_LOG, '', LOCK_EX);
    }
    $record = [
        'timestamp' => date('Y-m-d H:i:s'),
        'request' => $request,
        'code' => $status_code,
        'response' => $response,
    ];
    $line = json_encode($record, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    @file_put_contents(PROXY_LOG, $line . "\n", FILE_APPEND | LOCK_EX);
}

function show_proxy_log() {
    $content = @file_get_contents(PROXY_LOG);
    $records = [];
    if ($content !== false) {
        foreach (explode("\n", $content) as $line) {
            $record = json_decode(trim($line), true);
            if (is_array($record)) {
                $records[] = $record;
            }
        }
    }
    output_json(200, $records);
}

function clear_proxy_log() {
    @file_put_contents(PROXY_LOG, '', LOCK_EX);
    header('Content-Type: text/plain; charset=utf-8');
    echo 'clear ok';
}

function create_redis_client() {
    if (!extension_loaded('redis')) {
        output_error(500, 'redis extension unavailable');
    }
    $redis_config = read_redis_config();
    $use_tls = isset($redis_config['tls']) && $redis_config['tls'] === true;
    if ($use_tls && !extension_loaded('openssl')) {
        output_error(500, 'openssl extension unavailable');
    }
    $options = [];
    if ($use_tls) {
        $options['stream'] = ['verify_peer' => false, 'verify_peer_name' => false];
    }
    $target = ($use_tls ? 'tls://' : '') . $redis_config['host'];
    $redis = new Redis();
    if (!@$redis->connect($target, (int)$redis_config['port'], 5, null, 0, 5, $options)) {
        output_error(500, 'redis unavailable');
    }
    $password = isset($redis_config['password']) ? $redis_config['password'] : '';
    if ($password !== '' && !$redis->auth($password)) {
        output_error(500, 'redis auth failed');
    }
    return $redis;
}

function normalize_chat_completion_response($response) {
    if (!is_array($response) || !isset($response['choices']) || !is_array($response['choices']) || count($response['choices']) === 0) {
        output_error(400, 'response error: choices must be a non-empty array');
    }

    $response['choices'] = array_values($response['choices']);
    $response['id'] = isset($response['id']) && is_string($response['id']) && $response['id'] !== '' ? $response['id'] : 'chatcmpl-' . bin2hex(random_bytes(16));
    $response['object'] = 'chat.completion';
    $response['created'] = isset($response['created']) && is_numeric($response['created']) ? (int)$response['created'] : time();
    $response['model'] = isset($response['model']) && is_string($response['model']) && $response['model'] !== '' ? $response['model'] : MODEL_ID;

    foreach ($response['choices'] as $index => &$choice) {
        if (!is_array($choice) || !isset($choice['message']) || !is_array($choice['message'])) {
            output_error(400, 'response error: choice.message must be an object');
        }
        $choice['index'] = isset($choice['index']) && is_int($choice['index']) ? $choice['index'] : $index;
        $choice['finish_reason'] = isset($choice['finish_reason']) && is_string($choice['finish_reason']) ? $choice['finish_reason'] : 'stop';
        if (isset($choice['message']['tool_calls']) && is_array($choice['message']['tool_calls'])) {
            foreach ($choice['message']['tool_calls'] as &$tool_call) {
                if (!is_array($tool_call) || !isset($tool_call['function']) || !is_array($tool_call['function'])) {
                    output_error(400, 'response error: tool_call.function must be an object');
                }
                if (!isset($tool_call['function']['name']) || !is_string($tool_call['function']['name']) || $tool_call['function']['name'] === '') {
                    output_error(400, 'response error: tool_call.function.name must be a non-empty string');
                }
                if (!array_key_exists('arguments', $tool_call['function'])) {
                    output_error(400, 'response error: tool_call.function.arguments is missing');
                }
                if (!is_string($tool_call['function']['arguments'])) {
                    $arguments = json_encode($tool_call['function']['arguments'], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
                    if ($arguments === false) {
                        output_error(400, 'response error: tool arguments cannot be encoded - ' . json_last_error_msg());
                    }
                    $tool_call['function']['arguments'] = $arguments;
                }
                json_decode($tool_call['function']['arguments'], true);
                if (json_last_error() !== JSON_ERROR_NONE) {
                    output_error(400, 'response error: tool arguments are not valid JSON - ' . json_last_error_msg());
                }
            }
            if (count($choice['message']['tool_calls']) > 0) {
                $choice['finish_reason'] = 'tool_calls';
            }
            unset($tool_call);
        }
    }
    unset($choice);
    return $response;
}

function output_chat_completion_chunk($chunk, $choices, $usage = null) {
    $chunk['choices'] = $choices;
    if ($usage !== null) {
        $chunk['usage'] = $usage;
    }
    echo 'data: ' . json_encode($chunk, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n\n";
}

function output_chat_completion_stream($response) {
    header('Content-Type: text/event-stream; charset=utf-8');
    header('Cache-Control: no-cache');
    header('X-Accel-Buffering: no');

    $chunk = [
        'id' => $response['id'],
        'object' => 'chat.completion.chunk',
        'created' => $response['created'],
        'model' => $response['model'],
    ];
    if (isset($response['system_fingerprint'])) {
        $chunk['system_fingerprint'] = $response['system_fingerprint'];
    }

    $choice = $response['choices'][0];
    $message = $choice['message'];

    output_chat_completion_chunk($chunk, [[
        'index' => $choice['index'],
        'delta' => ['role' => 'assistant', 'content' => isset($message['content']) ? $message['content'] : ''],
        'finish_reason' => null,
    ]]);

    $tool_deltas = [];
    if (isset($message['tool_calls']) && is_array($message['tool_calls'])) {
        foreach ($message['tool_calls'] as $index => $tool_call) {
            $tool_deltas[] = [
                'index' => $index,
                'id' => isset($tool_call['id']) ? $tool_call['id'] : '',
                'type' => isset($tool_call['type']) ? $tool_call['type'] : 'function',
                'function' => [
                    'name' => $tool_call['function']['name'],
                    'arguments' => $tool_call['function']['arguments'],
                ],
            ];
        }
        if (count($tool_deltas) > 0) {
            output_chat_completion_chunk($chunk, [[
                'index' => $choice['index'],
                'delta' => ['tool_calls' => $tool_deltas],
                'finish_reason' => null,
            ]]);
        }
    }

    output_chat_completion_chunk($chunk, [[
        'index' => $choice['index'],
        'delta' => new stdClass(),
        'finish_reason' => $choice['finish_reason'],
    ]]);

    if (isset($response['usage'])) {
        output_chat_completion_chunk($chunk, [], $response['usage']);
    }

    echo "data: [DONE]\n\n";
    exit;
}

function try_output_handled($redis, $key, $request, $original_stream) {
    $value = $redis->get($key);
    if (!is_string($value)) {
        return;
    }
    $record = json_decode($value, true);
    if (!is_array($record) || !isset($record['status']) || $record['status'] !== 'handled') {
        return;
    }
    append_proxy_log($request, 200, $record['response']);
    if ($original_stream) {
        output_chat_completion_stream($record['response']);
    }
    output_json(200, $record['response']);
}

function proxy_request($redis) {
    $input = file_get_contents('php://input');
    $request = json_decode($input, true);
    if (!is_array($request)) {
        append_proxy_log($input, 400, 'request invalid');
        output_error(400, 'request invalid');
    }

    $original_stream = isset($request['stream']) && $request['stream'] === true;
    $request['stream'] = false;
    $request_json = json_encode($request, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);

    $hash = hash('sha256', $request_json);
    $key = PROXY_REQUEST_PREFIX . $hash;
    try_output_handled($redis, $key, $request, $original_stream);

    $saved_at = time();
    $record = ['hash' => $hash, 'request' => $request, 'status' => 'pending', 'response' => null, 'saved_at' => $saved_at];
    $record_json = json_encode($record, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    $redis->set($key, $record_json, REQUEST_TTL);
    $redis->lPush(PROXY_QUEUE, $hash);

    $poll_count = (int)ceil(WAIT_SECONDS / POLL_SECONDS);
    for ($index = 0; $index < $poll_count; $index++) {
        sleep(POLL_SECONDS);
        try_output_handled($redis, $key, $request, $original_stream);
    }

    $elapsed_seconds = microtime(true) - $_SERVER['REQUEST_TIME_FLOAT'];
    append_proxy_log($request, 429, 'request timeout ' . round($elapsed_seconds, 3) . 's');
    output_error(429, 'request timeout ' . round($elapsed_seconds, 3) . 's');
}

function get_request($redis) {
    $hashes = $redis->lRange(PROXY_QUEUE, 0, -1);
    if (!is_array($hashes) || count($hashes) === 0) {
        output_json(200, []);
    }
    $now = time();
    foreach ($hashes as $hash) {
        $value = $redis->get(PROXY_REQUEST_PREFIX . $hash);
        $record = is_string($value) ? json_decode($value, true) : null;
        $is_valid = is_array($record)
            && isset($record['hash'], $record['request'], $record['status'], $record['saved_at'])
            && !($record['status'] === 'handled')
            && ($now - $record['saved_at']) <= WAIT_SECONDS;
        if (!$is_valid) {
            $redis->lRem(PROXY_QUEUE, $hash, 0);
            continue;
        }
        output_json(200, ['hash' => $hash, 'request' => $record['request']]);
    }
    output_json(200, []);
}

function handle_request($redis) {
    $input = file_get_contents('php://input');
    $result = json_decode($input, true);
    if (!is_array($result) || !isset($result['hash'], $result['response'])) {
        output_error(400, 'request invalid');
    }

    $hash = $result['hash'];
    $key = PROXY_REQUEST_PREFIX . $hash;
    $value = $redis->get($key);
    if (!is_string($value)) {
        output_error(404, 'request not found');
    }
    $record = json_decode($value, true);
    if (!is_array($record)) {
        output_error(500, 'request cache invalid');
    }
    if (isset($record['status']) && $record['status'] === 'handled') {
        output_error(429, 'request already handled');
    }

    $response = normalize_chat_completion_response($result['response']);
    $record['status'] = 'handled';
    $record['response'] = $response;
    $record_json = json_encode($record, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    $redis->set($key, $record_json, REQUEST_TTL);
    $redis->lRem(PROXY_QUEUE, $hash, 0);
    output_json(200, ['hash' => $hash, 'status' => 'handled']);
}

$method = isset($_SERVER['REQUEST_METHOD']) ? $_SERVER['REQUEST_METHOD'] : '';
$path = isset($_SERVER['PATH_INFO']) ? $_SERVER['PATH_INFO'] : '';

if ($method === 'GET') {
    if ($path === '/v1/log/view') {
        show_proxy_log();
    }
    else if ($path === '/v1/log/clear') {
        clear_proxy_log();
    }
    else if (strpos($path, '/v1/models/') === 0) {
        get_model_info(urldecode(substr($path, strlen('/v1/models/'))));
    }
    else if ($path === '/v1/request/get') {
        $redis = create_redis_client();
        get_request($redis);
    }
    else {
        list_models();
    }
}
else if ($method === 'POST') {
    $redis = create_redis_client();
    if ($path === '/v1/request/handle') {
        handle_request($redis);
    }
    else {
        proxy_request($redis);
    }
}
else {
    header('Allow: GET, POST');
    output_error(405, 'method not allowed');
}
