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

const PENDING_QUEUE = 'llm-proxy:local:pending';
const REQUEST_PREFIX = 'llm-proxy:local:request:';
const RESPONSE_PREFIX = 'llm-proxy:local:response:';
const REQUEST_TTL = 120;
const WAIT_SECONDS = 40;
const POLL_SECONDS = 1;

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

function output_chat_completion_stream($response) {
    header('Content-Type: text/event-stream; charset=utf-8');
    header('Cache-Control: no-cache');
    header('X-Accel-Buffering: no');

    $is_raw_stream = is_array($response) && count($response) > 0;
    if ($is_raw_stream) {
        foreach ($response as $line) {
            if (!is_string($line) || strpos($line, 'data: ') !== 0) {
                $is_raw_stream = false;
                break;
            }
        }
    }
    if ($is_raw_stream) {
        $has_done = false;
        foreach ($response as $line) {
            echo $line;
            if (strpos($line, 'data: [DONE]') !== false) {
                $has_done = true;
            }
        }
        if (!$has_done) {
            echo "data: [DONE]\n\n";
        }
        exit;
    }

    $choices = is_array($response) && isset($response['choices']) && is_array($response['choices']) ? $response['choices'] : [];
    $choice = count($choices) > 0 && is_array($choices[0]) ? $choices[0] : [];
    $message = isset($choice['message']) && is_array($choice['message']) ? $choice['message'] : [];
    $content = isset($message['content']) ? $message['content'] : '';
    $tool_calls = isset($message['tool_calls']) && is_array($message['tool_calls']) ? $message['tool_calls'] : [];
    $finish_reason = isset($choice['finish_reason']) ? $choice['finish_reason'] : 'stop';

    if (count($tool_calls) > 0 && $finish_reason !== 'tool_calls') {
        $finish_reason = 'tool_calls';
    }
    $chunk = [
        'id' => is_array($response) && isset($response['id']) ? $response['id'] : 'chatcmpl-' . bin2hex(random_bytes(16)),
        'object' => 'chat.completion.chunk',
        'created' => is_array($response) && isset($response['created']) ? $response['created'] : time(),
        'model' => is_array($response) && isset($response['model']) ? $response['model'] : MODEL_ID,
    ];
    if (is_array($response) && isset($response['system_fingerprint'])) {
        $chunk['system_fingerprint'] = $response['system_fingerprint'];
    }

    $content_chunk = $chunk;
    $content_chunk['choices'] = [[
        'index' => 0,
        'delta' => ['role' => 'assistant', 'content' => $content],
        'finish_reason' => null,
    ]];
    echo 'data: ' . json_encode($content_chunk, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n\n";

    $tool_deltas = [];
    foreach ($tool_calls as $index => $tool_call) {
        if (!is_array($tool_call)) {
            continue;
        }
        $function = isset($tool_call['function']) && is_array($tool_call['function']) ? $tool_call['function'] : [];
        $function_arguments = isset($function['arguments']) ? $function['arguments'] : '';
        if (!is_string($function_arguments)) {
            $function_arguments = json_encode($function_arguments, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        }
        $tool_deltas[] = [
            'index' => $index,
            'id' => isset($tool_call['id']) ? $tool_call['id'] : '',
            'type' => isset($tool_call['type']) ? $tool_call['type'] : 'function',
            'function' => [
                'name' => isset($function['name']) ? $function['name'] : '',
                'arguments' => $function_arguments,
            ],
        ];
    }
    if (count($tool_deltas) > 0) {
        $tool_chunk = $chunk;
        $tool_chunk['choices'] = [[
            'index' => 0,
            'delta' => ['tool_calls' => $tool_deltas],
            'finish_reason' => null,
        ]];
        echo 'data: ' . json_encode($tool_chunk, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n\n";
    }

    $finish_chunk = $chunk;
    $finish_chunk['choices'] = [[
        'index' => 0,
        'delta' => new stdClass(),
        'finish_reason' => $finish_reason,
    ]];
    echo 'data: ' . json_encode($finish_chunk, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n\n";

    if (is_array($response) && isset($response['usage']) && is_array($response['usage'])) {
        $usage_chunk = $chunk;
        $usage_chunk['choices'] = [];
        $usage_chunk['usage'] = $response['usage'];
        echo 'data: ' . json_encode($usage_chunk, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n\n";
    }

    echo "data: [DONE]\n\n";
    exit;
}

function create_redis_client() {
    $redis_config = read_redis_config();
    $use_tls = isset($redis_config['tls']) && $redis_config['tls'] === true;
    if ($use_tls && !extension_loaded('openssl')) {
        output_error(500, 'openssl unavailable');
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

function proxy_request($redis) {
    $input = file_get_contents('php://input');
    $request = json_decode($input, true);
    if (!is_array($request)) {
        append_proxy_log($input, 400, 'invalid request');
        output_error(400, 'invalid request');
    }
    $original_stream = isset($request['stream']) && $request['stream'] === true;
    if ($original_stream) {
        $request['stream'] = false;
    }

    $cached_value = $redis->get(RESPONSE_PREFIX . $input);
    if (is_string($cached_value)) {
        $cached_record = json_decode($cached_value, true);
        if (is_array($cached_record) && array_key_exists('response', $cached_record)) {
            append_proxy_log($request, 200, $cached_record['response']);
            if ($original_stream) {
                output_chat_completion_stream($cached_record['response']);
            }
            output_json(200, $cached_record['response']);
        }
    }

    $uuid = bin2hex(random_bytes(16));
    $key = REQUEST_PREFIX . $uuid;
    $saved_at = time();
    $record = ['uuid' => $uuid, 'input' => $input, 'request' => $request, 'status' => 'pending', 'response' => null, 'saved_at' => $saved_at];
    $record_json = json_encode($record, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    $redis->set($key, $record_json, REQUEST_TTL);
    $redis->lPush(PENDING_QUEUE, $uuid);

    $poll_count = (int)ceil(WAIT_SECONDS / POLL_SECONDS);
    for ($index = 0; $index < $poll_count; $index++) {
        sleep(POLL_SECONDS);
        $value = $redis->get($key);
        if (!is_string($value)) {
            continue;
        }
        $current = json_decode($value, true);
        if (is_array($current) && isset($current['status']) && $current['status'] === 'handled') {
            $redis->del($key);
            append_proxy_log($request, 200, $current['response']);
            if ($original_stream) {
                output_chat_completion_stream($current['response']);
            }
            output_json(200, $current['response']);
        }
    }
    $redis->lRem(PENDING_QUEUE, $uuid, 0);
    append_proxy_log($request, 429, 'request timeout');
    output_error(429, 'request timeout');
}

function get_request($redis) {
    $uuids = $redis->lRange(PENDING_QUEUE, 0, -1);
    if (!is_array($uuids) || count($uuids) === 0) {
        output_error(404, 'no pending request');
    }
    $now = time();
    $latest_uuid = null;
    $latest_saved_at = 0;
    $latest_request = null;
    foreach ($uuids as $uuid) {
        $value = $redis->get(REQUEST_PREFIX . $uuid);
        $record = is_string($value) ? json_decode($value, true) : null;
        $is_valid = is_array($record)
            && isset($record['request'], $record['saved_at'])
            && !(isset($record['status']) && $record['status'] === 'handled')
            && ($now - $record['saved_at']) <= WAIT_SECONDS;
        if (!$is_valid) {
            $redis->lRem(PENDING_QUEUE, $uuid, 0);
            continue;
        }
        if ($record['saved_at'] > $latest_saved_at) {
            $latest_saved_at = $record['saved_at'];
            $latest_uuid = $uuid;
            $latest_request = $record['request'];
        }
    }
    if ($latest_uuid === null) {
        output_error(404, 'no pending request');
    }
    $redis->lRem(PENDING_QUEUE, $latest_uuid, 0);
    output_json(200, ['uuid' => $latest_uuid, 'request' => $latest_request]);
}

function handle_request($redis) {
    $input = file_get_contents('php://input');
    $result = json_decode($input, true);
    if (!is_array($result) || !isset($result['uuid']) || !array_key_exists('response', $result)) {
        output_error(400, 'invalid request');
    }
    $uuid = $result['uuid'];
    $key = REQUEST_PREFIX . $uuid;
    $value = $redis->get($key);
    if (!is_string($value)) {
        output_error(404, 'request not found');
    }
    $record = json_decode($value, true);
    if (!is_array($record)) {
        output_error(500, 'invalid request');
    }
    $record['status'] = 'handled';
    $record['response'] = $result['response'];
    $record_json = json_encode($record, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    $redis->set($key, $record_json, REQUEST_TTL);
    if (isset($record['input'])) {
        $response_record = ['input' => $record['input'], 'response' => $result['response'], 'saved_at' => time()];
        $response_json = json_encode($response_record, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        $redis->set(RESPONSE_PREFIX . $record['input'], $response_json, REQUEST_TTL);
    }
    output_json(200, ['uuid' => $uuid, 'status' => 'handled']);
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
