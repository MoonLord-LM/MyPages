<?php
const REPO_URL    = 'https://github.com/MoonLord-LM/MyPages.git';
const REPO_BRANCH = 'master';
const RUN_LOCK    = '/tmp/deploy/MoonLord-LM/MyPages.lock';
const REPO_DIR    = '/tmp/deploy/MoonLord-LM/MyPages';
const LOG_FILE    = '/var/log/deploy.log';
const RELEASES    = '/var/www/releases';
const TARGET      = '/var/www/html';

function log_msg($m) {
    $l = date('[Y-m-d H:i:s] ') . $m . "\n";
    file_put_contents(LOG_FILE, $l, FILE_APPEND);
}

function respond($s, $m) {
    log_msg($m);
    http_response_code($s);
    header('Content-Type: text/plain; charset=utf-8');
    echo $m;
    exit;
}

function run($cmd) {
    $cmd = 'timeout 300 ' . $cmd . ' 2>&1';
    $d = [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']];
    $p = proc_open($cmd, $d, $x);
    fclose($x[0]);
    $out = stream_get_contents($x[1]);
    $err = stream_get_contents($x[2]);
    fclose($x[1]);
    fclose($x[2]);
    $code = proc_close($p);
    $msg = trim($err . $out);
    if ($code !== 0) {
        log_msg("cmd failed ($code): $cmd\n$msg");
        respond(500, 'deploy failed');
    }
    return ['code' => $code, 'msg' => $msg];
}

$lockDir = dirname(RUN_LOCK);
if (!is_dir($lockDir) && !mkdir($lockDir, 0755, true)) {
    respond(500, 'cannot create lock dir');
}

$lock = fopen(RUN_LOCK, 'c');
if (!$lock || !flock($lock, LOCK_EX | LOCK_NB)) {
    respond(200, 'locked, skip');
}

log_msg('deploy start');

if (!is_dir(REPO_DIR) && !mkdir(REPO_DIR, 0755, true)) {
    respond(500, 'cannot create repo dir');
}

if (!is_dir(REPO_DIR . '/.git')) {
    run(sprintf('git clone --depth 1 --branch %s %s %s',
        escapeshellarg(REPO_BRANCH), escapeshellarg(REPO_URL), escapeshellarg(REPO_DIR)));
} else {
    run(sprintf('cd %s && git fetch --depth 1 origin %s && git reset --hard origin/%s && git clean -fdx',
        escapeshellarg(REPO_DIR), escapeshellarg(REPO_BRANCH), escapeshellarg(REPO_BRANCH)));
}

$src = REPO_DIR . '/dist';
if (!is_dir($src)) {
    respond(500, 'no dist');
}

if (!is_dir(RELEASES) && !mkdir(RELEASES, 0755, true)) {
    respond(500, 'cannot create releases dir');
}

$newVersionDir = RELEASES . '/' . date('YmdHis');
if (!is_dir($newVersionDir) && !mkdir($newVersionDir, 0755, true)) {
    respond(500, 'cannot create release new version dir');
}

run(sprintf('rsync -a %s/ %s/', escapeshellarg($src . '/'), escapeshellarg($newVersionDir . '/')));

$oldVersionDir = null;
if (is_link(TARGET)) {
    $oldVersionDir = readlink(TARGET);
}

if (file_exists(TARGET) && !is_link(TARGET)) {
    run('rm -rf ' . escapeshellarg(TARGET));
}

run(sprintf('ln -sfn %s %s && mv -T %s %s',
    escapeshellarg($newVersionDir), escapeshellarg(RELEASES . '/.current'),
    escapeshellarg(RELEASES . '/.current'), escapeshellarg(TARGET)));

if ($oldVersionDir && $oldVersionDir !== $newVersionDir && file_exists($oldVersionDir)) {
    run('rm -rf ' . escapeshellarg($oldVersionDir));
}

log_msg("deploy done -> $newVersionDir");
respond(200, 'deploy ok');
