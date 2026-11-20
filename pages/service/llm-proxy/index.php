<?php

# 需要授权：
# chown -R 'www-data:www-data' '/var/www/'

# 需要配置文件：
# /var/www/config/models.json
# 配置文件格式：
# { "models": [ { "id", "name", "vendor", "url", "apiKey", "desc" } ] }

const MODELS_FILE = '/var/www/config/models.json';
const PROXY_LOG = '/var/www/config/models.log';
const PROXY_LOG_MAX_BYTES = 5 * 1024 * 1024;

date_default_timezone_set('Asia/Shanghai');
mb_internal_encoding('UTF-8');
ini_set('default_charset', 'UTF-8');

function output_json($status_code, $data) {
    http_response_code($status_code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE), "\n";
    exit;
}

function output_error($status_code, $message) {
    output_json($status_code, ['error' => ['message' => $message, 'type' => $message, 'code' => $message, 'param' => $message]]);
}

function read_model_config() {
    $content = @file_get_contents(MODELS_FILE);
    if ($content === false) {
        output_error(500, 'config unavailable');
    }
    $config = json_decode($content, true);
    if (!is_array($config) || !isset($config['models']) || !is_array($config['models'])) {
        output_error(500, 'config invalid');
    }
    $models = [];
    foreach ($config['models'] as $model) {
        if (isset($model['id'], $model['url'], $model['apiKey'])) {
            if (is_string($model['id']) && is_string($model['url']) && is_string($model['apiKey'])) {
                $models[] = $model;
            }
        }
    }
    $config['models'] = $models;
    return $config;
}

function list_models($config) {
    $ids = [];
    $data = [];
    foreach ($config['models'] as $model) {
        $id = $model['id'];
        $name = isset($model['name']) ? $model['name'] : '';
        if ($id !== '' && !in_array($id, $ids, true)) {
            $ids[] = $id;
            $data[] = ['id' => $id, 'object' => 'model', 'created' => 0, 'owned_by' => $name];
        }
    }
    output_json(200, ['object' => 'list', 'data' => $data]);
}

function find_model_by_id($config, $id) {
    $pool = [];
    foreach ($config['models'] as $model) {
        if ($model['id'] === $id) {
            $pool[] = $model;
        }
    }
    if (count($pool) === 0) {
        return null;
    }
    return $pool[array_rand($pool)];
}

function get_model_info($config, $id) {
    $model = find_model_by_id($config, $id);
    if ($model === null) {
        output_error(404, 'model not found');
    }
    output_json(200, [
        'id' => $id,
        'object' => 'model',
        'created' => 0,
        'owned_by' => isset($model['name']) ? $model['name'] : '',
        'name' => isset($model['name']) ? $model['name'] : '',
        'vendor' => isset($model['vendor']) ? $model['vendor'] : '',
        'desc' => isset($model['desc']) ? $model['desc'] : '',
    ]);
}

