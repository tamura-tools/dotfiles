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
    { id = 'claude',     label = 'Claude Code',       cmd = '$env:CLAUDE_CONFIG_DIR = $null; claude' },
    { id = 'claude-work', label = 'Claude Code (会社)', cmd = '$env:CLAUDE_CONFIG_DIR = "$HOME\\.claude-work"; claude' },
    { id = 'gemini',     label = 'Gemini CLI',        cmd = 'cd C:\\claude; gemini' },
    { id = 'lazygit',    label = 'lazygit',           cmd = 'cd $HOME\\dotfiles; lazygit' },
    { id = 'dashboard',  label = 'Obsidian Tasks',     cmd = 'python C:\\claude\\tools\\task.py watch' },
    { id = 'codex',      label = 'Codex CLI',          cmd = 'cd C:\\claude; codex' },
    { id = 'yazi',       label = 'yazi',              cmd = 'yazi' },
    { id = 'shell',      label = 'PowerShell',        cmd = '' },
  }
else
  launcher_apps = {
    { id = 'claude',     label = 'Claude Code',       cmd = 'unset CLAUDE_CONFIG_DIR; claude' },
    { id = 'claude-work', label = 'Claude Code (会社)', cmd = 'CLAUDE_CONFIG_DIR=~/.claude-work claude' },
    { id = 'gemini',     label = 'Gemini CLI',        cmd = 'cd ~/claude && gemini' },
    { id = 'lazygit',    label = 'lazygit',           cmd = 'cd ~/dotfiles && lazygit' },
    { id = 'dashboard',  label = 'Obsidian Tasks',     cmd = 'python ~/claude/tools/task.py watch' },
    { id = 'codex',      label = 'Codex CLI',          cmd = 'cd ~/claude && codex' },
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

-- 6ペインレイアウトで最大化起動
-- 比率 = 左1 : 中5 : 右2
-- ┌──────┬────────────────────────┬──────────┐
-- │ yazi │     Claude Code        │ Gemini   │
-- │      │                        │  CLI     │
-- ├──────┼────────────────────────┼──────────┤
-- │lazy  │   Obsidian Tasks       │ Codex    │
-- │ git  │                        │  CLI     │
-- └──────┴────────────────────────┴──────────┘
wezterm.on('gui-startup', function(cmd)
  local tab, pane, window = mux.spawn_window(cmd or {})
  window:gui_window():maximize()

  -- 1) 右カラムを切り出し (3/10 = 0.3)
  local right_pane = pane:split {
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

  -- 4) 中央を上下に分割（上:Claude Code、下:Obsidian Tasks）
  local middle_bottom = middle_pane:split {
    direction = 'Bottom',
    size = 0.4,
  }

  -- 5) 右を上下に分割（上:Codex CLI、下:Gemini CLI）
  local right_bottom = right_pane:split {
    direction = 'Bottom',
    size = 0.35,
  }

  -- 各ペインでコマンド実行
  pane:send_text('yazi\n')

  if is_windows then
    left_bottom:send_text('cd $HOME\\dotfiles; lazygit\n')
    middle_pane:send_text('claude\n')
    middle_bottom:send_text('python C:\\claude\\tools\\task.py watch\n')
    right_pane:send_text('cd C:\\claude; codex\n')
    right_bottom:send_text('cd C:\\claude; gemini\n')
  else
    left_bottom:send_text('cd ~/dotfiles && lazygit\n')
    middle_pane:send_text('claude\n')
    middle_bottom:send_text('python ~/claude/tools/task.py watch\n')
    right_pane:send_text('cd ~/claude && codex\n')
    right_bottom:send_text('cd ~/claude && gemini\n')
  end
end)

