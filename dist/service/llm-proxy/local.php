<?php

# 需要授权：
# chown -R 'www-data:www-data' '/var/www/'

# 需要配置文件：
# /var/www/config/local.json
# 配置文件格式：
# { "Redis": { "host", "port", "password" } }

const LOCAL_CONFIG_FILE = '/var/www/config/local.json';
const LOCAL_LOG = '/var/www/config/local.log';
const LOCAL_LOG_MAX_BYTES = 5 * 1024 * 1024;

const PENDING_QUEUE = 'llm:local:pending';
const REQUEST_PREFIX = 'llm:local:request:';
const REQUEST_TTL = 60;
const WAIT_SECONDS = 15;
const POLL_SECONDS = 3;

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
    return $redis_config;
}

class RedisClient {
    private $socket;

    public function __construct($redis_config) {
        $this->socket = @fsockopen($redis_config['host'], (int)$redis_config['port'], $error_code, $error_message, 5);
        if ($this->socket === false) {
            output_error(500, 'redis unavailable');
        }
        stream_set_timeout($this->socket, 5);
        $password = isset($redis_config['password']) ? $redis_config['password'] : '';
        if ($password !== '' && $this->command('AUTH', $password) !== 'OK') {
            output_error(500, 'redis auth failed');
        }
    }

    public function command(...$arguments) {
        $payload = '*' . count($arguments) . "\r\n";
        foreach ($arguments as $argument) {
            $argument = (string)$argument;
            $payload .= '$' . strlen($argument) . "\r\n" . $argument . "\r\n";
        }
        $total = strlen($payload);
        $written = 0;
        while ($written < $total) {
            $count = fwrite($this->socket, substr($payload, $written));
            if ($count === false || $count === 0) {
                return false;
            }
            $written += $count;
        }
        return $this->read_response();
    }

    private function read_exactly($length) {
        $data = '';
        while (strlen($data) < $length) {
            $chunk = fread($this->socket, $length - strlen($data));
            if ($chunk === false || $chunk === '') {
                break;
            }
            $data .= $chunk;
        }
        return $data;
    }

    private function read_response() {
        $line = fgets($this->socket);
        if ($line === false) {
            return false;
        }
        $prefix = $line[0];
        $value = substr(rtrim($line, "\r\n"), 1);
        if ($prefix === '+') {
            return $value;
        }
        if ($prefix === '-') {
            return false;
        }
        if ($prefix === ':') {
            return (int)$value;
        }
        if ($prefix === '$') {
            $length = (int)$value;
            if ($length < 0) {
                return null;
            }
            $data = $this->read_exactly($length);
            $this->read_exactly(2);
            return $data;
        }
        if ($prefix === '*') {
            $count = (int)$value;
            if ($count < 0) {
                return null;
            }
            $items = [];
            for ($index = 0; $index < $count; $index++) {
                $items[] = $this->read_response();
            }
            return $items;
        }
        return false;
    }
}

function request_key($uuid) {
    return REQUEST_PREFIX . $uuid;
}

function generate_uuid() {
    $bytes = random_bytes(16);
    $bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40);
    $bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);
    $hex = bin2hex($bytes);
    return substr($hex, 0, 8) . '-' . substr($hex, 8, 4) . '-' . substr($hex, 12, 4) . '-' . substr($hex, 16, 4) . '-' . substr($hex, 20);
}

function encode_record($record) {
    return json_encode($record, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
}

function append_local_log($request, $code, $response) {
    if (@filesize(LOCAL_LOG) > LOCAL_LOG_MAX_BYTES) {
        @file_put_contents(LOCAL_LOG, '', LOCK_EX);
    }
    $record = [
        'timestamp' => date('Y-m-d H:i:s'),
        'request' => $request,
        'code' => $code,
        'response' => $response,
    ];
    $line = json_encode($record, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    @file_put_contents(LOCAL_LOG, $line . "\n", FILE_APPEND | LOCK_EX);
}

function submit_request($redis) {
    set_time_limit(60);
    $input = file_get_contents('php://input');
    $request = json_decode($input, true);
    if (!is_array($request)) {
        append_local_log($input, 400, 'invalid request');
        output_error(400, 'invalid request');
    }
    if (isset($request['stream']) && $request['stream'] === true) {
        append_local_log($request, 400, 'stream not supported');
        output_error(400, 'stream not supported');
    }

    $uuid = generate_uuid();
    $record = ['uuid' => $uuid, 'request' => $request, 'status' => 'pending', 'response' => null];
    $redis->command('SET', request_key($uuid), encode_record($record), 'EX', REQUEST_TTL);
    $redis->command('RPUSH', PENDING_QUEUE, $uuid);

    $poll_count = (int)ceil(WAIT_SECONDS / POLL_SECONDS);
    for ($index = 0; $index < $poll_count; $index++) {
        sleep(POLL_SECONDS);
        $value = $redis->command('GET', request_key($uuid));
        if (!is_string($value)) {
            continue;
        }
        $current = json_decode($value, true);
        if (is_array($current) && isset($current['status']) && $current['status'] === 'handled') {
            $redis->command('DEL', request_key($uuid));
            append_local_log($request, 200, $current['response']);
            output_json(200, $current['response']);
        }
    }
    $redis->command('DEL', request_key($uuid));
    $redis->command('LREM', PENDING_QUEUE, 0, $uuid);
    append_local_log($request, 429, 'request timeout');
    output_error(429, 'request timeout');
}

function get_request($redis) {
    $uuid = $redis->command('LPOP', PENDING_QUEUE);
    if (!is_string($uuid) || $uuid === '') {
        output_error(404, 'no pending request');
    }
    $value = $redis->command('GET', request_key($uuid));
    if (!is_string($value)) {
        $redis->command('LREM', PENDING_QUEUE, 0, $uuid);
        output_error(404, 'request not found');
    }
    $record = json_decode($value, true);
    if (!is_array($record)) {
        output_error(500, 'invalid request');
    }
    output_json(200, ['uuid' => $uuid, 'request' => $record['request']]);
}

function handle_request($redis) {
    $input = file_get_contents('php://input');
    $result = json_decode($input, true);
    if (!is_array($result) || !isset($result['uuid']) || !array_key_exists('response', $result)) {
        output_error(400, 'invalid request');
    }
    $uuid = $result['uuid'];
    $key = request_key($uuid);
    $value = $redis->command('GET', $key);
    if (!is_string($value)) {
        output_error(404, 'request not found');
    }
    $record = json_decode($value, true);
    if (!is_array($record)) {
        output_error(500, 'invalid request');
    }
    $record['status'] = 'handled';
    $record['response'] = $result['response'];
    $redis->command('SET', $key, encode_record($record), 'EX', REQUEST_TTL);
    output_json(200, ['uuid' => $uuid, 'status' => 'handled']);
}

$redis_config = read_redis_config();
$redis = new RedisClient($redis_config);
$method = isset($_SERVER['REQUEST_METHOD']) ? $_SERVER['REQUEST_METHOD'] : '';
$path = isset($_SERVER['PATH_INFO']) ? $_SERVER['PATH_INFO'] : '';

if ($method === 'GET') {
    if ($path === '/v1/request/get') {
        get_request($redis);
    }
    else {
        output_error(404, 'not found');
    }
}
else if ($method === 'POST') {
    if ($path === '/v1/request/handle') {
        handle_request($redis);
    }
    else {
        submit_request($redis);
    }
}
else {
    output_error(405, 'method not allowed');
}
