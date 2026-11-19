<?php

# 需要授权：
# chown -R 'www-data:www-data' '/var/www/'

# 需要配置文件：
# /var/www/config/models.json

date_default_timezone_set('Asia/Shanghai');
mb_internal_encoding('UTF-8');
ini_set('default_charset', 'UTF-8');

// 配置文件格式：{ "models": [ { "id", "name", "vendor", "url", "apiKey", "desc" } ] }
const MODELS_FILE = '/var/www/config/models.json';
const USAGE_FILE  = '/var/www/config/models-usage.json';

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
    return $config;
}

function read_usage() {
    $h = @fopen(USAGE_FILE, 'r');
    if (!$h) {
        return ['usage' => []];
    }
    flock($h, LOCK_SH);
    $raw = stream_get_contents($h);
    flock($h, LOCK_UN);
    fclose($h);
    $usage = json_decode($raw, true);
    if (!is_array($usage) || !isset($usage['usage']) || !is_array($usage['usage'])) {
        return ['usage' => []];
    }
    return $usage;
}

function save_stats($updates) {
    $h = @fopen(USAGE_FILE, 'c+');
    if (!$h || !flock($h, LOCK_EX)) {
        if ($h) {
            fclose($h);
        }
        return;
    }
    rewind($h);
    $usage = json_decode(stream_get_contents($h), true);
    if (!is_array($usage) || !isset($usage['usage']) || !is_array($usage['usage'])) {
        $usage = ['usage' => []];
    }
    foreach ($updates as $i => $u) {
        if (!isset($usage['usage'][$i])) {
            $usage['usage'][$i] = ['requests' => 0, 'successes' => 0];
        }
        $usage['usage'][$i]['requests'] += $u['req'];
        $usage['usage'][$i]['successes'] += $u['succ'];
        if (isset($u['time'])) {
            $usage['usage'][$i]['lastSuccess'] = $u['time'];
        }
    }
    rewind($h);
    ftruncate($h, 0);
    fwrite($h, json_encode($usage, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));
    fflush($h);
    flock($h, LOCK_UN);
    fclose($h);
}

function list_models($cfg, $usage) {
    $ids = [];
    $data = [];
    $stats = [];
    $req_all = 0;
    $succ_all = 0;
    foreach ($cfg['models'] as $i => $m) {
        $u = isset($usage['usage'][$i]) ? $usage['usage'][$i] : [];
        $id = isset($m['id']) ? $m['id'] : '';
        $req = isset($u['requests']) ? (int) $u['requests'] : 0;
        $succ = isset($u['successes']) ? (int) $u['successes'] : 0;
        $req_all += $req;
        $succ_all += $succ;
        if ($id !== '' && !in_array($id, $ids, true)) {
            $ids[] = $id;
            $data[] = ['id' => $id, 'object' => 'model', 'created' => 0, 'owned_by' => 'MoonLord'];
        }
        $stats[] = [
            'id' => $id,
            'name' => isset($m['name']) ? $m['name'] : '',
            'requests' => $req,
            'successes' => $succ,
            'successRate' => $req ? round($succ / $req, 4) : null,
            'lastSuccess' => isset($u['lastSuccess']) ? $u['lastSuccess'] : null,
        ];
    }
    output_json(200, [
        'object' => 'list',
        'data' => $data,
        'stats' => $stats,
        'successRate' => $req_all ? round($succ_all / $req_all, 4) : null,
    ]);
}

function model_info($cfg, $usage, $id) {
    foreach ($cfg['models'] as $i => $m) {
        if (!isset($m['id']) || $m['id'] !== $id) {
            continue;
        }
        $u = isset($usage['usage'][$i]) ? $usage['usage'][$i] : [];
        $req = isset($u['requests']) ? (int) $u['requests'] : 0;
        $succ = isset($u['successes']) ? (int) $u['successes'] : 0;
        output_json(200, [
            'id' => $id,
            'object' => 'model',
            'created' => 0,
            'owned_by' => 'MoonLord',
            'name' => isset($m['name']) ? $m['name'] : '',
            'vendor' => isset($m['vendor']) ? $m['vendor'] : '',
            'desc' => isset($m['desc']) ? $m['desc'] : '',
            'requests' => $req,
            'successes' => $succ,
            'successRate' => $req ? round($succ / $req, 4) : null,
            'lastSuccess' => isset($u['lastSuccess']) ? $u['lastSuccess'] : null,
        ]);
    }
    output_error404, 'model not found', 'invalid_request_error');
}