-- カスタムカラースキーム
config.color_schemes = {
  ['SF Terminal'] = {
    foreground = '#B0E0E6',       -- 淡いシアン（メインテキスト）
    background = '#0A0A12',       -- ほぼ黒（透過で見えなくなる）
    cursor_bg = '#00FFFF',        -- シアン発光カーソル
    cursor_fg = '#0A0A12',
    selection_bg = '#00FFFF',   -- シアンセレクション
    selection_fg = '#FFFFFF',
    ansi = {
      '#1A1A2E',  -- black: 深い紺
      '#FF3366',  -- red: ネオンピンク
      '#00FF88',  -- green: ネオングリーン
      '#FFAA00',  -- yellow: アンバー警告色
      '#00BBFF',  -- blue: スカイブルー
      '#CC44FF',  -- magenta: ネオンパープル
      '#00FFCC',  -- cyan: アクアグリーン
      '#8899AA',  -- white: スチールグレー
    },
    brights = {
      '#334455',  -- bright black: ダークスチール
      '#FF6699',  -- bright red: ホットピンク
      '#33FFAA',  -- bright green: ミントグロー
      '#FFCC33',  -- bright yellow: ゴールド
      '#33DDFF',  -- bright blue: エレクトリックブルー
      '#DD77FF',  -- bright magenta: ラベンダーグロー
      '#33FFDD',  -- bright cyan: ブライトアクア
      '#DDEEFF',  -- bright white: アイスホワイト
    },
  },
  ['Neuromancer'] = {
    foreground = '#00FF9C',       -- 毒々しいターミナルグリーン
    background = '#080814',       -- 漆黒の紺（壁紙と合う）
    cursor_bg = '#FF0055',        -- ネオンピンクカーソル（目立つ）
    cursor_fg = '#080814',
    selection_bg = '#BF00FF',     -- パープルセレクション
    selection_fg = '#FFFFFF',
    ansi = {
      '#12122A',  -- black: 深淵
      '#FF0055',  -- red: ネオンクリムゾン
      '#39FF14',  -- green: 放射性グリーン
      '#FF6600',  -- yellow: 警告オレンジ
      '#0088FF',  -- blue: エレクトリックブルー
      '#BF00FF',  -- magenta: サイバーパープル
      '#00FFD0',  -- cyan: ターコイズグロー
      '#708090',  -- white: スレートグレー
    },
    brights = {
      '#2A2A4A',  -- bright black: ミッドナイト
      '#FF3377',  -- bright red: ホットマゼンタ
      '#7CFF4B',  -- bright green: アシッドグリーン
      '#FFAA00',  -- bright yellow: アンバーグロー
      '#33BBFF',  -- bright blue: スカイネオン
      '#DD44FF',  -- bright magenta: UVパープル
      '#00FFEE',  -- bright cyan: プラズマシアン
      '#C0D0E0',  -- bright white: クロームシルバー
    },
  },
  ['Claude Light'] = {
    foreground = '#3C3836',
    background = '#F5EFE6',
    cursor_bg = '#5C534A',
    cursor_fg = '#F5EFE6',
    selection_bg = '#D4C9B8',
    selection_fg = '#3C3836',
    ansi = {
      '#3C3836',  -- black
      '#C35B4E',  -- red
      '#6A8F4E',  -- green
      '#B5873A',  -- yellow
      '#5079A5',  -- blue
      '#8E6BA1',  -- magenta
      '#5B9A8B',  -- cyan
      '#D5CFC4',  -- white
    },
    brights = {
      '#5C534A',  -- bright black
      '#D96D5E',  -- bright red
      '#7DA85E',  -- bright green
      '#C9974A',  -- bright yellow
      '#6090B8',  -- bright blue
      '#A37DB5',  -- bright magenta
      '#6DB3A2',  -- bright cyan
      '#F5EFE6',  -- bright white
    },
  },
}

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
  dashboard_cmd = 'python C:\\claude\\tools\\task.py watch\r\n'
else
  dashboard_cmd = 'python ~/claude/tools/task.py watch\r\n'
end

-- モデル指定解除
  config.set_environment_variables = {
    ANTHROPIC_MODEL = '',
  }

-- ===== プロファイル =====
-- テーマ + 壁紙 + 明るさをセットで切り替え
-- 用途: 個人/会社アカウントの視覚的な区別
local profiles = {
  {
    id = 'personal',
    label = '🏠 個人用 — Tokyo Night + 壁紙',
    color_scheme = 'Tokyo Night',
    wallpaper = true,           -- デフォルト壁紙を使う
    brightness = 0.1,
    window_background_opacity = nil,  -- デフォルト
  },
  {
    id = 'work',
    label = '🏢 会社用 — Claude Light (壁紙なし)',
    color_scheme = 'Claude Light',
    wallpaper = false,          -- 壁紙なし
    brightness = nil,
    window_background_opacity = 1.0,  -- 完全不透明
  },
  {
    id = 'work-dark',
    label = '🏢 会社用(Dark) — Catppuccin + 海',
    color_scheme = 'Catppuccin Mocha',
    wallpaper = 'sea001.jpg',   -- wallpapers/ 内のファイル名
    brightness = 0.07,
    window_background_opacity = nil,
  },
  {
    id = 'sf-terminal',
    label = '🛸 SF Terminal — スケスケHUD',
    color_scheme = 'SF Terminal',
    wallpaper = false,
    brightness = nil,
    window_background_opacity = 0.55,  -- デスクトップが透けて見える
  },
  {
    id = 'neuromancer',
    label = '💀 Neuromancer — サイバーパンク',
    color_scheme = 'Neuromancer',
    wallpaper = 'cyberpunk_matrix.png',
    brightness = 0.12,
    window_background_opacity = nil,
  },
}

