local wezterm = require 'wezterm'
local mux = wezterm.mux
local config = {}

-- OS判定
local is_windows = wezterm.target_triple:find('windows') ~= nil

-- 4ペインレイアウトで最大化起動
-- ┌──────────┬─────────────────────┐
-- │  yazi    │    Claude Code      │
-- ├──────────┼─────────────────────┤
-- │ lazygit  │ Sangha Dashboard    │
-- └──────────┴─────────────────────┘
wezterm.on('gui-startup', function(cmd)
  local tab, pane, window = mux.spawn_window(cmd or {})
  window:gui_window():maximize()

  -- 左右に分割
  local right_pane = pane:split {
    direction = 'Right',
    size = 0.75,
  }

  -- 左側を上下に分割（上:yazi、下:lazygit）
  local left_bottom = pane:split {
    direction = 'Bottom',
    size = 0.4,
  }

  -- 右側を上下に分割（上:Claude Code、下:Sangha Dashboard）
  local right_bottom = right_pane:split {
    direction = 'Bottom',
    size = 0.4,
  }

  -- 各ペインでコマンド実行
  pane:send_text('yazi\n')
  left_bottom:send_text('cd ~/dotfiles; lazygit\n')
  right_pane:send_text('claude\n')

  if is_windows then
    right_bottom:send_text('& ~/dotfiles/wezterm/sangha-dashboard.ps1\n')
  else
    right_bottom:send_text('~/dotfiles/wezterm/sangha-dashboard.sh\n')
  end
end)

config.color_scheme = 'Tokyo Night'
config.automatically_reload_config = true
config.font = wezterm.font('UDEV Gothic NF')
config.font_size = 12
config.initial_cols = 200
config.initial_rows = 50

-- OS別設定
if is_windows then
  config.default_prog = { 'powershell.exe' }
  config.default_cwd = 'C:/claude'
  config.background = {
    {
      source = { File = 'C:/Users/sss-0/OneDrive - トリプルエス株式会社/画像/壁紙/wallhaven-xlpv8v.jpg' },
      hsb = { brightness = 0.1 },
      opacity = 0.9,
      horizontal_align = 'Center',
      vertical_align = 'Middle',
      repeat_x = 'NoRepeat',
      repeat_y = 'NoRepeat',
    },
  }
else
  config.default_cwd = wezterm.home_dir .. '/claude'
  config.background = {
    {
      source = { File = wezterm.home_dir .. '/dotfiles/wezterm/wallpaper.jpg' },
      hsb = { brightness = 0.1 },
      opacity = 0.9,
      horizontal_align = 'Center',
      vertical_align = 'Middle',
      repeat_x = 'NoRepeat',
      repeat_y = 'NoRepeat',
    },
  }
end

-- ダッシュボード起動コマンド
local dashboard_cmd
if is_windows then
  dashboard_cmd = '& ~/dotfiles/wezterm/sangha-dashboard.ps1\r\n'
else
  dashboard_cmd = '~/dotfiles/wezterm/sangha-dashboard.sh\r\n'
end

-- キーバインド
config.keys = {
  { key = 'd', mods = 'CTRL|SHIFT', action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'e', mods = 'CTRL|SHIFT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 'h', mods = 'CTRL', action = wezterm.action.ActivatePaneDirection 'Left' },
  { key = 'l', mods = 'CTRL', action = wezterm.action.ActivatePaneDirection 'Right' },
  { key = 'k', mods = 'CTRL', action = wezterm.action.ActivatePaneDirection 'Up' },
  { key = 'j', mods = 'CTRL', action = wezterm.action.ActivatePaneDirection 'Down' },
  { key = 'w', mods = 'CTRL|SHIFT', action = wezterm.action.CloseCurrentPane { confirm = true } },
  -- Quick launch: lazygit (Ctrl+Shift+G)
  { key = 'g', mods = 'CTRL|SHIFT', action = wezterm.action.SendString('cd ~/dotfiles; lazygit\r\n') },
  -- Quick launch: Sangha Dashboard (Ctrl+Shift+S)
  { key = 's', mods = 'CTRL|SHIFT', action = wezterm.action.SendString(dashboard_cmd) },
}

return config
