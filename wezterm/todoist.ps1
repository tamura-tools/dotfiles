# ============================================
#  Todoist Dashboard
#  WezTerm Pane Dashboard with Todoist + Clock
#  Interactive: [a]dd  [c]omplete  [d]elete  [l]og  [r]efresh  [q]uit
#  Windows PowerShell 5.x compatible
# ============================================

param(
    [switch] $Once
)

$API_KEY  = $env:TODOIST_API_KEY
$INTERVAL = 60
$TZ       = "Tokyo Standard Time"
$THM      = "tokyo-night"

if ($env:TODOIST_DASHBOARD_LOG_DIR) {
    $LOG_DIR = $env:TODOIST_DASHBOARD_LOG_DIR
} elseif ($env:LOCALAPPDATA) {
    $LOG_DIR = Join-Path $env:LOCALAPPDATA "TodoistDashboard"
} else {
    $LOG_DIR = Join-Path $PSScriptRoot "logs"
}
$LOG_PATH = Join-Path $LOG_DIR "actions.jsonl"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$E = [char]27

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$allThemes = @{
    "tokyo-night" = @{
        fg        = "$E[38;2;169;177;214m"
        accent    = "$E[38;2;187;154;247m"
        highlight = "$E[38;2;224;175;104m"
        success   = "$E[38;2;158;206;106m"
        warning   = "$E[38;2;224;175;104m"
        error     = "$E[38;2;247;118;142m"
        dim       = "$E[38;2;86;95;137m"
        cyan      = "$E[38;2;125;207;255m"
        border    = "$E[38;2;60;64;90m"
    }
    "synthwave" = @{
        fg        = "$E[38;2;230;210;255m"
        accent    = "$E[38;2;255;56;172m"
        highlight = "$E[38;2;255;198;68m"
        success   = "$E[38;2;114;255;178m"
        warning   = "$E[38;2;255;198;68m"
        error     = "$E[38;2;255;56;100m"
        dim       = "$E[38;2;100;80;130m"
        cyan      = "$E[38;2;54;215;255m"
        border    = "$E[38;2;80;60;110m"
    }
    "dracula" = @{
        fg        = "$E[38;2;248;248;242m"
        accent    = "$E[38;2;189;147;249m"
        highlight = "$E[38;2;241;250;140m"
        success   = "$E[38;2;80;250;123m"
        warning   = "$E[38;2;255;184;108m"
        error     = "$E[38;2;255;85;85m"
        dim       = "$E[38;2;98;114;164m"
        cyan      = "$E[38;2;139;233;253m"
        border    = "$E[38;2;68;71;90m"
    }
    "nord" = @{
        fg        = "$E[38;2;216;222;233m"
        accent    = "$E[38;2;136;192;208m"
        highlight = "$E[38;2;235;203;139m"
        success   = "$E[38;2;163;190;140m"
        warning   = "$E[38;2;235;203;139m"
        error     = "$E[38;2;191;97;106m"
        dim       = "$E[38;2;76;86;106m"
        cyan      = "$E[38;2;143;188;187m"
        border    = "$E[38;2;67;76;94m"
    }
    "gruvbox" = @{
        fg        = "$E[38;2;235;219;178m"
        accent    = "$E[38;2;211;134;155m"
        highlight = "$E[38;2;250;189;47m"
        success   = "$E[38;2;184;187;38m"
        warning   = "$E[38;2;254;128;25m"
        error     = "$E[38;2;251;73;52m"
        dim       = "$E[38;2;124;111;100m"
        cyan      = "$E[38;2;131;165;152m"
        border    = "$E[38;2;80;73;69m"
    }
    "catppuccin" = @{
        fg        = "$E[38;2;205;214;244m"
        accent    = "$E[38;2;203;166;247m"
        highlight = "$E[38;2;249;226;175m"
        success   = "$E[38;2;166;227;161m"
        warning   = "$E[38;2;250;179;135m"
        error     = "$E[38;2;243;139;168m"
        dim       = "$E[38;2;88;91;112m"
        cyan      = "$E[38;2;137;220;235m"
        border    = "$E[38;2;69;71;90m"
    }
}

