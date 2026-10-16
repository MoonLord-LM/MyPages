<?php
const LOG_FILE = '/var/log/nginx/deploy.log';

if (!file_exists(LOG_FILE)) {
    http_response_code(404);
    header('Content-Type: text/plain; charset=utf-8');
    echo 'log not found: ' . LOG_FILE;
    exit;
}

header('Content-Type: text/plain; charset=utf-8');
readfile(LOG_FILE);
