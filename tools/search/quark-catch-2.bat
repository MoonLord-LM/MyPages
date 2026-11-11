@echo off
chcp 65001 >nul
setlocal disabledelayedexpansion
set "script=%~0" & set "script_path=%~f0" & set "script_dir=%~dp0" & set "script_name=%~n0" & set "script_ext=%~x0" & set "script_name_ext=%~nx0"
setlocal enabledelayedexpansion
if /i "!cd!"=="!SystemRoot!\System32" ( cd /d "!script_dir!" )
powershell -NoProfile -Command "Write-Host '[ !script_name_ext! ]' -ForegroundColor Cyan" && echo.



powershell -NoProfile -Command "Write-Host '采集夸克网盘资源链接' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '采集数据源 https://t.me/s/kduanju https://t.me/s/yoyokuakeduanju https://t.me/s/Quark_Movies' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '通过调用夸克 API 接口，验证资源有效性' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '有效的完整信息保存到 quark.json 中，无效的链接保存到 quark-invalid.json 中' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '在 quark.json 或 quark-invalid.json 中已存在的链接，不做处理' -ForegroundColor Green"
echo.



set "json_file=!script_dir!data\quark.json"
set "invalid_json_file=!script_dir!data\quark-invalid.json"



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
[System.Net.ServicePointManager]::DefaultConnectionLimit = $threadCount
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
$urlPattern = '^https://pan\.quark\.cn/s/([A-Za-z0-9]+)$'
$extractPattern = 'https://pan\.quark\.cn/s/[A-Za-z0-9]+'

$tgChannels = @('kduanju', 'yoyokuakeduanju', 'Quark_Movies')
$tgMaxPages = 100

$rawLinks = [System.Collections.Generic.List[string]]::new()
foreach ($ch in $tgChannels) {
    Write-Host ('开始采集频道 ' + $ch)
    $before = $null
    for ($page = 0; $page -lt $tgMaxPages; $page++) {
        $uri = 'https://t.me/s/' + $ch
        if ($before) { $uri += '?before=' + $before }
        try {
            $resp = Invoke-WebRequest -Uri $uri -Headers $headers -TimeoutSec 30 -UseBasicParsing
            $html = [string]$resp.Content
        } catch {
            Write-Host ('频道 ' + $ch + ' 页面获取失败: ' + $_.Exception.Message) -ForegroundColor Red
            break
        }
        $m = [regex]::Matches($html, $extractPattern)
        foreach ($x in $m) { [void]$rawLinks.Add($x.Value) }
        Write-Host ('频道 ' + $ch + ' 第 ' + ($page + 1) + ' 页，本页 ' + $m.Count + ' 条，累计 ' + $rawLinks.Count + ' 条')
        $ids = [regex]::Matches($html, 'data-post="' + [regex]::Escape($ch) + '/(\d+)"')
        if ($ids.Count -eq 0) { break }
        $minId = [int]::MaxValue
        foreach ($idm in $ids) {
            $v = [int]$idm.Groups[1].Value
            if ($v -lt $minId) { $minId = $v }
        }
        if ($minId -eq $before) { break }
        $before = $minId
    }
    Write-Host ('频道 ' + $ch + ' 采集完成，累计 ' + $rawLinks.Count + ' 条')
    Write-Host ''
}
if ($rawLinks.Count -eq 0) {
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

$candidates = [System.Collections.Generic.List[object]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($rawUrl in $rawLinks) {
    $url = ([string]$rawUrl).Trim()
    if ($url -notmatch $urlPattern) { continue }
    if ($existing.Contains($url)) { continue }
    if (-not $seen.Add($url)) { continue }
    $candidates.Add([pscustomobject]@{
        Index = $candidates.Count + 1
        Url   = $url
        Title = ''
        Time  = ''
    })
}

if ($candidates.Count -eq 0) {
    Write-Host ('采集完成：解析 ' + $rawLinks.Count + ' 条，无新增链接') -ForegroundColor Green
    exit 0
}

Write-Host ('采集 ' + $rawLinks.Count + ' 条，已有 ' + $existing.Count + ' 条，待验证 ' + $candidates.Count + ' 条')

$workerScript = @'
    param($item)
    [System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8;
    $ProgressPreference = 'SilentlyContinue'
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
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

$pool = [runspacefactory]::CreateRunspacePool(1, $threadCount)
$pool.Open()
$queue = [System.Collections.Generic.Queue[object]]::new()
foreach ($item in $candidates) { $queue.Enqueue($item) }
$active = [System.Collections.Generic.List[object]]::new()

try {
    while ($queue.Count -gt 0 -or $active.Count -gt 0) {
        while ($active.Count -lt $threadCount -and $queue.Count -gt 0) {
            $item = $queue.Dequeue()
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

        $tag = '[{0}/{1}]' -f $result.Index, $candidates.Count
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

Write-Host ('验证完成：待验证 ' + $candidates.Count + ' 条，有效 ' + $pass + ' 条，无效 ' + $fail + ' 条')

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
