@echo off
chcp 65001 >nul
setlocal disabledelayedexpansion
set "script=%~0" & set "script_path=%~f0" & set "script_dir=%~dp0" & set "script_name=%~n0" & set "script_ext=%~x0" & set "script_name_ext=%~nx0"
set "param1=%~1" & set "param1_path=%~f1" & set "param1_dir=%~dp1" & set "param1_name=%~n1" & set "param1_ext=%~x1" & set "param1_name_ext=%~nx1"
set "param2=%~2" & set "param2_path=%~f2" & set "param2_dir=%~dp2" & set "param2_name=%~n2" & set "param2_ext=%~x2" & set "param2_name_ext=%~nx2"
setlocal enabledelayedexpansion
if /i "!cd!"=="!SystemRoot!\System32" ( cd /d "!script_dir!" )
powershell -NoProfile -Command "Write-Host '[ !script_name_ext! ]' -ForegroundColor Cyan" && echo.



powershell -NoProfile -Command "Write-Host '采集 GitHub 用户资料，生成 html 的展示页面' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '默认采集用户 MoonLord-LM，默认输出文件 index.html' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '可以传 2 个参数：指定采集用户名，指定输出文件名' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '建议设置 GITHUB_TOKEN 环境变量，以提高 GitHub API 请求限额' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '脚本另外会下载每个仓库的 README，保存为 profile/repos/<项目名>.md' -ForegroundColor Green"
echo.



:input_user
    set "user_name=!param1!"
    if "!user_name!"=="" (
        echo 请输入要采集的 GitHub 用户名，例如 MoonLord-LM
        set /p "user_name="
        if !errorlevel! neq 0 (
            echo 无输入，使用默认值 MoonLord-LM
            set "user_name=MoonLord-LM"
            echo.
        )
    )
    set "user_name=!user_name:"=!"
    if "!user_name!"=="" (
        echo 输入为空，使用默认值 MoonLord-LM
        set "user_name=MoonLord-LM"
    )

:input_out
    set "out_name=!param2!"
    if "!out_name!"=="" (
        echo 请输入输出文件名，例如 index.html
        set /p "out_name="
        if !errorlevel! neq 0 (
            echo 无输入，使用默认值 index.html
            set "out_name=index.html"
            echo.
        )
    )
    set "out_name=!out_name:"=!"
    if "!out_name!"=="" (
        echo 输入为空，使用默认值 index.html
        set "out_name=index.html"
    )



set "profile_dir=!script_dir!profile\"
if not exist "!profile_dir!" ( mkdir "!profile_dir!" )
set "out_file=!profile_dir!!out_name!"



echo 采集 GitHub 用户: !user_name! & REM
echo 输出文件路径: !out_file! & REM
echo.

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
    echo 错误：生成 html 文件失败，请检查报错信息
    echo.
    pause
    exit /b 1
)
echo 生成 html 文件成功



echo.
pause
exit /b



-----BEGIN POWERSHELL CODE-----
[System.Console]::OutputEncoding=[System.Text.Encoding]::UTF8;

$ProgressPreference = 'SilentlyContinue'

$userName = $env:user_name
$outFile = $env:out_file
$scriptDir = $env:script_dir

# 尝试从环境变量读取 Token 提升 API 限额
$token = $env:GITHUB_TOKEN
$ua = @{ 'User-Agent' = 'github-bat-generator' }
if ($token) { $ua['Authorization'] = "Bearer $token" }

