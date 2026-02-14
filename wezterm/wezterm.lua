local wezterm = require 'wezterm'
local act = wezterm.action
local mux = wezterm.mux
local config = {}

-- OS判定
local is_windows = wezterm.target_triple:find('windows') ~= nil

-- ランチャーメニュー: アプリ定義
local launcher_apps
if is_windows then
  launcher_apps = {
    { id = 'claude',     label = 'Claude Code',       cmd = 'claudecode' },
    { id = 'claude-work', label = 'Claude Code (会社)', cmd = '$env:CLAUDE_CONFIG_DIR = "$HOME\\.claude-work"; claudecode' },
    { id = 'gemini',     label = 'Gemini CLI',        cmd = 'cd C:\\claude; gemini' },
    { id = 'lazygit',    label = 'lazygit',           cmd = 'cd $HOME\\dotfiles; lazygit' },
    { id = 'dashboard',  label = 'Sangha Dashboard',  cmd = '& "$HOME\\dotfiles\\wezterm\\sangha-dashboard.ps1"' },
    { id = 'yazi',       label = 'yazi',              cmd = 'yazi' },
    { id = 'shell',      label = 'PowerShell',        cmd = '' },
  }
else
  launcher_apps = {
    { id = 'claude',     label = 'Claude Code',       cmd = 'claude' },
    { id = 'claude-work', label = 'Claude Code (会社)', cmd = 'CLAUDE_CONFIG_DIR=~/.claude-work claude' },
    { id = 'gemini',     label = 'Gemini CLI',        cmd = 'cd ~/claude && gemini' },
    { id = 'lazygit',    label = 'lazygit',           cmd = 'cd ~/dotfiles && lazygit' },
    { id = 'dashboard',  label = 'Sangha Dashboard',  cmd = '~/dotfiles/wezterm/sangha-dashboard.sh' },
    { id = 'yazi',       label = 'yazi',              cmd = 'yazi' },
    { id = 'shell',      label = 'Shell',             cmd = '' },
  }
end

-- InputSelector用のchoicesを構築
local launcher_choices = {}
for _, app in ipairs(launcher_apps) do
  table.insert(launcher_choices, { id = app.id, label = app.label })
end

-- IDからコマンドを引くテーブル
local launcher_cmds = {}
for _, app in ipairs(launcher_apps) do
  launcher_cmds[app.id] = app.cmd
end

-- 5ペインレイアウトで最大化起動
-- 比率 = 左1 : 中5 : 右2
-- ┌──────┬────────────────────────┬──────────┐
-- │ yazi │     Claude Code        │          │
-- │      │   (プロジェクト実行)     │ Claude   │
-- ├──────┼────────────────────────┤ (壁打ち) │
-- │lazy  │   Sangha Dashboard     │          │
-- │ git  │                        │          │
-- └──────┴────────────────────────┴──────────┘
wezterm.on('gui-startup', function(cmd)
  local tab, pane, window = mux.spawn_window(cmd or {})
  window:gui_window():maximize()

  -- 1) 右端ぶち抜き壁打ちペイン (3/10 = 0.3)
  local chat_pane = pane:split {
    direction = 'Right',
    size = 0.3,
  }

  -- 2) 残りから中央ペインを切り出し (3/4 = 0.75)
  local middle_pane = pane:split {
    direction = 'Right',
    size = 0.75,
  }

  -- 3) 左側を上下に分割（上:yazi、下:lazygit）
  local left_bottom = pane:split {
    direction = 'Bottom',
    size = 0.25,
  }

  -- 4) 中央を上下に分割（上:Claude Code、下:Sangha Dashboard）
  local middle_bottom = middle_pane:split {
    direction = 'Bottom',
    size = 0.4,
  }

  -- 各ペインでコマンド実行
  pane:send_text('yazi\n')

  if is_windows then
    left_bottom:send_text('cd $HOME\\dotfiles; lazygit\n')
    -- 中央: プロジェクトディレクトリでClaude Code（実行者）
    middle_pane:send_text('claudecode\n')
    middle_bottom:send_text('& "$HOME\\dotfiles\\wezterm\\sangha-dashboard.ps1"\n')
    -- 右: 壁打ち専用ディレクトリでClaude Code
    chat_pane:send_text('cd $HOME\\claude-chat; claudecode\n')
  else
    left_bottom:send_text('cd ~/dotfiles && lazygit\n')
    middle_pane:send_text('claude\n')
    middle_bottom:send_text('~/dotfiles/wezterm/sangha-dashboard.sh\n')
    chat_pane:send_text('cd ~/claude-chat && claude\n')
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
      source = { File = wezterm.home_dir .. '/dotfiles/wezterm/wallpaper_win.jpg' },
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
  dashboard_cmd = '& "$HOME\\dotfiles\\wezterm\\sangha-dashboard.ps1"\r\n'