# 按文件顺序列出同 id 的条目，以最近成功的那条为起点
function ordered_candidates($cfg, $id, $usage) {
    $pool = [];
    foreach ($cfg['models'] as $i => $m) {
        if (isset($m['id'], $m['url'], $m['apiKey']) && $m['id'] === $id) {
            $u = isset($usage['usage'][$i]) ? $usage['usage'][$i] : [];
            $pool[] = ['i' => $i, 'm' => $m, 'u' => $u];
        }
    }
    $n = count($pool);
    if ($n === 0) {
        return $pool;
    }
    $anchor = 0;
    $latest = 0;
    foreach ($pool as $k => $c) {
        $t = isset($c['u']['lastSuccess']) && is_string($c['u']['lastSuccess'])
            ? strtotime($c['u']['lastSuccess']) : false;
        if ($t !== false && $t > $latest) {
            $latest = $t;
            $anchor = $k;
        }
    }
    $out = [];
    for ($j = 0; $j < $n; $j++) {
        $out[] = $pool[($anchor + $j) % $n];
    }
    return $out;
}



# 返回 ok=false 表示需要换下一个模型
function try_proxy($model, $req) {
    $payload_req = $req;
    $payload_req['model'] = $model['id'];
    $payload = json_encode($payload_req, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);

    $ch = curl_init($model['url']);
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => $payload,
        CURLOPT_HTTPHEADER => [
            'Content-Type: application/json',
            'Authorization: Bearer ' . $model['apiKey'],
        ],
        CURLOPT_CONNECTTIMEOUT => 15,
        CURLOPT_TIMEOUT => 300,
        CURLOPT_FOLLOWLOCATION => true,
    ]);

    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    $body = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $type = curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
    curl_close($ch);

    if ($body === false || $code >= 400) {
        return ['ok' => false, 'code' => $code];
    }
    $decoded = json_decode($body, true);
    if (is_array($decoded) && isset($decoded['error'])) {
        return ['ok' => false, 'code' => $code];
    }
    return ['ok' => true, 'code' => $code, 'type' => $type, 'body' => $body];
}



$cfg = read_model_config();
$usage = read_usage();
$method = isset($_SERVER['REQUEST_METHOD']) ? $_SERVER['REQUEST_METHOD'] : 'GET';
$path = isset($_SERVER['PATH_INFO']) ? trim($_SERVER['PATH_INFO'], '/') : '';
if ($path === '' && isset($_SERVER['REQUEST_URI'], $_SERVER['SCRIPT_NAME'])) {
    $path = trim(explode('?', substr($_SERVER['REQUEST_URI'], strlen($_SERVER['SCRIPT_NAME'])))[0], '/');
}

if ($method === 'GET' && ($path === '' || $path === 'v1/models')) {
    list_models($cfg, $usage);
}
if ($method === 'GET' && strpos($path, 'v1/models/') === 0) {
    model_info($cfg, $usage, urldecode(substr($path, strlen('v1/models/'))));
}
if (!($method === 'POST' && ($path === 'v1/chat/completions' || $path === 'v1/completions'))) {
    output_error404, 'not found', 'invalid_request_error');
}

$raw = file_get_contents('php://input');
$req = json_decode($raw, true);
if (!is_array($req)) {
    output_error400, 'invalid request', 'invalid_request_error');
}
if (!function_exists('curl_init')) {
    output_error500, 'curl unavailable');
}

$cands = ordered_candidates($cfg, isset($req['model']) ? $req['model'] : '', $usage);
if (!$cands) {
    output_error404, 'model not found', 'invalid_request_error');
}

$updates = [];
$resp = null;
foreach ($cands as $c) {
    $i = $c['i'];
    if (!isset($updates[$i])) {
        $updates[$i] = ['req' => 0, 'succ' => 0];
    }
    $updates[$i]['req']++;
    $resp = try_proxy($c['m'], $req);
    if ($resp['ok']) {
        $updates[$i]['succ'] = 1;
        $updates[$i]['time'] = date('Y-m-d H:i:s');
        break;
    }
}
save_stats($updates);

if (!$resp['ok']) {
    output_error502, 'upstream unavailable');
}
http_response_code($resp['code']);
header('Content-Type: ' . ($resp['type'] ?: 'application/json; charset=utf-8'));
echo $resp['body'];
exit;