$C = $allThemes[$THM]
$R = "$E[0m"
$B = "$E[1m"

$sepChar = [char]0x2500
$SEP = "$($C.border)$("$sepChar" * 44)$R"
$hideCursor = "$E[?25l"
$showCursor = "$E[?25h"

if (-not $API_KEY) {
    Write-Host ""
    Write-Host "  $($C.error)${B}! TODOIST_API_KEY is not set$R"
    Write-Host ""
    Write-Host "  $($C.fg)Run in PowerShell:$R"
    Write-Host "  $($C.cyan)[Environment]::SetEnvironmentVariable('TODOIST_API_KEY', 'your-key', 'User')$R"
    Write-Host ""
    Write-Host "  $($C.dim)Then restart WezTerm$R"
    Write-Host ""
    Start-Sleep -Seconds 5
}

# --- Todoist API helpers ----------------------------------------

function Invoke-Todoist {
    param(
        [Parameter(Mandatory)] [string] $Method,
        [Parameter(Mandatory)] [string] $Path,
        [hashtable] $Body
    )
    $uri = "https://api.todoist.com/api/v1$Path"
    $headers = @{
        Authorization = "Bearer $API_KEY"
        Accept        = "application/json"
    }
    $params = @{
        Uri        = $uri
        Method     = $Method
        Headers    = $headers
        TimeoutSec = 10
        UseBasicParsing = $true
    }
    if ($Body) {
        $jsonBody = ($Body | ConvertTo-Json -Compress)
        $params.Body        = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
        $params.ContentType = "application/json; charset=utf-8"
    }
    $resp = Invoke-WebRequest @params

    # PS 5.1 では charset 無し JSON が文字化けすることがあるため、
    # 可能なら生バイトを UTF-8 として読む。gzip のまま返った場合だけ展開する。
    $bytes = $null
    if ($resp.RawContentStream) {
        if ($resp.RawContentStream.CanSeek) { $resp.RawContentStream.Position = 0 }
        $ms = New-Object System.IO.MemoryStream
        try {
            $resp.RawContentStream.CopyTo($ms)
            $bytes = $ms.ToArray()
        } finally {
            $ms.Dispose()
        }
    }

    if ($bytes -and $bytes.Length -gt 0) {
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0x1f -and $bytes[1] -eq 0x8b) {
            $inputStream = New-Object System.IO.MemoryStream
            $outputStream = New-Object System.IO.MemoryStream
            $gzipStream = $null
            try {
                $inputStream.Write($bytes, 0, $bytes.Length)
                $inputStream.Position = 0
                $gzipStream = New-Object System.IO.Compression.GZipStream($inputStream, [System.IO.Compression.CompressionMode]::Decompress)
                $gzipStream.CopyTo($outputStream)
                $bytes = $outputStream.ToArray()
            } finally {
                if ($gzipStream) { $gzipStream.Dispose() }
                $outputStream.Dispose()
                $inputStream.Dispose()
            }
        }
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    } else {
        $text = [string]$resp.Content
    }

    if (-not $text -or -not $text.Trim()) { return $null }
    return $text | ConvertFrom-Json
}

function Invoke-TodoistQuickAdd {
    param(
        [Parameter(Mandatory)] [string] $Text
    )

    return Invoke-Todoist -Method Post -Path "/tasks/quick" -Body @{
        text = $Text
        meta = $false
    }
}

function Write-ActionLog {
    param(
        [Parameter(Mandatory)] [string] $Action,
        $Task,
        [string] $Detail
    )

    try {
        if (-not [System.IO.Directory]::Exists($LOG_DIR)) {
            [System.IO.Directory]::CreateDirectory($LOG_DIR) | Out-Null
        }

        $tzInfo = [System.TimeZoneInfo]::FindSystemTimeZoneById($TZ)
        $nowTz = [System.TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $tzInfo)
        $entry = [ordered]@{
            timestamp = $nowTz.ToString("yyyy-MM-ddTHH:mm:sszzz")
            action    = $Action
            taskId    = $null
            content   = $null
            priority  = $null
            dueDate   = $null
            detail    = $Detail
        }

        if ($null -ne $Task) {
            foreach ($name in @("id", "content", "priority", "dueDate")) {
                $prop = $Task.PSObject.Properties[$name]
                if ($prop) {
                    switch ($name) {
                        "id"       { $entry.taskId = [string]$prop.Value }
                        "content"  { $entry.content = [string]$prop.Value }
                        "priority" { $entry.priority = $prop.Value }
                        "dueDate"  { $entry.dueDate = [string]$prop.Value }
                    }
                }
            }
        }

        $json = $entry | ConvertTo-Json -Compress
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::AppendAllText($LOG_PATH, "$json`r`n", $utf8NoBom)
    } catch {
        # ログ書き込み失敗でダッシュボード操作を止めない。
    }
}

