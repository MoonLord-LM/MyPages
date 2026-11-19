<?php

# 需要授权：
# chown -R 'www-data:www-data' '/var/www/'

# 需要配置文件：
# /var/www/config/models.json
# 配置文件格式：
# { "models": [ { "id", "name", "vendor", "url", "apiKey", "desc" } ] }

const MODELS_FILE = '/var/www/config/models.json';
const MODELS_LOG = '/var/www/config/models.log';

date_default_timezone_set('Asia/Shanghai');
mb_internal_encoding('UTF-8');
ini_set('default_charset', 'UTF-8');

function output_json($code, $data) {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE), "\n";
    exit;
}

function output_error($code, $message) {
    output_json($code, ['error' => ['message' => $message, 'type' => $message, 'code' => $message, 'param' => $message]]);
}

function read_model_config() {
    $content = @file_get_contents(MODELS_FILE);
    if ($content === false) {
        output_error(500, 'config unavailable');
    }
    $config = json_decode($content, true);
    if (!is_array($config) || !isset($config['models']) || !is_array($config['models'])) {
        output_error(500, 'invalid config');
    }
    $models = [];
    foreach ($config['models'] as $model) {
        if (isset($model['id'], $model['url'], $model['apiKey'])) {
            $models[] = $model;
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

function model_info($config, $id) {
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

function append_proxy_log($payload_json, $code, $body) {
    $decoded_body = json_decode($body, true);
    $record = [
        'timestamp' => date('Y-m-d H:i:s'),
        'request' => json_decode($payload_json, true),
        'code' => $code,
        'response' => is_array($decoded_body) ? $decoded_body : $body,
    ];
    $line = json_encode($record, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    @file_put_contents(MODELS_LOG, $line . "\n", FILE_APPEND | LOCK_EX);
}

function show_proxy_log() {
    $content = @file_get_contents(MODELS_LOG);
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
    @file_put_contents(MODELS_LOG, '', LOCK_EX);
    header('Content-Type: text/plain; charset=utf-8');
    echo 'clear ok';
}

function proxy_request($config) {
    $input = file_get_contents('php://input');
    $request = json_decode($input, true);
    if (!is_array($request)) {
        output_error(400, 'invalid request');
    }

    $model = find_model_by_id($config, isset($request['model']) ? $request['model'] : '');
    if ($model === null) {
        output_error(404, 'model not found');
    }

    $payload = $request;
    $payload['model'] = $model['id'];
    $payload_json = json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);

    if (!function_exists('curl_init')) {
        append_proxy_log($payload_json, 500, 'curl unavailable');
        output_error(500, 'curl unavailable');
    }

    $curl_request = curl_init($model['url']);
    if ($curl_request === false) {
        append_proxy_log($payload_json, 500, 'curl init error');
        output_error(500, 'curl init error');
    }
    curl_setopt_array($curl_request, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => $payload_json,
        CURLOPT_HTTPHEADER => [
            'Content-Type: application/json',
            'Authorization: Bearer ' . $model['apiKey'],
        ],
        CURLOPT_CONNECTTIMEOUT => 30,
        CURLOPT_TIMEOUT => 300,
        CURLOPT_FOLLOWLOCATION => true,
    ]);

    if (isset($payload['stream']) && $payload['stream'] === true) {
        while (ob_get_level() > 0) {
            ob_end_flush();
        }
        $stream_body = '';
        $headers_sent = false;
        curl_setopt($curl_request, CURLOPT_RETURNTRANSFER, false);
        curl_setopt($curl_request, CURLOPT_WRITEFUNCTION, function ($curl_request, $chunk) use (&$stream_body, &$headers_sent) {
            if (!$headers_sent) {
                $response_code = curl_getinfo($curl_request, CURLINFO_HTTP_CODE);
                if ($response_code >= 400) {
                    http_response_code($response_code);
                    header('Content-Type: application/json; charset=utf-8');
                }
                else {
                    header('Content-Type: text/event-stream; charset=utf-8');
                    header('Cache-Control: no-cache');
                    header('X-Accel-Buffering: no');
                }
                $headers_sent = true;
            }
            $stream_body .= $chunk;
            echo $chunk;
            flush();
            return strlen($chunk);
        });
        curl_exec($curl_request);
        $code = curl_getinfo($curl_request, CURLINFO_HTTP_CODE);
        curl_close($curl_request);
        if (!$headers_sent) {
            if ($code >= 400) {
                http_response_code($code);
                header('Content-Type: application/json; charset=utf-8');
            }
            else {
                header('Content-Type: text/event-stream; charset=utf-8');
                header('Cache-Control: no-cache');
                header('X-Accel-Buffering: no');
            }
        }
        append_proxy_log($payload_json, $code, $stream_body);
        return;
    }

    curl_setopt($curl_request, CURLOPT_RETURNTRANSFER, true);
    $body = curl_exec($curl_request);
    $code = curl_getinfo($curl_request, CURLINFO_HTTP_CODE);
    $type = curl_getinfo($curl_request, CURLINFO_CONTENT_TYPE);
    curl_close($curl_request);

    if ($body === false) {
        append_proxy_log($payload_json, 502, 'upstream unavailable');
        output_error(502, 'upstream unavailable');
    }
    $decoded = json_decode($body, true);
    if (!is_array($decoded)) {
        append_proxy_log($payload_json, 502, $body);
        output_error(502, 'upstream json unavailable');
    }
    else if (isset($decoded['error']) && $code < 400) {
        append_proxy_log($payload_json, 502, $body);
        output_error(502, 'upstream json contains error');
    }
    append_proxy_log($payload_json, $code, $body);
    http_response_code($code);
    header('Content-Type: ' . ($type ?: 'application/json; charset=utf-8'));
    echo $body;
}

$config = read_model_config();
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
        model_info($config, urldecode(substr($path, strlen('/v1/models/'))));
    }
    else {
        list_models($config);
    }
}
else if ($method === 'POST') {
    proxy_request($config);
}
else {
    output_error(405, 'method not allowed');
}
