<?php

date_default_timezone_set('Asia/Shanghai');
mb_internal_encoding('UTF-8');
ini_set('default_charset', 'UTF-8');



# 重定向设置
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



# 兼容 Clean URL / Pretty URL
if (substr($path, -1) !== '/' && substr($path, -5) !== '.html') {
    $base_dir = realpath(__DIR__);
    if ($base_dir !== false) {
        $base_dir = $base_dir . DIRECTORY_SEPARATOR;
        $try_html_file = realpath($base_dir . $path . '.html');
        if ($try_html_file !== false && strpos($try_html_file, $base_dir) === 0 && is_file($try_html_file)) {
            header('Content-Type: text/html; charset=utf-8');
            readfile($try_html_file);
            exit;
        }
    }
}



# 优先展示 404.html
http_response_code(404);
header('Content-Type: text/plain; charset=utf-8');

if (is_file('404.html')) {
    readfile('404.html');
    exit;
}

echo '404 Not Found: ' . $path;