function append_proxy_log($request, $status_code, $response) {
    if (@filesize(PROXY_LOG) > PROXY_LOG_MAX_BYTES) {
        @file_put_contents(PROXY_LOG, '', LOCK_EX);
    }
    $decoded = is_array($response) ? $response : json_decode($response, true);
    if (!is_array($decoded)) {
        $decoded = $response;
    }
    $record = [
        'timestamp' => date('Y-m-d H:i:s'),
        'request' => $request,
        'code' => $status_code,
        'response' => $decoded,
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

function proxy_request($config) {
    $input = file_get_contents('php://input');
    $request = json_decode($input, true);
    if (!is_array($request)) {
        append_proxy_log($input, 400, 'request invalid');
        output_error(400, 'request invalid');
    }

    $model = find_model_by_id($config, isset($request['model']) ? $request['model'] : '');
    if ($model === null) {
        append_proxy_log($request, 400, 'model not found');
        output_error(404, 'model not found');
    }

    $request['model'] = $model['id'];
    $request_json = json_encode($request, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);

    if (!function_exists('curl_init')) {
        append_proxy_log($request, 500, 'curl unavailable');
        output_error(500, 'curl unavailable');
    }

    $curl_request = curl_init($model['url']);
    if ($curl_request === false) {
        append_proxy_log($request, 500, 'curl init error');
        output_error(500, 'curl init error');
    }
    curl_setopt_array($curl_request, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => $request_json,
        CURLOPT_HTTPHEADER => [
            'Content-Type: application/json',
            'Authorization: Bearer ' . $model['apiKey'],
        ],
        CURLOPT_CONNECTTIMEOUT => 30,
        CURLOPT_TIMEOUT => 300,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_PROTOCOLS => CURLPROTO_HTTP | CURLPROTO_HTTPS,
    ]);

    if (isset($request['stream']) && $request['stream'] === true) {
        while (ob_get_level() > 0) {
            ob_end_flush();
        }
        $stream_chunks = [];
        $headers_sent = false;
        curl_setopt($curl_request, CURLOPT_RETURNTRANSFER, false);
        curl_setopt($curl_request, CURLOPT_WRITEFUNCTION, function ($curl_request, $chunk) use (&$stream_chunks, &$headers_sent) {
            if (!$headers_sent) {
                $status_code = curl_getinfo($curl_request, CURLINFO_HTTP_CODE);
                if ($status_code >= 400) {
                    http_response_code($status_code);
                    header('Content-Type: application/json; charset=utf-8');
                }
                else {
                    header('Content-Type: text/event-stream; charset=utf-8');
                    header('Cache-Control: no-cache');
                    header('X-Accel-Buffering: no');
                }
                $headers_sent = true;
            }
            $stream_chunks[] = $chunk;
            echo $chunk;
            flush();
            return strlen($chunk);
        });
        $result = curl_exec($curl_request);
        if ($result === false && !$headers_sent) {
            append_proxy_log($request, 502, 'upstream unavailable');
            output_error(502, 'upstream unavailable');
        }

        $status_code = curl_getinfo($curl_request, CURLINFO_HTTP_CODE);
        if (!$headers_sent) {
            if ($status_code >= 400) {
                append_proxy_log($request, $status_code, 'upstream error');
                output_error($status_code, 'upstream error');
            }
            header('Content-Type: text/event-stream; charset=utf-8');
            header('Cache-Control: no-cache');
            header('X-Accel-Buffering: no');
        }
        append_proxy_log($request, $status_code, $stream_chunks);
        return;
    }

    curl_setopt($curl_request, CURLOPT_RETURNTRANSFER, true);
    $body = curl_exec($curl_request);
    $status_code = curl_getinfo($curl_request, CURLINFO_HTTP_CODE);
    $content_type = curl_getinfo($curl_request, CURLINFO_CONTENT_TYPE);

    if ($body === false) {
        append_proxy_log($request, 502, 'upstream unavailable');
        output_error(502, 'upstream unavailable');
    }
    $decoded = json_decode($body, true);
    if (!is_array($decoded)) {
        append_proxy_log($request, 502, $body);
        output_error(502, 'upstream json unavailable');
    }
    else if (isset($decoded['error']) && $status_code < 400) {
        append_proxy_log($request, 502, $body);
        output_error(502, 'upstream json contains error');
    }
    append_proxy_log($request, $status_code, $body);
    http_response_code($status_code);
    header('Content-Type: ' . ($content_type ?: 'application/json; charset=utf-8'));
    echo $body;
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
        $config = read_model_config();
        get_model_info($config, urldecode(substr($path, strlen('/v1/models/'))));
    }
    else {
        $config = read_model_config();
        list_models($config);
    }
}
else if ($method === 'POST') {
    $config = read_model_config();
    proxy_request($config);
}
else {
    header('Allow: GET, POST');
    output_error(405, 'method not allowed');
}
