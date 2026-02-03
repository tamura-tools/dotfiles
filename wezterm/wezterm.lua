local wezterm = require 'wezterm'
local mux = wezterm.mux
local config = {}

-- 最大化で起動
wezterm.on('gui-startup', function(cmd)
  local tab, pane, window = mux.spawn_window(cmd or {})
  
  -- 左右に分割
  local right_pane = pane:split {
    direction = 'Right',
    size = 0.75,
  }
  
  -- 左側を上下に分割（上:yazi、下:keifu）
  local left_bottom = pane:split {
    direction = 'Bottom',
    size = 0.4,
  }
  
  -- 右側を上下に分割（上:Claude Code、下:ターミナル）
  local right_bottom = right_pane:split {
    direction = 'Bottom',
    size = 0.4,
  }
  
  -- 各ペインでコマンド実行
  pane:send_text('yazi\n')
  left_bottom:send_text('keifu\n')
  right_pane:send_text('claude\n')
end)

config.color_scheme = 'Tokyo Night'
config.automatically_reload_config = true
config.font = wezterm.font('UDEV Gothic NF')
config.font_size = 12
config.default_prog = { 'powershell.exe' }
config.default_cwd = 'C:/claude'
config.initial_cols = 200  -- 横の文字数
config.initial_rows = 50   -- 縦の行数

-- 背景画像設定
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

-- キーバインド
config.keys = {
  { key = 'd', mods = 'CTRL|SHIFT', action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'e', mods = 'CTRL|SHIFT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 'h', mods = 'CTRL', action = wezterm.action.ActivatePaneDirection 'Left' },
  { key = 'l', mods = 'CTRL', action = wezterm.action.ActivatePaneDirection 'Right' },
  { key = 'k', mods = 'CTRL', action = wezterm.action.ActivatePaneDirection 'Up' },
  { key = 'j', mods = 'CTRL', action = wezterm.action.ActivatePaneDirection 'Down' },
  { key = 'w', mods = 'CTRL|SHIFT', action = wezterm.action.CloseCurrentPane { confirm = true } },
}

return config