else
  dashboard_cmd = '~/dotfiles/wezterm/sangha-dashboard.sh\r\n'
end

-- モデル指定解除
  config.set_environment_variables = {
    ANTHROPIC_MODEL = '',
  }

-- 一時的な外観変更（セッション限り、再起動で元に戻る）
local color_schemes = {
  'Tokyo Night',
  'Tokyo Night Storm',
  'Catppuccin Mocha',
  'Catppuccin Macchiato',
  'Dracula (Gogh)',
  'Gruvbox Dark (Gogh)',
  'Nord',
  'One Half Dark (Gogh)',
  'Solarized Dark (Gogh)',
  'Kanagawa (Gogh)',
  'rose-pine',
  'Everforest Dark (Gogh)',
  'Ayu Dark (Gogh)',
  'nightfox',
}

local theme_choices = {}
for _, scheme in ipairs(color_schemes) do
  local mark = ''
  if scheme == config.color_scheme then mark = ' (current)' end
  table.insert(theme_choices, { id = scheme, label = scheme .. mark })
end
table.insert(theme_choices, { id = '_reset', label = 'Reset to default' })

local brightness_choices = {
  { id = '0.03', label = 'Very Dark (0.03)' },
  { id = '0.07', label = 'Dark (0.07)' },
  { id = '0.1',  label = 'Default (0.1)' },
  { id = '0.15', label = 'Medium Dark (0.15)' },
  { id = '0.2',  label = 'Medium (0.2)' },
  { id = '0.3',  label = 'Bright (0.3)' },
  { id = '0',    label = 'No wallpaper' },
  { id = '_reset', label = 'Reset to default' },
}

local wallpaper_file
if is_windows then
  wallpaper_file = wezterm.home_dir .. '/dotfiles/wezterm/wallpaper_win.jpg'
else
  wallpaper_file = wezterm.home_dir .. '/dotfiles/wezterm/wallpaper.jpg'
end

-- wallpapers/ フォルダ内の画像リスト（設定リロード時にスキャン）
local wallpaper_dir
if is_windows then
  wallpaper_dir = wezterm.home_dir .. '\\dotfiles\\wezterm\\wallpapers\\'
else
  wallpaper_dir = wezterm.home_dir .. '/dotfiles/wezterm/wallpapers/'
end
local wallpaper_choices = {
  { id = '_none', label = 'No wallpaper' },
  { id = '_reset', label = 'Reset to default' },
}
do
  local ok, _ = pcall(function()
    for _, ext in ipairs({ '*.jpg', '*.jpeg', '*.png', '*.gif', '*.webp' }) do
      for _, path in ipairs(wezterm.glob(wallpaper_dir .. ext)) do
        local name = path:match('[/\\]([^/\\]+)$') or path
        table.insert(wallpaper_choices, 1, { id = path, label = name })
      end
    end
  end)
end

