# =====================================================================
#  ai_usage.ps1
#  WezTerm ステータスライン用の 1 行サマリを出力する（高速・同期前提）。
#   - Codex : ~/.codex/sessions の最新ログから 5h枠/週枠 の使用率をライブ取得
#   - Claude: $TEMP\wez_ai_usage.json（refresh が更新）から読む。古ければ
#             ai_usage_refresh.ps1 を detached で起動して次回に備える。
#  出力例:  C 個71% 社-   Cdx 5h50% wk8%
# =====================================================================
$ErrorActionPreference = 'SilentlyContinue'

$cachePath     = Join-Path $env:TEMP 'wez_ai_usage.json'
$lockPath      = Join-Path $env:TEMP 'wez_ai_refresh.lock'
$refreshScript = Join-Path $HOME 'dotfiles\wezterm\ai_usage_refresh.ps1'
$STALE         = 180   # 秒。これより古ければ refresh を起動

function Format-ClaudePart([string]$Label, $Stat) {
    if ($Stat -and $Stat.active) {
        if ($null -ne $Stat.pct) { return ("{0}{1}%" -f $Label, [int]$Stat.pct) }
        return ("{0}?" -f $Label)
    }
    return ("{0}-" -f $Label)
}

# ---- Claude（キャッシュ） ----
$claudeStr   = 'C —'
$needRefresh = $true
if (Test-Path $cachePath) {
    try {
        $c = Get-Content $cachePath -Raw | ConvertFrom-Json
        $age = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [int]$c.ts
        if ($age -le $STALE) { $needRefresh = $false }
        $parts = @()
        $parts += (Format-ClaudePart '個' $c.personal)
        $parts += (Format-ClaudePart '社' $c.work)
        $claudeStr = 'C ' + ($parts -join ' ')
    } catch { $claudeStr = 'C —'; $needRefresh = $true }
}

# 古い/無いときだけ refresh を detached 起動（多重起動はロックで抑止）
if ($needRefresh -and (Test-Path $refreshScript)) {
    $spawn = $true
    if (Test-Path $lockPath) {
        $lockAge = ((Get-Date) - (Get-Item $lockPath).LastWriteTime).TotalSeconds
        if ($lockAge -lt 120) { $spawn = $false }
    }
    if ($spawn) {
        try { [System.IO.File]::WriteAllText($lockPath, '') } catch { }
        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$refreshScript) `
            -WindowStyle Hidden | Out-Null
    }
}

# ---- Codex（ライブ） ----
$codexStr = 'Cdx —'
try {
    $base = Join-Path $HOME '.codex\sessions'
    $sess = $null
    $today = Get-Date
    $todayDir = Join-Path $base ('{0:yyyy}\{0:MM}\{0:dd}' -f $today)
    if (Test-Path $todayDir) {
        $sess = Get-ChildItem $todayDir -Filter *.jsonl | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }
    if (-not $sess -and (Test-Path $base)) {
        $sess = Get-ChildItem $base -Recurse -Filter *.jsonl | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }
    if ($sess) {
        $hit = Get-Content $sess.FullName -Tail 400 | Select-String -Pattern 'used_percent' | Select-Object -Last 1
        if ($hit) {
            $obj = $hit.Line | ConvertFrom-Json
            $rl = $obj.payload.rate_limits
            if ($rl -and $rl.primary) {
                $p = [int][math]::Round([double]$rl.primary.used_percent)
                $s = [int][math]::Round([double]$rl.secondary.used_percent)
                $codexStr = ("Cdx 5h{0}% wk{1}%" -f $p, $s)
            }
        }
    }
} catch { $codexStr = 'Cdx —' }

# ---- 合成 ----
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Output ("{0}   {1}" -f $claudeStr, $codexStr)
