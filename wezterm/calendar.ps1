# calendar.ps1 — 左中ペイン: Google Calendar アジェンダ（当日+数日）
# 実体は gcal.py（~/.config/gcal/ の資格情報で primary カレンダーを読む）。
# 初回だけ:  python $HOME\dotfiles\wezterm\gcal.py --auth  でブラウザ同意。
$ErrorActionPreference = 'SilentlyContinue'
$gcal = Join-Path $HOME 'dotfiles\wezterm\gcal.py'

while ($true) {
  Clear-Host
  Write-Host ""
  try {
    python $gcal
  } catch {
    Write-Host "  gcal.py 実行エラー:" -ForegroundColor Red
    Write-Host ("  " + $_.Exception.Message) -ForegroundColor DarkGray
  }
  Write-Host ""
  Write-Host "  Refresh: 300s" -ForegroundColor DarkGray
  Start-Sleep -Seconds 300
}