function Get-All-Pages {
    param([string]$Uri)
    $items = @()
    $next = $Uri
    $pageCount = 0
    while ($next -and $pageCount -lt 20) {
        try {
            $resp = Invoke-WebRequest -Uri $next -Headers $ua -UseBasicParsing
            $data = $resp.Content | ConvertFrom-Json
            foreach ($d in $data) { $items += $d }
            $next = $null
            $link = $resp.Headers['Link']
            if ($link) {
                foreach ($part in ($link -split ',')) {
                    if ($part -match '<([^>]+)>\s*;\s*rel="next"') { $next = $Matches[1] }
                }
            }
        } catch {
            $msg = $_.Exception.Message
            Write-Host "错误：请求失败：$msg" -ForegroundColor Red
            if ($msg -match 'rate limit') {
                Write-Host '错误：GitHub API 速率限制已触发，请设置 GITHUB_TOKEN 环境变量后重试' -ForegroundColor Red
            }
            exit 1
        }
        $pageCount++
    }
    return $items
}

function Html-Encode($Text) {
    if ($null -eq $Text) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

# 从 languages-color.json 读取语言配色
$langFile = Join-Path $scriptDir 'languages-color.json'
if (-not (Test-Path -LiteralPath $langFile)) {
    Write-Host "错误：未找到语言配色文件：$langFile" -ForegroundColor Red
    exit 1
}
try {
    $langColors = @{}
    $json = [System.IO.File]::ReadAllText($langFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($p in $json.PSObject.Properties) {
        $langColors[$p.Name] = [string]$p.Value
    }
} catch {
    Write-Host "错误：语言配色文件解析失败：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

function Get-Lang-Color($Language) {
    if ($langColors.ContainsKey($Language)) { return $langColors[$Language] }
    return '#8b949e'
}

function Get-Luminance($HexColor) {
    $HexColor = $HexColor.TrimStart('#')
    if ($HexColor.Length -eq 3) { $HexColor = "$($HexColor[0])$($HexColor[0])$($HexColor[1])$($HexColor[1])$($HexColor[2])$($HexColor[2])" }
    $r = [System.Convert]::ToInt32($HexColor.Substring(0,2),16)/255
    $g = [System.Convert]::ToInt32($HexColor.Substring(2,2),16)/255
    $b = [System.Convert]::ToInt32($HexColor.Substring(4,2),16)/255
    return 0.2126*$r + 0.7152*$g + 0.0722*$b
}
function Get-Contrast-Text($HexColor) {
    if ((Get-Luminance $HexColor) -gt 0.6) { return '#1f2328' } else { return '#ffffff' }
}

# 字节数格式化为 B / KB / MB / GB
function Format-Bytes($Bytes) {
    if ($Bytes -ge 1GB) { return "$(($Bytes/1GB).ToString('0.0')) GB" }
    if ($Bytes -ge 1MB) { return "$(($Bytes/1MB).ToString('0.0')) MB" }
    if ($Bytes -ge 1KB) { return "$(($Bytes/1KB).ToString('0.0')) KB" }
    return "$($Bytes.ToString('0.0')) B"
}

Write-Host "开始获取用户资料: $userName"
try {
    $profile = Invoke-RestMethod -Uri "https://api.github.com/users/$userName" -Headers $ua -UseBasicParsing
} catch {
    Write-Host "错误：获取用户资料失败：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 采集头像到本地 assets/avatar.png
$baseDir = Split-Path $outFile
$avatarDir = Join-Path $baseDir 'assets'
if (-not (Test-Path -LiteralPath $avatarDir)) { New-Item -ItemType Directory -Path $avatarDir | Out-Null }
$avatarPath = Join-Path $avatarDir 'avatar.png'
$avatarSrc = 'assets/avatar.png'
try {
    Invoke-WebRequest -Uri $profile.avatar_url -Headers $ua -OutFile $avatarPath -UseBasicParsing
    Write-Host "已下载头像: $avatarPath"
} catch {
    Write-Host "错误：头像下载失败：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host '开始获取仓库列表'
$repos = Get-All-Pages -Uri "https://api.github.com/users/$userName/repos?per_page=100&sort=updated"
Write-Host "共获取 $($repos.Count) 个仓库"

# 语言统计：逐个仓库拉取 languages 接口，按字节数合并汇总每种语言
$langBytes = @{}
$totalSize = 0
foreach ($r in $repos) {
    $langUrl = "https://api.github.com/repos/$($r.owner.login)/$($r.name)/languages"
    try {
        $langs = Invoke-RestMethod -Uri $langUrl -Headers $ua -UseBasicParsing
    } catch {
        Write-Host "错误：获取仓库语言统计失败 ($($r.name))：$($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    if ($langs) {
        foreach ($k in $langs.PSObject.Properties.Name) {
            $b = [int]$langs.$k
            if ($b -le 0) { continue }
            if (-not $langBytes.ContainsKey($k)) { $langBytes[$k] = 0 }
            $langBytes[$k] += $b
            $totalSize += $b
        }
    }
}

# 采集每个仓库的 README.md 到 profile/repos/<项目名>.md
$readmeDir = Join-Path $baseDir 'repos'
if (-not (Test-Path -LiteralPath $readmeDir)) { New-Item -ItemType Directory -Path $readmeDir | Out-Null }
Write-Host '开始采集各仓库 README'
function Sanitize-File-Name($Name) {
    if ($null -eq $Name) { return '' }
    return ($Name -replace '[\\/:*?"<>|]', '_').Trim()
}

# 统一按北京时间（UTC+8，中国不实行夏令时）生成时间，避免跟随运行机时区
try {
    $utc8Zone = [System.TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')
} catch {
    $utc8Zone = [System.TimeZoneInfo]::FindSystemTimeZoneById('Asia/Shanghai')
}

# 获取仓库最后一次提交的修改时间（转换为北京时间）
function Get-Last-Commit-Date($Owner, $RepoName) {
    try {
        $commitMeta = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$RepoName/commits?per_page=1" -Headers $ua -UseBasicParsing
        if ($commitMeta -and $commitMeta.Count -gt 0) {
            $dateStr = $commitMeta[0].commit.committer.date
            if (-not $dateStr) { $dateStr = $commitMeta[0].commit.author.date }
            if ($dateStr) {
                $dt = [DateTime]::Parse($dateStr).ToUniversalTime()
                return [System.TimeZoneInfo]::ConvertTimeFromUtc($dt, $utc8Zone).ToString('yyyy-MM-dd HH:mm:ss') + ' +08:00'
            }
        }
    } catch { }
    return ''
}

# 为每个 md 文件生成头部信息：第一行最后提交时间，第二行项目链接（每行末尾 2 空格，符合 md 换行），随后空行 + 分隔线 + 空行
function Build-Repo-Header($Repo, $LastCommitDate) {
    $owner = $Repo.owner.login
    $repoName = $Repo.name
    $repoUrl = "https://github.com/$owner/$repoName"
    $lines = @()
    $lines += ($LastCommitDate + '  ')
    $lines += ($repoUrl + '  ')
    $lines += ''
    $lines += '---'
    $lines += ''
    return $lines -join [System.Environment]::NewLine
}

$readmeCount = 0
$emptyCount = 0
foreach ($r in $repos) {
    $owner = $r.owner.login
    $repo = $r.name
    $safeName = Sanitize-File-Name $repo
    $mdPath = Join-Path $readmeDir "$safeName.md"
    $lastCommitDate = Get-Last-Commit-Date $owner $repo
    try {
        $readmeMeta = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/readme" -Headers $ua -UseBasicParsing
    } catch {
        # 没有 README（含 404）：保存含头部信息的占位文件，保证每个仓库都有对应的 md
        if ($_.Exception.Message -match 'rate limit') {
            Write-Host '错误：GitHub API 速率限制已触发，无法继续采集 README' -ForegroundColor Red
            break
        }
        $header = Build-Repo-Header $r $lastCommitDate
        [System.IO.File]::WriteAllText($mdPath, $header, [System.Text.UTF8Encoding]::new($false))
        $emptyCount++
        Write-Host "  仓库 $repo 无 README，已保存占位文件: $safeName.md"
        continue
    }
    if (-not $readmeMeta.download_url) {
        $header = Build-Repo-Header $r $lastCommitDate
        [System.IO.File]::WriteAllText($mdPath, $header, [System.Text.UTF8Encoding]::new($false))
        $emptyCount++
        Write-Host "  仓库 $repo 无可用 README 链接，已保存占位文件: $safeName.md"
        continue
    }
    try {
        $raw = Invoke-WebRequest -Uri $readmeMeta.download_url -Headers $ua -UseBasicParsing
        $header = Build-Repo-Header $r $lastCommitDate
        $content = $header + $raw.Content
        [System.IO.File]::WriteAllText($mdPath, $content, [System.Text.UTF8Encoding]::new($false))
        $readmeCount++
        Write-Host "  已保存 README: $safeName.md"
    } catch {
        Write-Host "  警告：仓库 $repo 的 README 下载失败：$($_.Exception.Message)" -ForegroundColor Yellow
    }
}
Write-Host "共采集 $readmeCount 个 README，另保存 $emptyCount 个含头部的占位文件"

$topLangs = $langBytes.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 9

# 语言标签
$langTagsHtml = ''
foreach ($l in $topLangs) {
    $c = Get-Lang-Color $l.Key
    $langTagsHtml += "<span class='lang-tag' style='background-color:$c;color:$(Get-Contrast-Text $c)'>$(Html-Encode $l.Key)</span>"
}

# 环形图 + 图例
$radius = 64
$stroke = 28
$size = 160
$cx = $size / 2
$circ = 2 * [System.Math]::PI * $radius
$cum = 0.0
$segs = ''
$legend = ''
$topLangsSum = 0
foreach ($l in $topLangs) {
    $pct = if ($totalSize -gt 0) { $l.Value / $totalSize } else { 0 }
    $len = $pct * $circ
    $c = Get-Lang-Color $l.Key
    $segs += "<circle cx='$cx' cy='$cx' r='$radius' fill='none' stroke-width='$stroke' stroke='$c' stroke-dasharray='$([System.Math]::Round($len,3)) $circ' stroke-dashoffset='$(-[System.Math]::Round($cum,3))'></circle>"
    $legend += "<div class='legend-row'><span class='dot' style='background-color:$c'></span><span class='lang-name'>$(Html-Encode $l.Key)</span><span class='lang-pct'>$([System.Math]::Round($pct*100))%</span><span class='lang-size'>$(Format-Bytes $l.Value)</span></div>"
    $cum += $len
    $topLangsSum += $l.Value
}
$otherBytes = $totalSize - $topLangsSum
if ($otherBytes -gt 0) {
    $pct = $otherBytes / $totalSize
    $len = $pct * $circ
    $c = '#8b949e'
    $segs += "<circle cx='$cx' cy='$cx' r='$radius' fill='none' stroke-width='$stroke' stroke='$c' stroke-dasharray='$([System.Math]::Round($len,3)) $circ' stroke-dashoffset='$(-[System.Math]::Round($cum,3))'></circle>"
    $legend += "<div class='legend-row'><span class='dot' style='background-color:$c'></span><span class='lang-name'>Other</span><span class='lang-pct'>$([System.Math]::Round($pct*100))%</span><span class='lang-size'>$(Format-Bytes $otherBytes)</span></div>"
}

# 汇总数据
$totalStars = ($repos | Measure-Object -Property stargazers_count -Sum).Sum
$totalForks = ($repos | Measure-Object -Property forks_count -Sum).Sum

# 精选项目：按 Star 排序取前 9
$topRepos = $repos | Sort-Object stargazers_count -Descending | Select-Object -First 9

# 统计「给出的 Star」
Write-Host '开始获取已点 Star 的仓库'
$starred = Get-All-Pages -Uri "https://api.github.com/users/$userName/starred?per_page=100"
$starsGiven = $starred.Count
Write-Host "共点 Star $starsGiven 个仓库"

$repoIcon = '<svg class="ico" viewBox="0 0 16 16" fill="currentColor" width="16" height="16"><path d="M2 2.5A2.5 2.5 0 014.5 0h8.75a.75.75 0 01.75.75v12.5a.75.75 0 01-.75.75h-2.5a.75.75 0 010-1.5h1.75v-2h-8a1 1 0 00-.714 1.7.75.75 0 01-1.072 1.05A2.495 2.495 0 012 11.5v-9zm10.5-1V9h-8c-.356 0-.694.074-1 .208V2.5a1 1 0 011-1h8zM5 12.25a.25.25 0 01.25-.25h3.5a.25.25 0 01.25.25v3.25a.25.25 0 01-.4.2l-1.45-1.087a.249.249 0 00-.3 0L5.4 15.7a.25.25 0 01-.4-.2v-3.25z"></path></svg>'
$githubIcon = '<svg class="follow-ico" viewBox="0 0 16 16" fill="currentColor" width="16" height="16" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"></path></svg>'
$starIcon = '<svg class="ico" viewBox="0 0 16 16" fill="currentColor" width="14" height="14"><path d="M8 .25a.75.75 0 01.673.418l1.882 3.815 4.21.612a.75.75 0 01.416 1.279l-3.046 2.97.719 4.192a.75.75 0 01-1.088.791L8 12.347l-3.766 1.98a.75.75 0 01-1.088-.79l.72-4.194L.818 6.374a.75.75 0 01.416-1.28l4.21-.611L7.327.668A.75.75 0 018 .25z"></path></svg>'
$forkIcon = '<svg class="ico" viewBox="0 0 16 16" fill="currentColor" width="14" height="14"><path d="M5 3.25a.75.75 0 11-1.5 0 .75.75 0 011.5 0zm0 2.122a2.25 2.25 0 10-1.5 0v.878A2.25 2.25 0 005.75 8.5h1.5v2.128a2.251 2.251 0 101.5 0V8.5h1.5a2.25 2.25 0 002.25-2.25v-.878a2.25 2.25 0 10-1.5 0v.878a.75.75 0 01-.75.75h-4.5A.75.75 0 015 6.25v-.878zm3.75 7.378a.75.75 0 11-1.5 0 .75.75 0 011.5 0zm3-8.75a.75.75 0 100-1.5.75.75 0 000 1.5z"></path></svg>'
$linkIcon = '<svg aria-hidden="true" data-component="Octicon" height="16" viewBox="0 0 16 16" version="1.1" width="16" data-view-component="true" class="ico octicon octicon-link"><path d="m7.775 3.275 1.25-1.25a3.5 3.5 0 1 1 4.95 4.95l-2.5 2.5a3.5 3.5 0 0 1-4.95 0 .751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018 1.998 1.998 0 0 0 2.83 0l2.5-2.5a2.002 2.002 0 0 0-2.83-2.83l-1.25 1.25a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042Zm-4.69 9.64a1.998 1.998 0 0 0 2.83 0l1.25-1.25a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042l-1.25 1.25a3.5 3.5 0 1 1-4.95-4.95l2.5-2.5a3.5 3.5 0 0 1 4.95 0 .751.751 0 0 1-.018 1.042.751.751 0 0 1-1.042.018 1.998 1.998 0 0 0-2.83 0l-2.5 2.5a1.998 1.998 0 0 0 0 2.83Z"></path></svg>'
$locIcon  = '<svg data-component="Octicon" class="ico octicon octicon-location" viewBox="0 0 16 16" version="1.1" width="16" height="16" aria-hidden="true"><path d="m12.596 11.596-3.535 3.536a1.5 1.5 0 0 1-2.122 0l-3.535-3.536a6.5 6.5 0 1 1 9.192-9.193 6.5 6.5 0 0 1 0 9.193Zm-1.06-8.132v-.001a5 5 0 1 0-7.072 7.072L8 14.07l3.536-3.534a5 5 0 0 0 0-7.072ZM8 9a2 2 0 1 1-.001-3.999A2 2 0 0 1 8 9Z"></path></svg>'
$orgIcon  = '<svg class="ico" viewBox="0 0 16 16" fill="currentColor" width="14" height="14"><path d="M1.75 1h12.5c.966 0 1.75.784 1.75 1.75v10.5A1.75 1.75 0 0114.25 15H1.75A1.75 1.75 0 010 13.25V2.75C0 1.784.784 1 1.75 1zM1.5 2.75v10.5c0 .138.112.25.25.25h12.5a.25.25 0 00.25-.25V2.75a.25.25 0 00-.25-.25H1.75a.25.25 0 00-.25.25zm3 3.25a1 1 0 100 2 1 1 0 000-2zm-1.75 1a.75.75 0 000 1.5h1.5a.75.75 0 000-1.5h-1.5z"></path></svg>'
$joinedIcon = '<svg class="ico" viewBox="0 0 16 16" fill="currentColor" width="14" height="14"><path d="M4.75 0a.75.75 0 0 1 .75.75V2h5.5V.75a.75.75 0 0 1 1.5 0V2h1.25c.966 0 1.75.784 1.75 1.75v10.5A1.75 1.75 0 0 1 13.25 16H2.75A1.75 1.75 0 0 1 1 14.25V3.75C1 2.784 1.784 2 2.75 2H4V.75A.75.75 0 0 1 4.75 0ZM2.5 7.5v6.75c0 .138.112.25.25.25h10.5a.25.25 0 0 0 .25-.25V7.5Zm10.75-4H2.75a.25.25 0 0 0-.25.25V6h11V3.75a.25.25 0 0 0-.25-.25Z"></path></svg>'

# 项目卡片
$cards = ''
foreach ($r in $topRepos) {
    $lang = if ($r.language) { $r.language } else { 'Other' }
    $c = Get-Lang-Color $lang
    $desc = Html-Encode $r.description
    $langMeta = if ($r.language) { "<span class='repo-lang'><span class='repo-lang-dot' style='background-color:$c'></span>$(Html-Encode $r.language)</span>" } else { '' }
    $cards += @"
<a class="repo-card" href="$($r.html_url)" target="_blank" rel="noopener">
  <div class="repo-head">$repoIcon<h3>$(Html-Encode $r.name)</h3></div>
  <p class="repo-desc">$desc</p>
  <div class="repo-meta">$langMeta<span class="meta-item">$starIcon<span>$($r.stargazers_count)</span></span><span class="meta-item">$forkIcon<span>$($r.forks_count)</span></span></div>
</a>
"@
}

# 资料行
$meta = ''
if ($profile.location) { $meta += "<span>$locIcon$(Html-Encode $profile.location)</span>" }
if ($profile.blog) {
    $blog = $profile.blog
    if ($blog -notmatch '^https?://') { $blog = 'https://' + $blog }
    $meta += "<span>$linkIcon<a href='$blog' target='_blank' rel='noopener'>$(Html-Encode $profile.blog)</a></span>"
}
if ($profile.company) { $meta += "<span>$orgIcon$(Html-Encode $profile.company)</span>" }
if ($profile.created_at) {
    $joined = [DateTime]::Parse($profile.created_at).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $meta += "<span>$joinedIcon Joined $joined</span>"
}

# 生成时间同样按北京时间（UTC+8，定义见上方 README 采集区）
$generated = [System.TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), $utc8Zone).ToString('yyyy-MM-dd HH:mm:ss') + ' +08:00'

$html = @"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<link rel="icon" href="favicon.ico">
<title>MoonLord-LM - GitHub Profile</title>
<style>
:root{ --bg:#f6f8fa; --bg-secondary:#ffffff; --bg-tertiary:#f6f8fa; --border:#d1d9e0; --text-primary:#1f2328; --text-secondary:#59636e; --text-tertiary:#59636e; --accent:#0969da; }
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--text-primary);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,"PingFang SC","Microsoft YaHei",sans-serif;line-height:1.5;}
.wrap{max-width:900px;margin:0 auto;padding:40px 16px;}
a{color:var(--accent);text-decoration:none;}
a:hover{text-decoration:underline;}
.profile{display:flex;gap:28px;align-items:flex-start;flex-wrap:wrap;padding-bottom:16px;border-bottom:1px solid var(--border);}
.avatar{width:128px;height:128px;border-radius:50%;border:1px solid var(--border);background:var(--bg-secondary);}
.info{flex:1;min-width:240px;}
.title-row{display:flex;align-items:center;gap:14px;flex-wrap:wrap;}
.name{font-size:28px;font-weight:600;line-height:1.2;}
.name a{color:var(--text-primary);}
.name a:hover{color:var(--accent);text-decoration:none;}
.login{color:var(--text-secondary);font-weight:400;font-size:20px;}
.avatar-link{display:inline-block;flex-shrink:0;}
.follow-btn{display:inline-flex;align-items:center;justify-content:center;gap:6px;background:var(--bg-secondary);color:var(--text-primary);border:1px solid var(--border);border-radius:6px;padding:5px 14px;font-size:14px;font-weight:600;text-decoration:none;transition:background .15s,border-color .15s;line-height:1.2;margin:5px 0 0;}
.follow-btn:hover{background:var(--bg-tertiary);border-color:var(--text-tertiary);color:var(--text-primary);text-decoration:none;}
.follow-btn svg{width:16px;height:16px;flex-shrink:0;}
.follow-btn:focus-visible{outline:2px solid var(--accent);outline-offset:2px;}
.bio{margin-top:10px;color:var(--text-primary);}
.meta{margin-top:12px;display:flex;gap:18px;flex-wrap:wrap;color:var(--text-secondary);font-size:14px;}
.meta span{display:inline-flex;align-items:center;gap:5px;}
.ico{opacity:.8;flex-shrink:0;}
.stats{display:flex;gap:22px;margin-top:18px;flex-wrap:wrap;}
.stat{display:flex;align-items:center;gap:6px;font-size:14px;color:var(--text-secondary);}
.stat b{color:var(--text-primary);font-weight:600;}
a.stat{text-decoration:none;}
a.stat:hover{color:var(--accent);}
.section{margin-top:20px;}
.section h2{font-size:18px;font-weight:600;display:flex;align-items:center;gap:8px;margin-bottom:16px;color:var(--text-primary);}
.lang-tags{display:flex;flex-wrap:wrap;gap:8px;}
.lang-tag{display:inline-flex;align-items:center;gap:6px;font-size:12px;font-weight:600;border:1px solid transparent;border-radius:999px;padding:3px 10px;}
.dot{width:8px;height:8px;border-radius:50%;display:inline-block;flex-shrink:0;}
.lang-flex{display:flex;gap:32px;align-items:center;flex-wrap:wrap;}
.donut{flex-shrink:0;}
.legend{flex:0 0 auto;min-width:220px;display:flex;flex-direction:column;gap:8px;}
.legend-row{display:flex;align-items:center;gap:10px;font-size:14px;}
.lang-name{color:var(--text-primary);font-weight:600;white-space:nowrap;min-width:120px;}
.lang-pct{color:var(--text-secondary);font-variant-numeric:tabular-nums;min-width:42px;text-align:right;}
.lang-size{color:var(--text-tertiary);font-size:13px;white-space:nowrap;font-variant-numeric:tabular-nums;margin-left:12px;}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(270px,1fr));gap:16px;}
.repo-card{display:block;min-width:0;background:var(--bg-secondary);border:1px solid var(--border);border-radius:8px;padding:16px;transition:border-color .15s,background .15s;text-decoration:none;}
.repo-card:hover{border-color:#8b949e;background:var(--bg-tertiary);text-decoration:none;}
.repo-head{display:flex;align-items:center;gap:8px;margin-bottom:8px;}
.repo-head h3{font-size:15px;font-weight:600;color:var(--accent);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.repo-desc{font-size:13px;color:var(--text-secondary);margin-bottom:12px;display:-webkit-box;-webkit-line-clamp:4;-webkit-box-orient:vertical;overflow:hidden;min-height:76px;}
.repo-meta{display:flex;align-items:center;justify-content:flex-start;flex-wrap:wrap;gap:16px;font-size:12px;color:var(--text-tertiary);}
.repo-meta span{display:inline-flex;align-items:center;gap:5px;}
.repo-lang{display:inline-flex;align-items:center;gap:5px;font-size:12px;color:var(--text-secondary);}
.repo-lang-dot{width:12px;height:12px;border-radius:50%;display:inline-block;flex-shrink:0;}
.footer{margin-top:24px;padding-top:12px;border-top:1px solid var(--border);font-size:12px;color:var(--text-tertiary);text-align:center;}
</style>
</head>
<body>
<div class="wrap">
  <header class="profile">
    <a class="avatar-link" href="$($profile.html_url)" target="_blank" rel="noopener"><img class="avatar" src="$(Html-Encode $avatarSrc)" alt="$(Html-Encode $profile.login)"></a>
    <div class="info">
      <div class="title-row"><div class="name"><a href="$($profile.html_url)" target="_blank" rel="noopener">$(Html-Encode ($profile.name, $profile.login | Where-Object {$_} | Select-Object -First 1))</a></div> <a class="follow-btn" href="https://github.com/${userName}" target="_blank" rel="noopener">$githubIcon<span>Follow</span></a></div>
      $(if($profile.bio){"<div class='bio'>$(Html-Encode $profile.bio)</div>"}else{''})
      <div class="meta">$meta</div>
      <div class="stats">
        <a class="stat" href="https://github.com/${userName}?tab=repositories" target="_blank" rel="noopener"><b>$($repos.Count)</b> Repositories</a>
        <a class="stat" href="https://github.com/${userName}?tab=repositories&q=&type=&language=&sort=stargazers" target="_blank" rel="noopener"><b>$totalStars</b> Stars Earned</a>
        <a class="stat" href="https://github.com/${userName}?tab=repositories&q=&type=&language=&sort=stargazers" target="_blank" rel="noopener"><b>$totalForks</b> Forks Earned</a>
        <a class="stat" href="https://github.com/${userName}?tab=followers" target="_blank" rel="noopener"><b>$($profile.followers)</b> Followers</a>
        <a class="stat" href="https://github.com/${userName}?tab=following" target="_blank" rel="noopener"><b>$($profile.following)</b> Following</a>
        <a class="stat" href="https://github.com/${userName}?tab=stars" target="_blank" rel="noopener"><b>$starsGiven</b> Stars Given</a>
      </div>
    </div>
  </header>

  <section class="section">
    <h2>Top Languages</h2>
    <div class="lang-flex">
      <svg class="donut" width="184" height="184" viewBox="0 0 160 160" style="transform:rotate(-90deg)">$segs</svg>
      <div class="legend">$legend</div>
    </div>
  </section>

  <section class="section">
    <h2>Top Repositories</h2>
    <div class="cards">$cards</div>
  </section>

  <div class="footer">Updated at $generated</div>
</div>
</body>
</html>
"@

# 采集 GitHub favicon 到本地
$favPath = Join-Path $baseDir 'favicon.ico'
try {
    Invoke-WebRequest -Uri 'https://github.com/favicon.ico' -Headers $ua -OutFile $favPath -UseBasicParsing
    Write-Host "已下载 favicon: $favPath"
} catch {
    Write-Host "错误：favicon 下载失败：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$utf8NoBOM = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($outFile, $html, $utf8NoBOM)
Write-Host "已生成: $outFile"
-----END POWERSHELL CODE-----
