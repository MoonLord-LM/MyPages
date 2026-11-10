@echo off
chcp 65001 >nul
setlocal disabledelayedexpansion
set "script=%~0" & set "script_path=%~f0" & set "script_dir=%~dp0" & set "script_name=%~n0" & set "script_ext=%~x0" & set "script_name_ext=%~nx0"
setlocal enabledelayedexpansion
if /i "!cd!"=="!SystemRoot!\System32" ( cd /d "!script_dir!" )
powershell -NoProfile -Command "Write-Host '[ !script_name_ext! ]' -ForegroundColor Cyan" && echo.



powershell -NoProfile -Command "Write-Host '检查 quark.json 中的夸克网盘资源链接，记录链接有效状态' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '通过调用夸克 API 接口，验证资源有效性' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '已失效的，以及 3 天内已检查过是有效的，不做处理' -ForegroundColor Green"
echo.



REM 检查 7-Zip 组件（可选）
if exist "!script_dir!7za.exe" (
    set "seven_zip=!script_dir!7za.exe"
) else if exist "!cd!\7za.exe" (
    set "seven_zip=!cd!\7za.exe"
) else if exist "!script_dir!..\7za.exe" (
    set "seven_zip=!script_dir!..\7za.exe"
) else if exist "..\7za.exe" (
    set "seven_zip=..\7za.exe"
) else if exist "!ProgramFiles!\7-Zip\7z.exe" (
    set "seven_zip=!ProgramFiles!\7-Zip\7z.exe"
) else if exist "!ProgramFiles(x86)!\7-Zip\7z.exe" (
    set "seven_zip=!ProgramFiles(x86)!\7-Zip\7z.exe"
) else (
    set "seven_zip=7z"
)
"!seven_zip!" i >nul 2>&1
if !errorlevel! neq 0 (
    set "seven_zip="
)



set "json_file=!script_dir!data\quark.json"
set "out_gzip=!script_dir!..\..\pages\service\internet-search\assets\pan-quark-cn.gz"
if not exist "!json_file!" (
    echo 错误：未找到数据文件 "!json_file!"
    echo.
    pause
    exit /b 1
)



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
$outGzip = [System.IO.Path]::GetFullPath($env:out_gzip)
$api = 'https://drive-h.quark.cn/1/clouddrive/share/sharepage'
$headers = @{
    'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36';
    'Referer' = 'https://pan.quark.cn/'
}
$cnOffset = [System.TimeSpan]::FromHours(8)
$checkTime = [System.DateTimeOffset]::UtcNow.ToOffset($cnOffset).ToString('yyyy-MM-dd HH:mm')
$nowCn = [System.DateTimeOffset]::UtcNow.ToOffset($cnOffset).DateTime
$skipHours = 72
$threadCount = 50
[System.Net.ServicePointManager]::DefaultConnectionLimit = $threadCount
$utf8 = [System.Text.UTF8Encoding]::new($false)

try {
    $raw = [System.IO.File]::ReadAllText($jsonPath, [System.Text.Encoding]::UTF8)
    $records = ConvertFrom-Json -InputObject $raw
} catch {
    Write-Host ('错误：数据文件解析失败 - ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

if ($records.Count -eq 0) {
    Write-Host '数据文件为空'
    exit 0
}

$workerScript = @'
    param($item)
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
            $time = [System.DateTimeOffset]::FromUnixTimeMilliseconds([int64]$share.created_at).ToOffset($cnOffset).ToString('yyyy-MM-dd HH:mm')
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

$results = @($records)
$sortByTime = @(
    @{ Expression = { [string]$_.time } },
    @{ Expression = { [string]$_.url } }
)
$pass = 0
$fail = 0
$checked = 0
$skipped = 0
$index = 0

$pending = [System.Collections.Generic.List[object]]::new()
foreach ($rec in $records) {
    $index++

    $validProp = $rec.PSObject.Properties['check_valid']
    if ($null -ne $validProp -and $validProp.Value -eq $false) {
        $skipped++
        continue
    }
    if ($null -ne $validProp -and $validProp.Value -eq $true) {
        $timeProp = $rec.PSObject.Properties['check_time']
        if ($null -ne $timeProp) {
            $lastCheck = [datetime]::MinValue
            if ([datetime]::TryParseExact([string]$timeProp.Value, 'yyyy-MM-dd HH:mm',
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::None, [ref]$lastCheck)) {
                if ([System.Math]::Abs(($nowCn - $lastCheck).TotalHours) -lt $skipHours) {
                    $skipped++
                    continue
                }
            }
        }
    }

    $pending.Add([pscustomobject]@{
        Index = $index
        Url   = [string]$rec.url
        Title = [string]$rec.title
        Time  = [string]$rec.time
    })
}

$pool = [runspacefactory]::CreateRunspacePool(1, $threadCount)
$pool.Open()
$queue = [System.Collections.Generic.Queue[object]]::new()
foreach ($item in $pending) { $queue.Enqueue($item) }
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

        $results[$result.Index - 1] = [pscustomobject][ordered]@{
            url         = $result.Url
            check_valid = $result.Valid
            check_time  = $checkTime
            title       = $result.Title
            time        = $result.Time
            author      = $result.Author
            file_count  = $result.FileCount
            file_size   = $result.FileSize
        }

        $tag = '[{0}/{1}]' -f $result.Index, $records.Count
        if ($result.Valid) {
            Write-Host ($tag + ' 通过  ' + $result.Title) -ForegroundColor Green
            $pass++
        } else {
            Write-Host ($tag + ' 失败  ' + $result.Title + '  ' + $result.Reason) -ForegroundColor Red
            $fail++
        }

        $checked++
        if ($checked % 5000 -eq 0) {
            try {
                $sorted = @($results | Sort-Object -Property $sortByTime)
                $checkedText = ConvertTo-Json -InputObject $sorted -Depth 5
                [System.IO.File]::WriteAllText($jsonPath, $checkedText + "`n", $utf8)
                Write-Host ('已保存（已检查 ' + $checked + ' 条，' + $result.Index + '/' + $records.Count + '）')
            } catch {
                Write-Host ('错误：保存进度失败 - ' + $_.Exception.Message) -ForegroundColor Red
                exit 1
            }
        }
    }
} finally {
    foreach ($job in $active) { $job.Pipe.Dispose() }
    $pool.Close()
    $pool.Dispose()
}

