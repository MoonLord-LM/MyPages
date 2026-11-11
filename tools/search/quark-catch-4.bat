@echo off
chcp 65001 >nul
setlocal disabledelayedexpansion
set "script=%~0" & set "script_path=%~f0" & set "script_dir=%~dp0" & set "script_name=%~n0" & set "script_ext=%~x0" & set "script_name_ext=%~nx0"
setlocal enabledelayedexpansion
if /i "!cd!"=="!SystemRoot!\System32" ( cd /d "!script_dir!" )
powershell -NoProfile -Command "Write-Host '[ !script_name_ext! ]' -ForegroundColor Cyan" && echo.



powershell -NoProfile -Command "Write-Host '采集夸克网盘资源链接' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '采集数据源 https://1000n.com' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '从 sitemap 采集全站 html 页面，逐页提取夸克链接' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '通过调用夸克 API 接口，验证资源有效性' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '有效的完整信息保存到 quark.json 中，无效的链接保存到 quark-invalid.json 中' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '在 quark.json 或 quark-invalid.json 中已存在的链接，不做处理' -ForegroundColor Green"
echo.



set "json_file=!script_dir!data\quark.json"
set "invalid_json_file=!script_dir!data\quark-invalid.json"
set "sitemap_url=https://1000n.com/sitemap.xml"



REM 从自身文件末尾的 -----BEGIN POWERSHELL CODE----- / -----END POWERSHELL CODE----- 之间提取 PowerShell 代码
set "begin_marker=-----BEGIN POWERSHELL CODE-----"
set "end_marker=-----END POWERSHELL CODE-----"
powershell -NoProfile -Command ^
    "[System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8;" ^
    "$lines = Get-Content -Encoding UTF8 -LiteralPath $env:script_path;" ^
    "$begin = [array]::IndexOf($lines, $env:begin_marker) + 1;" ^
    "$end = [array]::IndexOf($lines, $env:end_marker);" ^
    "if ($begin -lt 1 -or $end -lt $begin) {" ^
    "    Write-Host '错误：未找到内嵌的 PowerShell 代码块' -ForegroundColor Red;" ^
    "    exit 1;" ^
    "};" ^
    "$code = $lines[$begin..($end - 1)] -join [System.Environment]::NewLine;" ^
    "Invoke-Expression $code"
if !errorlevel! neq 0 (
    echo 错误：处理失败
    echo.
    pause
    exit /b 1
)



echo.
pause
exit /b



-----BEGIN POWERSHELL CODE-----
[System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8;
$ProgressPreference = 'SilentlyContinue'

$jsonPath = $env:json_file
$api = 'https://drive-h.quark.cn/1/clouddrive/share/sharepage'
$headers = @{
    'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36';
    'Referer' = 'https://pan.quark.cn/'
}
$cnOffset = [System.TimeSpan]::FromHours(8)
$checkTime = [System.DateTimeOffset]::UtcNow.ToOffset($cnOffset).ToString('yyyy-MM-dd HH:mm')
$threadCount = 50
if ([System.Net.ServicePointManager]::DefaultConnectionLimit -lt $threadCount) {
    [System.Net.ServicePointManager]::DefaultConnectionLimit = $threadCount
}
$urlPattern = '^https://pan\.quark\.cn/s/([A-Za-z0-9]+)$'
$pageLog = 500

function Invoke-Pool([string]$WorkerScript, [System.Collections.Generic.Queue[string]]$Queue, [scriptblock]$OnDone) {
    $pool = [runspacefactory]::CreateRunspacePool(1, $threadCount)
    $pool.Open()
    $active = [System.Collections.Generic.List[object]]::new()
    $doneCount = 0
    try {
        while ($Queue.Count -gt 0 -or $active.Count -gt 0) {
            while ($active.Count -lt $threadCount -and $Queue.Count -gt 0) {
                $url = $Queue.Dequeue()
                $ps = [powershell]::Create()
                $ps.RunspacePool = $pool
                [void]$ps.AddScript($WorkerScript).AddArgument($url)
                $active.Add([pscustomobject]@{ Pipe = $ps; Handle = $ps.BeginInvoke(); Url = $url })
            }

            $done = $null
            foreach ($job in $active) {
                if ($job.Handle.IsCompleted) { $done = $job; break }
            }
            if ($null -eq $done) { Start-Sleep -Milliseconds 20; continue }
            [void]$active.Remove($done)

            $res = $null
            try {
                $output = $done.Pipe.EndInvoke($done.Handle)
                if ($output.Count -gt 0) { $res = $output[$output.Count - 1] }
            } catch {
                $res = $null
            } finally {
                $done.Pipe.Dispose()
            }
            $doneCount++
            & $OnDone $done.Url $res $doneCount
        }
    } finally {
        foreach ($job in $active) { $job.Pipe.Dispose() }
        $pool.Close()
        $pool.Dispose()
    }
}
$httpGet = @'
function Get-PageText([string]$url, [string]$accept) {
    $ok = $false; $text = ''; $message = ''
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36'
    for ($try = 1; $try -le 3; $try++) {
        $resp = $null; $reader = $null
        try {
            $req = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($url)
            $req.UserAgent = $ua
            $req.Referer = 'https://1000n.com/'
            $req.Accept = $accept
            $req.Headers.Add('Accept-Language', 'zh-CN,zh;q=0.9')
            $req.Timeout = 20000
            $req.ReadWriteTimeout = 20000
            $req.AllowAutoRedirect = $true
            $req.MaximumAutomaticRedirections = 10
            $req.AutomaticDecompression = [System.Net.DecompressionMethods]::Gzip -bor [System.Net.DecompressionMethods]::Deflate
            $resp = $req.GetResponse()
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8, $false, 8192)
            $text = $reader.ReadToEnd()
            $ok = $true
            break
        } catch {
            $message = $_.Exception.Message
            Start-Sleep -Milliseconds 500
        } finally {
            if ($reader) { try { $reader.Close() } catch {} }
            if ($resp) { try { $resp.Close() } catch {} }
        }
    }
    return [pscustomobject]@{ Ok = $ok; Text = $text; Message = $message }
}
'@