function New-TaskList {
    $list = [System.Collections.Generic.List[object]]::new()
    return ,$list
}

function Add-ResponseItems {
    param(
        [Parameter(Mandatory)] $Target,
        $Response,
        [string] $PropertyName
    )
    if ($null -eq $Response) { return }

    $value = $Response
    if ($PropertyName) {
        $prop = $Response.PSObject.Properties[$PropertyName]
        if ($prop) {
            $value = $prop.Value
        } elseif (-not ($Response -is [System.Array])) {
            return
        }
    }

    if ($null -eq $value) { return }
    if ($value -is [System.Array]) {
        foreach ($item in $value) {
            if ($null -ne $item) { $Target.Add($item) }
        }
    } else {
        $Target.Add($value)
    }
}

function Get-TodoistDueDate {
    param($Task)
    if ($null -eq $Task -or $null -eq $Task.due) { return $null }

    $date = [string]$Task.due.date
    if (-not $date) { return $null }
    if ($date.Length -ge 10) { return $date.Substring(0, 10) }
    return $date
}

function Update-TodoistData {
    $script:TodayTasks = New-TaskList
    $script:CompletedCount = 0
    if (-not $API_KEY) { return }

    try {
        $resp = Invoke-Todoist -Method Get -Path "/tasks"
        $todayStr = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), $TZ).ToString("yyyy-MM-dd")
        $rawTasks = New-TaskList
        Add-ResponseItems -Target $rawTasks -Response $resp -PropertyName "results"

        $dueTasks = New-TaskList
        foreach ($task in $rawTasks) {
            $dueDate = Get-TodoistDueDate -Task $task
            if ($dueDate -and $dueDate -le $todayStr) {
                $dueTasks.Add([pscustomobject]@{
                    id       = [string]$task.id
                    content  = [string]$task.content
                    priority = [int]$task.priority
                    dueDate  = $dueDate
                })
            }
        }

        foreach ($task in ($dueTasks | Sort-Object -Property priority -Descending)) {
            $script:TodayTasks.Add($task)
        }
    } catch {
        $script:TodayTasks = New-TaskList
    }

    $script:CompletedCount = Get-CompletedCount
}

function Get-CompletedCount {
    if (-not $API_KEY) { return 0 }
    try {
        $nowTz = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), $TZ)
        $since = $nowTz.Date.ToString("yyyy-MM-ddTHH:mm:ss")
        $until = $nowTz.Date.AddDays(1).AddSeconds(-1).ToString("yyyy-MM-ddTHH:mm:ss")
        $resp = Invoke-Todoist -Method Get -Path "/tasks/completed/by_completion_date?since=$since&until=$until"
        $items = New-TaskList
        Add-ResponseItems -Target $items -Response $resp -PropertyName "items"
        return $items.Count
    } catch {
        return 0
    }
}

# --- Rendering --------------------------------------------------