-- プロファイルの壁紙パスを解決
local function resolve_wallpaper(profile)
  if profile.wallpaper == true then
    return wallpaper_file
  elseif profile.wallpaper and profile.wallpaper ~= false then
    if is_windows then
      return wezterm.home_dir .. '\\dotfiles\\wezterm\\wallpapers\\' .. profile.wallpaper
    else
      return wezterm.home_dir .. '/dotfiles/wezterm/wallpapers/' .. profile.wallpaper
    end
  end
  return nil  -- 壁紙なし
end

-- プロファイルをconfig overridesに適用
local function apply_profile(win, profile)
  local o = win:get_config_overrides() or {}
  o.color_scheme = profile.color_scheme

  local wp = resolve_wallpaper(profile)
  if wp then
    o.background = { {
      source = { File = wp },
      hsb = { brightness = profile.brightness or 0.1 },
      opacity = 0.9,
      horizontal_align = 'Center',
      vertical_align = 'Middle',
      repeat_x = 'NoRepeat',
      repeat_y = 'NoRepeat',
    } }
  else
    o.background = {}
  end

  o.window_background_opacity = profile.window_background_opacity
  win:set_config_overrides(o)
end

-- ===== 一時的な外観変更（セッション限り、再起動で元に戻る） =====
-- ライトテーマ別設定 { brightness, opacity }
-- brightness: 壁紙を白く飛ばす (1.0超え可)
-- opacity: テーマ背景の不透明度 (高い=テーマ色優先、壁紙はうっすら)
local light_default = { brightness = 2.0, opacity = 0.92 }
local light_themes = {
  ['Claude Light']             = light_default,
  ['Tokyo Night Day']         = light_default,
  ['Catppuccin Latte']        = light_default,
  ['Gruvbox Light (Gogh)']    = light_default,
  ['One Half Light (Gogh)']   = light_default,
  ['Solarized Light (Gogh)']  = light_default,
  ['rose-pine-dawn']          = light_default,
  ['Everforest Light (Gogh)'] = light_default,
  ['Ayu Light (Gogh)']        = light_default,
  ['dayfox']                  = light_default,
  ['dawnfox']                 = light_default,
}

local color_schemes = {
  -- Dark
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
  -- SF / Cyberpunk
  'SF Terminal',
  'Neuromancer',
  -- Light
  'Claude Light',
  'Tokyo Night Day',
  'Catppuccin Latte',
  'Gruvbox Light (Gogh)',
  'One Half Light (Gogh)',
  'Solarized Light (Gogh)',
  'rose-pine-dawn',
  'Everforest Light (Gogh)',
  'Ayu Light (Gogh)',
  'dayfox',
  'dawnfox',
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
        if id == '_reset' then
          o.color_scheme = nil
          o.background = nil
        else
          o.color_scheme = id
          local lt = light_themes[id]
          if lt then
            -- ライトテーマ: テーマ別の壁紙brightness＋背景opacity
            local f = wallpaper_file
            if o.background and o.background[1] and o.background[1].source then
              f = o.background[1].source.File or f
            end
            o.background = { { source = { File = f }, hsb = { brightness = lt.brightness }, opacity = 0.9, horizontal_align = 'Center', vertical_align = 'Middle', repeat_x = 'NoRepeat', repeat_y = 'NoRepeat' } }
            o.window_background_opacity = lt.opacity
          else
            -- ダークテーマ: デフォルトに戻す
            o.background = nil
            o.window_background_opacity = nil
          end
        end
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
  -- Profile switcher: テーマ+壁紙セット切り替え (Ctrl+Shift+F4)
  { key = 'F4', mods = 'CTRL|SHIFT',
    action = act.InputSelector {
      title = '  Profile (テーマ+壁紙セット)',
      choices = (function()
        local c = {}
        for _, p in ipairs(profiles) do
          table.insert(c, { id = p.id, label = p.label })
        end
        table.insert(c, { id = '_reset', label = '↩ Reset to default' })
        return c
      end)(),
      action = wezterm.action_callback(function(win, _, id)
        if not id then return end
        if id == '_reset' then
          local o = win:get_config_overrides() or {}
          o.color_scheme = nil
          o.background = nil
          o.window_background_opacity = nil
          win:set_config_overrides(o)
          return
        end
        for _, p in ipairs(profiles) do
          if p.id == id then
            apply_profile(win, p)
            return
          end
        end
      end),
    },
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