$sitemapWorker = @'
    param($url)
    [System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8;
    $ProgressPreference = 'SilentlyContinue'
'@ + $httpGet + @'
    $r = Get-PageText $url 'application/xml,text/xml,text/html,*/*;q=0.8'
    $ok = $r.Ok; $text = $r.Text; $message = $r.Message
    $locs = [System.Collections.Generic.List[string]]::new()
    if ($ok) {
        foreach ($m in [regex]::Matches($text, '<loc>([^<]+)</loc>')) {
            [void]$locs.Add($m.Groups[1].Value.Trim())
        }
    }
    return [pscustomobject]@{ Url = $url; Ok = $ok; Locs = $locs; Message = $message }
'@

$pageWorker = @'
    param($url)
    [System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8;
    $ProgressPreference = 'SilentlyContinue'
'@ + $httpGet + @'
    $siteBase = [System.Uri]::new('https://1000n.com/')
    $r = Get-PageText $url 'text/html,application/xhtml+xml,*/*;q=0.8'
    $ok = $r.Ok; $text = $r.Text; $message = $r.Message
    $quarks = [System.Collections.Generic.List[string]]::new()
    $subs = [System.Collections.Generic.List[string]]::new()
    if ($ok) {
        foreach ($m in [regex]::Matches($text, 'pan\.quark\.cn/s/([A-Za-z0-9]+)')) {
            [void]$quarks.Add('https://pan.quark.cn/s/' + $m.Groups[1].Value)
        }
        foreach ($m in [regex]::Matches($text, '/s/[^"\s<>]+?\.html')) {
            $abs = $null
            try { $abs = [System.Uri]::new($siteBase, $m.Value).AbsoluteUri } catch { continue }
            $abs = $abs -replace '[#?].*$', ''
            if ($abs -match '^https?://(www\.)?1000n\.com/s/') { [void]$subs.Add($abs) }
        }
    }
    return [pscustomobject]@{ Url = $url; Ok = $ok; Quarks = $quarks; Subs = $subs; Message = $message }
'@
$sitemapSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$sitemapQueue = [System.Collections.Generic.Queue[string]]::new()
$pageSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$pageQueue = [System.Collections.Generic.Queue[string]]::new()
$quarkSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$stat = @{ PageOk = 0; PageFail = 0; SitemapFail = 0 }
$sitemapTries = @{}
$pageTries = @{}
$maxTries = 3

$sitemapRoot = $env:sitemap_url
[void]$sitemapSeen.Add($sitemapRoot)
$sitemapQueue.Enqueue($sitemapRoot)

$onSitemap = {
    param($url, $res, $n)
    if ($null -eq $res -or -not $res.Ok) {
        $tries = 1
        if ($sitemapTries.ContainsKey($url)) { $tries = $sitemapTries[$url] + 1 }
        $sitemapTries[$url] = $tries
        if ($tries -lt $maxTries) {
            $sitemapQueue.Enqueue($url)
            return
        }
        $stat.SitemapFail++
        $msg = if ($res) { $res.Message } else { '处理失败' }
        Write-Host ('sitemap ' + $url + ' 采集失败 ' + $msg)
        return
    }
    foreach ($loc in $res.Locs) {
        if ($loc -match '\.xml$') {
            if ($sitemapSeen.Add($loc)) { $sitemapQueue.Enqueue($loc) }
            continue
        }
        if ($loc -notmatch '^https?://(www\.)?1000n\.com/') { continue }
        if ($loc -notmatch '\.html$' -and $loc -notmatch '/$') { continue }
        [void]$pageSeen.Add($loc)
    }
    if (($n % 20) -eq 0) {
        Write-Host ('已解析 sitemap ' + $n + '/' + $sitemapSeen.Count + ' 个，发现页面 ' + $pageSeen.Count + ' 个')
    }
}

Write-Host '开始解析 sitemap'
Invoke-Pool $sitemapWorker $sitemapQueue $onSitemap
Write-Host ('sitemap 解析完成：' + $sitemapSeen.Count + ' 个 sitemap，页面 ' + $pageSeen.Count + ' 个')
Write-Host ''

if ($pageSeen.Count -eq 0) {
    Write-Host '未采集到页面'
    exit 0
}

foreach ($u in $pageSeen) { $pageQueue.Enqueue($u) }

$onPage = {
    param($url, $res, $n)
    if ($null -ne $res -and $res.Ok) {
        $stat.PageOk++
        foreach ($q in $res.Quarks) { [void]$quarkSeen.Add($q) }
        foreach ($s in $res.Subs) {
            if ($pageSeen.Add($s)) { $pageQueue.Enqueue($s) }
        }
    } else {
        $tries = 1
        if ($pageTries.ContainsKey($url)) { $tries = $pageTries[$url] + 1 }
        $pageTries[$url] = $tries
        if ($tries -lt $maxTries) {
            $pageQueue.Enqueue($url)
        } else {
            $stat.PageFail++
        }
    }
    if (($n % $pageLog) -eq 0) {
        Write-Host ('已采集 ' + $n + '/' + ($pageQueue.Count + $n) + ' 页，发现夸克链接 ' + $quarkSeen.Count + ' 条')
    }
}

Write-Host ('开始采集页面，待采集 ' + $pageQueue.Count + ' 页')
Invoke-Pool $pageWorker $pageQueue $onPage
Write-Host ('页面采集完成：成功 ' + $stat.PageOk + ' 页，失败 ' + $stat.PageFail + ' 页，夸克链接 ' + $quarkSeen.Count + ' 条')
Write-Host ''

if ($quarkSeen.Count -eq 0) {
    Write-Host '未提取到夸克资源链接'
    exit 0
}

$emptyJson = "[]`n"
$emptyEncoding = [System.Text.UTF8Encoding]::new($false)

$records = @()
if ([System.IO.File]::Exists($jsonPath)) {
    try {
        $raw = [System.IO.File]::ReadAllText($jsonPath, [System.Text.Encoding]::UTF8)
        $records = ConvertFrom-Json -InputObject $raw
    } catch {
        Write-Host '错误：数据文件解析失败' -ForegroundColor Red
        exit 1
    }
} else {
    [System.IO.File]::WriteAllText($jsonPath, $emptyJson, $emptyEncoding)
}

$invalidRecords = [System.Collections.Generic.List[object]]::new()
if ([System.IO.File]::Exists($env:invalid_json_file)) {
    try {
        $invalidRaw = [System.IO.File]::ReadAllText($env:invalid_json_file, [System.Text.Encoding]::UTF8)
        $invalidParsed = ConvertFrom-Json -InputObject $invalidRaw
        foreach ($rec in $invalidParsed) {
            $url = [string]$rec.url
            if ($url) { [void]$invalidRecords.Add([pscustomobject][ordered]@{ url = $url }) }
        }
    } catch {
        Write-Host '错误：无效数据文件解析失败' -ForegroundColor Red
        exit 1
    }
} else {
    [System.IO.File]::WriteAllText($env:invalid_json_file, $emptyJson, $emptyEncoding)
}

$existing = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($rec in $records) {
    $url = [string]$rec.url
    if ($url) { [void]$existing.Add($url) }
}
foreach ($rec in $invalidRecords) {
    $url = [string]$rec.url
    if ($url) { [void]$existing.Add($url) }
}

$candidates = [System.Collections.Generic.List[string]]::new()
foreach ($url in $quarkSeen) {
    if ($url -notmatch $urlPattern) { continue }
    if ($existing.Contains($url)) { continue }
    $candidates.Add($url)
}

if ($candidates.Count -eq 0) {
    Write-Host ('采集完成：提取 ' + $quarkSeen.Count + ' 条，无新增链接') -ForegroundColor Green
    exit 0
}

Write-Host ('提取 ' + $quarkSeen.Count + ' 条，已有 ' + $existing.Count + ' 条，待验证 ' + $candidates.Count + ' 条')
$workerScript = @'
    param($item)
    [System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8;
    $ProgressPreference = 'SilentlyContinue'

    $api = 'https://drive-h.quark.cn/1/clouddrive/share/sharepage'
    $headers = @{
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36';
        'Referer' = 'https://pan.quark.cn/'
    }
    $cnOffset = [System.TimeSpan]::FromHours(8)
    $url = [string]$item.Url
    $title = [string]$item.Title
    $time = [string]$item.Time
    $valid = $false
    $author = $null
    $fileCount = $null
    $fileSize = $null
    $reason = ''

    if ($url -match '^https://pan\.quark\.cn/s/([A-Za-z0-9]+)') {
        $pwdId = $Matches[1]
        try {
            $body = '{"pwd_id":"' + $pwdId + '","passcode":""}'
            $tokenRaw = Invoke-WebRequest -Uri ($api + '/token?pr=ucd&fr=pc') -Method Post -Body $body `
                -ContentType 'application/json' -Headers $headers -TimeoutSec 20 -UseBasicParsing
            $token = ConvertFrom-Json -InputObject $tokenRaw.Content
            if ([int]$token.code -ne 0) {
                throw ('分享接口返回 code=' + $token.code + ' ' + $token.message)
            }
            $stoken = [System.Uri]::EscapeDataString([string]$token.data.stoken)
            $uri = $api + '/detail?pr=ucd&fr=pc&pwd_id=' + $pwdId + '&stoken=' + $stoken `
                + '&pdir_fid=0&force=0&_page=1&_size=50&_fetch_banner=1&_fetch_share=1'
            $detailRaw = Invoke-WebRequest -Uri $uri -Headers $headers -TimeoutSec 20 -UseBasicParsing
            $detail = ConvertFrom-Json -InputObject $detailRaw.Content
            if ([int]$detail.code -ne 0) {
                throw ('详情接口返回 code=' + $detail.code + ' ' + $detail.message)
            }
            $share = $detail.data.share
            $author = [string]$token.data.author.nick_name
            $fileCount = [int64]$share.file_only_num
            $fileSize = [int64]$share.size
            $title = [string]$share.title
            $fileTime = if ($share.first_file -and $share.first_file.updated_at) { $share.first_file.updated_at } else { $share.created_at }
            $time = [System.DateTimeOffset]::FromUnixTimeMilliseconds([int64]$fileTime).ToOffset($cnOffset).ToString('yyyy-MM-dd HH:mm')
            $expiredAt = [int64]$share.expired_at
            if ($expiredAt -gt 0 -and $expiredAt -lt [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) {
                $reason = '链接已过期'
            } elseif ([int64]$share.status -ne 1) {
                $reason = '链接已失效'
            } else {
                $valid = $true
            }
        } catch {
            $message = $_.Exception.Message
            if ($message -match '\(404\)') { $reason = '链接已失效' }
            else { $reason = '请求失败: ' + $message }
        }
    } else {
        $reason = '链接格式错误'
    }

    return [pscustomobject]@{
        Index     = $item.Index
        Url       = $url
        Title     = $title
        Time      = $time
        Author    = $author
        FileCount = $fileCount
        FileSize  = $fileSize
        Valid     = $valid
        Reason    = $reason
    }
'@
$added = [System.Collections.Generic.List[object]]::new()
$invalidAdded = [System.Collections.Generic.List[object]]::new()
$pass = 0
$fail = 0
$total = $candidates.Count

$pool = [runspacefactory]::CreateRunspacePool(1, $threadCount)
$pool.Open()
$queue = [System.Collections.Generic.Queue[string]]::new()
foreach ($u in $candidates) { $queue.Enqueue($u) }
$active = [System.Collections.Generic.List[object]]::new()
$index = 0

try {
    while ($queue.Count -gt 0 -or $active.Count -gt 0) {
        while ($active.Count -lt $threadCount -and $queue.Count -gt 0) {
            $index++
            $item = [pscustomobject]@{
                Index = $index
                Url   = $queue.Dequeue()
                Title = ''
                Time  = ''
            }
            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($workerScript).AddArgument($item)
            $active.Add([pscustomobject]@{ Pipe = $ps; Handle = $ps.BeginInvoke(); Item = $item })
        }

        $done = $null
        foreach ($job in $active) {
            if ($job.Handle.IsCompleted) { $done = $job; break }
        }
        if ($null -eq $done) { Start-Sleep -Milliseconds 20; continue }
        [void]$active.Remove($done)

        $result = $null
        try {
            $output = $done.Pipe.EndInvoke($done.Handle)
            if ($output.Count -gt 0) { $result = $output[$output.Count - 1] }
        } catch {
            $result = $null
        } finally {
            $done.Pipe.Dispose()
        }
        if ($null -eq $result) {
            $result = [pscustomobject]@{
                Index     = $done.Item.Index
                Url       = $done.Item.Url
                Title     = $done.Item.Title
                Time      = $done.Item.Time
                Author    = $null
                FileCount = $null
                FileSize  = $null
                Valid     = $false
                Reason    = '处理失败'
            }
        }

        $tag = '[{0}/{1}]' -f $result.Index, $total
        if ($result.Valid) {
            $added.Add([pscustomobject][ordered]@{
                url         = $result.Url
                check_valid = $true
                check_time  = $checkTime
                title       = $result.Title
                time        = $result.Time
                author      = $result.Author
                file_count  = $result.FileCount
                file_size   = $result.FileSize
            })
            Write-Host ($tag + ' 通过  ' + $result.Title) -ForegroundColor Green
            $pass++
        } else {
            $invalidAdded.Add([pscustomobject][ordered]@{
                url = $result.Url
            })
            Write-Host ($tag + ' 失败  ' + $result.Title + '  ' + $result.Reason) -ForegroundColor Red
            $fail++
        }
    }
} finally {
    foreach ($job in $active) { $job.Pipe.Dispose() }
    $pool.Close()
    $pool.Dispose()
}

Write-Host ('验证完成：待验证 ' + $total + ' 条，有效 ' + $pass + ' 条，无效 ' + $fail + ' 条')

if ($added.Count -eq 0 -and $invalidAdded.Count -eq 0) {
    Write-Host '无新增记录，数据文件未修改' -ForegroundColor Green
    exit 0
}

$sortByTime = @(
    @{ Expression = { [string]$_.time } },
    @{ Expression = { [string]$_.url } }
)
$sortByUrl = @(
    @{ Expression = { [string]$_.url } }
)

function Save-Quark-Data([string]$FilePath, [object]$BaseRecords, [object]$NewRecords, [object]$SortRule) {
    $enc = [System.Text.UTF8Encoding]::new($false)
    $all = [System.Collections.Generic.List[object]]::new()
    foreach ($rec in $BaseRecords) { [void]$all.Add($rec) }
    foreach ($rec in $NewRecords) { [void]$all.Add($rec) }
    $sorted = @($all | Sort-Object -Property $SortRule)
    $text = ConvertTo-Json -InputObject $sorted -Depth 5
    $verified = ConvertFrom-Json -InputObject $text
    if (@($verified).Count -ne $all.Count) { throw 'count' }
    [System.IO.File]::WriteAllText($FilePath, $text + "`n", $enc)
    return @($verified).Count
}

if ($added.Count -gt 0) {
    try {
        $validTotal = Save-Quark-Data $jsonPath $records $added $sortByTime
    } catch {
        Write-Host '错误：写入 quark.json 失败' -ForegroundColor Red
        exit 1
    }
    Write-Host ('已写回: ' + $jsonPath + '（新增 ' + $added.Count + ' 条，共 ' + $validTotal + ' 条）')
}

if ($invalidAdded.Count -gt 0) {
    try {
        $invalidTotal = Save-Quark-Data $env:invalid_json_file $invalidRecords $invalidAdded $sortByUrl
    } catch {
        Write-Host '错误：写入 quark-invalid.json 失败' -ForegroundColor Red
        exit 1
    }
    Write-Host ('已写回: ' + $env:invalid_json_file + '（新增 ' + $invalidAdded.Count + ' 条，共 ' + $invalidTotal + ' 条）')
}

Write-Host ('采集完成：新增有效 ' + $added.Count + ' 条，新增无效 ' + $invalidAdded.Count + ' 条') -ForegroundColor Green
exit 0
-----END POWERSHELL CODE-----
