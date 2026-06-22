# =====================================================================
#  ai_usage_pane.ps1
#  ⑤左下ペイン用: AI 使用量ライブ表示（Claude 個/社 ＋ Codex 5h/週）。
#  既存の ai_usage.ps1（ステータスライン用1行サマリ）を 30 秒ごとに
#  呼び出して表示するだけ。新規依存なし。
#  2026-06-22 新設（Codex 自動受信 watcher から転換）。
#  Grok の使用量追跡は形式未確定のため TBD。
# =====================================================================
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$usage = Join-Path $HOME 'dotfiles\wezterm\ai_usage.ps1'

while ($true) {
    Clear-Host
    $line = ''
    if (Test-Path $usage) { $line = (& $usage) }
    Write-Host ' AI Usage (live)'  -ForegroundColor Cyan
    Write-Host (' {0}' -f (Get-Date -Format 'HH:mm:ss')) -ForegroundColor DarkGray
    Write-Host ' ----------------'
    if ($line) { Write-Host (' ' + $line) } else { Write-Host ' (no data)' -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host ' C=Claude(個/社)'        -ForegroundColor DarkGray
    Write-Host ' Cdx=Codex(5h/週)'       -ForegroundColor DarkGray
    Write-Host ' Grok: 追跡未対応(TBD)'  -ForegroundColor DarkGray
    Start-Sleep -Seconds 30
}