function Show-Dashboard {
    Clear-Host

    $taskList = $script:TodayTasks
    if ($null -eq $taskList) { $taskList = New-TaskList }
    $taskCount = $taskList.Count
    $completed = [int]$script:CompletedCount
    $shownCompleted = if ($taskCount -gt 0) { 0 } else { $completed }
    $allTotal = if ($taskCount -gt 0) { $taskCount } else { $completed }
    $now       = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), $TZ)
    $timeStr   = $now.ToString("HH:mm:ss")
    $dateStr   = $now.ToString("yyyy-MM-dd (ddd)")

    Write-Host ""
    Write-Host "  $($C.accent)${B}  Todoist Dashboard$R"
    Write-Host "  $SEP"
    Write-Host ""
    Write-Host "  $($C.highlight)${B}  $timeStr$R"
    Write-Host "  $($C.fg)  $dateStr$R"
    Write-Host ""
    Write-Host "  $SEP"
    Write-Host ""
    Write-Host "  $($C.cyan)${B}  Today's Tasks$R"
    Write-Host ""

    if (-not $API_KEY) {
        Write-Host "  $($C.warning)  API not set$R"
    }
    elseif ($taskCount -eq 0) {
        Write-Host "  $($C.success)  All clear!$R"
    }
    else {
        $idx = 0
        foreach ($t in $taskList) {
            if ($idx -ge 12) {
                $rem = $taskCount - 12
                Write-Host "  $($C.dim)  ... +$rem more$R"
                break
            }
            $pc = $C.dim
            $pl = "p4"
            switch ($t.priority) {
                4 { $pc = $C.error;   $pl = "p1" }
                3 { $pc = $C.warning; $pl = "p2" }
                2 { $pc = $C.cyan;    $pl = "p3" }
            }
            $name = $t.content
            if ($name.Length -gt 28) { $name = $name.Substring(0, 25) + "..." }
            $pad = " " * [Math]::Max(0, 28 - $name.Length)
            $num = "{0,2}" -f ($idx + 1)
            Write-Host "  $($C.dim)[$num]$R $($C.fg)$name$pad$pc($pl)$R"
            $idx++
        }
    }

    Write-Host ""
    Write-Host "  $SEP"
    Write-Host ""

    $barW = 20
    $fill = 0
    if ($allTotal -gt 0) { $fill = [Math]::Floor(($shownCompleted / $allTotal) * $barW) }
    $empty = $barW - $fill
    $fc = [char]0x2588
    $ec = [char]0x2591
    $fBar = "$fc" * $fill
    $eBar = "$ec" * $empty
    Write-Host "  $($C.success)  [OK] $shownCompleted/$allTotal done$R  $($C.success)$fBar$($C.dim)$eBar$R"

    Write-Host ""
    Write-Host "  $SEP"
    Write-Host "  $($C.dim)  [a]dd  [c]omplete  [d]elete  [l]og  [r]efresh  [q]uit$R"
    Write-Host "  $($C.dim)  Refresh: ${INTERVAL}s  |  Theme: $THM$R"
}

# --- Prompt helpers ---------------------------------------------

function Read-Line {
    param([string] $Prompt)
    Write-Host $showCursor -NoNewline
    Write-Host ""
    $line = Read-Host -Prompt "  > $Prompt"
    Write-Host $hideCursor -NoNewline
    return $line
}

function Show-Message {
    param(
        [string] $Text,
        [string] $Color = $C.dim,
        [int]    $Seconds = 1
    )
    Write-Host ""
    Write-Host "  $Color  $Text$R"
    Start-Sleep -Seconds $Seconds
}

function Show-ActionLogTail {
    Write-Host $showCursor -NoNewline
    Clear-Host
    Write-Host ""
    Write-Host "  $($C.accent)${B}  Todoist Action Log$R"
    Write-Host "  $SEP"
    Write-Host "  $($C.dim)  $LOG_PATH$R"
    Write-Host ""

    if (-not (Test-Path -LiteralPath $LOG_PATH)) {
        Write-Host "  $($C.dim)  No log yet$R"
    } else {
        $lines = @(Get-Content -LiteralPath $LOG_PATH -Tail 12 -Encoding UTF8)
        if ($lines.Count -eq 0) {
            Write-Host "  $($C.dim)  No log yet$R"
        } else {
            foreach ($line in $lines) {
                try {
                    $entry = $line | ConvertFrom-Json
                    $ts = [string]$entry.timestamp
                    if ($ts.Length -ge 16) { $ts = $ts.Substring(5, 11) }
                    $action = ([string]$entry.action).PadRight(12)
                    $content = [string]$entry.content
                    if (-not $content) { $content = [string]$entry.detail }
                    if ($content.Length -gt 28) { $content = $content.Substring(0, 25) + "..." }
                    Write-Host "  $($C.dim)$ts$R  $($C.cyan)$action$R $($C.fg)$content$R"
                } catch {
                    Write-Host "  $($C.dim)$line$R"
                }
            }
        }
    }

    Write-Host ""
    Read-Host -Prompt "  > Enter to return" | Out-Null
    Write-Host $hideCursor -NoNewline
}

