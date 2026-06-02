# =====================================================================
#  ai_usage_refresh.ps1
#  Claude Code のプラン枠（5時間ブロック）使用率を ccusage で算出し、
#  キャッシュ（$TEMP\wez_ai_usage.json）に書き出す。
#  WezTerm から detached（バックグラウンド）で呼ばれる前提＝多少遅くてOK。
#
#  Claude のプラン上限は非公開のため pct は近似値：
#   - $env:CLAUDE_5H_TOKEN_LIMIT が設定されていればそれを 100% 基準にする
#   - 未設定なら「過去の最大 5h ブロック（履歴ピーク）」を 100% 基準にする
# =====================================================================
$ErrorActionPreference = 'SilentlyContinue'

$cachePath = Join-Path $env:TEMP 'wez_ai_usage.json'

function Get-ClaudeBlockStat([string]$ConfigDir) {
    $res = [ordered]@{ active = $false; pct = $null; resetMin = $null; cost = $null }
    if (-not (Test-Path $ConfigDir)) { return $res }

    $env:CLAUDE_CONFIG_DIR = $ConfigDir
    $raw = (bunx ccusage blocks --json 2>$null | Out-String)
    if (-not $raw) { return $res }
    $i = $raw.IndexOf('{')
    if ($i -lt 0) { return $res }
    $raw = $raw.Substring($i)

    $data = $null
    try { $data = $raw | ConvertFrom-Json } catch { return $res }
    if (-not $data.blocks) { return $res }

    $active = $null
    $maxTok = 0.0
    foreach ($b in $data.blocks) {
        if ($b.isGap) { continue }
        $tt = [double]$b.totalTokens
        if ($tt -gt $maxTok) { $maxTok = $tt }
        if ($b.isActive) { $active = $b }
    }
    if (-not $active) { return $res }

    $limit = 0.0
    if ($env:CLAUDE_5H_TOKEN_LIMIT) {
        [double]::TryParse($env:CLAUDE_5H_TOKEN_LIMIT, [ref]$limit) | Out-Null
    }
    if ($limit -le 0) { $limit = $maxTok }   # 履歴ピークを基準（近似）

    $res.active = $true
    $res.cost = [math]::Round([double]$active.costUSD, 1)
    if ($limit -gt 0) {
        $res.pct = [int][math]::Round(([double]$active.totalTokens / $limit) * 100)
    }
    if ($active.projection -and $active.projection.remainingMinutes) {
        $res.resetMin = [int]$active.projection.remainingMinutes
    }
    return $res
}

$out = [ordered]@{
    ts       = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    personal = (Get-ClaudeBlockStat "$HOME\.claude")
    work     = (Get-ClaudeBlockStat "$HOME\.claude-work")
}

try {
    $json = $out | ConvertTo-Json -Depth 5
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($cachePath, $json, $utf8)
} catch { }
