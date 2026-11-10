<?php

date_default_timezone_set('Asia/Shanghai');
mb_internal_encoding('UTF-8');
ini_set('default_charset', 'UTF-8');

$path = parse_url(isset($_SERVER['REQUEST_URI']) ? $_SERVER['REQUEST_URI'] : '', PHP_URL_PATH);

if ($path === '/service/network-proxy.html') {
    header('Location: /service/network-proxy/index.html', true, 301);
    exit;
}

http_response_code(200);
header('Content-Type: text/plain; charset=utf-8');
echo 'Page Not Found';