function Invoke-AddTask {
    if (-not $API_KEY) { Show-Message -Text "API not set" -Color $C.warning; return }
    $content = Read-Line -Prompt "Add task"
    if (-not $content -or -not $content.Trim()) { return }
    try {
        $taskText = $content.Trim()
        $created = Invoke-TodoistQuickAdd -Text $taskText
        $createdId = $null
        if ($created) { $createdId = [string]$created.id }
        Write-ActionLog -Action "add" -Task ([pscustomobject]@{
            id       = $createdId
            content  = $taskText
            priority = $null
            dueDate  = $null
        })
        Show-Message -Text "[OK] Added" -Color $C.success
    } catch {
        Write-ActionLog -Action "add_error" -Detail $_.Exception.Message
        Show-Message -Text "[ERR] $($_.Exception.Message)" -Color $C.error -Seconds 2
    }
}

function Resolve-TaskByNumber {
    param([string] $NumStr)
    $taskList = $script:TodayTasks
    if ($null -eq $taskList) { $taskList = New-TaskList }
    $taskCount = $taskList.Count
    $i = 0
    if (-not [int]::TryParse($NumStr.Trim(), [ref] $i)) {
        Show-Message -Text "[ERR] Not a number" -Color $C.error
        return $null
    }
    if ($i -lt 1 -or $i -gt $taskCount) {
        Show-Message -Text "[ERR] Out of range (1-$taskCount)" -Color $C.error
        return $null
    }
    return $taskList[$i - 1]
}

function Resolve-TasksBySpec {
    param(
        [string] $Spec,
        [switch] $AllowAll
    )

    $taskList = $script:TodayTasks
    if ($null -eq $taskList) { $taskList = New-TaskList }
    $taskCount = $taskList.Count
    $result = New-TaskList
    $seen = @{}
    $raw = ""
    if ($Spec) { $raw = $Spec.Trim() }
    if (-not $raw) { return @() }

    if ($AllowAll -and $raw -match '^(all|a|\*)$') {
        for ($idx = 0; $idx -lt $taskCount; $idx++) {
            $result.Add($taskList[$idx])
        }
        return $result.ToArray()
    }

    $tokens = @($raw -split '[,\s、，]+') | Where-Object { $_ }
    foreach ($token in $tokens) {
        $indexes = @()
        if ($token -match '^(\d+)-(\d+)$') {
            $start = [int]$Matches[1]
            $end = [int]$Matches[2]
            if ($start -gt $end) {
                $tmp = $start
                $start = $end
                $end = $tmp
            }
            $indexes = $start..$end
        } elseif ($token -match '^\d+$') {
            $indexes = @([int]$token)
        } else {
            Show-Message -Text "[ERR] Bad spec: $token" -Color $C.error
            return @()
        }

        foreach ($i in $indexes) {
            if ($i -lt 1 -or $i -gt $taskCount) {
                Show-Message -Text "[ERR] Out of range (1-$taskCount): $i" -Color $C.error
                return @()
            }
            if (-not $seen.ContainsKey($i)) {
                $seen[$i] = $true
                $result.Add($taskList[$i - 1])
            }
        }
    }

    return $result.ToArray()
}

