<?php

# 需要授权：
# chown -R 'www-data:www-data' '/var/www/'

# 需要配置文件：
# /var/www/config/models.json
# 配置文件格式：
# { "models": [ { "id", "name", "vendor", "url", "apiKey", "desc" } ] }

const MODELS_FILE = '/var/www/config/models.json';

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
    output_json(200, ['object' => 'list', 'data' => $data, ]);
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
    $payload_json = json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);

    if (!function_exists('curl_init')) {
        output_error(500, 'curl unavailable');
    }

    $curl_request = curl_init($model['url']);
    if ($curl_request === false) {
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

    curl_setopt($curl_request, CURLOPT_RETURNTRANSFER, true);
    $body = curl_exec($curl_request);
    $code = curl_getinfo($curl_request, CURLINFO_HTTP_CODE);
    $type = curl_getinfo($curl_request, CURLINFO_CONTENT_TYPE);
    curl_close($curl_request);

    if ($body === false) {
        output_error(502, 'upstream unavailable');
    }
    $decoded = json_decode($body, true);
    if(!is_array($decoded)){
        output_error(502, 'upstream json unavailable');
    }
    else if (is_array($decoded) && isset($decoded['error']) && $code < 400 ) {
        output_error(502, 'upstream json contains error');
    }
    http_response_code($code);
    header('Content-Type: ' . ($type ?: 'application/json; charset=utf-8'));
    echo $body;
    exit;
}

$config = read_model_config();
$method = isset($_SERVER['REQUEST_METHOD']) ? $_SERVER['REQUEST_METHOD'] : '';
$path = isset($_SERVER['PATH_INFO']) ? $_SERVER['PATH_INFO'] : '';

if ($method === 'GET') {
    if (strpos($path, '/v1/models/') === 0) {
        model_info($config, urldecode(substr($path, strlen('/v1/models/'))));
    }
    list_models($config);
}
else if ($method === 'POST') {
    proxy_request($config);
}
else {
    output_error(405, 'method not allowed');
}