-- キーバインド
config.keys = {
  -- Alt+Enter をターミナルに渡す（Claude Codeの改行用）
  { key = 'Enter', mods = 'ALT', action = act.SendKey { key = 'Enter', mods = 'ALT' } },
  { key = 'd', mods = 'CTRL|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'e', mods = 'CTRL|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 'h', mods = 'CTRL', action = act.ActivatePaneDirection 'Left' },
  { key = 'l', mods = 'CTRL', action = act.ActivatePaneDirection 'Right' },
  { key = 'k', mods = 'CTRL', action = act.ActivatePaneDirection 'Up' },
  { key = 'j', mods = 'CTRL', action = act.ActivatePaneDirection 'Down' },
  { key = 'w', mods = 'CTRL|SHIFT', action = act.CloseCurrentPane { confirm = true } },
  -- Quick launch: lazygit (Ctrl+Shift+G)
  { key = 'g', mods = 'CTRL|SHIFT', action = act.SendString('cd ~/dotfiles; lazygit\r\n') },
  -- Quick launch: Sangha Dashboard (Ctrl+Shift+S)
  { key = 's', mods = 'CTRL|SHIFT', action = act.SendString(dashboard_cmd) },
  -- Theme picker: カラースキーム一時切り替え (Ctrl+Shift+F1)
  { key = 'F1', mods = 'CTRL|SHIFT',
    action = act.InputSelector {
      title = 'Color Scheme (session only)',
      choices = theme_choices,
      action = wezterm.action_callback(function(win, _, id)
        if not id then return end
        local o = win:get_config_overrides() or {}
        if id == '_reset' then o.color_scheme = nil else o.color_scheme = id end
        win:set_config_overrides(o)
      end),
    },
  },
  -- Background picker: 壁紙の明るさ一時変更 (Ctrl+Shift+F2)
  { key = 'F2', mods = 'CTRL|SHIFT',
    action = act.InputSelector {
      title = 'Wallpaper Brightness (session only)',
      choices = brightness_choices,
      action = wezterm.action_callback(function(win, _, id)
        if not id then return end
        local o = win:get_config_overrides() or {}
        if id == '_reset' then
          o.background = nil
        elseif id == '0' then
          o.background = {}
        else
          local f = wallpaper_file
          if o.background and o.background[1] and o.background[1].source then
            f = o.background[1].source.File or f
          end
          o.background = { { source = { File = f }, hsb = { brightness = tonumber(id) }, opacity = 0.9, horizontal_align = 'Center', vertical_align = 'Middle', repeat_x = 'NoRepeat', repeat_y = 'NoRepeat' } }
        end
        win:set_config_overrides(o)
      end),
    },
  },
  -- Wallpaper picker: 壁紙画像の一時切り替え (Ctrl+Shift+F3)
  -- メニューを開くたびにフォルダをスキャンする
  { key = 'F3', mods = 'CTRL|SHIFT',
    action = wezterm.action_callback(function(win, pane)
      local choices = {
        { id = '_none', label = 'No wallpaper' },
        { id = '_reset', label = 'Reset to default' },
      }
      pcall(function()
        for _, ext in ipairs({ '*.jpg', '*.jpeg', '*.png', '*.gif', '*.webp' }) do
          for _, path in ipairs(wezterm.glob(wallpaper_dir .. ext)) do
            local name = path:match('[/\\]([^/\\]+)$') or path
            table.insert(choices, 1, { id = path, label = name })
          end
        end
      end)
      win:perform_action(
        act.InputSelector {
          title = 'Wallpaper Image (session only)',
          choices = choices,
          action = wezterm.action_callback(function(win2, _, id)
            if not id then return end
            local o = win2:get_config_overrides() or {}
            if id == '_reset' then
              o.background = nil
            elseif id == '_none' then
              o.background = {}
            else
              local b = 0.1
              if o.background and o.background[1] and o.background[1].hsb then
                b = o.background[1].hsb.brightness
              end
              o.background = { { source = { File = id }, hsb = { brightness = b }, opacity = 0.9, horizontal_align = 'Center', vertical_align = 'Middle', repeat_x = 'NoRepeat', repeat_y = 'NoRepeat' } }
            end
            win2:set_config_overrides(o)
          end),
        },
        pane
      )
    end),
  },
  -- Launcher menu: アプリ切り替え (F9)
  { key = 'F9', mods = 'NONE',
    action = act.InputSelector {
      title = '  Launch App',
      choices = launcher_choices,
      action = wezterm.action_callback(function(window, pane, id, label)
        if not id then return end
        local cmd = launcher_cmds[id]
        -- 現在のプロセスを停止 (Ctrl+C x2 + Enter)
        pane:send_text('\x03\x03\r\n')
        -- 新しいコマンドを送信（shell以外）
        if cmd ~= '' then
          pane:send_text(cmd .. '\r\n')
        end
      end),
    },
  },
}

return config