function Invoke-CompleteTask {
    if (-not $API_KEY) { Show-Message -Text "API not set" -Color $C.warning; return }
    $taskList = $script:TodayTasks
    if ($null -eq $taskList) { $taskList = New-TaskList }
    $taskCount = $taskList.Count
    if ($taskCount -eq 0) { Show-Message -Text "No tasks" -Color $C.dim; return }
    $spec = Read-Line -Prompt "Complete # (1-$taskCount, 1,3,5-7, all)"
    if (-not $spec) { return }
    $tasks = @(Resolve-TasksBySpec -Spec $spec -AllowAll)
    if ($tasks.Count -eq 0) { return }

    if ($tasks.Count -gt 1) {
        $confirm = Read-Line -Prompt "Complete $($tasks.Count) tasks? y/N"
        if ($confirm -notmatch '^(y|yes)$') {
            Show-Message -Text "Canceled" -Color $C.dim
            return
        }
    }

    $ok = 0
    $failed = 0
    foreach ($t in $tasks) {
        try {
            Invoke-Todoist -Method Post -Path "/tasks/$($t.id)/close" | Out-Null
            Write-ActionLog -Action "complete" -Task $t
            $ok++
        } catch {
            Write-ActionLog -Action "complete_error" -Task $t -Detail $_.Exception.Message
            $failed++
        }
    }

    if ($failed -gt 0) {
        Show-Message -Text "[WARN] Completed $ok, failed $failed" -Color $C.warning -Seconds 2
    } elseif ($ok -eq 1) {
        Show-Message -Text "[OK] Completed: $($tasks[0].content)" -Color $C.success
    } else {
        Show-Message -Text "[OK] Completed $ok tasks" -Color $C.success
    }
}

function Invoke-DeleteTask {
    if (-not $API_KEY) { Show-Message -Text "API not set" -Color $C.warning; return }
    $taskList = $script:TodayTasks
    if ($null -eq $taskList) { $taskList = New-TaskList }
    $taskCount = $taskList.Count
    if ($taskCount -eq 0) { Show-Message -Text "No tasks" -Color $C.dim; return }
    $spec = Read-Line -Prompt "Delete # (1-$taskCount, 1,3,5-7, all)"
    if (-not $spec) { return }
    $tasks = @(Resolve-TasksBySpec -Spec $spec -AllowAll)
    if ($tasks.Count -eq 0) { return }

    if ($tasks.Count -gt 1) {
        $confirm = Read-Line -Prompt "Delete $($tasks.Count) tasks? y/N"
        if ($confirm -notmatch '^(y|yes)$') {
            Show-Message -Text "Canceled" -Color $C.dim
            return
        }
    }

    $ok = 0
    $failed = 0
    foreach ($t in $tasks) {
        try {
            Invoke-Todoist -Method Delete -Path "/tasks/$($t.id)" | Out-Null
            Write-ActionLog -Action "delete" -Task $t
            $ok++
        } catch {
            Write-ActionLog -Action "delete_error" -Task $t -Detail $_.Exception.Message
            $failed++
        }
    }

    if ($failed -gt 0) {
        Show-Message -Text "[WARN] Deleted $ok, failed $failed" -Color $C.warning -Seconds 2
    } elseif ($ok -eq 1) {
        Show-Message -Text "[OK] Deleted: $($tasks[0].content)" -Color $C.success
    } else {
        Show-Message -Text "[OK] Deleted $ok tasks" -Color $C.success
    }
}

# --- Main loop --------------------------------------------------

Write-Host $hideCursor -NoNewline

try {
    $running = $true
    while ($running) {
        Update-TodoistData
        Show-Dashboard
        if ($Once) { break }

        $action = $null
        $elapsedMs = 0
        $intervalMs = $INTERVAL * 1000
        while ($elapsedMs -lt $intervalMs -and -not $action) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                $ch = [System.Char]::ToLowerInvariant($key.KeyChar)
                switch ($ch) {
                    'a' { $action = 'add' }
                    'c' { $action = 'complete' }
                    'd' { $action = 'delete' }
                    'l' { $action = 'log' }
                    'r' { $action = 'refresh' }
                    'q' { $action = 'quit' }
                }
            }
            if (-not $action) {
                Start-Sleep -Milliseconds 200
                $elapsedMs += 200
            }
        }

        switch ($action) {
            'add'      { Invoke-AddTask }
            'complete' { Invoke-CompleteTask }
            'delete'   { Invoke-DeleteTask }
            'log'      { Show-ActionLogTail }
            'quit'     { $running = $false }
        }
    }
}
finally {
    Write-Host $showCursor -NoNewline
}