try {
    $sorted = @($results | Sort-Object -Property $sortByTime)
    $checkedText = ConvertTo-Json -InputObject $sorted -Depth 5
    [System.IO.File]::WriteAllText($jsonPath, $checkedText + "`n", $utf8)

    $siteList = @($sorted | Where-Object { $_.check_valid } | ForEach-Object {
        [pscustomobject][ordered]@{
            url        = $_.url
            title      = $_.title
            time       = $_.time
            file_count = $_.file_count
            file_size  = $_.file_size
        }
    })
    $siteText = if ($siteList.Count -eq 0) { '[]' } else { ConvertTo-Json -InputObject $siteList -Depth 5 -Compress }
    $siteBytes = $utf8.GetBytes($siteText)

    if ($env:seven_zip) {
        Write-Host '压缩方式：使用 7-Zip 压缩 gzip 格式' -ForegroundColor Green
        if (Test-Path -LiteralPath $outGzip) { Remove-Item -Force -LiteralPath $outGzip }
        $argLine = 'a -tgzip -mx=9 -mmt=on -mtc=off -mtm=off -mta=off -y "' + $outGzip + '" -sipan-quark-cn.json'
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $env:seven_zip
        $startInfo.Arguments = $argLine
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $process.StandardInput.BaseStream.Write($siteBytes, 0, $siteBytes.Length)
        $process.StandardInput.BaseStream.Flush()
        $process.StandardInput.BaseStream.Close()
        [void]$process.StandardOutput.ReadToEnd()
        [void]$process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw '7-Zip 压缩失败' }
    } else {
        Write-Host '压缩方式：使用 PowerShell 内置的 GZipStream 压缩' -ForegroundColor Green
        Add-Type -AssemblyName System.IO.Compression
        $memStream = New-Object System.IO.MemoryStream
        $mode = [System.IO.Compression.CompressionMode]::Compress
        $gzipStream = New-Object System.IO.Compression.GzipStream($memStream, $mode)
        $gzipStream.Write($siteBytes, 0, $siteBytes.Length)
        $gzipStream.Close()
        $bytes = $memStream.ToArray()
        $memStream.Close()
        [System.IO.File]::WriteAllBytes($outGzip, $bytes)
    }
    if (-not (Test-Path -LiteralPath $outGzip)) { throw '压缩文件生成失败' }
} catch {
    Write-Host ('错误：写入结果失败 - ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

Write-Host ('检查完成：共 ' + $records.Count + ' 条，跳过 ' + $skipped + ' 条，检查 ' + $checked + ' 条，检查有效 ' + $pass + ' 条，检查无效 ' + $fail + ' 条')
Write-Host ('数据统计：共 ' + $records.Count + ' 条，有效数据共 ' + $siteList.Count + ' 条，无效数据共 ' + ($records.Count - $siteList.Count) + ' 条')
Write-Host ('已写回检查结果: ' + $jsonPath)
Write-Host ('已生成站点数据: ' + $outGzip)
-----END POWERSHELL CODE-----
