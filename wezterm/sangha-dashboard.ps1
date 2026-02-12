# ============================================
#  Sangha Dashboard v1.6
#  WezTerm Pane Dashboard with Todoist + Clock
#  Windows PowerShell 5.x compatible
# ============================================

$API_KEY  = $env:TODOIST_API_KEY
$INTERVAL = 60
$TZ       = "Tokyo Standard Time"
$THM      = "tokyo-night"

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

$hideCursor = "$E[?25l"
$showCursor = "$E[?25h"
Write-Host $hideCursor -NoNewline

try {
    while ($true) {
        $tasks = @()
        $taskCount = 0
        $completedCount = 0

        if ($API_KEY) {
            # --- Active tasks (API v1, client-side filter) ---
            $wc = $null
            try {
                $wc = New-Object System.Net.WebClient
                $wc.Encoding = [System.Text.Encoding]::UTF8
                $wc.Headers.Add("Authorization", "Bearer $API_KEY")
                $json = $wc.DownloadString("https://api.todoist.com/api/v1/tasks")
                $allTasks = ($json | ConvertFrom-Json).results
                $todayStr = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), $TZ).ToString("yyyy-MM-dd")
                $filtered = @($allTasks | Where-Object { $_.due -and $_.due.date -le $todayStr })
                $tasks = $filtered
                $taskCount = $filtered.Count
            }
            catch {
                $tasks = @()
                $taskCount = 0
            }
            if ($wc) { $wc.Dispose() }

            # --- Completed tasks (Sync v9) ---
            $wc2 = $null
            try {
                $jstNow = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), $TZ)
                $today = $jstNow.Date.ToString("yyyy-MM-ddT00:00:00")
                $wc2 = New-Object System.Net.WebClient
                $wc2.Encoding = [System.Text.Encoding]::UTF8
                $wc2.Headers.Add("Authorization", "Bearer $API_KEY")
                $json2 = $wc2.DownloadString("https://api.todoist.com/api/v1/tasks/completed?since=$today")
                $cResp = $json2 | ConvertFrom-Json
                if ($cResp.items -and $cResp.items -is [System.Array]) {
                    $completedCount = $cResp.items.Length
                }
                elseif ($cResp.items) {
                    $completedCount = 1
                }
            }
            catch {
                $completedCount = 0
            }
            if ($wc2) { $wc2.Dispose() }
        }

        $allTotal = $taskCount + $completedCount

        $now = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), $TZ)
        $timeStr = $now.ToString("HH:mm:ss")
        $dateStr = $now.ToString("yyyy-MM-dd (ddd)")

        Clear-Host

        Write-Host ""
        Write-Host "  $($C.accent)${B}  Sangha Dashboard$R"
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
            $sorted = $tasks | Sort-Object -Property priority -Descending
            foreach ($t in $sorted) {
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
                if ($name.Length -gt 30) { $name = $name.Substring(0, 27) + "..." }
                $pad = " " * [Math]::Max(0, 30 - $name.Length)
                $circle = [char]0x25CB
                Write-Host "  $($C.fg)  $circle $name$pad$pc($pl)$R"
                $idx++
            }
        }

        Write-Host ""
        Write-Host "  $SEP"
        Write-Host ""

        $barW = 20
        $fill = 0
        if ($allTotal -gt 0) { $fill = [Math]::Floor(($completedCount / $allTotal) * $barW) }
        $empty = $barW - $fill
        $fc = [char]0x2588
        $ec = [char]0x2591
        $fBar = "$fc" * $fill
        $eBar = "$ec" * $empty
        Write-Host "  $($C.success)  [OK] $completedCount/$allTotal done$R  $($C.success)$fBar$($C.dim)$eBar$R"

        Write-Host ""
        Write-Host "  $SEP"
        Write-Host "  $($C.dim)  Refresh: ${INTERVAL}s  |  Theme: $THM$R"
        Write-Host "  $($C.dim)  Ctrl+C: exit$R"

        Start-Sleep -Seconds $INTERVAL
    }
}
finally {
    Write-Host $showCursor -NoNewline
}
