<?php

date_default_timezone_set('Asia/Shanghai');
mb_internal_encoding('UTF-8');
ini_set('default_charset', 'UTF-8');



$redirects = [
    '/service/network-proxy.html' => '/service/network-proxy/index.html',
];



$path = parse_url(isset($_SERVER['REQUEST_URI']) ? $_SERVER['REQUEST_URI'] : '', PHP_URL_PATH);

if ($path === '/404.php') {
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode((object) $redirects, JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT), "\n";
    exit;
}

if (isset($redirects[$path])) {
    header('Location: ' . $redirects[$path], true, 301);
    exit;
}



http_response_code(404);
header('Content-Type: text/plain; charset=utf-8');
echo '404 Not Found';
